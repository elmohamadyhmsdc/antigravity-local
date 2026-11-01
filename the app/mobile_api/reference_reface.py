"""Reference-guided, face-region-only image/video replacement.

This is a separate image-conditioned diffusion operation, not an ArcFace swapper
and not a CCIP-to-ArcFace conversion. Both source kinds use actual image pixels.
Video identities are used ONLY to locate the explicitly selected target.
Generation/temporal fidelity requires separate GPU acceptance.

API: reface_image_reference / reface_video_reference; inputs target and
source_reference (an explicitly chosen cropped face image). Boxes are normalized
xywh. target_regions entries are {frame: absolute_source_frame, boxes: [...]};
images require frame 0. Videos can instead use target_identity {model_id,
embedding}; known explicit frame entries override matching on those frames.
Without target_identity, explicit entries must cover every frame in the trim.

Only the installed local models are loaded. No body/clothing edit pipeline is
imported. CLI --locate runs in the existing main venv (CPU ONNX); --render runs
in existing venv_ai. All personal inputs/checkpoints remain in the owned job dir.
"""
from pathlib import Path
import base64
import json
import math
import os
import sys

import numpy as np

APP_DIR = Path(__file__).resolve().parent.parent
REFERENCE_TYPES = frozenset(("reface_image_reference", "reface_video_reference"))
IDENTITY_DIMS = {"buffalo_l@1": 512, "ccip-caformer24@1": 768}
MAX_VIDEO_FRAMES = 9000
MAX_IMAGE_PIXELS = 40_000_000
BASE_REL = Path("models/undress/Uminosachi--realisticVisionV51_v51VAE-inpainting")
ADAPTER_REL = Path("models/undress/h94--IP-Adapter")


def reference_reface_missing(app_dir=APP_DIR):
    root = Path(app_dir)
    required = [
        root / "venv/Scripts/python.exe", root / "venv_ai/Scripts/python.exe",
        root / BASE_REL / "model_index.json", root / BASE_REL / "unet/config.json",
        root / BASE_REL / "unet/diffusion_pytorch_model.safetensors",
        root / BASE_REL / "vae/config.json",
        root / BASE_REL / "vae/diffusion_pytorch_model.safetensors",
        root / BASE_REL / "text_encoder/config.json",
        root / BASE_REL / "text_encoder/model.safetensors",
        root / BASE_REL / "tokenizer/vocab.json", root / BASE_REL / "tokenizer/merges.txt",
        root / BASE_REL / "tokenizer/tokenizer_config.json",
        root / BASE_REL / "scheduler/scheduler_config.json",
        root / BASE_REL / "feature_extractor/preprocessor_config.json",
        root / ADAPTER_REL / "models/ip-adapter-plus_sd15.bin",
        root / ADAPTER_REL / "models/image_encoder/model.safetensors",
        root / ADAPTER_REL / "models/image_encoder/config.json",
        root / "models/anime_face_detect.onnx", root / "models/ccip_character.onnx",
    ]
    face_root = Path.home() / ".insightface/models/buffalo_l"
    required += [face_root / n for n in ("det_10g.onnx", "w600k_r50.onnx")]
    return [str(p) for p in required if not p.is_file() or p.stat().st_size == 0]


def reference_reface_ready(app_dir=APP_DIR):
    """Asset availability only; never a claim that inference/quality was tested."""
    return not reference_reface_missing(app_dir)


def _number(params, key, default, low, high, integer=False):
    value = params.get(key, default)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{key} must be a finite number")
    if not low <= value <= high or (integer and not isinstance(value, int)):
        raise ValueError(f"{key} is outside the supported range")
    return value


def normalized_box(box):
    if not isinstance(box, dict) or set(box) != {"x", "y", "w", "h"}:
        raise ValueError("A region must be normalized x/y/w/h")
    values = [box[k] for k in ("x", "y", "w", "h")]
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in values):
        raise ValueError("Region coordinates must be finite")
    x, y, w, h = map(float, values)
    if min(x, y) < 0 or min(w, h) <= 0 or x + w > 1.000001 or y + h > 1.000001:
        raise ValueError("A selected region must be inside the image")
    return dict(x=x, y=y, w=w, h=h)


