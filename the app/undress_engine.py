"""
Undress Engine — native SD 1.5 inpaint worker (no ControlNet).

Runs in venv_ai (Python 3.10) as a subprocess. Called by undress_core.UndressClient
from the main venv / job worker.

Pipeline: parse clothes at <=768 -> build masks -> lift them to native resolution
with an edge-aware filter -> repaint the garment region into a colour-matched base
that keeps the original folds and neckline -> inpaint a native-res crop at strength
~0.6 -> optional tiled refine pass at full resolution -> skin-match and composite.

The init base matters: at strength 1.0 the garment area starts from pure noise, and
with skin on every side the model frequently resolves it as bare skin rather than
fabric. Starting from a garment-shaped base removes that ambiguity.

ControlNet is deliberately absent: on a 6 GB laptop card it does not fit alongside
the inpaint UNet and the CLIP image encoder. Reference images are handled by
IP-Adapter instead, which is far cheaper.

Modes:
  python undress_engine.py           # one-shot: JSON on stdin, one result, exit
  python undress_engine.py --worker  # load models once, JSON-lines until EXIT
"""
from __future__ import annotations

import base64
import gc
import json
import os
import socket
import sys
import traceback
from io import BytesIO
from pathlib import Path

# Prevent downloads from hanging indefinitely on flaky connections
socket.setdefaulttimeout(15)

import cv2
import diffusers
import mediapipe as mp
import numpy as np
import torch
import torch.nn.functional as F
from PIL import Image
from diffusers import (
    StableDiffusionInpaintPipeline,
    StableDiffusionControlNetInpaintPipeline,
    StableDiffusionXLInpaintPipeline,
    ControlNetModel,
    UniPCMultistepScheduler,
)
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import ImageSegmenter, ImageSegmenterOptions
from transformers import AutoModelForSemanticSegmentation, SegformerImageProcessor

diffusers.utils.logging.disable_progress_bar()

from undress_core import (
    APP_DIR,
    CLOTHES_PARSER_ID,
    CONTROLNET_MODEL_ID,
    OPENPOSE_CONTROLNET_ID,
    OPENPOSE_DETECTOR_ID,
    SDXL_WORK_MAX_DIM,
    DEFAULT_REF_SCALE,
    DEFAULT_REFINE_STEPS,
    DEFAULT_REFINE_STRENGTH,
    INPAINT_MODEL_ID,
    SDXL_INPAINT_MODEL_ID,
    IP_ADAPTER_SUBFOLDER,
    IP_ADAPTER_WEIGHT_NAME,
    SDXL_IP_ADAPTER_SUBFOLDER,
    SDXL_IP_ADAPTER_WEIGHT_NAME,
    REFINE_OVERLAP,
    REFINE_TILE,
    build_inpaint_mask,
    clean_binary_mask,
    ensure_ip_adapter,
    ensure_local_model,
    exposed_skin_mask,
    DEFAULT_STRENGTH,
    fit_work_size,
    format_result_line,
    garment_base_init,
    garment_color_from_prompt,
    garment_inpaint_mask,
    hair_keep_mask,
    hands_keep_mask,
    harden_inpaint_mask,
    harmonize_generated_region,
    identity_keep_mask,
    limited_size,
    mask_crop_box,
    paste_crop_into,
    plan_refine_tiles,
    refine_mask_edges,
    scale_bbox,
    subtract_keep_soft,
    tile_blend_weights,
)

_SELFIE_SEGMENTER = APP_DIR / "models" / "selfie_segmenter.tflite"


def _emit(payload: dict) -> None:
    print(format_result_line(payload), flush=True)


def _img_to_b64(img: Image.Image) -> str:
    buf = BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")


