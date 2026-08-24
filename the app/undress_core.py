"""
Magic Undress — shared helpers used by the Streamlit UI (main venv) and
undress_engine.py (venv_ai). No torch, no diffusers: numpy / OpenCV / PIL only.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path
from queue import Empty, Queue
from typing import Any, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw

RESULT_MARKER = "__UNDRESS_RESULT__"

APP_DIR = Path(__file__).parent
VENV_AI_PYTHON = APP_DIR / "venv_ai" / "Scripts" / "python.exe"
UNDRESS_SCRIPT = APP_DIR / "undress_engine.py"
OUTPUT_DIR = APP_DIR / "outputs" / "undress"
INPUT_DIR = APP_DIR / "outputs" / "undress_input"

DEFAULT_PROMPT = (
    "raw photo of the same woman, brand new white strapless summer dress, "
    "smooth fabric, natural red-carpet lighting, matching her real skin tone, "
    "photorealistic, sharp details, film grain"
)
DEFAULT_NEGATIVE_PROMPT = (
    "black dress, lace overlay, ruffles, spaghetti straps, original clothes, "
    "brown melted fabric, leftover garment, mixed two dresses, "
    "watermark, text, logo, getty, stock photo banner, "
    "deformed hands, extra fingers, fused fingers, "
    "anime, cartoon, painting, blurry, low quality, bad anatomy, 3d render"
)

INPAINT_MODEL_ID = "Uminosachi/realisticVisionV51_v51VAE-inpainting"
CONTROLNET_MODEL_ID = "lllyasviel/control_v11p_sd15_inpaint"
OPENPOSE_CONTROLNET_ID = "lllyasviel/control_v11p_sd15_openpose"
OPENPOSE_DETECTOR_ID = "lllyasviel/ControlNet"
CLOTHES_PARSER_ID = "mattmdjaga/segformer_b2_clothes"
WORK_MAX_DIM = 768
UNDRESS_MODELS_DIR = APP_DIR / "models" / "undress"
_HF_IGNORE = ("*.bin", "*.msgpack", "*.h5", "*.ot", "*.md", ".gitattributes")

# IP-Adapter (optional): reference images steer the generated garment.
IP_ADAPTER_REPO_ID = "h94/IP-Adapter"
IP_ADAPTER_SUBFOLDER = "models"
IP_ADAPTER_WEIGHT_NAME = "ip-adapter-plus_sd15.bin"
DEFAULT_REF_SCALE = 0.6

# Tiled high-res refine pass: flat VRAM cost regardless of image size.
REFINE_TILE = 768
REFINE_OVERLAP = 128
DEFAULT_REFINE_STRENGTH = 0.28
DEFAULT_REFINE_STEPS = 28

# Below 1.0 the garment region starts from a colour-matched base instead of noise.
DEFAULT_STRENGTH = 0.6


def hf_cache_snapshot(repo_id: str, marker: str) -> Optional[Path]:
    """Return a complete-enough local snapshot folder, or None."""
    bundled = UNDRESS_MODELS_DIR / repo_id.replace("/", "--")
    if (bundled / marker).is_file():
        return bundled
    name = "models--" + repo_id.replace("/", "--")
    snaps = Path.home() / ".cache" / "huggingface" / "hub" / name / "snapshots"
    if not snaps.is_dir():
        return None
    found: List[Path] = []
    for snap in snaps.iterdir():
        if snap.is_dir() and (snap / marker).exists():
            found.append(snap)
    if not found:
        return None
    return sorted(found, key=lambda p: p.stat().st_mtime, reverse=True)[0]


def ensure_local_model(repo_id: str, marker: str) -> str:
    """Prefer a disk folder so huggingface_hub 1.x cannot demand Hub metadata."""
    existing = hf_cache_snapshot(repo_id, marker)
    if existing is not None:
        return str(existing)
    from huggingface_hub import snapshot_download

    dest = UNDRESS_MODELS_DIR / repo_id.replace("/", "--")
    dest.mkdir(parents=True, exist_ok=True)
    return snapshot_download(
        repo_id,
        local_dir=str(dest),
        ignore_patterns=list(_HF_IGNORE),
    )


def ensure_ip_adapter(repo_id: str = IP_ADAPTER_REPO_ID) -> Optional[Path]:
    """Local snapshot of the SD1.5 IP-Adapter weights plus its CLIP image encoder.

    Fetched with an explicit allow-list: the shared `_HF_IGNORE` excludes `*.bin`,
    which is exactly the file this adapter ships as.
    """
    marker = f"{IP_ADAPTER_SUBFOLDER}/{IP_ADAPTER_WEIGHT_NAME}"
    existing = hf_cache_snapshot(repo_id, marker)
    if existing is not None:
        return existing
    try:
        from huggingface_hub import snapshot_download

        dest = UNDRESS_MODELS_DIR / repo_id.replace("/", "--")
        dest.mkdir(parents=True, exist_ok=True)
        path = snapshot_download(
            repo_id,
            local_dir=str(dest),
            allow_patterns=[
                f"{IP_ADAPTER_SUBFOLDER}/{IP_ADAPTER_WEIGHT_NAME}",
                f"{IP_ADAPTER_SUBFOLDER}/image_encoder/*",
            ],
        )
        return Path(path)
    except Exception as e:
        print(f"IP-Adapter download skipped: {e}", file=sys.stderr)
        return None


# ATR labels used by mattmdjaga/segformer_b2_clothes
PARSE_CLOTHES_IDS = (4, 5, 6, 7, 8, 17)  # upper, skirt, pants, dress, belt, scarf
PARSE_KEEP_IDS = (1, 2, 3, 9, 10, 11, 12, 13, 14, 15, 16)  # hat, hair, glasses, shoes, face, limbs, bag

SETUP_INSTRUCTIONS = """
**Setup (once):** from the `the app` folder run:

```
py -3.10 -m venv venv_ai
venv_ai\\Scripts\\activate.bat
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements_ai.txt
```

