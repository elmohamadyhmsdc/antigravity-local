"""Photo-only background/object editing with immutable person protection.

Model inference lives in a separate process. Pixels outside the user's mask are
copied from the original, including alpha; originals are never overwritten.
"""
import base64
import io
import json
import math
import re
import secrets
import subprocess
import tempfile
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

APP = Path(__file__).resolve().parent
BASE_MODEL = APP / 'models/undress/Uminosachi--realisticVisionV51_v51VAE-inpainting'
SAFETY_MODEL = APP / 'models/photo_edit/safety_checker'
REMOVAL_MODEL = APP / 'models/photo_edit/big-lama.pt'
WORKER_PYTHON = APP / 'venv_ai/Scripts/python.exe'
PREFIX = '@@photo_edit '
MAX_PIXELS = 40_000_000
MAX_MASK_SHARE = .60
WORK_SIZE = 768


class PhotoEditError(ValueError):
    """An actionable, non-sensitive message that may be shown on the phone."""


def ready(app_dir=APP):
    root = Path(app_dir)
    base = root / BASE_MODEL.relative_to(APP)
    safety = root / SAFETY_MODEL.relative_to(APP)
    paths = [root/'venv_ai/Scripts/python.exe',
             base/'unet/diffusion_pytorch_model.safetensors',
             base/'vae/diffusion_pytorch_model.safetensors', base/'text_encoder/model.safetensors',
             safety/'model.safetensors', safety/'config.json', safety/'preprocessor_config.json',
             root/REMOVAL_MODEL.relative_to(APP),
             root/'models/body/yolox_m_humanart.onnx', root/'models/sensitive/640m.onnx',
             Path.home()/'.insightface/models/buffalo_l/det_10g.onnx']
    return all(p.is_file() and p.stat().st_size > 0 for p in paths)


def validate_options(params):
    if not isinstance(params, dict) or set(params) - {'operation','instruction','steps','seed','mask_normalized'}:
        raise PhotoEditError('Unsupported photo editing options.')
    operation = params.get('operation', 'replace')
    instruction = params.get('instruction', '')
    if operation not in ('remove','replace'):
        raise PhotoEditError('Choose Remove or Replace.')
    if not isinstance(instruction, str) or len(instruction) > 600:
        raise PhotoEditError('Describe the result in at most 600 characters.')
    text = unicodedata.normalize('NFKC', instruction)
    text = ''.join(c for c in text if unicodedata.category(c) != 'Cf').strip()
    if any(ord(c) < 32 and c not in '\n\t' for c in text):
        raise PhotoEditError('The description contains unsupported characters.')
    if operation == 'replace' and not text:
        raise PhotoEditError('Describe what should appear inside the selection.')
    if re.search(r'\b(?:nsfw|nudes?|nudity|naked|undress(?:ed|ing)?|porn\w*|genitals?|penis|vagina|nipples?|sex(?:ual)?|topless)\b|عري|عُري|عاري|عارية|خلع\s+الملابس|بدون\s+ملابس|إباح|اباح', text, re.I):
        raise PhotoEditError('This editor supports nonsexual background/object edits. People and clothing stay protected.')
    steps, seed = params.get('steps', 26), params.get('seed', -1)
    if type(steps) is not int or not 10 <= steps <= 40:
        raise PhotoEditError('Steps must be between 10 and 40.')
    if type(seed) is not int or not -1 <= seed <= 2**31-1:
        raise PhotoEditError('The seed is outside the supported range.')
    normalized = params.get('mask_normalized',False)
    if type(normalized) is not bool:
        raise PhotoEditError('mask_normalized must be true or false.')
    return dict(operation=operation,instruction=text,steps=steps,seed=seed,mask_normalized=normalized)


def read_inputs(image_path, mask_path, mask_normalized=False):
    with Image.open(image_path) as opened:
        if getattr(opened, 'n_frames', 1) != 1:
            raise PhotoEditError('Choose a still photo, not an animation or video.')
        if not 0 < opened.width * opened.height <= MAX_PIXELS:
            raise PhotoEditError('The photo exceeds the 40 megapixel limit.')
        photo = np.asarray(ImageOps.exif_transpose(opened).convert('RGBA')).copy()
    with Image.open(mask_path) as opened:
        if opened.format != 'PNG' or getattr(opened, 'n_frames', 1) != 1:
            raise PhotoEditError('The selection must be a single PNG mask.')
        if opened.size != (photo.shape[1], photo.shape[0]):
            mw,mh = opened.size
            h,w = photo.shape[:2]
            if not mask_normalized or max(mw,mh) > 4096 or abs(mw*h-mh*w) > 2*max(h,w):
                raise PhotoEditError('The selection does not match the upright photo dimensions.')
            # Phone selections use upright normalized coordinates. Keeping the
            # mask at preview size avoids full-resolution bitmap allocations.
            mask = cv2.resize(np.asarray(opened.convert('L')),(w,h),interpolation=cv2.INTER_NEAREST)
        else:
            mask = np.asarray(opened.convert('L'))
        mask = (mask >= 128).astype(np.uint8)
    count = int(mask.sum())
    if count < 16:
        raise PhotoEditError('Paint or draw a larger selection first.')
    if count > mask.size * MAX_MASK_SHARE:
        raise PhotoEditError('Select one object or a smaller background area (at most 60% of the photo).')
    return photo, mask