def _person_mask_tasks(image_rgb: np.ndarray) -> np.ndarray:
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
    options = ImageSegmenterOptions(
        base_options=BaseOptions(model_asset_path=str(_SELFIE_SEGMENTER)),
        output_confidence_masks=True,
    )
    with ImageSegmenter.create_from_options(options) as segmenter:
        result = segmenter.segment(mp_image)
        confidence = result.confidence_masks[0].numpy_view()
    person = np.squeeze(confidence) > 0.5
    return (person.astype(np.uint8)) * 255


def _person_mask_solutions(image_rgb: np.ndarray) -> np.ndarray:
    with mp.solutions.selfie_segmentation.SelfieSegmentation(model_selection=1) as selfie_segmentation:
        results = selfie_segmentation.process(image_rgb)
        person = results.segmentation_mask > 0.5
    return (person.astype(np.uint8)) * 255


def generate_person_mask(image_pil: Image.Image) -> np.ndarray:
    image_rgb = np.array(image_pil.convert("RGB"))
    errors = []
    if _SELFIE_SEGMENTER.exists():
        try:
            return _person_mask_tasks(image_rgb)
        except Exception as e:
            errors.append(f"Tasks API: {e}")
            print(f"MediaPipe Tasks segmenter failed: {e}", file=sys.stderr)
    try:
        return _person_mask_solutions(image_rgb)
    except Exception as e:
        errors.append(f"solutions API: {e}")
        raise RuntimeError(
            "Person mask failed (" + "; ".join(errors) + "). "
            "Install mediapipe in venv_ai and/or run: python download_models.py selfie_segmenter"
        ) from e


def _hand_landmarks_xy(landmarks, width: int, height: int) -> np.ndarray:
    return np.array([[lm.x * width, lm.y * height] for lm in landmarks], np.float32)


def detect_hands_keep_mask(image_rgb: np.ndarray) -> np.ndarray:
    """Keep-mask covering palms and fingers. Empty if no hand is found."""
    h, w = image_rgb.shape[:2]
    hands: list[np.ndarray] = []
    try:
        try:
            detector = mp.solutions.hands.Hands(
                static_image_mode=True,
                max_num_hands=2,
                model_complexity=1,
                min_detection_confidence=0.35,
            )
        except TypeError:
            detector = mp.solutions.hands.Hands(
                static_image_mode=True,
                max_num_hands=2,
                min_detection_confidence=0.35,
            )
        with detector:
            result = detector.process(image_rgb)
        if result.multi_hand_landmarks:
            for hand in result.multi_hand_landmarks:
                hands.append(_hand_landmarks_xy(hand.landmark, w, h))
    except Exception as e:
        print(f"MediaPipe Hands failed: {e}", file=sys.stderr)

    if not hands:
        try:
            with mp.solutions.pose.Pose(
                static_image_mode=True,
                model_complexity=1,
                enable_segmentation=False,
                min_detection_confidence=0.4,
            ) as pose:
                result = pose.process(image_rgb)
            if result.pose_landmarks:
                lm = result.pose_landmarks.landmark
                # Wrists only. Pinky/index/thumb hulls stretch across the dress.
                for i in (15, 16):
                    p = lm[i]
                    if float(getattr(p, "visibility", 1.0)) < 0.45:
                        continue
                    hands.append(np.array([[p.x * w, p.y * h]], np.float32))
        except Exception as e:
            print(f"MediaPipe Pose hand fallback failed: {e}", file=sys.stderr)

    if not hands:
        print("No hands detected — fingers may still be kept via skin mask", file=sys.stderr)
        return np.zeros((h, w), np.uint8)
    print(f"Keeping {len(hands)} hand(s) from the original photo", file=sys.stderr)
    return hands_keep_mask((h, w), hands)


def load_image(payload: dict) -> Image.Image:
    if payload.get("image_path"):
        path = Path(payload["image_path"])
        if not path.exists():
            raise FileNotFoundError(f"input image not found: {path}")
        return Image.open(path).convert("RGB")
    if payload.get("image"):
        return Image.open(BytesIO(base64.b64decode(payload["image"]))).convert("RGB")
    raise ValueError("payload missing image_path and image")


