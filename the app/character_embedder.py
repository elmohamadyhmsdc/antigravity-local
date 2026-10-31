"""Character Embedder using deepghs/ccip (caformer-24) ONNX and hybrid appearance features.

Extracts a 768-d CCIP character identity embedding from an asymmetric portrait crop,
plus 16-d outfit hue and 8-d hat/hair hue features -> 792-d total character appearance.
"""
from __future__ import annotations

import os
from typing import List, Tuple, Optional

import cv2
import numpy as np
import onnxruntime as ort

try:
    import cuda_dll_dirs
    cuda_dll_dirs.add_nvidia_dll_dirs()
except ImportError:
    pass

CCIP_DIM = 768
OUTFIT_DIM = 16
HAT_DIM = 8
HUE_BINS = 8
TOTAL_APPEARANCE_DIM = CCIP_DIM + OUTFIT_DIM + HAT_DIM

CCIP_SIZE = 384
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32).reshape(1, 3, 1, 1)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32).reshape(1, 3, 1, 1)


def asymmetric_ccip_crop(bbox: List[float], img_w: int, img_h: int) -> Tuple[int, int, int, int]:
    """Asymmetric portrait crop for CCIP: up 0.8*h, down 1.2*h, sides 0.5*w."""
    w = bbox[2] - bbox[0]
    h = bbox[3] - bbox[1]
    l = max(0, min(img_w - 1, int(round(bbox[0] - w * 0.5))))
    t = max(0, min(img_h - 1, int(round(bbox[1] - h * 0.8))))
    r = max(l + 1, min(img_w, int(round(bbox[2] + w * 0.5))))
    b = max(t + 1, min(img_h, int(round(bbox[3] + h * 1.2))))
    return l, t, r, b