def decode_identity(identity):
    if not isinstance(identity, dict) or set(identity) != {"model_id", "embedding"}:
        raise ValueError("Choose a target occurrence with its model-aware identity")
    model = identity["model_id"]
    if model not in IDENTITY_DIMS or not isinstance(identity["embedding"], str):
        raise ValueError("The target identity model is unsupported")
    try:
        raw = base64.b64decode(identity["embedding"], validate=True)
        if len(raw) != IDENTITY_DIMS[model] * 4:
            raise ValueError("Identity vector dimension does not match its model")
        vector = np.frombuffer(raw, dtype="<f4").copy()
    except (ValueError, TypeError) as exc:
        raise ValueError("The target identity embedding is invalid") from exc
    if not np.isfinite(vector).all() or np.linalg.norm(vector) < 1e-8:
        raise ValueError("The target identity must be finite and nonzero")
    return model, vector / np.linalg.norm(vector)


def validate_reference_reface(body, capabilities):
    from mobile_api.errors import ApiError, bad_request
    try:
        kind, params, inputs = body.get("type"), body.get("params"), body.get("inputs")
        if kind not in REFERENCE_TYPES or not isinstance(params, dict) or not isinstance(inputs, dict):
            raise ValueError("A supported reference-guided request is required")
        if set(inputs) != {"target", "source_reference"} or not all(isinstance(v, str) for v in inputs.values()):
            raise ValueError("Choose one target and one explicit source face crop")
        if params.get("experimental_acknowledged") is not True:
            raise ValueError("Reference-guided quality is experimental. Explicit experimental acknowledgment is required before running it.")
        allowed = {"source_kind", "target_kind", "target_regions", "target_identity", "seed", "steps",
                   "strength", "reference_scale", "start_time", "end_time", "initialization", "experimental_acknowledged"}
        if set(params) - allowed:
            raise ValueError("An unsupported reference-guided option was supplied")
        if params.get("source_kind") not in ("person", "character") or params.get("target_kind") not in ("person", "character"):
            raise ValueError("Source and target kinds must be person or character")
        if params.get("initialization", "target") not in ("target", "source_pixels"):
            raise ValueError("Choose target or source_pixels initialization")
        _number(params, "seed", 0, 0, 2**32 - 1, True)
        _number(params, "steps", 20, 5, 50, True)
        _number(params, "strength", .75, .1, 1)
        _number(params, "reference_scale", .8, 0, 1)
        start = _number(params, "start_time", 0, 0, 86400)
        end = _number(params, "end_time", start + 120, 0, 86400)
        if end <= start:
            raise ValueError("The trim end must follow its start")
        regions = params.get("target_regions", [])
        if not isinstance(regions, list) or len(regions) > MAX_VIDEO_FRAMES:
            raise ValueError("Too many explicit frame regions")
        seen = set()
        for item in regions:
            if not isinstance(item, dict) or set(item) != {"frame", "boxes"}:
                raise ValueError("A frame region needs frame and boxes")
            frame, boxes = item["frame"], item["boxes"]
            if isinstance(frame, bool) or not isinstance(frame, int) or frame < 0 or frame in seen:
                raise ValueError("Explicit frame numbers must be unique nonnegative integers")
            seen.add(frame)
            if not isinstance(boxes, list) or len(boxes) > 8:
                raise ValueError("Choose up to eight explicit face regions per frame")
            for box in boxes:
                normalized_box(box)
        video = kind == "reface_video_reference"
        if not video:
            if start or "end_time" in params or "target_identity" in params or len(regions) != 1 or regions[0]["frame"] != 0 or not regions[0]["boxes"]:
                raise ValueError("Photo replacement requires explicit face regions at frame zero")
        elif "target_identity" in params:
            model, _ = decode_identity(params["target_identity"])
            expected = "ccip-caformer24@1" if params["target_kind"] == "character" else "buffalo_l@1"
            if model != expected:
                raise ValueError("The target kind and identity model must agree")
        elif not regions:
            raise ValueError("Choose a target video identity or explicit frame regions")
    except (ValueError, TypeError, KeyError) as exc:
        raise bad_request(str(exc)) from exc
    if not capabilities.get("engines", {}).get("reface_reference", False):
        raise ApiError(409, "engine_unavailable", "Reference-guided face replacement is unavailable on this PC.")