def protected_people(image_bgr):
    """CPU-only person/face/region detection; failures never mean 'no people'."""
    from body_detector import BodyAnalyzer
    from sensitive_detection import SensitiveDetector
    from insightface.app import FaceAnalysis
    face_dir = Path.home()/'.insightface/models/buffalo_l'
    if not (face_dir/'det_10g.onnx').is_file():
        raise PhotoEditError('The person-protection models are unavailable.')
    providers = ['CPUExecutionProvider']
    bodies = BodyAnalyzer(use_pose=False,providers=providers,allow_downloads=False,log=lambda _:None)
    if not bodies.available:
        raise PhotoEditError('The person-protection models are unavailable.')
    faces = FaceAnalysis(name='buffalo_l',allowed_modules=['detection'],providers=providers)
    faces.prepare(ctx_id=-1,det_size=(640,640),det_thresh=.35)
    found_faces = [f.bbox[:4].tolist() for f in faces.get(image_bgr)]
    found_bodies = bodies.analyze(image_bgr,score_thr=.25)
    found_bodies = bodies.recover_for_faces(image_bgr,found_faces,found_bodies,score_thr=.25)
    regions = SensitiveDetector(providers=providers).detect(image_bgr)
    boxes = [b.bbox[:4].tolist() for b in found_bodies]
    boxes.extend(found_faces)
    boxes.extend(r['bbox'] for r in regions)
    return boxes


def check_protection(mask, boxes):
    h, w = mask.shape
    for box in boxes:
        a = np.asarray(box, np.float64)
        if a.shape != (4,) or not np.isfinite(a).all():
            raise PhotoEditError('Person protection returned invalid geometry.')
        x1,y1,x2,y2 = a
        if x2 <= x1 or y2 <= y1:
            raise PhotoEditError('Person protection returned invalid geometry.')
        pad = max(4., min(x2-x1,y2-y1)*.05)
        x1,y1 = max(0,int(math.floor(x1-pad))), max(0,int(math.floor(y1-pad)))
        x2,y2 = min(w,int(math.ceil(x2+pad))), min(h,int(math.ceil(y2+pad)))
        if x2 <= x1 or y2 <= y1:
            raise PhotoEditError('Person protection returned invalid geometry.')
        if np.any(mask[y1:y2,x1:x2]):
            raise PhotoEditError('The selection overlaps a protected person. Select a background object or move the selection away from people.')


def prepare_crop(photo, mask):
    ys,xs = np.where(mask)
    h,w = mask.shape
    pad = max(48,int(max(xs.max()-xs.min()+1,ys.max()-ys.min()+1)*.25))
    x0,y0 = max(0,int(xs.min())-pad), max(0,int(ys.min())-pad)
    x1,y1 = min(w,int(xs.max())+pad+1), min(h,int(ys.max())+pad+1)
    crop, selected = photo[y0:y1,x0:x1,:3], mask[y0:y1,x0:x1]
    ch,cw = selected.shape
    scale = WORK_SIZE/max(ch,cw)
    rw,rh = max(1,round(cw*scale)), max(1,round(ch*scale))
    left,top = (WORK_SIZE-rw)//2,(WORK_SIZE-rh)//2
    resized = cv2.resize(crop,(rw,rh),interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC)
    canvas = cv2.copyMakeBorder(resized,top,WORK_SIZE-rh-top,left,WORK_SIZE-rw-left,cv2.BORDER_REFLECT_101)
    canvas_mask = np.zeros((WORK_SIZE,WORK_SIZE),np.uint8)
    canvas_mask[top:top+rh,left:left+rw] = cv2.resize(selected,(rw,rh),interpolation=cv2.INTER_NEAREST)*255
    return canvas,canvas_mask,(x0,y0,x1,y1,left,top,rw,rh)


