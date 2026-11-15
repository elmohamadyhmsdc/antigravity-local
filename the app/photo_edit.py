"""Masked still-photo editing with face-core protection.

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
from types import SimpleNamespace

import cv2
import numpy as np
from PIL import Image, ImageOps

APP = Path(__file__).resolve().parent
V6_MODEL = APP / 'models/undress/andregn--Realistic_Vision_V6.0-inpainting'
V5_MODEL = APP / 'models/undress/Uminosachi--realisticVisionV51_v51VAE-inpainting'
BASE_MODEL = V6_MODEL if (V6_MODEL / 'unet/diffusion_pytorch_model.safetensors').exists() else V5_MODEL
CYBER_MODEL = APP / 'models/undress/CyberRealistic_FINAL_FP16.safetensors'
SDXL_MODEL = APP / 'models/undress/diffusers--stable-diffusion-xl-1.0-inpainting-0.1'
SAFETY_MODEL = APP / 'models/photo_edit/safety_checker'
REMOVAL_MODEL = APP / 'models/photo_edit/big-lama.pt'
WORKER_PYTHON = APP / 'venv_ai/Scripts/python.exe'
PREFIX = '@@photo_edit '
MAX_PIXELS = 40_000_000
MAX_MASK_SHARE = .60
MAX_REFERENCES = 3
WORK_SIZE = 768
WORK_SIZE_SDXL = 1024
WORK_SIZE_GUIDED = 512

MODEL_REALISTIC_VISION = 'realistic_vision'
MODEL_CYBER_REALISTIC = 'cyber_realistic'
MODEL_SDXL = 'sdxl'
MODEL_SDXL_GGUF = 'sdxl_gguf'
BUILTIN_MODELS = (MODEL_REALISTIC_VISION, MODEL_CYBER_REALISTIC, MODEL_SDXL)
SUPPORTED_MODELS = (*BUILTIN_MODELS, MODEL_SDXL_GGUF)
DEFAULT_MODEL = MODEL_REALISTIC_VISION


class PhotoEditError(ValueError):
    """An actionable, non-sensitive message that may be shown on the phone."""


def clothing_labels(instruction):
    """Resolve supported garment edits before starting the parser."""
    from photo_edit_worker import normalize_arabic

    text = normalize_arabic(instruction.casefold())
    upper = re.search(r'\b(?:shirts?|t-shirts?|tops?|jackets?|coats?|hoodies?|sweaters?|bare chest|shirtless|[وبل]?(?:ال)?(?:قميص|تيشيرت|بلوزه|جاكيت|معطف|صدر))\b', text)
    lower = re.search(r'\b(?:pants|trousers|jeans|shorts|trunks|skirts?|[وبل]?(?:ال)?(?:بنطلون|بنطال|شورت|جينز|جيبه|تنوره))\b', text)
    outfit = re.search(r'\b(?:swimwear|swimsuits?|outfits?|clothes|dresses?|[وبل]?(?:ال)?(?:مايوه|ملابس|هدوم|فستان|بدله))\b', text)
    if outfit or (upper and lower):
        return (4, 5, 6, 7, 8, 17)
    if upper:
        return (4,)
    if lower:
        return (5, 6, 8)
    raise PhotoEditError('For automatic selection, name the garment, such as shirt, trousers or swimwear.')


def ready(app_dir=APP):
    root = Path(app_dir)
    base = root / BASE_MODEL.relative_to(APP)
    paths = [root/'venv_ai/Scripts/python.exe',
             base/'unet/diffusion_pytorch_model.safetensors',
             base/'vae/diffusion_pytorch_model.safetensors', base/'text_encoder/model.safetensors',
             root/REMOVAL_MODEL.relative_to(APP),
             root/'models/body/yolox_m_humanart.onnx', root/'models/sensitive/640m.onnx',
             Path.home()/'.insightface/models/buffalo_l/det_10g.onnx']
    return all(p.is_file() and p.stat().st_size > 0 for p in paths)


def available_replace_models(app_dir=APP):
    from comfy_bridge import ready as comfy_ready

    models = [MODEL_REALISTIC_VISION]
    root = Path(app_dir)
    if (root / CYBER_MODEL.relative_to(APP)).is_file():
        models.append(MODEL_CYBER_REALISTIC)
    if (root / SDXL_MODEL.relative_to(APP) / 'model_index.json').is_file():
        models.append(MODEL_SDXL)
    if comfy_ready():
        models.append(MODEL_SDXL_GGUF)
    return models


def validate_options(params, *, guided=False):
    if not isinstance(params, dict) or set(params) - {'operation','instruction','steps','seed','mask_normalized','strength','model','preserve_body_shape','auto_body'}:
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
        if not guided:
            raise PhotoEditError('Describe what should appear inside the selection.')
        text = 'Match the appearance shown in the reference photos within the selection.'
    steps, seed = params.get('steps', 26), params.get('seed', -1)
    if type(steps) is not int or not 10 <= steps <= 40:
        raise PhotoEditError('Steps must be between 10 and 40.')
    if type(seed) is not int or not -1 <= seed <= 2**31-1:
        raise PhotoEditError('The seed is outside the supported range.')
    normalized = params.get('mask_normalized',False)
    if type(normalized) is not bool:
        raise PhotoEditError('mask_normalized must be true or false.')
    strength = params.get('strength', 0.75)
    if isinstance(strength, bool) or not isinstance(strength, (int, float)) or not 0.2 <= strength <= 1.0:
        raise PhotoEditError('Strength must be between 0.2 and 1.0.')
    model = params.get('model', DEFAULT_MODEL)
    if model not in SUPPORTED_MODELS:
        raise PhotoEditError(f"Model must be one of {', '.join(SUPPORTED_MODELS)}.")
    if model == MODEL_SDXL_GGUF and operation != 'replace':
        raise PhotoEditError('SDXL GGUF is available for Replace only.')
    preserve_shape = params.get('preserve_body_shape', False)
    auto_body = params.get('auto_body', False)
    if type(preserve_shape) is not bool or type(auto_body) is not bool:
        raise PhotoEditError('Body editing options must be true or false.')
    if (preserve_shape or auto_body) and operation != 'replace':
        raise PhotoEditError('Automatic selection and Keep body shape are available for Replace only.')
    if auto_body:
        clothing_labels(text)
    return dict(operation=operation,instruction=text,steps=steps,seed=seed,mask_normalized=normalized,strength=float(strength),model=model,
                preserve_body_shape=preserve_shape or auto_body, auto_body=auto_body)


def read_photo(image_path):
    with Image.open(image_path) as opened:
        if getattr(opened, 'n_frames', 1) != 1:
            raise PhotoEditError('Choose a still photo, not an animation or video.')
        if not 0 < opened.width * opened.height <= MAX_PIXELS:
            raise PhotoEditError('The photo exceeds the 40 megapixel limit.')
        return np.asarray(ImageOps.exif_transpose(opened).convert('RGBA')).copy()


def read_inputs(image_path, mask_path, mask_normalized=False):
    photo = read_photo(image_path)
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
        raise PhotoEditError('Select a smaller area (at most 60% of the photo).')
    return photo, mask


def protected_people(image_bgr):
    """CPU-only person/face detection; failures never mean 'no people'."""
    from body_detector import BodyAnalyzer
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
    return [b.bbox[:4].tolist() for b in found_bodies], found_faces


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
        # Geometry is verified. Overlapping clothing, body, or objects is permitted.


def protect_face_cores(mask, boxes, *, force=False):
    """Safeguard facial features (eyes, nose, mouth) against accidental brush overlap on clothes."""
    if not boxes:
        return mask
    safe_mask = mask.copy()
    h, w = mask.shape[:2]
    total_mask = int(safe_mask.sum())
    if total_mask == 0:
        return safe_mask
    for box in boxes:
        a = np.asarray(box, np.float64)
        if a.shape != (4,) or not np.isfinite(a).all():
            continue
        x1, y1, x2, y2 = a
        bw, bh = x2 - x1, y2 - y1
        if bw <= 0 or bh <= 0:
            continue
        # Only treat face boxes as faces (faces are roughly square, 0.5 <= bh/bw <= 1.7, and not tall bodies)
        aspect = bh / max(1.0, bw)
        if aspect > 1.7 or aspect < 0.5:
            continue
        if bh > h * 0.55:
            continue
        center = (int(round((x1 + x2) / 2)), int(round(y1 + bh * 0.48)))
        axes = (max(1, int(round(bw * 0.42))), max(1, int(round(bh * 0.44))))
        face_oval = np.zeros((h, w), np.uint8)
        cv2.ellipse(face_oval, center, axes, 0, 0, 360, 1, -1)
        overlap = int(np.count_nonzero(safe_mask & face_oval))
        # If the user is editing clothes/body (< 45% of the mask is inside the face), protect the face
        if overlap > 0 and (force or (overlap / total_mask) < 0.45):
            safe_mask[face_oval > 0] = 0
    return safe_mask


def prepare_crop(photo, mask, boxes=None, work_size=WORK_SIZE):
    ys, xs = np.where(mask)
    h, w = mask.shape
    # For standard photo resolutions, keep full context to preserve head, limbs, and natural anatomy
    if max(h, w) <= 1280:
        x0, y0, x1, y1 = 0, 0, w, h
    else:
        # For high-res photos, crop with generous margin including face/head context
        sel_w = xs.max() - xs.min() + 1
        sel_h = ys.max() - ys.min() + 1
        pad_x = max(64, int(sel_w * 0.6))
        pad_y = max(64, int(sel_h * 0.6))
        x0 = max(0, int(xs.min()) - pad_x)
        x1 = min(w, int(xs.max()) + pad_x + 1)
        y0 = max(0, int(ys.min()) - pad_y)
        y1 = min(h, int(ys.max()) + pad_y + 1)
        if boxes:
            for box in boxes:
                bx1, by1, bx2, by2 = [int(v) for v in box[:4]]
                if bx1 < x1 and bx2 > x0 and by1 < y1:
                    y0 = min(y0, max(0, by1 - 40))
                    x0 = min(x0, max(0, bx1 - 40))
                    x1 = max(x1, min(w, bx2 + 40))
    crop, selected = photo[y0:y1, x0:x1, :3], mask[y0:y1, x0:x1]
    ch, cw = selected.shape
    scale = work_size / max(ch, cw)
    rw, rh = max(1, round(cw * scale)), max(1, round(ch * scale))
    left, top = (work_size - rw) // 2, (work_size - rh) // 2
    resized = cv2.resize(crop, (rw, rh), interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC)
    canvas = cv2.copyMakeBorder(resized, top, work_size - rh - top, left, work_size - rw - left, cv2.BORDER_REPLICATE)
    canvas_mask = np.zeros((work_size, work_size), np.uint8)
    canvas_mask[top:top + rh, left:left + rw] = cv2.resize(selected, (rw, rh), interpolation=cv2.INTER_NEAREST) * 255
    return canvas, canvas_mask, (x0, y0, x1, y1, left, top, rw, rh)


def composite(photo, mask, rendered, geometry, work_size=WORK_SIZE, *, feather=None):
    if not isinstance(rendered,np.ndarray) or rendered.shape != (work_size,work_size,3) or rendered.dtype != np.uint8:
        raise PhotoEditError('The editor returned an invalid image.')
    x0,y0,x1,y1,left,top,rw,rh = geometry
    crop = cv2.resize(rendered[top:top+rh,left:left+rw],(x1-x0,y1-y0),interpolation=cv2.INTER_CUBIC)
    selected = mask[y0:y1,x0:x1]
    # The ramp lies INSIDE the selection, so no unselected pixel can change.
    distance = cv2.distanceTransform(np.pad(selected,1),cv2.DIST_L2,5)[1:-1,1:-1]
    if feather is None:
        feather = max(2.,min(14.,min(x1-x0,y1-y0)*.025))
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


def _invoke_worker(payload, stopped):
    request = json.dumps(payload).encode('utf-8')
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
            return base64.b64decode(result['image'], validate=True)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)


def render_crop(image, mask, options, stopped, work_size=WORK_SIZE, *, references=()):
    payload = dict(image=png64(image), mask=png64(mask), work_size=work_size, **options)
    if references:
        payload['references'] = [png64(reference) for reference in references]
    encoded = _invoke_worker(payload, stopped)
    if encoded is None:
        return None
    with Image.open(io.BytesIO(encoded)) as opened:
        if opened.size != (work_size, work_size):
            raise PhotoEditError('The photo editor returned invalid dimensions.')
        return np.asarray(opened.convert('RGB')).copy()


def body_outline_mask(bgr, bodies, selection):
    from outlines import OutlineEngine

    height, width = bgr.shape[:2]
    if selection is None:
        if len(bodies) != 1:
            raise PhotoEditError('Automatic selection needs one visible person. Use the brush for a group photo.')
        body = bodies[0]
    else:
        ranked = []
        for x1, y1, x2, y2 in bodies:
            left, right = max(0, int(x1)), min(width, math.ceil(x2))
            top, bottom = max(0, int(y1)), min(height, math.ceil(y2))
            coverage = int(selection[top:bottom, left:right].sum()) if right > left and bottom > top else 0
            if coverage:
                ranked.append((coverage, [x1, y1, x2, y2]))
        ranked.sort(key=lambda item: item[0], reverse=True)
        if not ranked or (len(ranked) > 1 and ranked[1][0] > ranked[0][0] / 3):
            raise PhotoEditError('Paint the area on one visible person to lock their outline.')
        body = ranked[0][1]

    engine = OutlineEngine(providers=['CPUExecutionProvider'])
    polygon, = engine.body_outlines(bgr, [SimpleNamespace(bbox=body)])
    if polygon is None or len(polygon) < 3 or not np.isfinite(polygon).all():
        raise PhotoEditError('The PC could not trace this person’s outline. Try another photo.')
    silhouette = np.zeros((height, width), np.uint8)
    cv2.fillPoly(silhouette, [np.rint(polygon).astype(np.int32)], 1)
    return silhouette


def automatic_clothing_mask(photo, silhouette, instruction, stopped):
    labels = clothing_labels(instruction)
    x, y, width, height = cv2.boundingRect(silhouette)
    if not width or not height:
        raise PhotoEditError('The PC could not trace this person’s outline.')
    scale = min(1., 1024 / max(width, height))
    size = max(1, round(width * scale)), max(1, round(height * scale))
    crop = cv2.resize(photo[y:y+height, x:x+width, :3], size, interpolation=cv2.INTER_AREA)
    encoded = _invoke_worker({'task': 'parse_clothes', 'image': png64(crop)}, stopped)
    if encoded is None:
        return None
    with Image.open(io.BytesIO(encoded)) as parsed:
        if parsed.size != size:
            raise PhotoEditError('The clothing parser returned an invalid mask.')
        garment = np.isin(np.asarray(parsed.convert('L')), labels).astype(np.uint8)
    selected = np.zeros_like(silhouette)
    selected[y:y+height, x:x+width] = cv2.resize(garment, (width, height), interpolation=cv2.INTER_NEAREST)
    radius = max(2, min(6, round(max(height, width) / 180)))
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * radius + 1, 2 * radius + 1))
    return cv2.dilate(cv2.morphologyEx(selected, cv2.MORPH_CLOSE, kernel), kernel) & silhouette


def _read_references(directory, count):
    images = []
    for index in range(count):
        try:
            with Image.open(directory/f'input.refs.{index:04d}') as opened:
                if getattr(opened, 'n_frames', 1) != 1 or not 0 < opened.width * opened.height <= MAX_PIXELS:
                    raise PhotoEditError('Choose a still reference photo under 40 megapixels.')
                photo = ImageOps.exif_transpose(opened).convert('RGB')
                photo.thumbnail((512, 512), Image.Resampling.LANCZOS)
                # Keep the entire selected crop within the vision encoder's square input.
                square = Image.new('RGB', (512, 512), (127, 127, 127))
                square.paste(photo, ((512 - photo.width) // 2, (512 - photo.height) // 2))
                images.append(np.asarray(square).copy())
        except (OSError, Image.DecompressionBombError) as exc:
            raise PhotoEditError('A reference photo could not be opened. Choose it again.') from exc
    return images


def edit_photo(job, directory, report, stopped, *, finder=None, renderer=None):
    count = len(job.get('request', {}).get('inputs', {}).get('refs', ()))
    options = validate_options(job['params'], guided=bool(count))
    if stopped():
        return None
    report(.05,'Reading photo and selection')
    if options['auto_body']:
        photo, mask = read_photo(directory/'input.image'), None
    else:
        photo, mask = read_inputs(directory/'input.image', directory/'input.mask', options['mask_normalized'])
    report(.12,'Protecting people and faces')
    bgr = cv2.cvtColor(photo[:,:,:3],cv2.COLOR_RGB2BGR)
    bodies, faces = protected_people(bgr) if finder is None else ([], finder(bgr))
    boxes = [*bodies, *faces]
    if options['preserve_body_shape']:
        report(.16, 'Tracing the original body outline')
        silhouette = body_outline_mask(bgr, bodies, mask)
        if options['auto_body']:
            report(.2, 'Selecting clothing from the description')
            mask = automatic_clothing_mask(photo, silhouette, options['instruction'], stopped)
            if mask is None:
                return None
            if int(mask.sum()) < 16:
                raise PhotoEditError('Could not find the described clothing. Try the brush or name a visible garment.')
            if int(mask.sum()) > mask.size * MAX_MASK_SHARE:
                raise PhotoEditError('The automatic area is too large. Use the brush to narrow the edit.')
        interior = cv2.erode(silhouette, np.ones((3, 3), np.uint8), borderType=cv2.BORDER_CONSTANT, borderValue=0)
        mask &= interior
    check_protection(mask,boxes)
    mask = protect_face_cores(mask, faces, force=bool(count) or options['preserve_body_shape'])
    if not mask.any():
        raise PhotoEditError('No editable area remains. Choose clothing or an area inside the body outline, away from the face.')
    if stopped():
        return None
    work_size = WORK_SIZE
    if count:
        work_size = WORK_SIZE_GUIDED
    elif options['model'] in (MODEL_SDXL, MODEL_SDXL_GGUF):
        work_size = WORK_SIZE_SDXL
    canvas,canvas_mask,geometry = prepare_crop(photo,mask,boxes,work_size=work_size)
    if options['seed'] == -1:
        options['seed'] = secrets.randbelow(2**31)
    references = ()
    if count:
        report(.22, 'Reading visual references')
        references = _read_references(directory, count)
    report(.3,'Generating selected area')
    if renderer is None and options['model'] == MODEL_SDXL_GGUF:
        from comfy_bridge import ComfyError, render
        from photo_edit_worker import translate_instruction

        comfy_options = dict(options, instruction=translate_instruction(options['instruction']))
        try:
            rendered = render(canvas, canvas_mask, comfy_options, report, stopped, work_size)
        except ComfyError as exc:
            raise PhotoEditError(str(exc)) from exc
    elif renderer is not None:
        rendered = renderer(canvas, canvas_mask, options, stopped)
    elif references:
        rendered = render_crop(canvas, canvas_mask, options, stopped, work_size=work_size, references=references)
    else:
        rendered = render_crop(canvas, canvas_mask, options, stopped, work_size=work_size)
    if rendered is None or stopped():
        return None
    report(.9,'Preserving original pixels outside the selection')
    result = composite(photo, mask, rendered, geometry, work_size=work_size,
                       feather=2. if options['preserve_body_shape'] else None)
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
                editor='masked_background_v1',steps=options['steps'],model=options['model'],
                reference_count=count, automatic_selection=options['auto_body'],
                body_outline_preserved=options['preserve_body_shape'])