def choose_target(identity, candidates):
    """Return one matched current-frame box, or none on absence/ambiguity.

    Similarity/margin are conservative starting gates, not calibrated accuracy.
    Candidates from another model space are never compared or converted.
    """
    model, vector = decode_identity(identity)
    ranked = []
    for c in candidates:
        if c.get("model_id") != model:
            continue
        other = np.asarray(c.get("embedding", []), dtype=np.float32).reshape(-1)
        if other.size != vector.size or not np.isfinite(other).all() or np.linalg.norm(other) < 1e-8:
            continue
        score = float(np.dot(vector, other / np.linalg.norm(other)))
        ranked.append((score, normalized_box(c["box"])))
    ranked.sort(key=lambda pair: pair[0], reverse=True)
    threshold = .80 if model == "ccip-caformer24@1" else .55
    if not ranked or ranked[0][0] < threshold:
        return [], "absent"
    if len(ranked) > 1 and ranked[0][0] - ranked[1][0] < .10:
        return [], "ambiguous"
    return [ranked[0][1]], "matched"


def _atomic_json(path, value):
    path = Path(path)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value), encoding="utf-8")
    os.replace(temp, path)


def _open_rgb(path):
    from PIL import Image, ImageOps
    with Image.open(path) as image:
        if image.width * image.height > MAX_IMAGE_PIXELS:
            raise ValueError("The selected image is too large")
        return ImageOps.exif_transpose(image).convert("RGB")


def _face_mask(size, box):
    from PIL import Image, ImageDraw, ImageFilter
    width, height = size
    b = normalized_box(box)
    bounds = (max(0, int(b["x"] * width)), max(0, int(b["y"] * height)),
              min(width, math.ceil((b["x"] + b["w"]) * width)),
              min(height, math.ceil((b["y"] + b["h"]) * height)))
    l, t, r, bottom = bounds
    if r - l < 8 or bottom - t < 8:
        raise ValueError("A selected face region is too small")
    hard = Image.new("L", size, 0)
    ImageDraw.Draw(hard).ellipse((l, t, r - 1, bottom - 1), fill=255)
    # Feather INWARD only: a blur must not change pixels beyond the requested mask.
    blurred = hard.filter(ImageFilter.GaussianBlur(max(1, min(r-l, bottom-t) * .04)))
    alpha = Image.fromarray((np.asarray(blurred, dtype=np.float32) * (np.asarray(hard) > 0)).astype(np.uint8))
    return bounds, hard, alpha


def apply_regions(image, source_reference, boxes, params, predictor):
    """Apply only explicit face ellipses; preserve every other decoded pixel."""
    from PIL import Image
    result = image.copy().convert("RGB")
    for box in boxes:
        bounds, hard, alpha = _face_mask(result.size, box)
        l, t, r, b = bounds
        pad = int(max(r-l, b-t) * .6)
        crop_box = (max(0, l-pad), max(0, t-pad), min(result.width, r+pad), min(result.height, b+pad))
        crop, crop_mask = result.crop(crop_box), hard.crop(crop_box)
        generated = predictor(crop, crop_mask, source_reference, params).convert("RGB")
        if generated.size != crop.size:
            generated = generated.resize(crop.size, Image.Resampling.LANCZOS)
        result.paste(Image.composite(generated, crop, alpha.crop(crop_box)), crop_box)
    return result


def seed_reference_pixels(crop, mask, reference, source_box):
    """Experimental bbox alignment only, not landmark/pose reconstruction."""
    from PIL import Image
    bounds = mask.getbbox()
    if bounds is None:
        return crop.copy()
    l, t, r, b = bounds
    box = normalized_box(source_box)
    sw, sh = reference.size
    source_bounds = (int(box["x"]*sw), int(box["y"]*sh),
                     min(sw, math.ceil((box["x"]+box["w"])*sw)),
                     min(sh, math.ceil((box["y"]+box["h"])*sh)))
    face = reference.crop(source_bounds).resize((r-l, b-t), Image.Resampling.LANCZOS)
    seeded = crop.copy()
    seeded.paste(Image.composite(face, crop.crop(bounds), mask.crop(bounds)), bounds)
    return seeded


