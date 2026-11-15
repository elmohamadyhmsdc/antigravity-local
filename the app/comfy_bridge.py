"""Run the private ComfyUI photo editor under a Studio GPU job."""

import io
import json
import logging
import shutil
import time
from pathlib import Path
from uuid import uuid4

import httpx
import numpy as np
from PIL import Image

WORKSPACE = Path(__file__).resolve().parent / 'build/comfy-photo-edit'
WORKFLOW = Path(__file__).resolve().parent / 'workflows_api/sdxl_gguf_inpaint.json'
URL = 'http://127.0.0.1:8188'
MODEL_INPUTS = {'1': ('unet_name',), '2': ('clip_name1', 'clip_name2'), '3': ('vae_name',)}
log = logging.getLogger(__name__)


class ComfyError(RuntimeError):
    pass


def _request(client, method, path, **kwargs):
    response = client.request(method, path, **kwargs)
    response.raise_for_status()
    return response.json() if response.content else None


def _has_workspace(client):
    stats = _request(client, 'GET', '/system_stats')
    args = stats['system']['argv']
    for flag, directory in (('--input-directory', 'input'), ('--output-directory', 'output')):
        if flag not in args or Path(args[args.index(flag) + 1]).resolve() != WORKSPACE / directory:
            return False
    return any(device['type'] == 'cuda' for device in stats['devices'])


def ready():
    try:
        workflow = json.loads(WORKFLOW.read_text(encoding='utf-8'))
        with httpx.Client(base_url=URL, timeout=1, trust_env=False) as client:
            if not _has_workspace(client):
                return False
            for node_id, fields in MODEL_INPUTS.items():
                node = workflow[node_id]
                name = node['class_type']
                info = _request(client, 'GET', '/object_info/' + name)
                required = info[name]['input']['required']
                if any(node['inputs'][field] not in required[field][0] for field in fields):
                    return False
        return True
    except (httpx.HTTPError, OSError, ValueError, KeyError, TypeError, IndexError):
        return False


def _job_state(client, prompt_id):
    queue = _request(client, 'GET', '/queue')
    if any(item[1] == prompt_id for item in queue['queue_running']):
        return 'running'
    if any(item[1] == prompt_id for item in queue['queue_pending']):
        return 'queued'
    return None


def _stop_prompt(client, prompt_id):
    _request(client, 'POST', '/queue', json={'delete': [prompt_id]})
    _request(client, 'POST', '/interrupt', json={'prompt_id': prompt_id})
    deadline = time.monotonic() + 20
    while _job_state(client, prompt_id) is not None:
        if time.monotonic() >= deadline:
            return False
        time.sleep(.25)
    return True


def _result(client, entry, prompt_id, work_size):
    if entry['status']['status_str'] != 'success':
        errors = [data.get('exception_message', '') for event, data in entry['status']['messages']
                  if event == 'execution_error']
        log.warning('ComfyUI prompt %s failed: %s', prompt_id, errors)
        if any('defaultcpuallocator' in message.lower() for message in errors):
            raise ComfyError('The PC ran out of RAM while loading SDXL. Free memory or choose Realistic Vision.')
        if any('out of memory' in message.lower() for message in errors):
            raise ComfyError('SDXL ran out of GPU memory. Retry with Realistic Vision.')
        raise ComfyError('ComfyUI could not render this edit. Check the PC log, then retry.')
    image, = entry['outputs']['11']['images']
    if image['type'] != 'output' or image['subfolder'] != prompt_id:
        raise ComfyError('ComfyUI returned an unexpected output for this edit.')
    data = bytearray()
    with client.stream('GET', '/view', params=image) as response:
        response.raise_for_status()
        for chunk in response.iter_bytes():
            data.extend(chunk)
            if len(data) > 8 * 1024 * 1024:
                raise ComfyError('ComfyUI returned too much image data.')
    with Image.open(io.BytesIO(data)) as opened:
        if opened.size != (work_size, work_size):
            raise ComfyError('ComfyUI returned invalid image dimensions.')
        return np.asarray(opened.convert('RGB')).copy()


