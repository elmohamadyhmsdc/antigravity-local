"""
Antigravity Local - ONNX face restoration (CodeFormer / GFPGAN / GPEN)

Runs a face-restoration GAN on an ALIGNED face crop via onnxruntime-gpu and
returns the restored crop at the model's native resolution (usually 512). This
is what turns the 128px inswapper output into something that looks natively
sharp.

All of these models share facefusion's I/O convention:
  input : aligned face, RGB, normalized to [-1, 1], NCHW float32
  output: restored face, RGB, [-1, 1], NCHW  -> back to BGR uint8

CodeFormer has a second scalar input ("weight"/fidelity w): higher w keeps more
of the (degraded) input identity, lower w restores more aggressively. We detect
that input by shape and feed it automatically.
"""

import os
import sys
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

# Add NVIDIA DLL dirs so onnxruntime-gpu finds CUDA
from cuda_dll_dirs import add_nvidia_dll_dirs
add_nvidia_dll_dirs()

import onnxruntime as ort

MODELS_DIR = Path(__file__).parent / "models"

# Known restorer filenames in models/ (first existing one wins for "auto")
RESTORER_FILES = {
    "codeformer": "codeformer.onnx",
    "gfpgan_1.4": "gfpgan_1.4.onnx",
    "gpen_bfr_512": "gpen_bfr_512.onnx",
}


class FaceRestorer:
    """ONNX face restorer operating on an aligned crop."""

    def __init__(
        self,
        model_name: str = "codeformer",
        model_path: Optional[str] = None,
        providers=None,
        weight: float = 0.7,
    ):
        self.weight = float(weight)
        self.available = False
        self.size = 512
        self.session = None
        self._img_input = None
        self._scalar_input = None  # (name, dtype) for codeformer's weight

        if model_path is None:
            fname = RESTORER_FILES.get(model_name, f"{model_name}.onnx")
            model_path = str(MODELS_DIR / fname)
        self.model_name = model_name
        self.model_path = model_path

        if not Path(model_path).exists():
            print(f"[RESTORE] model not found: {model_path} (restoration disabled)")
            return

        providers = providers or ["CUDAExecutionProvider", "CPUExecutionProvider"]
        try:
            so = ort.SessionOptions()
            so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            self.session = ort.InferenceSession(model_path, sess_options=so, providers=providers)
            self._introspect()
            self.available = True
            actual = self.session.get_providers()[0] if self.session.get_providers() else "?"
            print(f"[RESTORE] {self.model_name} loaded ({self.size}px, {actual})")
        except Exception as e:
            print(f"[RESTORE] failed to load {model_path}: {e}")
            self.session = None

    def _introspect(self):
        """Find the image input (4-D) and the optional scalar weight input."""
        for inp in self.session.get_inputs():
            shape = inp.shape
            if len(shape) == 4:
                self._img_input = inp.name
                # spatial size = last static dim, default 512
                dims = [d for d in shape[2:] if isinstance(d, int) and d > 0]
                if dims:
                    self.size = dims[-1]
            else:
                # scalar / 1-element input -> codeformer fidelity weight
                self._scalar_input = (inp.name, inp.type, inp.shape)
        if self._img_input is None:
            # fall back to first input
            self._img_input = self.session.get_inputs()[0].name

    def _scalar_value(self):
        """Build the weight tensor matching the model's declared dtype and rank.
        CodeFormer declares this input as a 0-d scalar ([]), so feed a 0-d array."""
        name, type_str, shape = self._scalar_input
        dtype = np.float64 if "double" in type_str else np.float32
        if len([d for d in shape if d not in (None, 0)]) == 0:  # scalar []
            return name, np.array(self.weight, dtype=dtype)
        return name, np.array([self.weight], dtype=dtype)

    def enhance(self, crop_bgr: np.ndarray) -> np.ndarray:
        """Restore an aligned face crop. Returns BGR uint8 at model size."""
        if not self.available or crop_bgr is None:
            return crop_bgr
        try:
            face = cv2.resize(crop_bgr, (self.size, self.size), interpolation=cv2.INTER_LINEAR)
            blob = face[:, :, ::-1].astype(np.float32) / 255.0       # BGR->RGB, [0,1]
            blob = (blob - 0.5) / 0.5                                 # [-1,1]
            blob = blob.transpose(2, 0, 1)[None, ...].astype(np.float32)  # NCHW

            feeds = {self._img_input: blob}
            if self._scalar_input is not None:
                name, val = self._scalar_value()
                feeds[name] = val

            out = self.session.run(None, feeds)[0]
            out = out[0].transpose(1, 2, 0)                            # HWC
            out = np.clip(out, -1, 1)
            out = (out + 1) / 2 * 255.0
            out = out[:, :, ::-1]                                      # RGB->BGR
            return np.clip(out, 0, 255).astype(np.uint8)
        except Exception as e:
            print(f"[RESTORE] enhance failed: {e}")
            return crop_bgr


def resolve_restorer_name(preferred: str = "codeformer") -> Optional[str]:
    """Return a restorer name whose model file exists in models/, preferring
    `preferred`, else any available, else None."""
    if (MODELS_DIR / RESTORER_FILES.get(preferred, "")).exists():
        return preferred
    for name, fname in RESTORER_FILES.items():
        if (MODELS_DIR / fname).exists():
            return name
    return None