def _pipeline_predictor(params):
    import torch
    from diffusers import StableDiffusionInpaintPipeline
    from transformers import CLIPVisionModelWithProjection
    if not torch.cuda.is_available():
        raise RuntimeError("Reference-guided generation requires the configured CUDA runtime")
    encoder = CLIPVisionModelWithProjection.from_pretrained(
        str(APP_DIR / ADAPTER_REL / "models/image_encoder"), torch_dtype=torch.float16,
        local_files_only=True, use_safetensors=True)
    pipe = StableDiffusionInpaintPipeline.from_pretrained(
        str(APP_DIR / BASE_REL), torch_dtype=torch.float16, image_encoder=encoder,
        local_files_only=True, safety_checker=None, requires_safety_checker=False)
    pipe.load_ip_adapter(str(APP_DIR / ADAPTER_REL), subfolder="models",
                         weight_name="ip-adapter-plus_sd15.bin", image_encoder_folder=None,
                         local_files_only=True)
    pipe.set_ip_adapter_scale(float(params.get("reference_scale", .8)))
    # Load the adapter before offload and keep its attention processors intact.
    pipe.enable_model_cpu_offload()
    pipe.vae.enable_slicing()
    cartoon = params["target_kind"] == "character"
    prompt = ("a neutral 2D anime cartoon face matching the reference appearance, drawn line art, cel shading, preserve the existing illustration style and lighting"
              if cartoon else "a neutral human face matching the reference appearance, preserve the existing lighting and photographic style")
    negative = ("photograph, photorealistic, realistic skin, distorted face, duplicate face, text, watermark"
                if cartoon else "anime, cartoon, illustration, distorted face, duplicate face, text, watermark")

    def predict(crop, mask, reference, _params):
        from PIL import Image
        ratio = min(768 / max(crop.size), 512 / min(crop.size))
        size = tuple(max(64, min(768, int(round(v * ratio / 8)) * 8)) for v in crop.size)
        initial = seed_reference_pixels(crop, mask, reference, params["_source_reference_box"]) if params.get("initialization") == "source_pixels" else crop
        result = pipe(prompt=prompt, negative_prompt=negative,
                      image=initial.resize(size, Image.Resampling.LANCZOS),
                      mask_image=mask.resize(size, Image.Resampling.NEAREST),
                      ip_adapter_image=reference, num_inference_steps=int(params.get("steps", 20)),
                      strength=float(params.get("strength", .75)), guidance_scale=7.5,
                      generator=torch.Generator(device="cpu").manual_seed(int(params.get("seed", 0))))
        return result.images[0].resize(crop.size, Image.Resampling.LANCZOS)
    return predict


def _video_info(path, params):
    import cv2
    cap = cv2.VideoCapture(str(path))
    try:
        if not cap.isOpened():
            raise ValueError("The target video cannot be opened")
        fps = float(cap.get(cv2.CAP_PROP_FPS))
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if not math.isfinite(fps) or fps <= 0 or total <= 0:
            raise ValueError("The target video has no valid frame rate or duration")
        first = round(float(params.get("start_time", 0)) * fps)
        end = min(total, round(float(params["end_time"]) * fps)) if "end_time" in params else total
        if first >= end or first < 0 or end-first > MAX_VIDEO_FRAMES:
            raise ValueError("Choose a nonempty range of at most 9000 video frames")
        width, height = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        if width <= 0 or height <= 0 or width * height > MAX_IMAGE_PIXELS:
            raise ValueError("The target video dimensions are invalid or too large")
        return dict(fps=fps, first=first, end=end, width=width, height=height)
    finally:
        cap.release()


