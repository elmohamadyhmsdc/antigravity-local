"""
Phase 8 (roadmap section 7.5): fetch DINOv2 ViT-S/14 (facebook/dinov2-small, 384-d) and export it to ONNX as
models/reid/dinov2_vits14.onnx. Two steps, because the CUDA-torch environment has no onnxruntime and the main
venv has no torch. Both run on the CPU, so a running scan is never disturbed:

    venv_ai\\Scripts\\python.exe export_dinov2.py            # 1. download + export to a .part file + a probe
    venv\\Scripts\\python.exe export_dinov2.py --verify      # 2. compare onnxruntime with torch, move into place

Input  : images  (batch, 3, 224, 224) float32, RGB, ImageNet mean/std normalised.
Output : embedding (batch, 384) - the pooled CLS token, NOT unit length (callers normalise).
"""

import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
TARGET = HERE / "models" / "reid" / "dinov2_vits14.onnx"
PART = TARGET.with_suffix(".onnx.part")
PROBE = TARGET.with_suffix(".probe.npz")
MIN_BYTES = 40 * 1024 * 1024        # ViT-S/14 in fp32 is ~88 MB


def export() -> int:
    os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")        # CPU only: the overnight scan owns the GPU
    import numpy as np
    import torch
    from transformers import Dinov2Model

    torch.set_num_threads(4)
    last = None
    for _ in range(2):
        try:
            model = Dinov2Model.from_pretrained("facebook/dinov2-small").eval()
            break
        except Exception as error:      # noqa: BLE001 - network hiccup: retry once
            last = error
    else:
        raise SystemExit(f"download failed: {last}")

    class Embedder(torch.nn.Module):
        def __init__(self, inner):
            super().__init__()
            self.inner = inner

        def forward(self, images):
            return self.inner(pixel_values=images).pooler_output

    wrapped = Embedder(model).eval()
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    probe = np.random.default_rng(0).standard_normal((2, 3, 224, 224)).astype(np.float32)
    with torch.no_grad():
        expected = wrapped(torch.from_numpy(probe)).numpy()
        torch.onnx.export(wrapped, torch.zeros(1, 3, 224, 224), str(PART), input_names=["images"],
                          output_names=["embedding"],
                          dynamic_axes={"images": {0: "batch"}, "embedding": {0: "batch"}},
                          opset_version=17, dynamo=False)
    np.savez(PROBE, probe=probe, expected=expected)
    print(f"exported {PART} ({PART.stat().st_size} bytes); now run: venv\\Scripts\\python.exe export_dinov2.py --verify")
    return 0


def verify() -> int:
    import numpy as np
    import onnxruntime as ort

    if not PART.exists() or not PROBE.exists():
        raise SystemExit("run the export step first (venv_ai)")
    if PART.stat().st_size < MIN_BYTES:
        raise SystemExit("exported file is too small")
    with np.load(PROBE) as data:
        probe, expected = data["probe"], data["expected"]
    sess = ort.InferenceSession(str(PART), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"images": probe})[0]
    diff = float(np.abs(got - expected).max())
    if got.shape != (2, 384) or diff > 1e-2:
        raise SystemExit(f"ONNX output differs from torch: shape {got.shape}, max diff {diff}")
    one = sess.run(None, {"images": probe[:1]})[0]       # dynamic batch really works
    assert one.shape == (1, 384)
    os.replace(PART, TARGET)
    PROBE.unlink(missing_ok=True)
    print(f"wrote {TARGET} ({TARGET.stat().st_size} bytes), max diff to torch {diff:.2e}")
    return 0


if __name__ == "__main__":
    sys.exit(verify() if "--verify" in sys.argv else export())