def prepare_image(payload: dict):
    original = load_image(payload)
    orig_w, orig_h = original.size
    new_w, new_h = limited_size(orig_w, orig_h)
    if (new_w, new_h) != (orig_w, orig_h):
        work = original.resize((new_w, new_h), Image.LANCZOS)
    else:
        work = original
    face_bbox = payload.get("face_bbox") or payload.get("face_bbox")
    if face_bbox:
        if (new_w, new_h) != (orig_w, orig_h):
            face_bbox = scale_bbox(face_bbox, (orig_w, orig_h), (new_w, new_h))
        else:
            face_bbox = [int(v) for v in face_bbox]
    else:
        face_bbox = None
    return original, work, face_bbox


def parse_clothes(image_pil: Image.Image, processor, model) -> np.ndarray:
    inputs = processor(images=image_pil, return_tensors="pt")
    with torch.no_grad():
        logits = model(**inputs).logits
    up = F.interpolate(
        logits, size=image_pil.size[::-1], mode="bilinear", align_corners=False
    )
    return up.argmax(dim=1)[0].cpu().numpy().astype(np.uint8)


def get_sd15_pipeline(device: str, dtype):
    inpaint_src = ensure_local_model(INPAINT_MODEL_ID, "model_index.json")
    print(f"Loading SD1.5 Inpaint + ControlNet from {inpaint_src}...", file=sys.stderr)
    
    cnet_src = ensure_local_model(OPENPOSE_CONTROLNET_ID, "config.json")
    controlnet = ControlNetModel.from_pretrained(cnet_src, torch_dtype=dtype, local_files_only=True)
    
    pipe = StableDiffusionControlNetInpaintPipeline.from_pretrained(
        inpaint_src,
        controlnet=controlnet,
        torch_dtype=dtype,
        safety_checker=None,
        requires_safety_checker=False,
        local_files_only=True,
    )
    pipe.scheduler = UniPCMultistepScheduler.from_config(pipe.scheduler.config)

    ip_loaded = False
    ip_src = ensure_ip_adapter()
    if ip_src is not None:
        try:
            pipe.load_ip_adapter(
                str(ip_src),
                subfolder=IP_ADAPTER_SUBFOLDER,
                weight_name=IP_ADAPTER_WEIGHT_NAME,
            )
            pipe.set_ip_adapter_scale(0.0)
            ip_loaded = True
        except Exception as e:
            print(f"IP-Adapter unavailable: {e}", file=sys.stderr)

    if device == "cuda":
        # 6 GB cards: keep offload. Only the active submodule sits in VRAM.
        pipe.enable_model_cpu_offload()
        # Do NOT touch attention processors while IP-Adapter is attached. xformers and
        # attention-slicing both call set_attn_processor, which replaces IP-Adapter's
        # IPAdapterAttnProcessor. The plain processor then hits encoder_hidden_states
        # as a (text, image) tuple and dies with "tuple has no attribute shape".
        # torch 2.x already defaults to SDPA, so there is nothing to gain here anyway.
        if not ip_loaded:
            try:
                pipe.enable_xformers_memory_efficient_attention()
            except Exception:
                pass
        try:
            pipe.enable_vae_slicing()
        except Exception:
            pass
    else:
        pipe.to(device)
        
    pipe.set_progress_bar_config(disable=True)
    return pipe, ip_loaded