def _cpu_onnx_instance(cls, model_path):
    """Reuse existing detector/embedder methods with CPU-only local sessions."""
    import onnxruntime as ort
    obj = cls.__new__(cls)
    obj.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    obj.input_name = obj.session.get_inputs()[0].name
    return obj


def _clamped_detection_box(xyxy, width, height):
    values = np.asarray(xyxy, dtype=np.float32).reshape(-1)
    if values.size < 4 or not np.isfinite(values[:4]).all():
        return None
    x1, x2 = np.clip(values[[0, 2]], 0, width)
    y1, y2 = np.clip(values[[1, 3]], 0, height)
    if x2-x1 < 8 or y2-y1 < 8:
        return None
    return dict(x=float(x1)/width, y=float(y1)/height,
                w=float(x2-x1)/width, h=float(y2-y1)/height)


def _target_detector(identity):
    model, _ = decode_identity(identity)
    if model == "buffalo_l@1":
        from insightface.app import FaceAnalysis
        home = Path.home() / ".insightface/models/buffalo_l"
        if not all((home / n).is_file() for n in ("det_10g.onnx", "w600k_r50.onnx")):
            raise FileNotFoundError("Local human face models are missing; downloads are disabled")
        app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition"], providers=["CPUExecutionProvider"])
        app.prepare(ctx_id=-1, det_size=(640, 640))
        from analysis import detect_faces

        def detect(frame):
            h, w = frame.shape[:2]
            found = []
            for face in detect_faces(app, frame):
                box = _clamped_detection_box(face.bbox, w, h)
                if box is not None:
                    found.append(dict(model_id=model, embedding=face.normed_embedding, box=box))
            return found
        return detect
    from anime_detector import AnimeFaceDetector, DEFAULT_SIZE
    from character_embedder import CcipEmbedder, asymmetric_ccip_crop
    detector = _cpu_onnx_instance(AnimeFaceDetector, APP_DIR / "models/anime_face_detect.onnx")
    shape = detector.session.get_inputs()[0].shape
    detector.size = shape[2] if len(shape) >= 4 and isinstance(shape[2], int) and shape[2] > 0 else DEFAULT_SIZE
    embedder = _cpu_onnx_instance(CcipEmbedder, APP_DIR / "models/ccip_character.onnx")

    def detect(frame):
        h, w = frame.shape[:2]
        found = []
        for face in detector.detect(frame):
            x1, y1, x2, y2 = face["bbox"]
            l, t, r, b = asymmetric_ccip_crop(face["bbox"], w, h)
            crop = frame[t:b, l:r]
            if not crop.size:
                continue
            found.append(dict(model_id=model, embedding=embedder.embed_crop(crop),
                              box=dict(x=x1/w, y=y1/h, w=(x2-x1)/w, h=(y2-y1)/h)))
        return found
    return detect


def locate_video(target, directory, params, detector=None, emit=lambda **kw: None):
    """Locate from CURRENT decoded frames; never interpolate stale boxes."""
    import cv2
    directory = Path(directory)
    info = _video_info(target, params)
    explicit = {entry["frame"]: entry["boxes"] for entry in params.get("target_regions", [])}
    identity = params.get("target_identity")
    if identity is None and any(i not in explicit for i in range(info["first"], info["end"])):
        raise ValueError("Explicit regions must cover every frame when no target identity is supplied")
    checkpoint = directory / "reference.regions.json"
    data = json.loads(checkpoint.read_text(encoding="utf-8")) if checkpoint.exists() else {"info": info, "frames": {}}
    if data["info"] != info:
        raise ValueError("The video checkpoint no longer matches the target")
    if identity is not None and detector is None:
        detector = _target_detector(identity)
    cap = cv2.VideoCapture(str(target))
    try:
        cap.set(cv2.CAP_PROP_POS_FRAMES, info["first"])
        for frame_index in range(info["first"], info["end"]):
            ok, frame = cap.read()
            if not ok or frame is None:
                raise ValueError("Video decode ended before the requested range")
            key = str(frame_index)
            if key in data["frames"]:
                continue
            if frame_index in explicit:
                boxes, status = explicit[frame_index], "explicit"
            else:
                boxes, status = choose_target(identity, detector(frame))
            data["frames"][key] = dict(boxes=boxes, status=status)
            _atomic_json(checkpoint, data)
            emit(stage="locating", progress=.05+.25*len(data["frames"])/(info["end"]-info["first"]), frame=frame_index)
    finally:
        cap.release()
    return data


