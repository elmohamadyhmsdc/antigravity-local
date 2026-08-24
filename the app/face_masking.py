"""
Antigravity Local - Face masking (parser + occluder)

Produces the paste-back mask used by the HD reface pipeline. Two ONNX models,
both on onnxruntime-gpu:

  * face parser (BiSeNet, CelebAMask-HQ 19 classes) -> which pixels are the
    face *region* we want to replace (skin, brows, eyes, nose, lips). Hair,
    glasses, hat, neck and background are excluded, so they keep original pixels
    and the hairline/jaw blend stays clean.

  * face occluder (XSeg) -> which pixels are an actual occluder in front of the
    face (hand, mic, glasses frame...). The final mask is region * occlusion, so
    occluders are preserved instead of being painted over.

If a model file is absent the masker degrades gracefully (soft box instead of a
parser region; no occluder subtraction).
"""

import os
import sys
from pathlib import Path
from typing import List, Optional

import cv2
import numpy as np

if os.name == "nt":
    _nvidia_base = os.path.join(sys.prefix, "Lib", "site-packages", "nvidia")
    if os.path.isdir(_nvidia_base):
        for _pkg in os.listdir(_nvidia_base):
            _bin = os.path.join(_nvidia_base, _pkg, "bin")
            if os.path.isdir(_bin):
                try:
                    os.add_dll_directory(_bin)
                    os.environ["PATH"] = _bin + os.pathsep + os.environ.get("PATH", "")
                except Exception:
                    pass

import onnxruntime as ort

MODELS_DIR = Path(__file__).parent / "models"

PARSER_FILE = "bisenet_resnet_34.onnx"
OCCLUDER_FILE = "xseg_1.onnx"

# CelebAMask-HQ class indices used by BiSeNet
REGIONS = {
    "skin": 1, "left-eyebrow": 2, "right-eyebrow": 3, "left-eye": 4,
    "right-eye": 5, "glasses": 6, "left-ear": 7, "right-ear": 8,
    "nose": 10, "mouth": 11, "upper-lip": 12, "lower-lip": 13,
    "neck": 14, "cloth": 16, "hair": 17, "hat": 18,
}
# Default swap region: facial skin + features, NOT hair/glasses/hat/neck/ears
DEFAULT_REGIONS = ["skin", "left-eyebrow", "right-eyebrow", "left-eye",
                   "right-eye", "nose", "mouth", "upper-lip", "lower-lip"]

_IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_IMAGENET_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def _make_session(path: Path, providers):
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    return ort.InferenceSession(str(path), sess_options=so, providers=providers)


def _layout(shape):
    """Return ('nchw'|'nhwc', size) from a 4-D input shape."""
    # channel axis is the dim equal to 3
    if len(shape) == 4 and shape[1] == 3:
        dims = [d for d in shape[2:] if isinstance(d, int) and d > 0]
        return "nchw", (dims[-1] if dims else 512)
    dims = [d for d in shape[1:3] if isinstance(d, int) and d > 0]
    return "nhwc", (dims[-1] if dims else 256)


