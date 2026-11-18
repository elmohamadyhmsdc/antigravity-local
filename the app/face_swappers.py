"""
Antigravity Local - face swapper models for the V3 pipeline

Every swapper here exposes the one call RefaceEngineV3 makes on insightface's
INSwapper:

    swapper.get(img, target_face, source_face, paste_back=False) -> (crop_bgr, M)

where M is the 2x3 frame->crop affine. face_compositor takes it from there
(restore, masks, harmonize, paste), so a swapper only has to produce the
swapped face crop and say where it came from.

HyperSwap (FaceFusion, 256 px) reads the same unit-norm ArcFace w600k
embedding that inswapper does - identity.AveragedSource.normed_embedding - so
an identity built for one works for the other. Alignment and normalisation
follow FaceFusion's model set for it: 'arcface_128' template, input and output
in [-1, 1], RGB, NCHW.
"""

from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from cuda_dll_dirs import add_nvidia_dll_dirs
add_nvidia_dll_dirs()

import onnxruntime as ort

MODELS_DIR = Path(__file__).parent / "models"

# FaceFusion's WARP_TEMPLATE_SET['arcface_128'], normalised to [0, 1].
ARCFACE_128 = np.array([[0.36167656, 0.40387734],
                        [0.63696719, 0.40235469],
                        [0.50019687, 0.56044219],
                        [0.38710391, 0.72160547],
                        [0.61507734, 0.72034453]], np.float32)

# name -> (file, crop size). inswapper_128 uses inswapper_loader.
SWAPPERS = {
    "inswapper_128": ("inswapper_128.onnx", 128),
    "hyperswap_1b_256": ("hyperswap_1b_256.onnx", 256),
    "hyperswap_1c_256": ("hyperswap_1c_256.onnx", 256),
}
DEFAULT_SWAPPER = "inswapper_128"


def available_swappers():
    return [n for n, (f, _) in SWAPPERS.items() if (MODELS_DIR / f).exists()]


def template_matrix(kps, template: np.ndarray, size: int) -> Optional[np.ndarray]:
    """frame->crop similarity transform taking 5-point kps onto a template
    (FaceFusion's estimate_matrix_by_face_landmark_5)."""
    src = np.asarray(kps, np.float32)
    if src.shape != (5, 2):
        return None
    m, _ = cv2.estimateAffinePartial2D(src, template * size, method=cv2.RANSAC,
                                       ransacReprojThreshold=100.0)
    return m


class HyperSwapper:
    """FaceFusion HyperSwap 1a/1b/1c at 256 px, on onnxruntime."""

    def __init__(self, model_path, providers=None):
        providers = providers or ["CUDAExecutionProvider", "CPUExecutionProvider"]
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        self.session = ort.InferenceSession(str(model_path), sess_options=so, providers=providers)
        self.size = 256
        self.pixel_boost = False
        self._img_in, self._emb_in = None, None
        inputs = {i.name: i for i in self.session.get_inputs()}
        for inp in inputs.values():
            if len(inp.shape) == 4:
                self._img_in = inp.name
                dims = [d for d in inp.shape[2:] if isinstance(d, int) and d > 0]
                if dims:
                    self.size = dims[-1]
            else:
                self._emb_in = inp.name
        if self._img_in is None or self._emb_in is None:
            raise ValueError(f"unexpected HyperSwap inputs: {list(inputs)}")
        self._img_type = inputs[self._img_in].type   # the fp16 builds may declare float16 I/O
        self._emb_type = inputs[self._emb_in].type
        self.name = Path(model_path).stem

    @staticmethod
    def _np_dtype(type_str):
        return np.float16 if "float16" in type_str else np.float32

    def swap_crop(self, crop_bgr: np.ndarray, embedding: np.ndarray) -> np.ndarray:
        """Swap an already-aligned crop (arcface_128 at self.size)."""
        blob = (crop_bgr[:, :, ::-1].astype(np.float32) / 255.0 - 0.5) / 0.5
        blob = blob.transpose(2, 0, 1)[None].astype(self._np_dtype(self._img_type))
        emb = np.asarray(embedding, np.float32).reshape(1, -1).astype(self._np_dtype(self._emb_type))
        out = self.session.run(None, {self._img_in: blob, self._emb_in: emb})[0][0]
        out = out.astype(np.float32).transpose(1, 2, 0) * 0.5 + 0.5
        return (np.clip(out, 0.0, 1.0)[:, :, ::-1] * 255.0).round().astype(np.uint8)

    def get(self, img, target_face, source_face, paste_back: bool = False):
        m = template_matrix(target_face.kps, ARCFACE_128, self.size)
        if m is None:
            raise ValueError("degenerate target landmarks")
        box = getattr(target_face, "bbox", None)
        detail = 0.
        if self.pixel_boost and box is not None:
            detail = float(np.clip((box[3] - box[1] - self.size) / (.25 * self.size), 0, 1))
        size = self.size * 2 if detail > 0 else self.size
        if detail > 0:
            m = m * 2
        crop = cv2.warpAffine(img, m, (size, size), borderMode=cv2.BORDER_REPLICATE,
                              flags=cv2.INTER_AREA)
        if detail > 0:
            # Each interleaved view contains the entire face at model resolution.
            # Sequential inference uses the ordinary batch-one ONNX session.
            swapped = np.empty_like(crop)
            for y in range(2):
                for x in range(2):
                    swapped[y::2, x::2] = self.swap_crop(crop[y::2, x::2], source_face.normed_embedding)
            if detail < 1:
                # The (0,0) sub-grid samples exactly the ordinary crop. Fade
                # from it as a tracked face grows, avoiding a sharpness jump.
                ordinary = cv2.warpAffine(swapped[::2, ::2], np.float32([[2, 0, 0], [0, 2, 0]]),
                                          (size, size), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
                swapped = cv2.addWeighted(ordinary, 1 - detail, swapped, detail, 0)
        else:
            swapped = self.swap_crop(crop, source_face.normed_embedding)
        if not paste_back:
            return swapped, m
        # Plain feathered-box paste, the same last resort insightface offers.
        h, w = img.shape[:2]
        im = cv2.invertAffineTransform(m)
        mask = np.zeros((size, size), np.float32)
        b = size // 10
        mask[b:-b, b:-b] = 1.0
        mask = cv2.GaussianBlur(mask, (0, 0), size / 20)
        back = cv2.warpAffine(swapped, im, (w, h), borderMode=cv2.BORDER_REPLICATE)
        mb = cv2.warpAffine(mask, im, (w, h))[..., None]
        return (img.astype(np.float32) * (1 - mb) + back.astype(np.float32) * mb).astype(np.uint8)


def load_swapper(name: str, providers=None):
    """A non-insightface swapper by name, or None if it isn't one / isn't downloaded."""
    if name not in SWAPPERS or name == "inswapper_128":
        return None
    path = MODELS_DIR / SWAPPERS[name][0]
    if not path.exists():
        print(f"[SWAP] {path.name} not downloaded "
              f"(venv\\Scripts\\python download_models.py {name}); using inswapper_128")
        return None
    if name.startswith("hyperswap"):
        return HyperSwapper(path, providers)
    return None