def render_video_frames(target, source, directory, params, predictor, emit=lambda **kw: None):
    import cv2
    from PIL import Image
    directory = Path(directory)
    data = json.loads((directory / "reference.regions.json").read_text(encoding="utf-8"))
    info = data["info"]
    frames = directory / "reference.frames"
    frames.mkdir(exist_ok=True)
    cap = cv2.VideoCapture(str(target))
    edited, untouched = 0, 0
    try:
        cap.set(cv2.CAP_PROP_POS_FRAMES, info["first"])
        for index in range(info["first"], info["end"]):
            ok, bgr = cap.read()
            if not ok or bgr is None:
                raise ValueError("Video decode ended before all frames were rendered")
            image = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
            entry = data["frames"].get(str(index))
            if entry is None:
                raise ValueError("Target selection is missing for a video frame")
            boxes = entry["boxes"]
            path = frames / f"frame_{index:09d}.png"
            if path.exists():
                with Image.open(path) as previous:
                    if previous.size != image.size:
                        raise ValueError("A rendered frame checkpoint has invalid dimensions")
                    previous.verify()
            else:
                output = apply_regions(image, source, boxes, params, predictor)
                temporary = path.with_suffix(".tmp")
                output.save(temporary, format="PNG")
                os.replace(temporary, path)
            edited += bool(boxes)
            untouched += not boxes
            emit(stage="rendering", progress=.30+.64*(index-info["first"]+1)/(info["end"]-info["first"]),
                 frame=index, frames_done=index-info["first"]+1)
    finally:
        cap.release()
    if not edited:
        raise ValueError("The selected identity was absent or ambiguous throughout the video")
    return dict(info=info, edited_frames=edited, unchanged_frames=untouched,
                ambiguous_frames=sum(e["status"] == "ambiguous" for e in data["frames"].values()))


def _emit(**details):
    print("@@reference_reface " + json.dumps(details), flush=True)


def prepare_source_reference(directory, params):
    import cv2
    directory = Path(directory)
    model = "ccip-caformer24@1" if params["source_kind"] == "character" else "buffalo_l@1"
    vector = np.zeros(IDENTITY_DIMS[model], dtype="<f4")
    vector[0] = 1
    detector = _target_detector(dict(model_id=model, embedding=base64.b64encode(vector.tobytes()).decode("ascii")))
    image = cv2.imread(str(directory/"input.source_reference"))
    if image is None:
        raise ValueError("The source face crop cannot be decoded")
    candidates = detector(image)
    if len(candidates) != 1:
        raise ValueError("Source-pixel initialization requires exactly one detected source face")
    data = dict(box=candidates[0]["box"], model_id=model, alignment="bounding_box_only")
    _atomic_json(directory/"reference.source.json", data)
    return data


def _worker(mode, request_path):
    request = json.loads(Path(request_path).read_text(encoding="utf-8"))
    directory = Path(request["directory"])
    params = request["params"]
    if mode == "source":
        prepare_source_reference(directory, params)
        _emit(stage="preparing_source", progress=.02)
        return
    if mode == "locate":
        locate_video(directory/"input.target", directory, params, emit=_emit)
        return
    source = _open_rgb(directory/"input.source_reference")
    if params.get("initialization") == "source_pixels":
        params = dict(params, _source_reference_box=json.loads((directory/"reference.source.json").read_text(encoding="utf-8"))["box"])
    predictor = _pipeline_predictor(params)
    if request["type"] == "reface_image_reference":
        target = _open_rgb(directory/"input.target")
        output = apply_regions(target, source, params["target_regions"][0]["boxes"], params, predictor)
        temporary = directory / "result.tmp.png"
        output.save(temporary, format="PNG")
        os.replace(temporary, directory/"result.png")
        meta = dict(edited_regions=len(params["target_regions"][0]["boxes"]))
    else:
        meta = render_video_frames(directory/"input.target", source, directory, params, predictor, emit=_emit)
    _atomic_json(directory/"reference.render.json", meta)
    _emit(stage="rendered", progress=.95)