def _rgb_to_hue_sat(bgr: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Calculate hue [0, 360) and saturation [0, 1] from BGR pixels."""
    rgb = bgr[..., ::-1].astype(np.float32) / 255.0
    c_max = np.max(rgb, axis=-1)
    c_min = np.min(rgb, axis=-1)
    delta = c_max - c_min

    sat = np.zeros_like(c_max)
    non_zero = c_max > 1e-5
    sat[non_zero] = delta[non_zero] / c_max[non_zero]

    hue = np.zeros_like(c_max)
    mask = delta > 1e-5
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]

    # r == c_max
    r_max = mask & (c_max == r)
    hue[r_max] = (60.0 * (((g[r_max] - b[r_max]) / delta[r_max]) % 6.0))

    # g == c_max
    g_max = mask & (c_max == g) & ~r_max
    hue[g_max] = (60.0 * (((b[g_max] - r[g_max]) / delta[g_max]) + 2.0))

    # b == c_max
    b_max = mask & (c_max == b) & ~r_max & ~g_max
    hue[b_max] = (60.0 * (((r[b_max] - g[b_max]) / delta[b_max]) + 4.0))

    hue[hue < 0] += 360.0
    return hue, sat


def extract_hat_hue(img: np.ndarray, bbox: List[float]) -> List[float]:
    """Extract 8 hue bins from the hat/hair region above the face (y1 - 0.8*h to y1)."""
    h_box = bbox[3] - bbox[1]
    img_h, img_w = img.shape[:2]
    y0 = max(0, min(img_h - 1, int(round(bbox[1] - h_box * 0.8))))
    y1 = max(y0 + 1, min(img_h, int(round(bbox[1]))))
    x0 = max(0, min(img_w - 1, int(round(bbox[0]))))
    x1 = max(x0 + 1, min(img_w, int(round(bbox[2]))))

    crop = img[y0:y1, x0:x1]
    if crop.size == 0 or crop.shape[0] < 2 or crop.shape[1] < 2:
        return [0.0] * HAT_DIM

    hue, sat = _rgb_to_hue_sat(crop)
    valid = sat >= 0.12
    if not np.any(valid):
        return [0.0] * HAT_DIM

    bins = (hue[valid] / 360.0 * HUE_BINS).astype(np.int32)
    bins = np.clip(bins, 0, HUE_BINS - 1)

    hist, _ = np.histogram(bins, bins=HUE_BINS, range=(0, HUE_BINS))
    hist = hist.astype(np.float32)
    norm = np.linalg.norm(hist)
    if norm > 0:
        hist /= norm
    return [round(float(x), 4) for x in hist]


def extract_outfit_hue(img: np.ndarray, bbox: List[float]) -> List[float]:
    """Extract 16 hue features (weights + counts) from the torso below the face (y2 to y2 + 2.0*h)."""
    h_box = bbox[3] - bbox[1]
    img_h, img_w = img.shape[:2]
    y0 = max(0, min(img_h - 1, int(round(bbox[3]))))
    y1 = max(y0 + 1, min(img_h, int(round(bbox[3] + h_box * 2.0))))
    x0 = max(0, min(img_w - 1, int(round(bbox[0]))))
    x1 = max(x0 + 1, min(img_w, int(round(bbox[2]))))

    crop = img[y0:y1, x0:x1]
    if crop.size == 0 or crop.shape[0] < 2 or crop.shape[1] < 2:
        return [0.0] * OUTFIT_DIM

    hue, sat = _rgb_to_hue_sat(crop)
    valid = sat >= 0.12
    if not np.any(valid):
        return [0.0] * OUTFIT_DIM

    bins = (hue[valid] / 360.0 * HUE_BINS).astype(np.int32)
    bins = np.clip(bins, 0, HUE_BINS - 1)
    sat_valid = sat[valid]

    weights = np.zeros(HUE_BINS, dtype=np.float32)
    counts = np.zeros(HUE_BINS, dtype=np.float32)
    for b, s in zip(bins, sat_valid):
        weights[b] += s
        counts[b] += 1.0

    combined = np.concatenate([weights, counts])
    norm = np.linalg.norm(combined)
    if norm > 0:
        combined /= norm
    return [round(float(x), 4) for x in combined]


class CcipEmbedder:
    """Extracts 768-d CCIP character identity embedding plus hue features."""

    def __init__(self, model_path: str):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"CCIP model not found: {model_path}")

        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        available = ort.get_available_providers()
        chosen = [p for p in providers if p in available]
        if not chosen:
            chosen = ["CPUExecutionProvider"]

        opts = ort.SessionOptions()
        opts.enable_mem_pattern = True
        self.session = ort.InferenceSession(model_path, sess_options=opts, providers=chosen)
        self.input_name = self.session.get_inputs()[0].name

    def embed_crop(self, crop_bgr: np.ndarray) -> np.ndarray:
        """Run CCIP ONNX model on a single portrait crop."""
        rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
        resized = cv2.resize(rgb, (CCIP_SIZE, CCIP_SIZE), interpolation=cv2.INTER_LINEAR)
        blob = resized.astype(np.float32) / 255.0
        blob = np.transpose(blob, (2, 0, 1))  # (3, H, W)
        blob = np.expand_dims(blob, axis=0)  # (1, 3, H, W)

        # Normalize with ImageNet mean and std
        blob = (blob - IMAGENET_MEAN) / IMAGENET_STD

        raw_out = self.session.run(None, {self.input_name: blob})
        feat = raw_out[0].flatten().astype(np.float32)
        norm = np.linalg.norm(feat)
        if norm > 0:
            feat /= norm
        return feat

    def embed(self, img: np.ndarray, bbox: List[float]) -> List[float]:
        """Extract total 792-d appearance (768 CCIP + 16 outfit + 8 hat)."""
        img_h, img_w = img.shape[:2]
        l, t, r, b = asymmetric_ccip_crop(bbox, img_w, img_h)
        crop = img[t:b, l:r]

        if crop.size == 0 or crop.shape[0] < 2 or crop.shape[1] < 2:
            ccip_feat = np.zeros(CCIP_DIM, dtype=np.float32)
        else:
            ccip_feat = self.embed_crop(crop)

        outfit_feat = extract_outfit_hue(img, bbox)
        hat_feat = extract_hat_hue(img, bbox)

        total = np.concatenate([ccip_feat, np.array(outfit_feat), np.array(hat_feat)])
        return [round(float(x), 5) for x in total]
