"""mask_utils: RMBG 1.4 pre/post-processing, person selection, BGR/RGB handling.

CPU only. The last check runs the real models/rmbg.onnx on lora_datasets body crops
when both exist (skipped otherwise): the 2026-10-31 bug marked 75-99 % of every
photo as foreground. Exits 1 on failure.
"""
import glob
import sys

import cv2
import numpy as np

import mask_utils

failures = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f" - {detail}" if detail and not ok else ""))
    if not ok:
        failures.append(name)


# --- preprocessing: RGB order, x/255 - 0.5, NCHW --------------------------------
img = np.zeros((10, 20, 3), np.uint8)
img[..., 0] = 255                                 # pure red in RGB
x = mask_utils.rmbg_input(img)
check("input shape", x.shape == (1, 3, 1024, 1024) and x.dtype == np.float32, str(x.shape))
check("input normalisation", abs(x[0, 0].mean() - 0.5) < 1e-5 and abs(x[0, 1].mean() + 0.5) < 1e-5,
      f"{x[0, 0].mean()} {x[0, 1].mean()}")

# --- postprocessing: min-max before the threshold ---------------------------------
raw = np.full((1024, 1024), 0.30, np.float32)
raw[:, 512:] = 0.40                               # all below 0.5 before normalising
m = mask_utils.rmbg_mask(raw, 64, 32)
check("min-max postprocess", m.shape == (32, 64) and m[:, :20].max() == 0 and m[:, 50:].min() == 255)
check("flat output is empty", mask_utils.rmbg_mask(np.full((8, 8), 0.7, np.float32), 4, 4).max() == 0)

# --- person selection --------------------------------------------------------------
mask = np.zeros((400, 400), np.uint8)
mask[50:300, 100:180] = 255                       # the person (face at the top)
mask[320:390, 110:170] = 255                      # legs split off below, sizeable
mask[20:80, 300:390] = 255                        # another object, far right
kept = mask_utils.keep_person(mask, (110, 50, 170, 110))
check("keeps the anchored person", kept[100, 140] == 255)
check("keeps split legs below the face", kept[350, 140] == 255)
check("drops unrelated object", kept[50, 350] == 0)
check("no anchor keeps all", mask_utils.keep_person(mask, None)[50, 350] == 255)
check("anchor on background keeps all", mask_utils.keep_person(mask, (0, 350, 20, 399))[50, 350] == 255)


# --- get_person_bbox converts BGR to RGB before segmenting ---------------------------
class _Sess:
    def __init__(self):
        self.seen = None

    def get_inputs(self):
        return [type("I", (), {"name": "input"})()]

    def run(self, _, feeds):
        self.seen = feeds["input"]
        out = np.zeros((1, 1, 1024, 1024), np.float32)
        out[0, 0, 256:768, 256:768] = 1.0
        return [out]


class _Face:
    bbox = np.array([45, 30, 55, 40], np.float32)


class _FaceApp:
    def get(self, _):
        return [_Face()]


fake = _Sess()
saved = mask_utils._RMBG_SESSION
mask_utils._RMBG_SESSION = fake
try:
    bgr = np.zeros((100, 100, 3), np.uint8)
    bgr[..., 0] = 255                             # pure blue in BGR
    box = mask_utils.get_person_bbox(bgr, _FaceApp(), margin_ratio=0.0)
    check("BGR converted to RGB", fake.seen is not None and fake.seen[0, 2].mean() > 0.49 and fake.seen[0, 0].mean() < -0.49)
    check("person box from the mask", box is not None and box[0] <= 26 and box[2] >= 74, str(box))
finally:
    mask_utils._RMBG_SESSION = saved

# --- real model regression (optional) ---------------------------------------------------
crops = sorted(glob.glob("lora_datasets/*/*/*_body.jpg"))[:6]
if crops and mask_utils._RMBG_MODEL_PATH.exists():
    fractions = []
    for path in crops:
        bgr = cv2.imread(path)
        m = mask_utils.get_segmentation_mask(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        fractions.append(float((m > 0).mean()))
    mean = sum(fractions) / len(fractions)
    check("real RMBG separates the person", 0.05 < mean < 0.80, f"mean foreground {mean:.2f}: {fractions}")
else:
    print("SKIP real RMBG check (no model or no lora_datasets body crops)")

if failures:
    print(f"\n{len(failures)} failure(s): {failures}")
    sys.exit(1)
print("\nAll mask_utils checks passed.")