class FaceMasker:
    def __init__(self, parser_path: Optional[str] = None,
                 occluder_path: Optional[str] = None, providers=None):
        providers = providers or ["CUDAExecutionProvider", "CPUExecutionProvider"]
        self.parser = None
        self.occluder = None
        self._parser_in = None
        self._parser_layout = ("nchw", 512)
        self._occ_in = None
        self._occ_layout = ("nhwc", 256)

        pp = Path(parser_path) if parser_path else MODELS_DIR / PARSER_FILE
        op = Path(occluder_path) if occluder_path else MODELS_DIR / OCCLUDER_FILE

        if pp.exists():
            try:
                self.parser = _make_session(pp, providers)
                self._parser_in = self.parser.get_inputs()[0].name
                self._parser_layout = _layout(self.parser.get_inputs()[0].shape)
                print(f"[MASK] face parser loaded ({self._parser_layout})")
            except Exception as e:
                print(f"[MASK] parser load failed: {e}")
        else:
            print(f"[MASK] parser not found: {pp} (using box region mask)")

        if op.exists():
            try:
                self.occluder = _make_session(op, providers)
                self._occ_in = self.occluder.get_inputs()[0].name
                self._occ_layout = _layout(self.occluder.get_inputs()[0].shape)
                print(f"[MASK] face occluder loaded ({self._occ_layout})")
            except Exception as e:
                print(f"[MASK] occluder load failed: {e}")
        else:
            print(f"[MASK] occluder not found: {op} (no occlusion handling)")

    # ---- individual masks -------------------------------------------------

    def segment(self, crop_bgr: np.ndarray):
        """Run the parser and return a (H, W) class-index map at crop size.

        Returns None if the parser is unavailable or fails. One pass yields
        every region, so callers needing both a swap region and a skin mask
        should call this once rather than region_mask twice.
        """
        if self.parser is None:
            return None
        try:
            h, w = crop_bgr.shape[:2]
            layout, size = self._parser_layout
            prep = cv2.resize(crop_bgr, (size, size))[:, :, ::-1].astype(np.float32) / 255.0
            prep = (prep - _IMAGENET_MEAN) / _IMAGENET_STD
            if layout == "nchw":
                prep = prep.transpose(2, 0, 1)
            prep = prep[None, ...].astype(np.float32)
            out = self.parser.run(None, {self._parser_in: prep})[0][0]
            seg = out.argmax(0) if out.shape[0] <= 32 else out.argmax(-1)
            return cv2.resize(seg.astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST)
        except Exception as e:
            print(f"[MASK] segment failed: {e}")
            return None

    def region_mask(self, crop_bgr: np.ndarray, regions: List[str]) -> np.ndarray:
        """Float [0,1] mask of the given regions, at crop resolution."""
        h, w = crop_bgr.shape[:2]
        seg = self.segment(crop_bgr)
        if seg is None:
            return box_mask(h, w)
        return region_from_seg(seg, regions)

    def occlusion_mask(self, crop_bgr: np.ndarray) -> Optional[np.ndarray]:
        """Float [0,1] mask: 1 = visible face, 0 = occluder. None if unavailable."""
        if self.occluder is None:
            return None
        try:
            h, w = crop_bgr.shape[:2]
            layout, size = self._occ_layout
            prep = cv2.resize(crop_bgr, (size, size)).astype(np.float32) / 255.0
            if layout == "nchw":
                prep = prep.transpose(2, 0, 1)
            prep = prep[None, ...].astype(np.float32)
            out = self.occluder.run(None, {self._occ_in: prep})[0][0]
            out = np.squeeze(out).clip(0, 1).astype(np.float32)
            return cv2.resize(out, (w, h), interpolation=cv2.INTER_LINEAR)
        except Exception as e:
            print(f"[MASK] occlusion_mask failed: {e}")
            return None

    # ---- combined paste mask ---------------------------------------------

    def build_paste_mask(
        self,
        restored_crop: np.ndarray,
        original_aligned_crop: Optional[np.ndarray] = None,
        regions: Optional[List[str]] = None,
        use_parser: bool = True,
        use_occluder: bool = True,
        feather: float = 0.08,
        erode: float = 0.0,
    ) -> np.ndarray:
        """Combine region (from restored face) and occlusion (from the original
        aligned crop) into a single feathered [0,1] paste mask."""
        h, w = restored_crop.shape[:2]
        regions = regions or DEFAULT_REGIONS

        if use_parser and self.parser is not None:
            mask = self.region_mask(restored_crop, regions)
        else:
            mask = box_mask(h, w)

        if use_occluder and self.occluder is not None and original_aligned_crop is not None:
            occ = self.occlusion_mask(original_aligned_crop)
            if occ is not None:
                mask = mask * occ

        # Pull the boundary in a touch so we never blend swapped pixels past the jaw
        if erode > 0:
            k = max(1, int(min(h, w) * erode))
            mask = cv2.erode(mask, np.ones((k, k), np.uint8))

        if feather > 0:
            k = max(1, int(min(h, w) * feather))
            k = k + 1 if k % 2 == 0 else k
            mask = cv2.GaussianBlur(mask, (k, k), 0)

        return np.clip(mask, 0.0, 1.0)


def box_mask(h: int, w: int, padding: float = 0.12) -> np.ndarray:
    """Soft rectangular mask used when the parser is unavailable."""
    mask = np.zeros((h, w), dtype=np.float32)
    py, px = int(h * padding), int(w * padding)
    mask[py:h - py, px:w - px] = 1.0
    k = max(1, int(min(h, w) * 0.08))
    k = k + 1 if k % 2 == 0 else k
    return cv2.GaussianBlur(mask, (k, k), 0)


def region_from_seg(seg: np.ndarray, regions: List[str]) -> np.ndarray:
    """Float [0,1] mask selecting the named classes out of a segmentation map."""
    idx = [REGIONS[r] for r in regions if r in REGIONS]
    return np.isin(seg, idx).astype(np.float32)


def harden_occlusion(occ: np.ndarray, sigma: float = 5.0) -> np.ndarray:
    """Turn the occluder's soft probability field into a usable matte.

    Blur, then remap [0.5, 1] onto [0, 1] (facefusion's convention). Without
    this the raw field dissolves under feathering and an occluding hand comes
    back as a translucent ghost.
    """
    blurred = cv2.GaussianBlur(occ.astype(np.float32), (0, 0), sigma)
    return np.clip((np.clip(blurred, 0.5, 1.0) - 0.5) * 2.0, 0.0, 1.0)


def feather_mask(mask: np.ndarray, erode: float = 0.02, feather: float = 0.05) -> np.ndarray:
    """Erode, then ramp inward with a distance transform.

    A Gaussian applied to a binary mask gives an edge whose width varies with
    local shape. A distance transform gives a uniform-width ramp, which is what
    a clean paste boundary needs.
    """
    h, w = mask.shape[:2]
    size = min(h, w)
    binary = (mask > 0.5).astype(np.uint8)

    e = int(size * erode)
    if e > 0:
        binary = cv2.erode(binary, np.ones((2 * e + 1, 2 * e + 1), np.uint8))

    f = max(2.0, size * feather)
    dist = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    ramp = np.clip(dist / f, 0.0, 1.0).astype(np.float32)
    return cv2.GaussianBlur(ramp, (0, 0), 1.0)