def get_sdxl_pipeline(device: str, dtype):
    inpaint_src = ensure_local_model(SDXL_INPAINT_MODEL_ID, "model_index.json")
    print(f"Loading SDXL Inpaint from {inpaint_src}...", file=sys.stderr)
    pipe = StableDiffusionXLInpaintPipeline.from_pretrained(
        inpaint_src,
        torch_dtype=dtype,
        variant="fp16",
        local_files_only=True,
    )

    ip_loaded = False
    # No IP-adapter loaded for SDXL in this multi-stage setup because it's only for the refiner step.
    
    if device == "cuda":
        pipe.to(device)
        try: pipe.enable_xformers_memory_efficient_attention()
        except Exception: pass
        try: pipe.enable_vae_slicing()
        except Exception: pass
    else:
        pipe.to(device)
        
    pipe.set_progress_bar_config(disable=True)
    return pipe


def load_global_models():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32
    if device != "cuda":
        print("WARNING: CUDA not available, running on CPU (will be very slow)", file=sys.stderr)

    parser_src = ensure_local_model(CLOTHES_PARSER_ID, "config.json")
    print(f"Loading clothes parser from {parser_src}...", file=sys.stderr)
    parser_proc = SegformerImageProcessor.from_pretrained(parser_src, local_files_only=True)
    parser = AutoModelForSemanticSegmentation.from_pretrained(parser_src, local_files_only=True)
    parser.eval()
    return device, dtype, parser_proc, parser


def _blurred_mask_pil(mask_u8: np.ndarray, blur_px: int = 11) -> Image.Image:
    m = np.where(mask_u8 > 127, 255, 0).astype(np.uint8)
    if blur_px > 0:
        k = int(blur_px) * 2 + 1
        if k % 2 == 0:
            k += 1
        m = cv2.GaussianBlur(m, (k, k), blur_px / 2.0)
    return Image.fromarray(m).convert("L")


def load_reference_images(payload: dict) -> list:
    """Optional garment/style references for IP-Adapter. Paths or base64, both work."""
    refs = payload.get("ref_images") or []
    out = []
    for item in refs:
        try:
            if isinstance(item, str) and Path(item).exists():
                out.append(Image.open(item).convert("RGB"))
            elif isinstance(item, str) and item:
                out.append(Image.open(BytesIO(base64.b64decode(item))).convert("RGB"))
        except Exception as e:
            print(f"Reference image skipped: {e}", file=sys.stderr)
    if out:
        print(f"Using {len(out)} reference image(s)", file=sys.stderr)
    return out


def build_ip_kwargs(pipe, payload: dict, ip_loaded: bool) -> dict:
    """Scale 0 plus a black tile is how a loaded adapter stays inert for one job."""
    if not ip_loaded:
        return {}
    refs = load_reference_images(payload)
    if refs:
        pipe.set_ip_adapter_scale(float(payload.get("ref_scale", DEFAULT_REF_SCALE)))
        # diffusers requires a list of lists when passing multiple images to a single adapter
        return {"ip_adapter_image": [refs]}
    pipe.set_ip_adapter_scale(0.0)
    return {"ip_adapter_image": [[Image.new("RGB", (224, 224), (0, 0, 0))]]}


