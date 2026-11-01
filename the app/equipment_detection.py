"""Local Florence object detection, isolated from ONNX/CUDA in venv_ai.

Object proximity is an editable association suggestion, never proof of use.
Images cross an anonymous pipe; no input files or personal results are kept.
Florence OD format: https://huggingface.co/microsoft/Florence-2-base
"""
import base64
import json
import math
import os
from pathlib import Path
import subprocess
import sys

import cv2

APP_DIR = Path(__file__).resolve().parent
MODEL_DIR = APP_DIR / "models" / "florence-2-base-nsfw-v2-ext"
WORKER_PYTHON = APP_DIR / "venv_ai" / "Scripts" / "python.exe"
VERSION = 1
PREFIX = "@@equipment "
EQUIPMENT = {
    "dumbbell", "barbell", "kettlebell", "weight", "weight plate", "exercise machine",
    "treadmill", "exercise bike", "bicycle", "motorcycle", "tennis racket", "racket",
    "baseball bat", "baseball glove", "sports ball", "ball", "basketball", "football",
    "soccer ball", "volleyball", "golf club", "hockey stick", "skateboard", "surfboard",
    "skis", "snowboard", "ski pole", "jump rope", "yoga mat", "resistance band",
    "boxing glove", "punching bag", "helmet", "paddle", "oar", "bat", "club",
    "guitar", "violin", "piano", "drum", "microphone", "camera", "phone", "cell phone",
    "laptop", "tablet", "book", "umbrella", "bottle", "cup", "mug", "backpack", "bag",
    "hammer", "screwdriver", "drill", "saw", "wrench", "scissors", "knife", "fork",
    "spoon", "pan", "pot", "brush", "broom", "mop", "vacuum cleaner", "rope",
    "walking stick", "cane", "crutch", "wheelchair", "stroller", "suitcase", "tool",
}
ALIASES = {"bike": "bicycle", "racquet": "racket", "tennis racquet": "tennis racket",
           "dumbbells": "dumbbell", "barbells": "barbell", "weights": "weight",
           "mobile phone": "phone", "smartphone": "phone"}


def model_path():
    return Path(os.environ.get("AG_EQUIPMENT_MODEL", str(MODEL_DIR)))


def model_available():
    return WORKER_PYTHON.is_file() and (model_path() / "model.safetensors").is_file()


def equipment_label(raw):
    label = " ".join(str(raw).lower().replace("_", " ").split())
    label = ALIASES.get(label, label)
    return label if label in EQUIPMENT else None


def _point_distance(x, y, box):
    return math.hypot(max(box[0] - x, 0, x - box[2]),
                      max(box[1] - y, 0, y - box[3]))


def associate_objects(objects, bodies, width, height):
    """Keep equipment in contact range; leave an ambiguous owner unassigned."""
    result = []
    for obj in objects[:100]:
        if not isinstance(obj, dict):
            continue
        label = equipment_label(obj.get("label"))
        box = obj.get("bbox")
        if label is None or not isinstance(box, (list, tuple)) or len(box) != 4:
            continue
        try:
            x1, y1, x2, y2 = map(float, box)
        except (ValueError, TypeError):
            continue
        if not all(math.isfinite(v) for v in (x1, y1, x2, y2)):
            continue
        x1, x2 = max(0, min(width, x1)), max(0, min(width, x2))
        y1, y2 = max(0, min(height, y1)), max(0, min(height, y2))
        if x2 - x1 < 2 or y2 - y1 < 2:
            continue
        box = (x1, y1, x2, y2)
        nearby = []
        for i, body in enumerate(bodies):
            bx1, by1, bx2, by2 = body["bbox"]
            scale = max(by2 - by1, bx2 - bx1, 1)
            points, scores = body.get("kpts"), body.get("kpt_scores")
            hands = [] if points is None or scores is None else [
                points[k] for k in (9, 10) if scores[k] >= 0.3]
            # Include the body/object overlap for bicycles, mats and large machines.
            ix = max(0, min(x2, bx2) - max(x1, bx1))
            iy = max(0, min(y2, by2) - max(y1, by1))
            overlap = ix * iy / min((x2-x1)*(y2-y1), max(1, (bx2-bx1)*(by2-by1)))
            hand_dist = min((_point_distance(p[0], p[1], box) / scale for p in hands), default=1)
            if hand_dist <= 0.18 or overlap >= 0.12:
                nearby.append((min(hand_dist, 0.3 * (1 - overlap)), i))
        if not nearby:
            continue
        nearby.sort()
        owner = nearby[0][1] if len(nearby) == 1 or nearby[1][0] - nearby[0][0] > 0.08 else None
        key = f"{label}:{round(x1/width*100)}:{round(y1/height*100)}:{round(x2/width*100)}:{round(y2/height*100)}"
        if any(r["object_key"] == key for r in result):
            continue
        result.append({"object_key": key, "label": label, "body_index": owner,
                       "bbox": {"x": x1/width, "y": y1/height, "w": (x2-x1)/width, "h": (y2-y1)/height}})
    return result


def detect_equipment(image, bodies, *, worker_command=None):
    if worker_command is None and not model_available():
        raise FileNotFoundError("The local equipment recognition model is unavailable")
    ok, encoded = cv2.imencode('.jpg', image)
    if not ok:
        raise ValueError("Image encoding failed")
    command = worker_command or [str(WORKER_PYTHON), '-u', str(Path(__file__).resolve()), '--worker']
    payload = json.dumps({"image": base64.b64encode(encoded).decode('ascii'), "model": str(model_path())})
    process = subprocess.run(command, input=payload, text=True, capture_output=True, timeout=240,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    if process.returncode != 0:
        raise RuntimeError("Equipment recognition worker failed")
    for line in reversed(process.stdout.splitlines()):
        if line.startswith(PREFIX):
            objects = json.loads(line[len(PREFIX):])
            if not isinstance(objects, list):
                raise ValueError("Invalid equipment response")
            h, w = image.shape[:2]
            return associate_objects(objects, bodies, w, h)
    raise RuntimeError("Equipment recognition returned no result")


def _worker():
    import io
    import torch
    from PIL import Image
    from florence_captioner import FlorenceCaptioner
    request = json.loads(sys.stdin.read())
    with Image.open(io.BytesIO(base64.b64decode(request['image']))) as opened:
        image = opened.convert('RGB')
    captioner = FlorenceCaptioner(model_path=request['model'], device=os.environ.get('AG_EQUIPMENT_DEVICE') or None)
    captioner._ensure_loaded()
    size = image.size
    inputs = captioner.processor(text='<OD>', images=image.resize((768, 768)), return_tensors='pt')
    inputs = {k: v.to(captioner.device) for k, v in inputs.items()}
    if captioner.device == 'cuda':
        inputs['pixel_values'] = inputs['pixel_values'].to(torch.float16)
    with torch.inference_mode():
        ids = captioner.model.generate(**inputs, max_new_tokens=768, num_beams=3, do_sample=False)
    text = captioner.processor.batch_decode(ids, skip_special_tokens=False)[0]
    parsed = captioner.processor.post_process_generation(text, task='<OD>', image_size=size)['<OD>']
    objects = [{"label": label, "bbox": box} for label, box in zip(parsed['labels'], parsed['bboxes'])]
    print(PREFIX + json.dumps(objects), flush=True)


if __name__ == '__main__' and '--worker' in sys.argv:
    _worker()