First generation downloads the inpaint checkpoint and the clothes parser into
the Hugging Face cache (several GB). Stay on the network for that run.
""".strip()

_shared_client: Optional["UndressClient"] = None


def format_result_line(payload: Dict[str, Any]) -> str:
    return RESULT_MARKER + json.dumps(payload)


def parse_result_stdout(stdout: str) -> Dict[str, Any]:
    if not stdout:
        raise ValueError("empty undress engine output (missing result marker)")
    chosen = None
    for line in stdout.splitlines():
        stripped = line.strip()
        if stripped.startswith(RESULT_MARKER):
            chosen = stripped[len(RESULT_MARKER):]
    if chosen is None:
        raise ValueError(
            f"undress engine output missing {RESULT_MARKER} marker"
        )
    return json.loads(chosen)


def limited_size(
    width: int,
    height: int,
    max_dim: int = WORK_MAX_DIM,
    multiple: int = 64,
) -> Tuple[int, int]:
    width, height = int(width), int(height)
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid size {width}x{height}")
    scale = min(max_dim / width, max_dim / height, 1.0)
    if min(width * scale, height * scale) < multiple:
        scale = min(max_dim / width, max_dim / height, multiple / min(width, height))
    nw = int(round(width * scale / multiple)) * multiple
    nh = int(round(height * scale / multiple)) * multiple
    cap = (max_dim // multiple) * multiple
    nw = max(multiple, min(nw, cap))
    nh = max(multiple, min(nh, cap))
    return nw, nh


def fit_work_size(
    width: int,
    height: int,
    max_dim: int = WORK_MAX_DIM,
    multiple: int = 64,
) -> Tuple[int, int]:
    """Scale a crop up or down so the long side uses max_dim, aligned to multiple."""
    width, height = max(1, int(width)), max(1, int(height))
    scale = min(max_dim / width, max_dim / height)
    nw = int(round(width * scale / multiple)) * multiple
    nh = int(round(height * scale / multiple)) * multiple
    cap = (max_dim // multiple) * multiple
    nw = max(multiple, min(nw, cap))
    nh = max(multiple, min(nh, cap))
    return nw, nh


def scale_bbox(
    bbox: Sequence[float],
    src_size: Tuple[int, int],
    dst_size: Tuple[int, int],
) -> List[int]:
    src_w, src_h = src_size
    dst_w, dst_h = dst_size
    x1, y1, x2, y2 = bbox
    return [
        int(x1 * dst_w / src_w),
        int(y1 * dst_h / src_h),
        int(x2 * dst_w / src_w),
        int(y2 * dst_h / src_h),
    ]


def expand_head_bbox(
    bbox: Sequence[float],
    img_w: int,
    img_h: int,
    pad_x: float = 0.18,
    pad_up: float = 0.22,
    pad_down: float = 0.08,
) -> Tuple[int, int, int, int]:
    x1, y1, x2, y2 = [float(v) for v in bbox]
    bw, bh = max(1.0, x2 - x1), max(1.0, y2 - y1)
    x1 = int(x1 - bw * pad_x)
    x2 = int(x2 + bw * pad_x)
    y1 = int(y1 - bh * pad_up)
    y2 = int(y2 + bh * pad_down)
    x1 = max(0, x1)
    y1 = max(0, y1)
    x2 = min(img_w, x2)
    y2 = min(img_h, y2)
    return x1, y1, x2, y2


def _as_gray_u8(mask) -> np.ndarray:
    arr = np.asarray(mask)
    if arr.ndim == 3:
        arr = arr[:, :, 0]
    return arr


def _filled_ellipse(shape_hw, bbox) -> np.ndarray:
    h, w = shape_hw
    out = np.zeros((h, w), np.uint8)
    x1, y1, x2, y2 = [int(v) for v in bbox]
    cx = (x1 + x2) // 2
    cy = (y1 + y2) // 2
    ax = max(1, (x2 - x1) // 2)
    ay = max(1, (y2 - y1) // 2)
    cv2.ellipse(out, (cx, cy), (ax, ay), 0, 0, 360, 255, -1)
    return out


def _ycrcb_skin_gate(ycrcb: np.ndarray) -> np.ndarray:
    """Loose YCrCb skin band; excludes near-neutral whites/grays (typical fabric)."""
    y, cr, cb = ycrcb[:, :, 0], ycrcb[:, :, 1], ycrcb[:, :, 2]
    chroma = np.abs(cr - 128.0) + np.abs(cb - 128.0)
    return (cr > 133) & (cr < 185) & (cb > 77) & (cb < 135) & (y > 40) & (y < 245) & (chroma > 12)


_HAND_FINGERS = (
    (1, 2, 3, 4),
    (5, 6, 7, 8),
    (9, 10, 11, 12),
    (13, 14, 15, 16),
    (17, 18, 19, 20),
)
_HAND_PALM = (0, 1, 5, 9, 13, 17)


def hands_keep_mask(shape_hw, hands_xy: Sequence) -> np.ndarray:
    """Keep palm + finger strokes. Does not fill the gaps between spread fingers."""
    h, w = shape_hw
    out = np.zeros((h, w), np.uint8)
    min_side = min(h, w)
    for hand in hands_xy:
        pts = np.asarray(hand, np.float32).reshape(-1, 2)
        if pts.shape[0] < 1:
            continue
        pts_i = np.round(pts).astype(np.int32)
        pts_i[:, 0] = np.clip(pts_i[:, 0], 0, w - 1)
        pts_i[:, 1] = np.clip(pts_i[:, 1], 0, h - 1)
        if pts_i.shape[0] >= 21:
            palm = pts_i[list(_HAND_PALM)]
            palm_span = max(
                float(palm[:, 0].max() - palm[:, 0].min()),
                float(palm[:, 1].max() - palm[:, 1].min()),
                8.0,
            )
            thickness = int(np.clip(palm_span * 0.20, 3, max(3, 0.028 * min_side)))
            radius = int(np.clip(palm_span * 0.12, 3, max(3, 0.022 * min_side)))
            cv2.fillConvexPoly(out, cv2.convexHull(palm), 255)
            for chain in _HAND_FINGERS:
                cv2.polylines(out, [pts_i[list(chain)]], False, 255, thickness, cv2.LINE_AA)
            for x, y in pts_i:
                cv2.circle(out, (int(x), int(y)), radius, 255, -1)
        else:
            radius = max(8, int(0.035 * min_side))
            for x, y in pts_i:
                cv2.circle(out, (int(x), int(y)), radius, 255, -1)
    ksz = max(5, (int(0.022 * min_side) | 1))
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz))
    return cv2.dilate(out, k, iterations=1)


def torso_garment_mask(
    person_mask_uint8: np.ndarray,
    face_bbox: Optional[Sequence[float]] = None,
) -> np.ndarray:
    """Central body below the chin — the dress/shirt that must stay inpaintable."""
    person = _as_gray_u8(person_mask_uint8)
    h, w = person.shape[:2]
    ys, xs = np.where(person > 127)
    if xs.size < 16:
        return np.zeros((h, w), np.uint8)
    x0, x1 = int(xs.min()), int(xs.max())
    y0, y1 = int(ys.min()), int(ys.max())
    pw = max(1, x1 - x0)
    ph = max(1, y1 - y0)
    if face_bbox is not None:
        _, _, _, chin = expand_head_bbox(
            face_bbox, w, h, pad_x=0.02, pad_up=0.0, pad_down=0.10
        )
        top = min(h - 1, max(y0, int(chin)))
    else:
        top = y0 + int(0.20 * ph)
    cx = (x0 + x1) * 0.5
    half = 0.34 * pw
    lx = max(0, int(cx - half))
    rx = min(w, int(cx + half) + 1)
    out = np.zeros((h, w), np.uint8)
    out[top : y1 + 1, lx:rx] = 255
    return cv2.bitwise_and(out, person)


def exposed_skin_mask(
    image_rgb: np.ndarray,
    person_mask_uint8: np.ndarray,
    face_bbox: Optional[Sequence[float]] = None,
) -> np.ndarray:
    """Person pixels whose color matches already-visible skin (face sample when available)."""
    rgb = np.asarray(image_rgb)
    person = _as_gray_u8(person_mask_uint8)
    h, w = person.shape[:2]
    ycrcb = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    skin = _ycrcb_skin_gate(ycrcb) & (person > 127)

    if face_bbox is not None:
        ix1, iy1, ix2, iy2 = expand_head_bbox(
            face_bbox, w, h, pad_x=-0.22, pad_up=-0.18, pad_down=-0.22
        )
        inner = _filled_ellipse((h, w), (ix1, iy1, ix2, iy2)) > 0
        inner &= person > 127
        if int(inner.sum()) < 16:
            x1, y1, x2, y2 = [int(v) for v in face_bbox]
            inner = np.zeros((h, w), bool)
            inner[max(0, y1):max(0, y2), max(0, x1):max(0, x2)] = True
            inner &= person > 127
        if int(inner.sum()) >= 16:
            sample = ycrcb[inner]
            mean = sample.mean(axis=0)
            std = np.maximum(sample.std(axis=0), np.array([18.0, 8.0, 8.0], np.float32))
            dist = np.abs(ycrcb - mean) / std
            dist_ok = dist.max(axis=2) < 2.8
            # Only the head/neck band uses the face sample. Arms and hands
            # keep the looser YCrCb gate; the torso dress is handled later.
            head = _filled_ellipse(
                (h, w),
                expand_head_bbox(face_bbox, w, h, pad_x=0.35, pad_up=0.35, pad_down=0.35),
            )
            near = head > 0
            skin = np.where(near, skin & dist_ok, skin)

    out = (skin.astype(np.uint8)) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    out = cv2.morphologyEx(out, cv2.MORPH_CLOSE, k)
    out = cv2.dilate(out, k, iterations=1)
    out = cv2.bitwise_and(out, person)
    return out


def hair_keep_mask(
    image_rgb,
    person_mask_uint8: np.ndarray,
    face_bbox: Sequence[float],
) -> np.ndarray:
    """Head ellipse plus shoulder-length hair sampled from the crown, not the dress."""
    person = _as_gray_u8(person_mask_uint8)
    h, w = person.shape[:2]
    ellipse = _filled_ellipse(
        (h, w),
        expand_head_bbox(face_bbox, w, h, pad_x=0.22, pad_up=0.80, pad_down=0.04),
    )
    rgb = np.asarray(image_rgb)
    x1, y1, x2, y2 = [int(v) for v in face_bbox]
    bh = max(1, y2 - y1)
    ycc = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    skin = _ycrcb_skin_gate(ycc)
    crown = np.zeros((h, w), bool)
    crown[max(0, y1 - int(0.75 * bh)) : max(0, y1 + int(0.22 * bh)), max(0, x1) : min(w, x2)] = True
    crown &= ellipse > 0
    crown &= person > 127
    crown &= ~skin
    if int(crown.sum()) < 12:
        return cv2.bitwise_and(ellipse, person)

    sample = lab[crown]
    mean = sample.mean(axis=0)
    std = np.maximum(sample.std(axis=0), np.array([10.0, 6.0, 6.0], np.float32))
    dist = np.abs(lab - mean) / std
    match = (dist.max(axis=2) < 2.3) & (person > 127) & (~skin)
    match &= lab[:, :, 0] > (mean[0] - 20.0)
    y_limit = min(h, y2 + int(2.05 * bh))
    match[y_limit:, :] = False

    num, labels = cv2.connectedComponents((match.astype(np.uint8)) * 255)
    grown = np.zeros((h, w), np.uint8)
    seed = ellipse > 0
    for i in range(1, num):
        region = labels == i
        if np.any(region & seed):
            grown[region] = 255
    hair = cv2.bitwise_or(ellipse, grown)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    hair = cv2.dilate(hair, k, iterations=1)
    return cv2.bitwise_and(hair, person)


def harden_inpaint_mask(
    inpaint_mask,
    hard_keep=None,
    dilate_px: int = 7,
    gray_as_inpaint: int = 48,
) -> np.ndarray:
    """Binary mask for SD: no gray leak of the original dress, keep hands/hair exact."""
    hard = np.where(_as_gray_u8(inpaint_mask) > int(gray_as_inpaint), 255, 0).astype(np.uint8)
    if dilate_px > 0:
        ksz = int(dilate_px) * 2 + 1
        k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz))
        hard = cv2.dilate(hard, k)
    if hard_keep is not None:
        hk = _as_gray_u8(hard_keep)
        if hk.shape[:2] == hard.shape[:2]:
            hard[hk > 127] = 0
    return hard


def build_inpaint_mask(
    person_mask_uint8: np.ndarray,
    face_bbox: Optional[Sequence[float]] = None,
    feather_px: int = 21,
    image_rgb=None,
    extra_keep=None,
) -> np.ndarray:
    """White = inpaint (clothes). Black = keep (hair, arms, hands, background)."""
    person = _as_gray_u8(person_mask_uint8)
    h, w = person.shape[:2]
    hair = np.zeros((h, w), np.uint8)
    keep = np.zeros((h, w), np.uint8)
    if face_bbox is not None:
        keep = _filled_ellipse((h, w), expand_head_bbox(face_bbox, w, h))
        if image_rgb is not None:
            hair = hair_keep_mask(image_rgb, person, face_bbox)
            skin = exposed_skin_mask(image_rgb, person, face_bbox)
            keep = cv2.bitwise_or(hair, skin)
    elif image_rgb is not None:
        keep = exposed_skin_mask(image_rgb, person)
    extra = np.zeros((h, w), np.uint8)
    if extra_keep is not None:
        extra = _as_gray_u8(extra_keep)
        if extra.shape[:2] != (h, w):
            extra = cv2.resize(extra, (w, h), interpolation=cv2.INTER_NEAREST)
        keep = cv2.bitwise_or(keep, extra)
    torso = torso_garment_mask(person, face_bbox)
    protected = cv2.bitwise_or(hair, extra)
    # Dress/shirt in the torso column is always inpaint, except hands on top of it.
    keep = cv2.bitwise_and(keep, cv2.bitwise_not(cv2.bitwise_and(torso, cv2.bitwise_not(protected))))
    inpaint = cv2.bitwise_and(person, cv2.bitwise_not(keep))
    inpaint = cv2.bitwise_or(inpaint, cv2.bitwise_and(torso, cv2.bitwise_not(protected)))
    if feather_px > 0:
        k = int(feather_px) * 2 + 1
        inpaint = cv2.GaussianBlur(inpaint, (k, k), feather_px / 2.0)
    # Hands stay bit-exact; do not hard-lock dilated skin or the dress will stick.
    if int(extra.max()) > 0:
        inpaint[extra > 127] = 0
    return inpaint


def inpaint_from_parse_map(
    parse_map,
    extra_keep=None,
    feather_px: int = 15,
) -> np.ndarray:
    """Clothes labels → inpaint. Hair, face, arms, bag, background stay keep."""
    labels = np.asarray(parse_map)
    if labels.ndim == 3:
        labels = labels[:, :, 0]
    inpaint = np.isin(labels, PARSE_CLOTHES_IDS).astype(np.uint8) * 255
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    inpaint = cv2.morphologyEx(inpaint, cv2.MORPH_CLOSE, k)
    extra = np.zeros(inpaint.shape, np.uint8)
    if extra_keep is not None:
        extra = _as_gray_u8(extra_keep)
        if extra.shape[:2] != inpaint.shape[:2]:
            extra = cv2.resize(extra, (inpaint.shape[1], inpaint.shape[0]), interpolation=cv2.INTER_NEAREST)
        inpaint[extra > 127] = 0
    if feather_px > 0:
        fk = int(feather_px) * 2 + 1
        inpaint = cv2.GaussianBlur(inpaint, (fk, fk), feather_px / 2.0)
    if int(extra.max()) > 0:
        inpaint[extra > 127] = 0
    return inpaint


def grow_straps_into_garment(parse_map, image_rgb, person_mask=None) -> np.ndarray:
    """Dilate the garment into thin dark straps, not hair/face/arms or the backdrop."""
    labels = np.asarray(parse_map)
    if labels.ndim == 3:
        labels = labels[:, :, 0]
    h, w = labels.shape[:2]
    clothes = np.isin(labels, PARSE_CLOTHES_IDS)
    keep = np.isin(labels, PARSE_KEEP_IDS)
    rgb = np.asarray(image_rgb)
    if rgb.shape[:2] != (h, w):
        rgb = cv2.resize(rgb, (w, h), interpolation=cv2.INTER_LINEAR)
    ycc = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    y, cr, cb = ycc[:, :, 0], ycc[:, :, 1], ycc[:, :, 2]
    chroma = np.abs(cr - 128.0) + np.abs(cb - 128.0)
    dark = (y < 95) & (chroma < 28) & (~_ycrcb_skin_gate(ycc))
    ksz = max(31, (min(h, w) // 8) | 1)
    if ksz % 2 == 0:
        ksz += 1
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz))
    grown = cv2.dilate((clothes.astype(np.uint8)) * 255, k)
    extra = (grown > 0) & dark & (~keep) & (~clothes)
    if person_mask is not None:
        pm = _as_gray_u8(person_mask)
        if pm.shape[:2] != (h, w):
            pm = cv2.resize(pm, (w, h), interpolation=cv2.INTER_NEAREST)
        extra &= pm > 127
    extra_u8 = (extra.astype(np.uint8)) * 255
    if int(extra_u8.max()) > 0:
        dist = cv2.distanceTransform(extra_u8, cv2.DIST_L2, 3)
        max_r = max(6.0, min(h, w) / 50.0)
        extra_u8 = np.where((dist > 0) & (dist <= max_r), 255, 0).astype(np.uint8)
    out = ((clothes | (extra_u8 > 0)).astype(np.uint8)) * 255
    out[keep] = 0
    return out


def identity_keep_mask(
    parse_map,
    face_bbox=None,
    extra_keep=None,
    watermark=None,
    image_rgb=None,
    arm_erode_px: int = 3,
) -> np.ndarray:
    """Hair/hat/bag, the real face ellipse, arms (except a watermark bar), hands.

    Arms are the tricky part. The parser is imprecise where an arm rests against the
    body, so keeping label 14/15 verbatim punches a notch out of the garment and the
    original arm-toned pixels show through as a tear. Near clothing we therefore drop
    arm pixels that are not skin-toned (those are misparsed garment) and erode the
    remaining border so the arm/garment transition gets redrawn rather than preserved.
    Away from clothing the arm mask is left alone, so a shadowed arm is never eaten.
    """
    labels = np.asarray(parse_map)
    if labels.ndim == 3:
        labels = labels[:, :, 0]
    h, w = labels.shape[:2]
    keep = (np.isin(labels, (1, 2, 3, 16)).astype(np.uint8)) * 255
    if face_bbox is not None:
        head = _filled_ellipse((h, w), expand_head_bbox(face_bbox, w, h))
        keep = np.maximum(keep, head)
    else:
        keep = np.maximum(keep, (labels == 11).astype(np.uint8) * 255)
    arms = (np.isin(labels, (14, 15)).astype(np.uint8)) * 255
    if watermark is not None:
        wm = _as_gray_u8(watermark)
        if wm.shape[:2] != (h, w):
            wm = cv2.resize(wm, (w, h), interpolation=cv2.INTER_NEAREST)
        arms[wm > 127] = 0

    clothes = (np.isin(labels, PARSE_CLOTHES_IDS).astype(np.uint8)) * 255
    if int(arms.max()) > 0 and int(clothes.max()) > 0:
        arm_area = int((arms > 0).sum())
        if image_rgb is not None:
            rgb = np.asarray(image_rgb)
            if rgb.shape[:2] != (h, w):
                rgb = cv2.resize(rgb, (w, h), interpolation=cv2.INTER_LINEAR)
            not_skin = ~_ycrcb_skin_gate(cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32))
            suspect = ((arms > 0) & not_skin).astype(np.uint8)
            if int(suspect.max()) > 0:
                # Misparsed garment forms a strip CONTIGUOUS with the dress, while a
                # genuinely shadowed arm is its own island. Connectivity tells them
                # apart at any strip width; a distance threshold only catches strips
                # narrower than its own radius.
                touch = cv2.dilate(
                    clothes, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
                ) > 0
                _, cc = cv2.connectedComponents(suspect)
                drop = np.zeros(suspect.shape, bool)
                for i in np.unique(cc[touch & (suspect > 0)]):
                    if i == 0:
                        continue
                    comp = cc == i
                    # Never swallow the whole arm - that is a shadow, not a misparse.
                    if int(comp.sum()) <= 0.45 * arm_area:
                        drop |= comp
                arms[drop] = 0
        if arm_erode_px > 0:
            reach = int(max(9, arm_erode_px * 3)) | 1
            near_clothes = cv2.dilate(
                clothes, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (reach, reach))
            ) > 0
            ksz = int(arm_erode_px) * 2 + 1
            eroded = cv2.erode(arms, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz)))
            arms = np.where(near_clothes, eroded, arms).astype(np.uint8)
    keep = np.maximum(keep, arms)
    if extra_keep is not None:
        extra = _as_gray_u8(extra_keep)
        if extra.shape[:2] != (h, w):
            extra = cv2.resize(extra, (w, h), interpolation=cv2.INTER_NEAREST)
        keep = np.maximum(keep, extra)
    return keep


def garment_inpaint_mask(
    parse_map,
    image_rgb,
    face_bbox=None,
    person_mask=None,
    extra_keep=None,
) -> np.ndarray:
    """Clothes + dark straps/ruffles. Exposed cleavage stays keep."""
    labels = np.asarray(parse_map)
    if labels.ndim == 3:
        labels = labels[:, :, 0]
    h, w = labels.shape[:2]
    if person_mask is None:
        person = ((labels > 0).astype(np.uint8)) * 255
    else:
        person = _as_gray_u8(person_mask)
        if person.shape[:2] != (h, w):
            person = cv2.resize(person, (w, h), interpolation=cv2.INTER_NEAREST)
    clothes = grow_straps_into_garment(parse_map, image_rgb, person_mask=person)
    torso = torso_garment_mask(person, face_bbox)
    ksz = max(21, (min(h, w) // 16) | 1)
    if ksz % 2 == 0:
        ksz += 1
    torso_wide = cv2.dilate(torso, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz)))

    rgb = np.asarray(image_rgb)
    if rgb.shape[:2] != (h, w):
        rgb = cv2.resize(rgb, (w, h), interpolation=cv2.INTER_LINEAR)
    ycc = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    y, cr, cb = ycc[:, :, 0], ycc[:, :, 1], ycc[:, :, 2]
    chroma = np.abs(cr - 128.0) + np.abs(cb - 128.0)
    skin = _ycrcb_skin_gate(ycc)
    dark = (y < 110) & (chroma < 40) & (~skin)
    ruffles = (torso_wide > 0) & (person > 127) & dark
    out = np.maximum(clothes, (ruffles.astype(np.uint8)) * 255)

    wm = watermark_banner_mask(rgb, person_mask=person)
    if int(wm.max()) > 0:
        near_garment = cv2.dilate(out, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
        on_fabric = (wm > 127) & (near_garment > 127) & (~skin)
        out = np.maximum(out, (on_fabric.astype(np.uint8)) * 255)

    keep = identity_keep_mask(
        labels, face_bbox=face_bbox, extra_keep=extra_keep, image_rgb=rgb
    )
    out[keep > 127] = 0
    return out


def restyle_body_mask(
    parse_map,
    person_mask,
    face_bbox=None,
    extra_keep=None,
) -> np.ndarray:
    """Dress-shaped hole: person below the chin, not the old garment silhouette."""
    labels = np.asarray(parse_map)
    if labels.ndim == 3:
        labels = labels[:, :, 0]
    h, w = labels.shape[:2]
    person = _as_gray_u8(person_mask)
    if person.shape[:2] != (h, w):
        person = cv2.resize(person, (w, h), interpolation=cv2.INTER_NEAREST)
    torso = torso_garment_mask(person, face_bbox)
    ksz = max(25, (min(h, w) // 10) | 1)
    if ksz % 2 == 0:
        ksz += 1
    body = cv2.dilate(torso, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksz, ksz)))
    clothes = (np.isin(labels, PARSE_CLOTHES_IDS).astype(np.uint8)) * 255
    out = np.maximum(body, clothes)
    out[person <= 127] = 0
    keep = identity_keep_mask(labels, face_bbox=face_bbox, extra_keep=extra_keep)
    out[keep > 127] = 0
    return out


def mask_crop_box(mask, pad_frac: float = 0.14) -> Tuple[int, int, int, int]:
    """Inclusive-exclusive xyxy crop around the mask, padded, clipped to the image."""
    m = _as_gray_u8(mask)
    h, w = m.shape[:2]
    ys, xs = np.where(m > 127)
    if xs.size < 8:
        return 0, 0, w, h
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    pad = int(max(8, pad_frac * max(x1 - x0, y1 - y0)))
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(w, x1 + pad)
    y1 = min(h, y1 + pad)
    return x0, y0, x1, y1


def paste_crop_into(canvas_rgb, crop_rgb, box) -> np.ndarray:
    x0, y0, x1, y1 = [int(v) for v in box]
    out = np.array(canvas_rgb, copy=True)
    cw, ch = max(1, x1 - x0), max(1, y1 - y0)
    resized = cv2.resize(np.asarray(crop_rgb), (cw, ch), interpolation=cv2.INTER_LINEAR)
    out[y0:y1, x0:x1] = resized
    return out


def watermark_banner_mask(image_rgb, person_mask=None) -> np.ndarray:
    """Wide, short, low-chroma mid-gray bars (Getty-style overlays), clipped to the body."""
    rgb = np.asarray(image_rgb)
    h, w = rgb.shape[:2]
    ycc = cv2.cvtColor(rgb, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    y, cr, cb = ycc[:, :, 0], ycc[:, :, 1], ycc[:, :, 2]
    chroma = np.abs(cr - 128.0) + np.abs(cb - 128.0)
    grayish = (chroma < 42) & (y > 55) & (y < 220)
    m = (grayish.astype(np.uint8)) * 255
    kx = max(9, w // 18)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (kx, 5)))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (max(11, w // 16), 3)))
    num, labels, stats, _ = cv2.connectedComponentsWithStats(m)
    out = np.zeros((h, w), np.uint8)
    max_h = 0.14 * h
    for i in range(1, num):
        _, y0, bw, bh, _area = stats[i]
        if bw < 0.22 * w or bh < 5 or bh > max_h:
            continue
        if bh > 0 and (bw / float(bh)) < 2.5:
            continue
        cy = y0 + bh * 0.5
        if cy < 0.16 * h or cy > 0.88 * h:
            continue
        out[labels == i] = 255
    if int(out.max()) > 0:
        out = cv2.dilate(out, cv2.getStructuringElement(cv2.MORPH_RECT, (5, 7)))
    if person_mask is not None:
        pm = _as_gray_u8(person_mask)
        if pm.shape[:2] != (h, w):
            pm = cv2.resize(pm, (w, h), interpolation=cv2.INTER_NEAREST)
        out[pm <= 127] = 0
    return out


def clean_binary_mask(mask, min_area_frac: float = 0.0015) -> np.ndarray:
    """Fill holes, drop specks, keep large garment blobs."""
    m = np.where(_as_gray_u8(mask) > 127, 255, 0).astype(np.uint8)
    if int(m.max()) == 0:
        return m
    h, w = m.shape[:2]
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    inv = cv2.bitwise_not(m)
    ff = inv.copy()
    flood = np.zeros((h + 2, w + 2), np.uint8)
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if ff[y, x] > 0:
            cv2.floodFill(ff, flood, (x, y), 0)
    m = cv2.bitwise_or(m, ff)
    num, cc, stats, _ = cv2.connectedComponentsWithStats(m)
    min_area = max(16, int(min_area_frac * h * w))
    out = np.zeros((h, w), np.uint8)
    for i in range(1, num):
        if int(stats[i, cv2.CC_STAT_AREA]) >= min_area:
            out[cc == i] = 255
    return out


def fill_masked_region(image_rgb, mask, fill_rgb) -> np.ndarray:
    """Paint the mask with a solid color so the old garment cannot leak into SD."""
    out = np.array(image_rgb, copy=True)
    m = _as_gray_u8(mask)
    if m.shape[:2] != out.shape[:2]:
        m = cv2.resize(m, (out.shape[1], out.shape[0]), interpolation=cv2.INTER_NEAREST)
    color = np.asarray(fill_rgb, np.uint8).reshape(1, 1, 3)
    out[m > 127] = color
    return out


def skin_fill_color(image_rgb, face_bbox=None, skin_mask=None) -> Tuple[int, int, int]:
    """Median skin color for neutralizing the garment region."""
    rgb = np.asarray(image_rgb)
    if skin_mask is not None:
        sm = _as_gray_u8(skin_mask) > 127
        if sm.shape[:2] == rgb.shape[:2] and int(sm.sum()) >= 16:
            med = np.median(rgb[sm], axis=0)
            return int(med[0]), int(med[1]), int(med[2])
    if face_bbox is not None:
        x1, y1, x2, y2 = expand_head_bbox(
            face_bbox, rgb.shape[1], rgb.shape[0], pad_x=-0.22, pad_up=-0.18, pad_down=-0.22
        )
        crop = rgb[y1:y2, x1:x2]
        if crop.size >= 48:
            med = np.median(crop.reshape(-1, 3), axis=0)
            return int(med[0]), int(med[1]), int(med[2])
    return (210, 175, 155)


def pose_control_scale(face_bbox, shape_hw, closeup_face_frac: float = 0.16) -> float:
    """0 on waist-up / close portraits — OpenPose invents extra legs and warps the body."""
    if not face_bbox:
        return 0.0
    h = int(shape_hw[0])
    face_h = max(1.0, float(face_bbox[3]) - float(face_bbox[1]))
    if face_h / max(h, 1) > closeup_face_frac:
        return 0.0
    return 0.55


def feather_mask_at_size(mask, dest_hw, feather_px: int) -> np.ndarray:
    """Resize a binary work mask to dest, then feather in dest pixels (not work pixels)."""
    h, w = int(dest_hw[0]), int(dest_hw[1])
    m = _mask_at_hw(mask, h, w)
    if feather_px > 0:
        k = int(feather_px) * 2 + 1
        if k % 2 == 0:
            k += 1
        m = cv2.GaussianBlur(m, (k, k), feather_px / 2.0)
    return m


def paste_work_onto_original(original_rgb, work_rgb, work_mask) -> np.ndarray:
    """Upscale the work result and composite onto the native-resolution original."""
    return composite_inpaint(original_rgb, work_rgb, work_mask)


def image_to_nchw_01(image_rgb) -> np.ndarray:
    arr = np.asarray(image_rgb).astype(np.float32) / 255.0
    if arr.ndim == 2:
        arr = np.stack([arr, arr, arr], axis=-1)
    return np.transpose(arr, (2, 0, 1))[None].astype(np.float32)


def composite_inpaint(original_rgb, generated_rgb, inpaint_mask) -> np.ndarray:
    """Keep original pixels where the mask is black; use generated where white."""
    orig = np.asarray(original_rgb).astype(np.float32)
    gen = np.asarray(generated_rgb).astype(np.float32)
    if gen.shape[:2] != orig.shape[:2]:
        gen = cv2.resize(gen, (orig.shape[1], orig.shape[0]), interpolation=cv2.INTER_LINEAR)
    alpha = _as_gray_u8(inpaint_mask).astype(np.float32) / 255.0
    if alpha.shape != orig.shape[:2]:
        alpha = cv2.resize(alpha, (orig.shape[1], orig.shape[0]), interpolation=cv2.INTER_LINEAR)
    a3 = alpha[:, :, None]
    out = gen * a3 + orig * (1.0 - a3)
    return np.clip(out, 0, 255).astype(np.uint8)


def _mask_at_hw(mask, height: int, width: int) -> np.ndarray:
    arr = _as_gray_u8(mask)
    if arr.shape[:2] != (height, width):
        arr = cv2.resize(arr, (width, height), interpolation=cv2.INTER_LINEAR)
    return arr


def harmonize_generated_region(
    original_rgb,
    generated_rgb,
    inpaint_mask,
    skin_mask,
) -> np.ndarray:
    """Keep hair/skin pixels exact, then match newly generated skin to original skin tone."""
    orig = np.asarray(original_rgb)
    gen = np.asarray(generated_rgb)
    h, w = orig.shape[:2]
    inpaint_mask = _mask_at_hw(inpaint_mask, h, w)
    skin_mask = _mask_at_hw(skin_mask, h, w)
    out = composite_inpaint(orig, gen, inpaint_mask)
    sel = inpaint_mask > 127
    ref = skin_mask > 127
    if int(sel.sum()) < 16 or int(ref.sum()) < 16:
        return out

    gen_ycc = cv2.cvtColor(out, cv2.COLOR_RGB2YCrCb).astype(np.float32)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15))
    near = cv2.dilate((ref.astype(np.uint8)) * 255, k) > 127
    near_white = (out[:, :, 0] > 230) & (out[:, :, 1] > 228) & (out[:, :, 2] > 220)
    target = sel & _ycrcb_skin_gate(gen_ycc) & near & (~near_white)
    if int(target.sum()) < 16:
        return out

    orig_lab = cv2.cvtColor(orig, cv2.COLOR_RGB2LAB).astype(np.float32)
    out_lab = cv2.cvtColor(out, cv2.COLOR_RGB2LAB).astype(np.float32)
    ref_pix = orig_lab[ref]
    sel_pix = out_lab[target]
    mu_r = ref_pix.mean(axis=0)
    sd_r = np.maximum(ref_pix.std(axis=0), 1.0)
    mu_s = sel_pix.mean(axis=0)
    sd_s = np.maximum(sel_pix.std(axis=0), 1.0)
    transferred = (sel_pix - mu_s) * (sd_r / sd_s) + mu_r
    out_lab[target] = np.clip(transferred, 0, 255)
    matched = cv2.cvtColor(out_lab.astype(np.uint8), cv2.COLOR_LAB2RGB)
    matched[~target] = out[~target]
    return matched



def _guided_filter_gray(guide_f32, src_f32, radius: int, eps: float) -> np.ndarray:
    """He et al. guided filter with a grayscale guide. Base OpenCV only (no contrib)."""
    r = max(1, int(radius))
    ksz = (r * 2 + 1, r * 2 + 1)
    mean_i = cv2.blur(guide_f32, ksz)
    mean_p = cv2.blur(src_f32, ksz)
    corr_i = cv2.blur(guide_f32 * guide_f32, ksz)
    corr_ip = cv2.blur(guide_f32 * src_f32, ksz)
    var_i = corr_i - mean_i * mean_i
    cov_ip = corr_ip - mean_i * mean_p
    a = cov_ip / (var_i + float(eps))
    b = mean_p - a * mean_i
    return cv2.blur(a, ksz) * guide_f32 + cv2.blur(b, ksz)


def refine_mask_edges(mask, guide_rgb, radius: int = 8, eps: float = 1e-3) -> np.ndarray:
    """Lift a work-res mask to the guide's resolution, snapping its edges to real ones.

    A plain resize turns a 768px mask boundary into a staircase at 2048px — that is the
    sawtooth seam along hair and arms. The guided filter re-fits the mask to local image
    structure instead, so the paste edge follows hair strands and fabric folds.
    """
    guide = np.asarray(guide_rgb)
    if guide.ndim == 3:
        guide_gray = cv2.cvtColor(guide.astype(np.uint8), cv2.COLOR_RGB2GRAY)
    else:
        guide_gray = _as_gray_u8(guide)
    h, w = guide_gray.shape[:2]
    m = _mask_at_hw(mask, h, w)
    out = _guided_filter_gray(
        guide_gray.astype(np.float32) / 255.0,
        m.astype(np.float32) / 255.0,
        radius,
        eps,
    )
    return np.clip(out * 255.0, 0, 255).astype(np.uint8)


def subtract_keep_soft(inpaint_mask, keep_mask, feather_px: int = 3) -> np.ndarray:
    """Remove keep pixels with a feathered edge instead of a binary punch.

    `mask[keep > 127] = 0` leaves a one-pixel cliff that upscales into a visible
    staircase. Ramping the subtraction keeps the paste boundary soft.
    """
    m = _as_gray_u8(inpaint_mask)
    k = _mask_at_hw(keep_mask, m.shape[0], m.shape[1]).astype(np.float32)
    if feather_px > 0:
        ksz = int(feather_px) * 2 + 1
        k = cv2.GaussianBlur(k, (ksz, ksz), feather_px / 2.0)
    out = m.astype(np.float32) * (1.0 - np.clip(k / 255.0, 0.0, 1.0))
    return np.clip(out, 0, 255).astype(np.uint8)


GARMENT_COLORS = {
    "white": (240, 238, 234),
    "ivory": (243, 238, 226),
    "cream": (243, 236, 219),
    "beige": (226, 211, 187),
    "black": (28, 28, 30),
    "grey": (140, 140, 142),
    "gray": (140, 140, 142),
    "silver": (196, 198, 201),
    "gold": (198, 163, 90),
    "red": (176, 42, 46),
    "burgundy": (110, 32, 44),
    "pink": (226, 160, 176),
    "blue": (54, 84, 158),
    "navy": (32, 44, 84),
    "teal": (34, 118, 124),
    "green": (54, 118, 68),
    "emerald": (28, 122, 88),
    "yellow": (226, 200, 84),
    "orange": (216, 128, 52),
    "purple": (104, 60, 146),
    "lavender": (188, 174, 216),
    "brown": (108, 78, 54),
}
DEFAULT_INIT_COLOR = (238, 236, 232)


def garment_color_from_prompt(prompt: str, default=DEFAULT_INIT_COLOR):
    """First colour word in the prompt, so the init base matches the target garment.

    Longest match wins, so "navy" beats "blue" in "navy blue dress".
    """
    if not prompt:
        return default
    text = str(prompt).lower()
    hits = [(len(name), name) for name in GARMENT_COLORS if name in text]
    if not hits:
        return default
    return GARMENT_COLORS[max(hits)[1]]


def garment_base_init(
    image_rgb,
    garment_mask,
    target_rgb=DEFAULT_INIT_COLOR,
    target_contrast: float = 26.0,
):
    """Repaint the garment region in a flat target colour, keeping its shading.

    At strength 1.0 the masked area starts from pure noise, and with skin all around
    it the model often resolves the garment as bare skin. Handing it a garment-coloured
    base that still carries the original folds means it only has to refine fabric that
    is already in the right place, at the right neckline.

    Luminance keeps the original relative shape (rescaled for contrast); chroma is
    replaced outright so the old garment's colour identity does not survive.
    """
    rgb = np.asarray(image_rgb).astype(np.uint8)
    h, w = rgb.shape[:2]
    alpha = _mask_at_hw(garment_mask, h, w).astype(np.float32) / 255.0
    sel = alpha > 0.02
    if int(sel.sum()) < 16:
        return rgb.copy()

    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    target = cv2.cvtColor(
        np.asarray(target_rgb, np.uint8).reshape(1, 1, 3), cv2.COLOR_RGB2LAB
    )[0, 0].astype(np.float32)

    lum = lab[:, :, 0]
    sd = float(max(lum[sel].std(), 1.0))
    gain = float(np.clip(target_contrast / sd, 0.25, 1.6))
    # Anchor the target colour to the garment's HIGHLIGHT, not its mean. Fabric folds
    # read as shadow, so they need headroom below the base; centring on the mean pushes
    # half the range past pure white and clips the folds flat.
    hi = float(np.percentile(lum[sel], 85.0))
    lo_clip = max(4.0, target[0] - 3.5 * target_contrast)
    hi_clip = min(251.0, target[0] + 0.6 * target_contrast)

    out_lab = lab.copy()
    out_lab[:, :, 0] = np.clip(target[0] + (lum - hi) * gain, lo_clip, hi_clip)
    out_lab[:, :, 1] = target[1]
    out_lab[:, :, 2] = target[2]
    recolored = cv2.cvtColor(out_lab.astype(np.uint8), cv2.COLOR_LAB2RGB)

    a3 = alpha[:, :, None]
    blended = recolored.astype(np.float32) * a3 + rgb.astype(np.float32) * (1.0 - a3)
    return np.clip(blended, 0, 255).astype(np.uint8)


def _tile_positions(start: int, end: int, tile: int, step: int, limit: int) -> List[int]:
    """Evenly spaced tile origins across [start, end), each fully inside [0, limit).

    Stepping by a fixed amount and clamping the last origin squashes the final row
    against the previous one, so you pay for a tile that adds almost no new pixels.
    Spreading the same count evenly keeps overlap >= the requested amount.
    """
    lo = max(0, min(int(start), max(0, limit - tile)))
    hi = max(0, min(int(end) - tile, limit - tile))
    if hi <= lo:
        return [lo]
    n = int(np.ceil((hi - lo) / float(max(1, step)))) + 1
    if n <= 1:
        return [lo]
    return sorted({int(round(lo + (hi - lo) * i / (n - 1))) for i in range(n)})


def plan_refine_tiles(
    mask,
    tile: int = REFINE_TILE,
    overlap: int = REFINE_OVERLAP,
    multiple: int = 8,
) -> List[Tuple[int, int, int, int]]:
    """Overlapping tile boxes covering the mask, so a refine pass has flat VRAM cost.

    Only tiles that actually contain mask pixels are returned. Sizes stay a multiple
    of `multiple` because the VAE downsamples by 8.
    """
    m = _as_gray_u8(mask)
    h, w = m.shape[:2]
    ys, xs = np.where(m > 8)
    if xs.size < 8:
        return []
    tile = max(multiple, (int(tile) // multiple) * multiple)
    tw = max(multiple, min(tile, (w // multiple) * multiple))
    th = max(multiple, min(tile, (h // multiple) * multiple))
    x0b, x1b = int(xs.min()), int(xs.max()) + 1
    y0b, y1b = int(ys.min()), int(ys.max()) + 1
    # Grow the planning box by one overlap so each tile's blend taper falls OUTSIDE
    # the mask. Starting flush with the mask edge leaves that border near zero weight.
    pad = int(overlap)
    x0b, y0b = max(0, x0b - pad), max(0, y0b - pad)
    x1b, y1b = min(w, x1b + pad), min(h, y1b + pad)
    step_x = max(multiple, tw - int(overlap))
    step_y = max(multiple, th - int(overlap))
    xs_pos = _tile_positions(x0b, x1b, tw, step_x, w)
    ys_pos = _tile_positions(y0b, y1b, th, step_y, h)
    boxes: List[Tuple[int, int, int, int]] = []
    seen = set()
    for yy0 in ys_pos:
        for xx0 in xs_pos:
            box = (xx0, yy0, xx0 + tw, yy0 + th)
            if box in seen:
                continue
            if int(m[yy0:yy0 + th, xx0:xx0 + tw].max()) > 8:
                seen.add(box)
                boxes.append(box)
    return boxes


def tile_blend_weights(height: int, width: int, feather_px: int = 64) -> np.ndarray:
    """Cosine-eased edge ramp so overlapping refine tiles blend without seams."""
    h, w = int(height), int(width)
    f = int(max(1, min(int(feather_px), min(h, w) // 2)))
    ramp = (np.arange(f, dtype=np.float32) + 0.5) / f
    ramp = 0.5 - 0.5 * np.cos(np.pi * ramp)
    wx = np.ones(w, np.float32)
    wy = np.ones(h, np.float32)
    wx[:f] = ramp
    wx[w - f:] = ramp[::-1]
    wy[:f] = ramp
    wy[h - f:] = ramp[::-1]
    return np.clip(np.outer(wy, wx), 1e-6, 1.0).astype(np.float32)


def make_inpaint_condition(image_rgb, mask_u8) -> np.ndarray:
    """Control image for inpaint ControlNet: masked pixels = -1, else RGB in [0, 1].

    Returns float32 with shape (1, 3, H, W).
    """
    image = np.asarray(image_rgb).astype(np.float32) / 255.0
    mask = np.asarray(mask_u8)
    if mask.ndim == 3:
        mask = mask[:, :, 0]
    out = image.copy()
    out[mask > 127] = -1.0
    return np.transpose(out, (2, 0, 1))[None].astype(np.float32)


def protection_preview_masks(image_rgb, face_bbox) -> Tuple[np.ndarray, np.ndarray]:
    """CPU preview of locked vs restyle pixels. Green keep / red clothes in the UI.

    Approximate (no SegFormer): head ellipse, exposed skin, and everything
    outside the torso column stay keep. Non-skin torso is the restyle hole.
    """
    rgb = np.asarray(image_rgb)
    h, w = rgb.shape[:2]
    person = np.full((h, w), 255, np.uint8)
    head = _filled_ellipse(
        (h, w),
        expand_head_bbox(face_bbox, w, h, pad_x=0.22, pad_up=0.80, pad_down=0.08),
    )
    torso = torso_garment_mask(person, face_bbox)
    skin = exposed_skin_mask(rgb, person, face_bbox)
    restyle = torso.copy()
    restyle[head > 127] = 0
    restyle[skin > 127] = 0
    keep = np.full((h, w), 255, np.uint8)
    keep[restyle > 127] = 0
    return keep, restyle


def annotate_face_preview(image_pil: Image.Image, bbox: Sequence[int]) -> Image.Image:
    """Green overlay on protected pixels, red on clothes that will be restyled."""
    rgb = np.array(image_pil.convert("RGB"))
    keep, restyle = protection_preview_masks(rgb, bbox)
    out = rgb.astype(np.float32)
    green = np.array([36.0, 220.0, 72.0], np.float32)
    red = np.array([230.0, 48.0, 40.0], np.float32)
    k = keep > 127
    r = restyle > 127
    out[k] = out[k] * 0.58 + green * 0.42
    out[r] = out[r] * 0.58 + red * 0.42
    annotated = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(annotated)
    ex1, ey1, ex2, ey2 = expand_head_bbox(
        bbox, rgb.shape[1], rgb.shape[0], pad_x=0.22, pad_up=0.80, pad_down=0.08
    )
    draw.ellipse([ex1, ey1, ex2, ey2], outline=(0, 255, 80), width=max(3, min(rgb.shape[:2]) // 220))
    return annotated


def terminate_process(proc: Optional[subprocess.Popen], wait_seconds: float = 5.0) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=wait_seconds)
    except Exception:
        try:
            proc.kill()
            proc.wait(timeout=wait_seconds)
        except Exception:
            pass


def write_undress_output(job_id: str, png_bytes: bytes, out_dir: str | Path) -> str:
    dest = Path(out_dir)
    dest.mkdir(parents=True, exist_ok=True)
    path = dest / f"{job_id}.png"
    path.write_bytes(png_bytes)
    return str(path)


class UndressClient:
    """Persistent venv_ai worker. Loads SD weights once, then runs jobs as JSON lines."""

    def __init__(
        self,
        python_exe,
        script_path=None,
        script_args: Optional[Sequence[str]] = None,
        is_module_script: bool = False,
    ):
        if is_module_script:
            self.cmd = [str(python_exe)] + list(script_args or [])
        else:
            self.cmd = [str(python_exe), str(script_path), "--worker"]
        self.proc: Optional[subprocess.Popen] = None
        self._out_q: Queue = Queue()
        self._err_chunks: List[str] = []
        self._reader_started = False

    def _ensure(self) -> None:
        if self.proc is not None and self.proc.poll() is None:
            return
        kwargs: Dict[str, Any] = dict(
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        if os.name == "nt":
            kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        self.proc = subprocess.Popen(self.cmd, **kwargs)
        self._out_q = Queue()
        self._err_chunks = []
        threading.Thread(target=self._read_stdout, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()

    def _read_stdout(self) -> None:
        proc = self.proc
        if proc is None or proc.stdout is None:
            return
        for line in proc.stdout:
            self._out_q.put(line)

    def _read_stderr(self) -> None:
        proc = self.proc
        if proc is None or proc.stderr is None:
            return
        for line in proc.stderr:
            self._err_chunks.append(line)

    def generate(self, payload: Dict[str, Any], timeout: float = 1800) -> Dict[str, Any]:
        self._ensure()
        assert self.proc is not None and self.proc.stdin is not None
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        collected: List[str] = []
        while time.time() < deadline:
            if self.proc.poll() is not None:
                # Drain anything already queued so a fast worker still parses.
                while True:
                    try:
                        collected.append(self._out_q.get_nowait())
                    except Empty:
                        break
                try:
                    return parse_result_stdout("".join(collected))
                except ValueError as e:
                    err = "".join(self._err_chunks[-20:])
                    raise RuntimeError(f"undress worker exited: {e}\n{err}") from e
            try:
                line = self._out_q.get(timeout=0.1)
            except Empty:
                continue
            collected.append(line)
            if RESULT_MARKER in line:
                return parse_result_stdout("".join(collected))
        terminate_process(self.proc)
        self.proc = None
        raise TimeoutError(f"undress worker timed out after {int(timeout)} seconds")

    def close(self) -> None:
        if self.proc is None:
            return
        try:
            if self.proc.poll() is None and self.proc.stdin:
                self.proc.stdin.write("EXIT\n")
                self.proc.stdin.flush()
        except Exception:
            pass
        terminate_process(self.proc, wait_seconds=8)
        self.proc = None


def get_shared_client() -> UndressClient:
    global _shared_client
    if _shared_client is None:
        if not VENV_AI_PYTHON.exists():
            raise FileNotFoundError(
                f"venv_ai not found at {VENV_AI_PYTHON}. {SETUP_INSTRUCTIONS}"
            )
        _shared_client = UndressClient(VENV_AI_PYTHON, script_path=UNDRESS_SCRIPT)
    return _shared_client


def close_shared_client() -> None:
    global _shared_client
    if _shared_client is not None:
        _shared_client.close()
        _shared_client = None


def run_undress_job(job, manager) -> bool:
    """Entry point for job_manager.run_single_job (job_type == undress_image)."""
    from datetime import datetime

    from job_manager import JobStatus

    params = job.params or {}
    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.message = "Starting clothes restyle..."
    job.queue_position = 0
    manager.save_job(job)

    try:
        if manager.is_stop_requested(job.id):
            manager.pause_job(job.id, 0)
            return False

        job.message = "Generating (models stay loaded if the queue is busy)..."
        job.progress = 0.15
        manager.save_job(job)

        timeout = float(params.get("timeout", 1800))
        client = get_shared_client()
        result = client.generate(
            {
                "image_path": params["image_path"],
                "face_bbox": params.get("face_bbox"),
                "prompt": params.get("prompt") or DEFAULT_PROMPT,
                "negative_prompt": params.get("negative_prompt") or DEFAULT_NEGATIVE_PROMPT,
                "seed": params.get("seed", -1),
                "steps": params.get("steps", 26),
                "guidance_scale": params.get("guidance_scale", 6.0),
                "strength": params.get("strength", DEFAULT_STRENGTH),
                "init_color": params.get("init_color"),
                "controlnet_scale": params.get("controlnet_scale", 0.0),
                "ref_images": params.get("ref_images") or [],
                "ref_scale": params.get("ref_scale", DEFAULT_REF_SCALE),
                "refine": bool(params.get("refine", True)),
                "refine_strength": params.get("refine_strength", DEFAULT_REFINE_STRENGTH),
                "refine_steps": params.get("refine_steps", DEFAULT_REFINE_STEPS),
            },
            timeout=timeout,
        )
        engine_tb = result.get("traceback") if isinstance(result, dict) else None
        if not result.get("success"):
            if engine_tb:
                print(f"[JOB {job.id}] engine traceback:\n{engine_tb}", file=sys.stderr)
            raise RuntimeError(result.get("error") or "undress engine failed")

        png = base64.b64decode(result["output_image"])
        out_path = write_undress_output(job.id, png, OUTPUT_DIR)
        if result.get("pose_image"):
            pose_path = Path(out_path).with_name(f"{job.id}_pose.png")
            pose_path.write_bytes(base64.b64decode(result["pose_image"]))
        if result.get("mask_image"):
            mask_path = Path(out_path).with_name(f"{job.id}_mask.png")
            mask_path.write_bytes(base64.b64decode(result["mask_image"]))

        job.status = JobStatus.COMPLETED
        job.progress = 1.0
        job.completed_at = datetime.now().isoformat()
        job.result_path = out_path
        job.message = f"Saved {out_path}"
        manager.save_job(job)
        return True
    except Exception as e:
        import traceback

        job.status = JobStatus.FAILED
        job.progress = 0.0
        job.message = f"Error: {e}"
        local_tb = traceback.format_exc()
        engine_tb = locals().get("engine_tb")
        # The worker runs in venv_ai, so its traceback is the only useful one here.
        job.error = f"{engine_tb}\n--- job worker ---\n{local_tb}" if engine_tb else local_tb
        job.completed_at = datetime.now().isoformat()
        manager.save_job(job)
        print(f"[JOB {job.id}] ERROR: {e}", file=sys.stderr)
        print(traceback.format_exc(), file=sys.stderr)
        return False