def composite(photo, mask, rendered, geometry):
    if not isinstance(rendered,np.ndarray) or rendered.shape != (WORK_SIZE,WORK_SIZE,3) or rendered.dtype != np.uint8:
        raise PhotoEditError('The editor returned an invalid image.')
    x0,y0,x1,y1,left,top,rw,rh = geometry
    crop = cv2.resize(rendered[top:top+rh,left:left+rw],(x1-x0,y1-y0),interpolation=cv2.INTER_CUBIC)
    selected = mask[y0:y1,x0:x1]
    # The ramp lies INSIDE the selection, so no unselected pixel can change.
    distance = cv2.distanceTransform(np.pad(selected,1),cv2.DIST_L2,5)[1:-1,1:-1]
    feather = max(1.,min(8.,min(x1-x0,y1-y0)*.015))
    alpha = np.clip(distance/feather,0,1)[...,None]
    result = photo.copy()
    original = photo[y0:y1,x0:x1].astype(np.float32)
    replacement = np.concatenate([crop,np.full((*crop.shape[:2],1),255,np.uint8)],axis=2)
    result[y0:y1,x0:x1] = np.clip(np.rint(original*(1-alpha)+replacement*alpha),0,255).astype(np.uint8)
    if not np.array_equal(result[mask == 0],photo[mask == 0]):
        raise PhotoEditError('The edit changed pixels outside the selection.')
    return result


def png64(array):
    buffer = io.BytesIO()
    Image.fromarray(array).save(buffer,format='PNG')
    return base64.b64encode(buffer.getvalue()).decode('ascii')


def render_crop(image, mask, options, stopped):
    request = json.dumps(dict(image=png64(image),mask=png64(mask),**options)).encode('utf-8')
    with tempfile.TemporaryFile() as errors, ThreadPoolExecutor(max_workers=1) as pool:
        process = subprocess.Popen([str(WORKER_PYTHON),'-u',str(APP/'photo_edit_worker.py')],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,
            creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        pending = pool.submit(process.communicate,request)
        deadline = time.monotonic()+600
        try:
            while True:
                try:
                    output,_ = pending.result(timeout=.25)
                    break
                except TimeoutError:
                    if stopped() or time.monotonic() > deadline:
                        process.kill()
                        process.wait(timeout=10)
                        pending.result(timeout=10)
                        if stopped():
                            return None
                        raise PhotoEditError('The photo editor timed out.')
            if process.returncode != 0:
                raise PhotoEditError('The photo edit could not be generated. Try a different background selection or description.')
            if len(output) > 12*1024*1024:
                raise PhotoEditError('The photo editor returned too much data.')
            lines = [line[len(PREFIX):] for line in output.decode('utf-8').splitlines() if line.startswith(PREFIX)]
            if len(lines) != 1:
                raise PhotoEditError('The photo editor returned no image.')
            result = json.loads(lines[0])
            if result.get('safe') is not True:
                if result.get('reason') == 'description_too_long':
                    raise PhotoEditError('Shorten the description to a few clear words so the model can read all of it.')
                raise PhotoEditError('The requested result is not supported by this photo editor.')
            encoded = base64.b64decode(result['image'],validate=True)
            with Image.open(io.BytesIO(encoded)) as opened:
                if opened.size != (WORK_SIZE,WORK_SIZE):
                    raise PhotoEditError('The photo editor returned invalid dimensions.')
                return np.asarray(opened.convert('RGB')).copy()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)


def edit_photo(job, directory, report, stopped, *, finder=None, renderer=None):
    options = validate_options(job['params'])
    if stopped():
        return None
    report(.05,'Reading photo and selection')
    photo,mask = read_inputs(directory/'input.image',directory/'input.mask',options['mask_normalized'])
    report(.12,'Protecting people and faces')
    boxes = (finder or protected_people)(cv2.cvtColor(photo[:,:,:3],cv2.COLOR_RGB2BGR))
    check_protection(mask,boxes)
    if stopped():
        return None
    canvas,canvas_mask,geometry = prepare_crop(photo,mask)
    if options['seed'] == -1:
        options['seed'] = secrets.randbelow(2**31)
    report(.3,'Generating selected area')
    rendered = (renderer or render_crop)(canvas,canvas_mask,options,stopped)
    if rendered is None or stopped():
        return None
    report(.9,'Preserving original pixels outside the selection')
    result = composite(photo,mask,rendered,geometry)
    output = directory/'result.png'
    try:
        with Image.open(directory/'input.image') as source:
            profile = source.info.get('icc_profile')
        Image.fromarray(result).save(output,format='PNG',icc_profile=profile)
    except Exception:
        output.unlink(missing_ok=True)
        raise
    return dict(operation=options['operation'],seed=options['seed'],width=photo.shape[1],height=photo.shape[0],
                selected_pixels=int(mask.sum()),protected_people=len(boxes),outside_selection_unchanged=True,
                editor='masked_background_v1',steps=options['steps'])