def render(image, mask, options, report, stopped, work_size):
    if stopped():
        return None
    prompt_id = str(uuid4())
    inputs = WORKSPACE / 'input' / prompt_id
    outputs = WORKSPACE / 'output' / prompt_id
    submitted = False
    finished = False
    with httpx.Client(base_url=URL, timeout=httpx.Timeout(8, connect=1), trust_env=False) as client:
        try:
            if not _has_workspace(client):
                raise ComfyError('Start the Gallary ComfyUI photo editor on the PC, then retry.')
            workflow = json.loads(WORKFLOW.read_text(encoding='utf-8'))
            inputs.mkdir()
            Image.fromarray(image).save(inputs / 'image.png')
            Image.fromarray((mask != 0).astype(np.uint8) * 255).save(inputs / 'mask.png')
            workflow['4']['inputs']['image'] = f'{prompt_id}/image.png'
            workflow['5']['inputs']['image'] = f'{prompt_id}/mask.png'
            workflow['6']['inputs']['text'] = options['instruction']
            if options.get('preserve_body_shape'):
                workflow['6']['inputs']['text'] += ', original body build and pose, natural skin texture and original lighting'
                workflow['7']['inputs']['text'] += ', exaggerated muscles, sculpted abs, plastic skin, stray garment logos, leftover cuffs'
            workflow['9']['inputs'].update(seed=options['seed'], steps=options['steps'], denoise=options['strength'])
            workflow['11']['inputs']['filename_prefix'] = f'{prompt_id}/edit'
            if stopped():
                return None
            submitted = True
            response = _request(client, 'POST', '/prompt', timeout=30,
                                json={'prompt_id': prompt_id, 'prompt': workflow})
            if response['prompt_id'] != prompt_id:
                raise ComfyError('ComfyUI returned an unexpected job ID.')
            deadline = time.monotonic() + 600
            last_state = None
            while not stopped():
                if time.monotonic() >= deadline:
                    raise ComfyError('The ComfyUI edit timed out. Retry or choose Realistic Vision.')
                try:
                    entry = _request(client, 'GET', f'/history/{prompt_id}').get(prompt_id)
                    state = _job_state(client, prompt_id) if entry is None else None
                except httpx.ReadTimeout:
                    continue  # A busy worker can delay polling without losing the submitted prompt.
                if entry is not None:
                    finished = True
                    if stopped():
                        return None
                    report(.85, 'Downloading the SDXL edit')
                    return _result(client, entry, prompt_id, work_size)
                if state != last_state:
                    if state == 'queued':
                        report(.35, 'Waiting for ComfyUI')
                    elif state == 'running':
                        report(.5, 'Rendering the selection with SDXL')
                    last_state = state
                time.sleep(.35)
            return None
        except httpx.HTTPStatusError as exc:
            request = exc.response.request
            if request.url.path == '/prompt' and exc.response.status_code == 400:
                submitted = False
                log.warning('ComfyUI rejected prompt %s: %s', prompt_id, exc.response.text[:1500])
                raise ComfyError('ComfyUI rejected this workflow. Check the PC model installation.') from exc
            raise ComfyError('ComfyUI could not complete the edit. Check the PC service, then retry.') from exc
        except (httpx.RequestError, OSError, ValueError, KeyError, TypeError, IndexError) as exc:
            if stopped():
                return None
            raise ComfyError('The ComfyUI photo editor is unavailable or returned an invalid result. Check the PC service, then retry.') from exc
        finally:
            try:
                if submitted and not finished:
                    finished = _stop_prompt(client, prompt_id)
                if submitted and finished:
                    _request(client, 'POST', '/history', json={'delete': [prompt_id]})
                    queue = _request(client, 'GET', '/queue')
                    if not queue['queue_running'] and not queue['queue_pending']:
                        _request(client, 'POST', '/free', json={'unload_models': True, 'free_memory': True})
            except (httpx.HTTPError, ValueError, KeyError, TypeError, IndexError):
                log.warning('ComfyUI cleanup could not reach the service for %s', prompt_id)
            shutil.rmtree(inputs, ignore_errors=True)
            if not submitted or finished:
                shutil.rmtree(outputs, ignore_errors=True)