def run_reference_reface(job, directory, report, stopped):
    """Use the existing Studio compute guard, ownership, retention and ACK lifecycle."""
    from mobile_api.artifact_jobs import run_process
    directory = Path(directory)
    if not reference_reface_ready():
        raise FileNotFoundError("Reference-guided face replacement assets are missing")
    request_path = directory / "reference.request.json"
    _atomic_json(request_path, dict(type=job["type"], params=job["params"], directory=str(directory)))

    def progress(line):
        if not line.startswith("@@reference_reface "):
            return
        details = json.loads(line.split(" ", 1)[1])
        stage = details.pop("stage")
        value = float(details.pop("progress", 0))
        public = {"details": dict(stage=stage, engine="reference_guided", **details)}
        if stage == "rendering":
            public.update(last_frame=int(details["frame"]), frames_done=int(details["frames_done"]))
        message = "Preparing source face" if stage == "preparing_source" else "Locating selected identity" if stage == "locating" else "Rendering reference-guided face"
        report(value, message, **public)

    module_path = Path(__file__).resolve()
    if job["params"].get("initialization") == "source_pixels":
        code = run_process([str(APP_DIR/"venv/Scripts/python.exe"), str(module_path), "--source", str(request_path)],
                           directory, stopped, progress)
        if stopped():
            return None
        if code:
            raise RuntimeError("The explicit source face could not be prepared; see the job log")
    if job["type"] == "reface_video_reference":
        code = run_process([str(APP_DIR/"venv/Scripts/python.exe"), str(module_path), "--locate", str(request_path)],
                           directory, stopped, progress)
        if stopped():
            return None
        if code:
            raise RuntimeError("The selected video identity could not be located; see the job log")
    if stopped():
        return None
    code = run_process([str(APP_DIR/"venv_ai/Scripts/python.exe"), str(module_path), "--render", str(request_path)],
                       directory, stopped, progress)
    if stopped():
        return None
    if code:
        raise RuntimeError("Reference-guided face rendering failed; see the job log")
    meta = json.loads((directory/"reference.render.json").read_text(encoding="utf-8"))
    if job["type"] == "reface_video_reference":
        from ffmpeg_utils import _ffmpeg_exe, mux_audio
        from reface_video_io import validate_video
        info = meta.pop("info")
        output = directory / "result.mp4"
        count = info["end"]-info["first"]
        command = [_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", format(info["fps"], ".12g"),
                   "-start_number", str(info["first"]), "-i", str(directory/"reference.frames/frame_%09d.png"),
                   "-frames:v", str(count), "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-crf", "16",
                   "-pix_fmt", "yuv420p", "-an", str(output)]
        # A bounded subprocess uses the same cancellable monitor as the worker.
        if run_process(command, directory, stopped, lambda line: None):
            if stopped():
                return None
            raise RuntimeError("The reference-guided video could not be encoded")
        validate_video(output, count, info["fps"])
        meta["audio_preserved"] = mux_audio(output, str(directory/"input.target"),
                                             info["first"]/info["fps"], info["end"]/info["fps"])
        validate_video(output, count, info["fps"])
        meta.update(frames_done=count, fps=info["fps"])
    warnings = ["Reference guidance may not reproduce exact identity."]
    if job["type"] == "reface_video_reference":
        warnings.append("Video consistency has not been validated on the GPU.")
    return dict(meta, engine="reference_guided", identity_fidelity="unverified", temporal_quality="unverified",
                preservation="outside_face_mask_before_encoding", initialization=job["params"].get("initialization", "target"), warnings=warnings)


if __name__ == "__main__":
    if str(APP_DIR) not in sys.path:
        sys.path.insert(0, str(APP_DIR))
    if len(sys.argv) != 3 or sys.argv[1] not in ("--source", "--locate", "--render"):
        raise SystemExit("Use --locate or --render with an internal job request path")
    _worker(sys.argv[1][2:], sys.argv[2])