def refine_tiles(pipe, image_np, mask_np, payload: dict, ip_kwargs: dict):
    """Low-strength pass at native resolution, tiled so VRAM stays flat.

    The first pass generates at <=768 and is then scaled up, which is what makes the
    garment look plastic. This re-denoises the pasted region at full resolution in
    fixed-size tiles, so fabric weave and shadow micro-contrast come back.
    """
    boxes = plan_refine_tiles(mask_np, tile=REFINE_TILE, overlap=REFINE_OVERLAP)
    if not boxes:
        return image_np
    strength = float(payload.get("refine_strength", DEFAULT_REFINE_STRENGTH))
    steps = int(payload.get("refine_steps", DEFAULT_REFINE_STEPS))
    guidance = float(payload.get("guidance_scale", 6.0))
    print(
        f"Refine pass: {len(boxes)} tile(s) strength={strength} steps={steps}",
        file=sys.stderr,
    )
    acc = np.zeros(image_np.shape, np.float32)
    wsum = np.zeros(image_np.shape[:2], np.float32)
    for i, (x0, y0, x1, y1) in enumerate(boxes, 1):
        tile_rgb = image_np[y0:y1, x0:x1]
        tile_mask = mask_np[y0:y1, x0:x1]
        th, tw = tile_rgb.shape[:2]
        gh, gw = (th // 8) * 8, (tw // 8) * 8
        if gh < 64 or gw < 64:
            continue
        tile_rgb = tile_rgb[:gh, :gw]
        tile_mask = tile_mask[:gh, :gw]
        if int(np.max(tile_mask)) <= 8:
            continue
        try:
            res = pipe(
                prompt=payload["prompt"],
                negative_prompt=payload["negative_prompt"],
                image=Image.fromarray(tile_rgb),
                mask_image=_blurred_mask_pil(tile_mask, blur_px=0),
                num_inference_steps=steps,
                guidance_scale=guidance,
                strength=strength,
                height=gh,
                width=gw,
                **ip_kwargs,
            )
        except Exception as e:
            print(f"Refine tile {i}/{len(boxes)} failed ({e}); keeping base pixels", file=sys.stderr)
            continue
        gen = np.array(res.images[0].convert("RGB"))
        if gen.shape[:2] != (gh, gw):
            gen = cv2.resize(gen, (gw, gh), interpolation=cv2.INTER_LANCZOS4)
        wt = tile_blend_weights(gh, gw, REFINE_OVERLAP // 2)
        acc[y0:y0 + gh, x0:x0 + gw] += gen.astype(np.float32) * wt[:, :, None]
        wsum[y0:y0 + gh, x0:x0 + gw] += wt
    covered = wsum > 1e-4
    if int(covered.sum()) == 0:
        return image_np
    out = image_np.astype(np.float32).copy()
    out[covered] = acc[covered] / wsum[covered][:, None]
    return np.clip(out, 0, 255).astype(np.uint8)


def generate(payload: dict, device: str, dtype, parser_proc, parser) -> dict:
    original, work, face_bbox = prepare_image(payload)
    print(
        f"Processing work {work.size[0]}x{work.size[1]} from original "
        f"{original.size[0]}x{original.size[1]}...",
        file=sys.stderr,
    )
    work_np = np.array(work.convert("RGB"))
    orig_np = np.array(original.convert("RGB"))
    hands_np = detect_hands_keep_mask(work_np)

    person_np = None
    parse_map = None
    try:
        print("Parsing clothes (SegFormer)...", file=sys.stderr)
        parse_map = parse_clothes(work, parser_proc, parser)
        try:
            person_np = generate_person_mask(work)
        except Exception as e:
            print(f"Person mask skipped for strap grow: {e}", file=sys.stderr)
        composite_mask = garment_inpaint_mask(
            parse_map,
            work_np,
            face_bbox=face_bbox,
            person_mask=person_np,
            extra_keep=hands_np,
        )
    except Exception as e:
        print(f"Clothes parser failed, using heuristic mask: {e}", file=sys.stderr)
        person_np = generate_person_mask(work)
        composite_mask = build_inpaint_mask(
            person_np, face_bbox, image_rgb=work_np, extra_keep=hands_np, feather_px=0
        )

    if parse_map is not None:
        hard_keep = identity_keep_mask(
            parse_map, face_bbox=face_bbox, extra_keep=hands_np, image_rgb=work_np
        )
    else:
        hair_np = (
            hair_keep_mask(work_np, np.full(work_np.shape[:2], 255, np.uint8), face_bbox)
            if face_bbox
            else np.zeros(work_np.shape[:2], np.uint8)
        )
        hard_keep = np.maximum(hands_np, hair_np)

    composite_mask = subtract_keep_soft(composite_mask, hard_keep, feather_px=3)
    composite_mask = clean_binary_mask(composite_mask)
    composite_mask = subtract_keep_soft(composite_mask, hard_keep, feather_px=3)
    model_mask = harden_inpaint_mask(composite_mask, hard_keep=hard_keep, dilate_px=2)
    model_mask = clean_binary_mask(model_mask)
    model_mask = subtract_keep_soft(model_mask, hard_keep, feather_px=2)
    if int(model_mask.max()) == 0:
        raise RuntimeError("Inpaint mask is empty (no clothing pixels). Try a fuller-body photo.")

    print("Refining masks at native resolution...", file=sys.stderr)
    full_model_mask = refine_mask_edges(model_mask, orig_np, radius=12, eps=1e-3, hard=True)
    paste_mask_work = harden_inpaint_mask(composite_mask, hard_keep=hard_keep, dilate_px=2)
    paste_mask_work = subtract_keep_soft(paste_mask_work, hard_keep, feather_px=2)
    full_paste_mask = refine_mask_edges(paste_mask_work, orig_np, radius=15, eps=1e-3, hard=False)

    seed = int(payload.get("seed", -1))
    generator = None
    if seed != -1:
        generator = torch.Generator(device="cpu").manual_seed(seed)

    steps = int(payload.get("steps", 26))
    guidance = float(payload.get("guidance_scale", 6.0))
    strength = float(payload.get("strength", DEFAULT_STRENGTH))

    box = mask_crop_box(full_model_mask, pad_frac=0.18)
    bx0, by0, bx1, by1 = box
    crop_rgb = orig_np[by0:by1, bx0:bx1]
    crop_mask = full_model_mask[by0:by1, bx0:bx1]
    ch, cw = crop_rgb.shape[:2]
    
    # ---------------- STAGE 1: SD 1.5 + ControlNet ----------------
    print(f"--- STAGE 1: SD 1.5 Structural Generation ---", file=sys.stderr)
    
    # Generate pose control image first to save memory
    from controlnet_aux import OpenposeDetector
    
    old_offline = os.environ.get("HF_HUB_OFFLINE")
    os.environ["HF_HUB_OFFLINE"] = "1"
    try:
        pose_model = OpenposeDetector.from_pretrained("lllyasviel/Annotators", local_files_only=True).to(device)
    finally:
        if old_offline is not None:
            os.environ["HF_HUB_OFFLINE"] = old_offline
        else:
            del os.environ["HF_HUB_OFFLINE"]
            
    control_image_full = pose_model(Image.fromarray(orig_np))
    control_image_crop = np.array(control_image_full)[by0:by1, bx0:bx1]
    
    del pose_model
    gc.collect()
    if device == "cuda":
        torch.cuda.empty_cache()
        
    pipe_sd15, ip_loaded = get_sd15_pipeline(device, dtype)
    ip_kwargs = build_ip_kwargs(pipe_sd15, payload, ip_loaded)
    
    gw_15, gh_15 = fit_work_size(cw, ch, 768)
    control_image_15 = Image.fromarray(control_image_crop).resize((gw_15, gh_15), Image.LANCZOS)
    
    if strength < 0.999:
        init_color = payload.get("init_color") or garment_color_from_prompt(payload["prompt"])
        init_np = garment_base_init(crop_rgb, crop_mask, target_rgb=tuple(init_color))
        print(f"Garment init base colour {tuple(init_color)} (strength {strength})", file=sys.stderr)
    else:
        # At strength 1.0 the init is fully destroyed, so building a base is wasted work.
        init_np = crop_rgb
    gen_in_15 = Image.fromarray(cv2.resize(init_np, (gw_15, gh_15), interpolation=cv2.INTER_LANCZOS4))
    gen_mask_15 = _blurred_mask_pil(
        cv2.resize(crop_mask, (gw_15, gh_15), interpolation=cv2.INTER_LINEAR), blur_px=3
    )
    result_15 = pipe_sd15(
        prompt=payload["prompt"],
        negative_prompt=payload["negative_prompt"],
        image=gen_in_15,
        mask_image=gen_mask_15,
        control_image=control_image_15,
        num_inference_steps=20, # Fast base gen
        generator=generator,
        guidance_scale=guidance,
        strength=1.0,
        height=gh_15,
        width=gw_15,
        **ip_kwargs,
    )
    base_gen = np.array(result_15.images[0].convert("RGB"))
    
    del pipe_sd15
    gc.collect()
    if device == "cuda":
        torch.cuda.empty_cache()

    if str(payload.get("refine", True)).lower() in ("true", "1", "yes"):
        # ---------------- STAGE 2: SDXL High-Res Refinement ----------------
        print(f"--- STAGE 2: SDXL High-Res Refinement ---", file=sys.stderr)
        pipe_sdxl = get_sdxl_pipeline(device, dtype)
        
        gw_xl, gh_xl = fit_work_size(cw, ch, SDXL_WORK_MAX_DIM)
        gen_in_xl = Image.fromarray(base_gen).resize((gw_xl, gh_xl), Image.LANCZOS)
        gen_mask_xl = _blurred_mask_pil(
            cv2.resize(crop_mask, (gw_xl, gh_xl), interpolation=cv2.INTER_LINEAR), blur_px=3
        )
        
        result_xl = pipe_sdxl(
            prompt=payload["prompt"],
            negative_prompt=payload["negative_prompt"],
            image=gen_in_xl,
            mask_image=gen_mask_xl,
            num_inference_steps=steps,
            generator=generator,
            guidance_scale=guidance,
            strength=strength,
            height=gh_xl,
            width=gw_xl,
        )
        gen_crop = np.array(result_xl.images[0].convert("RGB"))
        
        del pipe_sdxl
        gc.collect()
        if device == "cuda":
            torch.cuda.empty_cache()
            
        if gen_crop.shape[:2] != (ch, cw):
            gen_crop = cv2.resize(gen_crop, (cw, ch), interpolation=cv2.INTER_LANCZOS4)
    else:
        print("Skipping SDXL refinement pass for speed.", file=sys.stderr)
        gen_crop = base_gen
        if gen_crop.shape[:2] != (ch, cw):
            gen_crop = cv2.resize(gen_crop, (cw, ch), interpolation=cv2.INTER_LANCZOS4)
    gen_full = paste_crop_into(orig_np, gen_crop, box)

    if parse_map is not None:
        skin_np = (np.isin(parse_map, (12, 13, 14, 15)).astype(np.uint8)) * 255
    else:
        skin_np = exposed_skin_mask(
            work_np, person_np if person_np is not None else generate_person_mask(work), face_bbox
        )

    print("Matching skin and compositing at native resolution...", file=sys.stderr)
    output_np = harmonize_generated_region(orig_np, gen_full, full_paste_mask, skin_np)
    output = Image.fromarray(output_np)
    return {
        "success": True,
        "output_image": _img_to_b64(output),
        "mask_image": _img_to_b64(Image.fromarray(full_model_mask).convert("L")),
    }


def run_oneshot() -> None:
    payload = json.loads(sys.stdin.read())
    device, dtype, parser_proc, parser = load_global_models()
    _emit(generate(payload, device, dtype, parser_proc, parser))


def run_worker() -> None:
    device = dtype = parser_proc = parser = None
    print("Undress worker ready", file=sys.stderr)
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        if line == "EXIT":
            print("Undress worker exiting", file=sys.stderr)
            break
        try:
            payload = json.loads(line)
            if device is None:
                device, dtype, parser_proc, parser = load_global_models()
            _emit(generate(payload, device, dtype, parser_proc, parser))
        except Exception as e:
            _emit({
                "success": False,
                "error": str(e),
                "traceback": traceback.format_exc(),
            })


if __name__ == "__main__":
    try:
        if "--worker" in sys.argv:
            run_worker()
        else:
            run_oneshot()
    except Exception as e:
        _emit({
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc(),
        })
        sys.exit(1)
