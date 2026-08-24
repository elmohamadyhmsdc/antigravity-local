"""Smoke test for the V3 HD reface pipeline: model I/O + a real swap."""
from pathlib import Path
import onnxruntime as ort

print("=== model I/O ===")
for f in ["codeformer", "bisenet_resnet_34", "xseg_1"]:
    p = Path("models") / f"{f}.onnx"
    if not p.exists():
        print(f"{f}: MISSING"); continue
    s = ort.InferenceSession(str(p), providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
    print(f"{f}: provider={s.get_providers()[0]}")
    for i in s.get_inputs():
        print("   in ", i.name, i.shape, i.type)
    for o in s.get_outputs():
        print("   out", o.name, o.shape, o.type)

print("\n=== V3 init ===")
from reface_engine_v3 import RefaceEngineV3
eng = RefaceEngineV3(restorer="codeformer")
print("swapper:", eng.swapper is not None,
      "| restorer:", eng.restorer.available,
      "| parser:", eng.masker.parser is not None,
      "| occluder:", eng.masker.occluder is not None)

print("\n=== real swap (alexandra faceset) ===")
fs = eng.load_faceset_by_name("alexandra")
print("faceset faces:", len(fs.faces) if fs else None)
if fs and fs.faces:
    tgt = fs.faces[0].image_path
    print("target:", tgt, "exists:", Path(tgt).exists())
    res = eng.reface_image_v3(tgt, fs)
    print("RESULT success:", res.success)
    print("RESULT msg:", res.message)
    print("RESULT path:", res.output_path)
