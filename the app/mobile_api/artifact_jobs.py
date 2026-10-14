"""Stateless clothing restyle and character LoRA adapters over the installed engines."""

import base64
import json
import math
import queue
import re
import shutil
import subprocess
import threading
import time
import zipfile
from pathlib import Path, PurePosixPath
from types import SimpleNamespace

import cv2
import numpy as np

from . import APP_DIR
from .errors import ApiError, bad_request
from .schemas import decode_embedding

ARTIFACT_TYPES = {'undress_image', 'build_lora_dataset', 'train_lora', 'generate_lora_images'}


def bounded(params, key, default, low, high, integer=False):
    value = params.get(key, default)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
        raise bad_request(f'{key} must be between {low} and {high}.')
    if integer and type(value) is not int:
        raise bad_request(f'{key} must be an integer.')
    return value


def validate_artifact(body, caps):
    kind, params, inputs = body.get('type'), body.get('params'), body.get('inputs')
    if kind not in ARTIFACT_TYPES or not isinstance(params, dict) or not isinstance(inputs, dict):
        raise bad_request('A supported Studio type, params and inputs are required.')
    slots = {'undress_image': ('image', {'image', 'refs'}), 'build_lora_dataset': ('images', {'images'}),
             'train_lora': ('dataset', {'dataset'}), 'generate_lora_images': ('lora', {'lora', 'reference'})}
    required, allowed = slots[kind]
    if required not in inputs or set(inputs) - allowed:
        raise bad_request('The job has missing or unsupported input slots.')
    for name, value in inputs.items():
        if name in ('images', 'refs'):
            limit = 64 if name == 'images' else 4
            if not isinstance(value, list) or not 1 <= len(value) <= limit:
                raise bad_request(f'{name} must contain 1 to {limit} images.')
        elif not isinstance(value, str):
            raise bad_request(f'{name} must reference one blob.')
    trigger = params.get('trigger_word')
    if kind != 'undress_image' and (not isinstance(trigger, str) or re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{2,63}', trigger) is None):
        raise bad_request('Use a trigger word of 3 to 64 letters, digits or underscores.')
    engine = {'undress_image': 'undress', 'train_lora': 'lora_train', 'generate_lora_images': 'lora_generate'}.get(kind)
    if engine and not caps['engines'][engine]:
        raise ApiError(409, 'engine_unavailable', 'The required engine is unavailable on this PC.')
    if kind in ('undress_image', 'generate_lora_images'):
        for key in ('prompt', 'negative_prompt'):
            if key in params and (not isinstance(params[key], str) or len(params[key]) > 4000):
                raise bad_request(f'{key} must be text of at most 4000 characters.')
        bounded(params, 'seed', -1, -1, 2**31-1, True)
        bounded(params, 'steps', 26, 5, 80, True)
        bounded(params, 'guidance_scale', 6, 1, 15)
    if kind == 'undress_image':
        allowed_params = {'prompt', 'negative_prompt', 'seed', 'steps', 'guidance_scale', 'strength', 'face_bbox',
                          'ref_scale', 'refine', 'refine_strength', 'refine_steps', 'controlnet_scale'}
        bounded(params, 'strength', .6, .05, 1)
        bounded(params, 'ref_scale', .85, 0, 1)
        bounded(params, 'refine_strength', .4, .05, 1)
        bounded(params, 'refine_steps', 35, 5, 80, True)
        bounded(params, 'controlnet_scale', 0, 0, 1)
        if 'refine' in params and not isinstance(params['refine'], bool):
            raise bad_request('refine must be true or false.')
        box = params.get('face_bbox')
        if box is not None and (not isinstance(box, dict) or set(box) != {'x','y','w','h'} or any(
                isinstance(v, bool) or not isinstance(v, (float,int)) or not math.isfinite(v) or v < 0
                for v in box.values()) or box['w'] <= 0 or box['h'] <= 0):
            raise bad_request('The protected face box is invalid.')
    elif kind == 'build_lora_dataset':
        allowed_params = {'trigger_word', 'repeats', 'anchor_embedding', 'max_frames_per_video'}
        bounded(params, 'repeats', 20, 1, 100, True)
        bounded(params, 'max_frames_per_video', 12, 1, 24, True)
        try:
            anchor = decode_embedding(params['anchor_embedding'])
            if not np.all(np.isfinite(anchor)) or np.linalg.norm(anchor) < 1e-8:
                raise ValueError()
        except (ValueError, TypeError, KeyError):
            raise bad_request('A valid person identity anchor is required.')
    elif kind == 'train_lora':
        allowed_params = {'trigger_word','output_name','base_checkpoint','epochs','network_dim','network_alpha','learning_rate','batch_size','max_resolution'}
        output_name=params.get('output_name','character')
        if not isinstance(output_name,str) or re.fullmatch(r'[A-Za-z0-9_-]{1,64}',output_name) is None:
            raise bad_request('Use a simple model output name.')
        bounded(params, 'epochs', 10, 1, 50, True)
        dim = bounded(params, 'network_dim', 32, 4, 128, True)
        bounded(params, 'network_alpha', 16, 1, dim, True)
        bounded(params, 'learning_rate', .0001, .000001, .001)
        bounded(params, 'batch_size', 1, 1, 2, True)
        if params.get('max_resolution',512) not in (512,768):
            raise bad_request('Choose 512 or 768 resolution.')
    else:
        allowed_params = {'trigger_word','base_checkpoint','prompt','negative_prompt','seed','steps','guidance_scale',
                          'num_images','lora_scale','multi_angle','reference_mode','reference_strength','reference_scale'}
        bounded(params, 'num_images', 4, 1, 16, True)
        bounded(params, 'lora_scale', .75, 0, 1.5)
        bounded(params, 'reference_strength', .6, .05, 1)
        bounded(params, 'reference_scale', .5, 0, 1)
        if params.get('reference_mode','composition') not in ('composition','style','both'):
            raise bad_request('Choose a supported reference mode.')
        if 'multi_angle' in params and not isinstance(params['multi_angle'], bool):
            raise bad_request('multi_angle must be true or false.')
    if set(params) - allowed_params:
        raise bad_request('An unsupported job option was supplied.')
    if kind in ('train_lora','generate_lora_images') and params.get('base_checkpoint') not in caps['lora_base_checkpoints']:
        raise bad_request('Choose a base checkpoint reported by this PC.')


def extract_dataset(source, directory):
    """Accept only bounded image/caption bundles; never extract executables or serialized state."""
    total = 0
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        if len(entries) > 2048:
            raise ValueError('The dataset contains too many files.')
        for entry in entries:
            name = PurePosixPath(entry.filename)
            if name.is_absolute() or '..' in name.parts or '\\' in entry.filename or ':' in entry.filename:
                raise ValueError('Unsafe dataset filename.')
            if entry.is_dir():
                continue
            if name.suffix.lower() not in ('.jpg','.jpeg','.png','.txt') or len(name.parts) != 2:
                raise ValueError('Datasets may contain only images and captions in one training folder.')
            match=re.fullmatch(r'(\d+)_[A-Za-z0-9_]+ person', name.parts[0])
            if not match or not 1<=int(match.group(1))<=100:
                raise ValueError('The training folder must use the repeats_trigger person layout.')
            total += entry.file_size
            if total > 512*1024*1024 or entry.file_size > (8192 if name.suffix == '.txt' else 32*1024*1024):
                raise ValueError('The expanded dataset is too large.')
            if (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Dataset links are not allowed.')
            destination = directory.joinpath(*name.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as src, open(destination,'wb') as target:
                shutil.copyfileobj(src,target)
    folders = [p for p in directory.iterdir() if p.is_dir()]
    if len(folders) != 1:
        raise ValueError('Choose one character dataset.')
    images = [p for p in folders[0].iterdir() if p.suffix.lower() in ('.jpg','.jpeg','.png')]
    if len(images) < 5 or any(not p.with_suffix('.txt').exists() for p in images):
        raise ValueError('Training needs at least five captioned images.')
    return folders[0]


def run_artifact(job, directory, report, stopped, ctx):
    kind, params = job['type'], job['params']
    if kind in ('undress_image','train_lora','generate_lora_images') and hasattr(ctx.engines,'unload'):
        ctx.engines.unload()
    if kind == 'undress_image':
        from undress_core import UndressClient, VENV_AI_PYTHON, UNDRESS_SCRIPT
        import os
        client = UndressClient(VENV_AI_PYTHON, UNDRESS_SCRIPT,
                              env=dict(os.environ,HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1'))
        payload = dict(params, image_path=str(directory/'input.image'),
                       ref_images=[str(p) for p in sorted(directory.glob('input.refs.*'))])
        box = payload.get('face_bbox')
        if box is not None:
            payload['face_bbox'] = [box['x'],box['y'],box['x']+box['w'],box['y']+box['h']]
        def status(message):
            if stopped():
                client.close()
                raise InterruptedError()
            report(.25,'Restyling clothing')
        try:
            if stopped(): return None
            result = client.generate(payload, timeout=7200, status_callback=status, stop_requested=stopped)
            if stopped(): return None
            if not result.get('success'):
                raise ValueError(result.get('error','Clothes restyle failed.'))
            (directory/'result.png').write_bytes(base64.b64decode(result['output_image'],validate=True))
            return {'seed':params.get('seed',-1)}
        except InterruptedError:
            return None
        finally:
            client.close()
    if kind == 'build_lora_dataset':
        from lora_dataset import detect_face_record_from_image, _write_dataset_records, WD14Tagger, sample_video_frames
        from face_restore import FaceRestorer
        anchor = decode_embedding(params['anchor_embedding'])
        records = []
        inputs = sorted(directory.glob('input.images.*'))
        ctx.engines.load()
        for index, source in enumerate(inputs):
            if stopped(): return None
            report(index/max(len(inputs),1)*.4,'Finding the selected person')
            image = cv2.imread(str(source))
            photo = directory/f'photo_{index}.jpg'
            if image is None:
                frames=sample_video_frames(str(source),directory/'frames'/str(index),max_frames=params.get('max_frames_per_video',12))
                if not frames: raise ValueError('A dataset input is not a readable photo or video.')
            else:
                if max(image.shape[:2])>4096:
                    scale=4096/max(image.shape[:2]);image=cv2.resize(image,None,fx=scale,fy=scale)
                cv2.imwrite(str(photo),image)
                frames=[str(photo)]
            for frame in frames:
                if stopped():return None
                record = detect_face_record_from_image(frame,ctx.engines._face_app,anchor)
                if record is not None: records.append(record)
        def crop_progress(fraction,message):
            if stopped(): raise InterruptedError()
            report(.4+.5*fraction,message)
        try:
            result = _write_dataset_records(records,params['trigger_word'],'mobile',directory/'dataset',
                params.get('repeats',20),ctx.engines._face_app,FaceRestorer(model_name='gpen_bfr_512'),WD14Tagger(),crop_progress)
        except InterruptedError: return None
        if result['blocked']: raise ValueError(result['warning'])
        folder = Path(result['dataset_dir'])
        with zipfile.ZipFile(directory/'dataset.zip','w',compression=zipfile.ZIP_STORED) as bundle:
            for path in sorted(folder.iterdir()): bundle.write(path,f'{folder.name}/{path.name}')
        return {'trigger_word':params['trigger_word'],'image_count':result['image_count']}
    if kind == 'train_lora':
        from lora_trainer import build_training_args, latest_resume_state, update_training_state, VENV_LORA_PYTHON, SD_SCRIPTS_TRAIN_SCRIPT, SD_SCRIPTS_DIR
        extracted = directory/'training'
        if not extracted.exists():
            extracted.mkdir()
            dataset = extract_dataset(directory/'input.dataset',extracted)
        else:
            dataset = next(extracted.iterdir())
        run_dir = directory/'training-output'
        run_dir.mkdir(exist_ok=True)
        output_name=params.get('output_name','character')
        resume = latest_resume_state(run_dir,output_name)
        args = build_training_args(str(dataset),str(run_dir),output_name,
            str(APP_DIR/'models'/f"{params['base_checkpoint']}.safetensors"),
            epochs=params.get('epochs',10),network_dim=params.get('network_dim',32),network_alpha=params.get('network_alpha',16),
            learning_rate=params.get('learning_rate',.0001),batch_size=params.get('batch_size',1),max_resolution=params.get('max_resolution',512),
            resume_state=str(resume[1]) if resume else None,resumed_epochs=resume[0] if resume else 0)
        state = {}
        def line(raw):
            update_training_state(state,raw,resume[0] if resume else 0)
            safe = {k:v for k,v in state.items() if k in ('stage','epoch','total_epochs','step','total_steps','loss','seconds_per_step')}
            progress = min(.99,state.get('step',0)/max(state.get('total_steps',1),1))
            report(progress,'Training character LoRA',details=safe)
        code = run_process([str(VENV_LORA_PYTHON),str(SD_SCRIPTS_TRAIN_SCRIPT),*args],directory,stopped,line,cwd=SD_SCRIPTS_DIR)
        if stopped(): return None
        if code != 0: raise ValueError('Training failed; inspect the PC job log.')
        shutil.copyfile(run_dir/f'{output_name}.safetensors',directory/'lora.safetensors')
        return {'trigger_word':params['trigger_word']}
    from lora_generate import EVENT_PREFIX
    output = directory/'generated'
    output.mkdir(exist_ok=True)
    current = len(list(output.glob('*.png')))
    if current < params.get('num_images',4):
        # diffusers chooses the decoder from the filename. Keep the safetensors
        # extension even though the content-addressed upload has no extension.
        lora = directory/'uploaded.safetensors'
        if not lora.exists(): shutil.copyfile(directory/'input.lora',lora)
        payload = dict(params, base_checkpoint=str(APP_DIR/'models'/f"{params['base_checkpoint']}.safetensors"),
                       lora_path=str(lora),output_dir=str(output),num_images=params.get('num_images',4)-current,
                       file_prefix=f'image_{current}')
        if params.get('seed',-1) >= 0: payload['seed']=params['seed']+current
        if (directory/'input.reference').exists(): payload['reference_image']=str(directory/'input.reference')
        def line(raw):
            if raw.startswith(EVENT_PREFIX):
                event=json.loads(raw[len(EVENT_PREFIX):])
                report(min(.99,len(list(output.glob('*.png')))/params.get('num_images',4)),'Generating portraits',
                       details={k:v for k,v in event.items() if k in ('stage','step','steps','index','total')})
        code=run_process([str(APP_DIR/'venv_ai'/'Scripts'/'python.exe'),str(APP_DIR/'lora_generate.py')],directory,stopped,line,stdin=json.dumps(payload))
        if stopped(): return None
        if code != 0: raise ValueError('Portrait generation failed; inspect the PC job log.')
    pictures=sorted(output.glob('*.png'))
    if len(pictures) != params.get('num_images',4): raise ValueError('Some generated portraits are missing.')
    with zipfile.ZipFile(directory/'portraits.zip','w',compression=zipfile.ZIP_STORED) as bundle:
        for path in pictures: bundle.write(path,path.name)
    return {'trigger_word':params['trigger_word'],'image_count':len(pictures)}


def run_process(command,directory,stopped,on_line,stdin=None,cwd=APP_DIR):
    """Drain output while polling pause even during silent model loading; no orphan child."""
    import os
    env=dict(os.environ,PYTHONIOENCODING='utf-8',PYTHONUNBUFFERED='1',HF_HUB_OFFLINE='1')
    process=subprocess.Popen(command,cwd=str(cwd),stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1,env=env,
        creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
    if stdin is not None: process.stdin.write(stdin);process.stdin.close()
    lines=queue.Queue()
    def read():
        for raw in process.stdout: lines.put(raw.rstrip())
        lines.put(None)
    threading.Thread(target=read,daemon=True).start()
    try:
        with open(directory/'engine.log','a',encoding='utf-8') as log:
            while True:
                if stopped(): return -1
                try: raw=lines.get(timeout=.5)
                except queue.Empty: continue
                if raw is None: break
                log.write(raw+'\n');log.flush()
                try: on_line(raw)
                except (ValueError,KeyError,TypeError): pass  # display-only parsing
        return process.wait()
    finally:
        if process.poll() is None: process.kill()
        process.wait()
