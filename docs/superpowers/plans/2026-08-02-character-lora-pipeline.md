# Character LoRA Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app pipeline that builds a face+body training set for a saved person, trains a per-person SD1.5 LoRA on it, and generates a clean "master reference" portrait from the trained LoRA — replacing the current bare-bones "📤 Export for LoRA" page with a three-tab "🧬 Character LoRA" page.

**Architecture:** Three new standalone modules (`lora_dataset.py`, `lora_trainer.py`, `lora_generate.py`) plug into `the app/`'s existing patterns: `database.py` for person/face records, `job_manager.py`'s sequential queue for the long-running training step, and the `venv_ai`-subprocess pattern (`undress_engine.py`) for GPU-heavy work. Training runs in a new isolated `venv_lora` (Python 3.10 + `kohya-ss/sd-scripts`) to avoid dependency conflicts with `venv_ai`'s Magic Undress stack; generation reuses `venv_ai` directly since `diffusers` is already installed there.

**Tech Stack:** Python 3.13 (main `venv`) for dataset building and UI; Python 3.10 (`venv_lora`, new) for training via `sd-scripts`; Python 3.10 (`venv_ai`, existing) for LoRA inference via `diffusers`; ONNX Runtime GPU (main `venv`) for WD14 auto-captioning; Streamlit for UI.

**Spec:** `docs/superpowers/specs/2026-08-02-character-lora-pipeline-design.md`

---

## Before You Start

- Working directory for all file paths below is `D:\AndroidScan\gallary\the app\` unless stated otherwise.
- This repo has a standing rule: **do not run terminal commands yourself** — post the exact command and wait for the user to run it and paste back the output. This applies to every `Run:` line below, and especially to the `venv_lora` setup (Task 10) and any model download script (Task 4) — downloading multi-GB model files also requires the user's explicit go-ahead per the file-download safety rule, so never invoke those scripts unattended.
- There is no pytest suite in this repo. Tests are standalone scripts that `print(...)` and `exit(1)` on failure — see `test_stats.py` for the exact convention to match.
- Commit after each task, not after each step, using the message shown at the end of the task.

---

### Task 1: Person LoRA metadata (trigger word + trained LoRA path)

**Files:**
- Modify: `database.py:150-178` (person methods), `database.py:453-479` (module-level wrappers)
- Test: `test_lora_dataset.py` (new)

- [ ] **Step 1: Write the failing test**

Create `test_lora_dataset.py`:

```python
try:
    from database import JsonDatabase, add_person, get_person_lora_info, set_person_lora_info

    db = JsonDatabase()
    pid = add_person("LoRA Test Person")

    info = get_person_lora_info(pid)
    if info.get("trigger_word") is not None or info.get("lora_path") is not None:
        print(f"Expected empty lora info for a new person, got: {info}")
        exit(1)

    set_person_lora_info(pid, trigger_word="sks7", lora_path="models/loras/lora_test_person.safetensors")
    info = get_person_lora_info(pid)
    if info["trigger_word"] != "sks7":
        print(f"trigger_word not persisted: {info}")
        exit(1)
    if info["lora_path"] != "models/loras/lora_test_person.safetensors":
        print(f"lora_path not persisted: {info}")
        exit(1)

    db.delete_person(pid)
    print("Task 1 verification successful! Person LoRA metadata round-trips correctly.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: FAIL with `Import failed: cannot import name 'get_person_lora_info' from 'database'`

- [ ] **Step 3: Add the fields to `JsonDatabase`**

In `database.py`, add these two methods right after `update_person_name` (after line 166, before `def delete_person`):

```python
    def set_person_lora_info(self, person_id: int, trigger_word: Optional[str] = None, lora_path: Optional[str] = None):
        """Attach LoRA training metadata to a person record."""
        if person_id not in self.persons:
            return
        if trigger_word is not None:
            self.persons[person_id]["trigger_word"] = trigger_word
        if lora_path is not None:
            self.persons[person_id]["lora_path"] = lora_path
        self.persons[person_id]["updated_at"] = datetime.utcnow().isoformat()
        self.save_db()

    def get_person_lora_info(self, person_id: int) -> Dict[str, Optional[str]]:
        """Return {trigger_word, lora_path} for a person, both None if unset."""
        person = self.persons.get(person_id, {})
        return {
            "trigger_word": person.get("trigger_word"),
            "lora_path": person.get("lora_path"),
        }
```

- [ ] **Step 4: Add module-level wrappers**

In `database.py`, right after `update_person_name` wrapper (after line 466):

```python
def set_person_lora_info(person_id, trigger_word=None, lora_path=None):
    db_instance.set_person_lora_info(person_id, trigger_word, lora_path)

def get_person_lora_info(person_id):
    return db_instance.get_person_lora_info(person_id)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: `Task 1 verification successful! Person LoRA metadata round-trips correctly.`

- [ ] **Step 6: Commit**

```bash
git add database.py test_lora_dataset.py
git commit -m "feat: add trigger_word/lora_path metadata to person records"
```

---

### Task 2: Person-region crop helper in `mask_utils.py`

**Files:**
- Modify: `mask_utils.py` (add a function; `generate_body_mask` stays untouched)
- Test: `test_lora_dataset.py` (append)

- [ ] **Step 1: Write the failing test**

Edit `test_lora_dataset.py`: keep everything from Task 1 as-is, and insert this block immediately after Task 1's `print("Task 1 verification successful! ...")` line and before the file's `except ImportError as e:` line (same indentation level, still inside the one big `try:`), using a synthetic image so the test doesn't depend on real photos:

```python
    # --- Task 2: person bbox helper ---
    import numpy as np
    from mask_utils import get_person_bbox

    synthetic = np.zeros((480, 640, 3), dtype=np.uint8)
    synthetic[100:400, 150:500] = 200  # a bright rectangular "person" blob

    class _FakeFace:
        bbox = np.array([250, 120, 380, 220], dtype=np.float32)

    class _FakeFaceApp:
        def get(self, image_bgr):
            return [_FakeFace()]

    bbox = get_person_bbox(synthetic, _FakeFaceApp())
    if bbox is None:
        print("get_person_bbox returned None for a synthetic person image")
        exit(1)
    x1, y1, x2, y2 = bbox
    if not (0 <= x1 < x2 <= 640 and 0 <= y1 < y2 <= 480):
        print(f"get_person_bbox returned an invalid box: {bbox}")
        exit(1)
    print(f"Task 2 verification successful! get_person_bbox -> {bbox}")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: FAIL with `ImportError: cannot import name 'get_person_bbox' from 'mask_utils'`

- [ ] **Step 3: Implement `get_person_bbox`**

Add to `mask_utils.py`, after `generate_body_mask` (after line 62):

```python
def get_person_bbox(image_bgr_or_np, face_app, margin_ratio: float = 0.08):
    """
    Returns (x1, y1, x2, y2) bounding the full person (segmentation mask
    unioned with the detected face box), or None if no person/face is found.
    Accepts an RGB or BGR numpy array (MediaPipe expects RGB internally, but
    since we only threshold the segmentation mask, channel order doesn't
    change the result here).
    """
    image_np = np.asarray(image_bgr_or_np)
    h, w = image_np.shape[:2]

    import mediapipe.python.solutions.selfie_segmentation as mp_selfie_segmentation_sol
    with mp_selfie_segmentation_sol.SelfieSegmentation(model_selection=1) as selfie_segmentation:
        results = selfie_segmentation.process(image_np)
        person_mask = results.segmentation_mask > 0.5

    ys, xs = np.where(person_mask)
    if len(xs) == 0:
        person_box = None
    else:
        person_box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

    faces = face_app.get(image_np)
    face_box = None
    if faces:
        main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
        fx1, fy1, fx2, fy2 = main_face.bbox.astype(int)
        face_box = (fx1, fy1, fx2, fy2)

    if person_box is None and face_box is None:
        return None
    if person_box is None:
        x1, y1, x2, y2 = face_box
    elif face_box is None:
        x1, y1, x2, y2 = person_box
    else:
        x1 = min(person_box[0], face_box[0])
        y1 = min(person_box[1], face_box[1])
        x2 = max(person_box[2], face_box[2])
        y2 = max(person_box[3], face_box[3])

    box_w, box_h = x2 - x1, y2 - y1
    mx, my = int(box_w * margin_ratio), int(box_h * margin_ratio)
    x1 = max(0, x1 - mx)
    y1 = max(0, y1 - my)
    x2 = min(w, x2 + mx)
    y2 = min(h, y2 + my)

    return (x1, y1, x2, y2)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: both Task 1 and Task 2 success lines printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add mask_utils.py test_lora_dataset.py
git commit -m "feat: add get_person_bbox helper for full-person cropping"
```

---

### Task 3: `lora_dataset.py` — per-face crop extraction

**Files:**
- Create: `lora_dataset.py`
- Test: `test_lora_dataset.py` (append)

This is the function that, given one face record from `database.py`, returns a restored face crop and (when possible) a body crop.

- [ ] **Step 1: Write the failing test**

Edit `test_lora_dataset.py`: insert this block immediately after Task 2's `print("Task 2 verification successful! ...")` line and before `except ImportError as e:` (same indentation level as before):

```python
    # --- Task 3: extract_face_and_body_crop ---
    import cv2
    from lora_dataset import extract_face_and_body_crop

    # Build a small fixture image on disk (a plain color image is enough:
    # we're testing the code path and fallback behavior, not detection quality).
    fixture_dir = Path("temp_lora_test")
    fixture_dir.mkdir(exist_ok=True)
    fixture_path = fixture_dir / "fixture.jpg"
    fixture_img = np.full((480, 640, 3), 180, dtype=np.uint8)
    cv2.imwrite(str(fixture_path), fixture_img)

    face_record_image = {
        "source_path": str(fixture_path),
        "bbox_x": 250, "bbox_y": 120, "bbox_width": 130, "bbox_height": 100,
        "quality_score": 0.8,
        "image_path": str(fixture_path),
    }
    result = extract_face_and_body_crop(face_record_image, _FakeFaceApp())
    if result["face_crop"] is None:
        print("extract_face_and_body_crop returned no face_crop for a valid image source")
        exit(1)
    if result["skipped_body"]:
        print("Body crop unexpectedly skipped for an image source")
        exit(1)

    # Video source_path must always fall back to face-only (frame_number isn't persisted).
    face_record_video = {
        "source_path": "some_video.mp4",
        "bbox_x": 250, "bbox_y": 120, "bbox_width": 130, "bbox_height": 100,
        "quality_score": 0.8,
        "image_path": str(fixture_path),
    }
    result_video = extract_face_and_body_crop(face_record_video, _FakeFaceApp())
    if not result_video["skipped_body"]:
        print("Expected skipped_body=True for a video source_path")
        exit(1)
    if result_video["face_crop"] is None:
        print("extract_face_and_body_crop should still fall back to the saved face crop for a video source")
        exit(1)

    import shutil as _shutil
    _shutil.rmtree(fixture_dir, ignore_errors=True)
    print("Task 3 verification successful! extract_face_and_body_crop handles image and video sources.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: FAIL with `ImportError: cannot import name 'extract_face_and_body_crop' from 'lora_dataset'` (module doesn't exist yet)

- [ ] **Step 3: Create `lora_dataset.py` with the crop extraction function**

```python
"""
Antigravity Local - LoRA dataset builder

Turns a person's saved face records into a face+body training set for
sd-scripts, reusing the app's existing face restoration and person
segmentation building blocks. Runs in the main venv (Python 3.13) —
no torch/diffusers dependency, only onnxruntime + cv2 + mediapipe,
all already installed there.
"""

import os
from pathlib import Path
from typing import Dict, Optional

import cv2
import numpy as np

from face_restore import FaceRestorer
from mask_utils import get_person_bbox

QUALITY_THRESHOLD = 0.6  # matches database.py / reface_engine_v3.py convention

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def _is_image_source(source_path: str) -> bool:
    return Path(source_path).suffix.lower() in IMAGE_EXTENSIONS


def extract_face_and_body_crop(face_record: Dict, face_app, restorer: Optional[FaceRestorer] = None) -> Dict:
    """
    Given one face record (as stored in database.py's faces.json) and an
    insightface FaceAnalysis instance, return:
        {
            "face_crop": np.ndarray (BGR) or None,
            "body_crop": np.ndarray (BGR) or None,
            "skipped_body": bool,   # True if no body crop could be produced
            "restored": bool,       # True if CodeFormer restoration ran
        }

    Video-sourced faces (source_path is a video file) always skip the body
    crop: face_miner.py tracks a frame_number during mining, but
    database.py's add_face() never persists it, so the exact source frame
    cannot be re-seeked after the fact. Falls back to the already-saved
    face-only crop (image_path) in that case, and whenever the source image
    is missing or unreadable.
    """
    if restorer is None:
        restorer = FaceRestorer(model_name="codeformer", weight=0.5)

    source_path = face_record.get("source_path", "")
    quality_score = float(face_record.get("quality_score", 0.0))
    result = {"face_crop": None, "body_crop": None, "skipped_body": True, "restored": False}

    source_image = None
    if source_path and _is_image_source(source_path) and os.path.exists(source_path):
        source_image = cv2.imread(source_path)

    if source_image is None:
        # Fall back to the already-saved face crop; no body crop possible.
        saved_crop_path = face_record.get("image_path")
        if saved_crop_path and os.path.exists(saved_crop_path):
            face_crop = cv2.imread(saved_crop_path)
        else:
            face_crop = None
        if face_crop is not None and quality_score < QUALITY_THRESHOLD:
            face_crop = restorer.enhance(face_crop)
            result["restored"] = restorer.available
        result["face_crop"] = face_crop
        return result

    h, w = source_image.shape[:2]
    bx, by = int(face_record.get("bbox_x") or 0), int(face_record.get("bbox_y") or 0)
    bw, bh = int(face_record.get("bbox_width") or 0), int(face_record.get("bbox_height") or 0)
    x1, y1 = max(0, bx), max(0, by)
    x2, y2 = min(w, bx + bw), min(h, by + bh)

    face_crop = source_image[y1:y2, x1:x2].copy() if x2 > x1 and y2 > y1 else None
    if face_crop is not None and quality_score < QUALITY_THRESHOLD:
        face_crop = restorer.enhance(face_crop)
        result["restored"] = restorer.available
    result["face_crop"] = face_crop

    person_bbox = get_person_bbox(source_image, face_app)
    if person_bbox is not None:
        px1, py1, px2, py2 = person_bbox
        body_crop = source_image[py1:py2, px1:px2].copy() if px2 > px1 and py2 > py1 else None
        if body_crop is not None:
            result["body_crop"] = body_crop
            result["skipped_body"] = False

    return result
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: Tasks 1-3 success lines printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lora_dataset.py test_lora_dataset.py
git commit -m "feat: add per-face face+body crop extraction for LoRA datasets"
```

---

### Task 4: Model downloads — WD14 tagger + base SD1.5 checkpoint

**Files:**
- Modify: `download_models.py`

Generalize the existing single-purpose downloader (currently hardcodes `.onnx`) and add the two new files this pipeline needs. This script is never run automatically — per the repo's file-download rule, the user runs it themselves.

- [ ] **Step 1: Generalize `_download_one` to support arbitrary extensions**

In `download_models.py`, replace the `MODELS` dict and `_download_one` function (lines 24-33 and 44-59) with:

```python
_BASE = "https://github.com/facefusion/facefusion-assets/releases/download"
MODELS = {
    # Face restoration (pick one as default; codeformer preserves identity best)
    "codeformer":        (f"{_BASE}/models-3.0.0/codeformer.onnx",        368116, ".onnx"),
    "gfpgan_1.4":        (f"{_BASE}/models-3.0.0/gfpgan_1.4.onnx",         332323, ".onnx"),
    "gpen_bfr_512":      (f"{_BASE}/models-3.0.0/gpen_bfr_512.onnx",       277676, ".onnx"),
    # Masking
    "bisenet_resnet_34": (f"{_BASE}/models-3.0.0/bisenet_resnet_34.onnx",   91438, ".onnx"),  # face parser
    "xseg_1":            (f"{_BASE}/models-3.1.0/xseg_1.onnx",              68676, ".onnx"),  # face occluder
    # LoRA dataset auto-captioning (WD14 tagger, ONNX)
    "wd14_tagger_model": ("https://huggingface.co/SmilingWolf/wd-v1-4-moat-tagger-v2/resolve/main/model.onnx", 375000, ".onnx"),
    "wd14_tagger_tags":  ("https://huggingface.co/SmilingWolf/wd-v1-4-moat-tagger-v2/resolve/main/selected_tags.csv", 300, ".csv"),
    # LoRA training base checkpoint (SD1.5, realistic, single-file safetensors)
    "sd15_realistic_base": ("https://huggingface.co/SG161222/Realistic_Vision_V6.0_B1_noVAE/resolve/main/Realistic_Vision_V6.0_NV_B1.safetensors", 2132000, ".safetensors"),
}

# Sets
ESSENTIAL = ["codeformer", "bisenet_resnet_34", "xseg_1"]
EXTRAS = ["gfpgan_1.4", "gpen_bfr_512"]
LORA = ["wd14_tagger_model", "wd14_tagger_tags", "sd15_realistic_base"]
```

Then replace `_download_one` (was: `dest = MODELS_DIR / f"{name}.onnx"`) with:

```python
def _download_one(name: str) -> bool:
    if name not in MODELS:
        print(f"[SKIP] Unknown model '{name}'. Known: {', '.join(MODELS)}")
        return False

    url, approx_kb, ext = MODELS[name]
    dest = MODELS_DIR / f"{name}{ext}"
    tmp = dest.with_suffix(dest.suffix + ".part")

    # Already present and roughly the right size? skip. For files without a
    # trustworthy expected size (e.g. tag CSVs, third-party checkpoints),
    # just check that something non-trivial was downloaded already.
    if dest.exists():
        have_kb = dest.stat().st_size / 1024
        if abs(have_kb - approx_kb) <= max(approx_kb * 0.05, 64):
            print(f"[OK]   {dest.name} already present ({_human(have_kb)})")
            return True
        print(f"[WARN] {dest.name} wrong size ({_human(have_kb)}, expected ~{_human(approx_kb)}); re-downloading")

    print(f"[GET]  {dest.name}  (~{_human(approx_kb)})  <- {url}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "antigravity-local/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as f:
            total = int(resp.headers.get("Content-Length", 0))
            done = 0
            chunk = 1024 * 256
            last_pct = -1
            while True:
                buf = resp.read(chunk)
                if not buf:
                    break
                f.write(buf)
                done += len(buf)
                if total:
                    pct = int(done * 100 / total)
                    if pct != last_pct and pct % 5 == 0:
                        print(f"       {pct:3d}%  ({done//(1024*1024)} / {total//(1024*1024)} MB)")
                        last_pct = pct
        tmp.replace(dest)
```

Leave the rest of that function (the `except` block and everything below it) unchanged.

- [ ] **Step 2: Add a `--lora` CLI flag**

Find the CLI argument handling near the bottom of `download_models.py` (search for `--extras` / `--all`) and add a `lora` branch alongside them, following the exact same pattern already used for `extras`/`all` so `python download_models.py --lora` downloads `LORA` and `python download_models.py --all` also includes it. Since the exact bottom-of-file CLI dispatch varies slightly, match its existing `if/elif` style for `--extras`/`--all` when wiring `--lora` in — add `LORA` to whatever set `--all` already unions together, and add a new `elif arg == "--lora": targets = LORA` branch next to the existing `--extras` one.

- [ ] **Step 3: Verify the module still imports cleanly**

Run: `venv\Scripts\python.exe -c "import download_models; print(sorted(download_models.MODELS.keys()))"`
Expected: a list containing all 8 keys (`codeformer`, `gfpgan_1.4`, `gpen_bfr_512`, `bisenet_resnet_34`, `xseg_1`, `wd14_tagger_model`, `wd14_tagger_tags`, `sd15_realistic_base`), no traceback.

- [ ] **Step 4: Commit**

```bash
git add download_models.py
git commit -m "feat: add WD14 tagger and SD1.5 base checkpoint to the model downloader"
```

**Note for the user before Task 5:** once this task lands, run this yourself (per the repo's terminal-command rule) to fetch the tagger model used by the next task's tests:
```bash
cd "the app"
venv\Scripts\python.exe download_models.py wd14_tagger_model
venv\Scripts\python.exe download_models.py wd14_tagger_tags
```

---

### Task 5: `lora_dataset.py` — WD14 auto-captioning

**Files:**
- Modify: `lora_dataset.py`
- Test: `test_lora_dataset.py` (append)

Implements the "isolate defects from identity" captioning trick from the design spec: trigger word + auto-detected tags + quality-flag tags for low-quality/blurry sources.

- [ ] **Step 1: Write the failing test**

Edit `test_lora_dataset.py`: insert this block immediately after Task 3's `print("Task 3 verification successful! ...")` line and before `except ImportError as e:` (same indentation level as before):

```python
    # --- Task 5: captioning ---
    from lora_dataset import build_caption

    caption_good = build_caption(fixture_img if False else np.full((512, 512, 3), 180, dtype=np.uint8),
                                  trigger_word="sks7", quality_score=0.9)
    if not caption_good.startswith("sks7 person"):
        print(f"Caption must start with the trigger word + class, got: {caption_good!r}")
        exit(1)
    if "low quality" in caption_good or "blurry" in caption_good:
        print(f"High-quality image should not get quality-flag tags: {caption_good!r}")
        exit(1)

    caption_bad = build_caption(np.full((512, 512, 3), 180, dtype=np.uint8),
                                 trigger_word="sks7", quality_score=0.2)
    if "low quality" not in caption_bad:
        print(f"Low-quality image should get a 'low quality' tag: {caption_bad!r}")
        exit(1)

    print("Task 5 verification successful! build_caption applies trigger word and quality flags.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: FAIL with `ImportError: cannot import name 'build_caption' from 'lora_dataset'`

- [ ] **Step 3: Implement the WD14 tagger wrapper and `build_caption`**

Append to `lora_dataset.py`:

```python
WD14_MODEL_PATH = Path(__file__).parent / "models" / "wd14_tagger_model.onnx"
WD14_TAGS_PATH = Path(__file__).parent / "models" / "wd14_tagger_tags.csv"

QUALITY_FLAG_TAGS = ("low quality", "blurry", "old photo")
BLUR_LAPLACIAN_THRESHOLD = 100.0  # below this variance, treat the crop as blurry


class WD14Tagger:
    """Thin ONNX wrapper around the WD14 tagger (SmilingWolf/wd-v1-4-moat-tagger-v2).
    Runs in the main venv via onnxruntime-gpu, same as face_restore.py's models."""

    def __init__(self, model_path: Path = WD14_MODEL_PATH, tags_path: Path = WD14_TAGS_PATH, threshold: float = 0.35):
        self.available = False
        self.threshold = threshold
        self.session = None
        self.tag_names = []
        if not model_path.exists() or not tags_path.exists():
            print(f"[TAGGER] model or tags file missing ({model_path}, {tags_path}); auto-tagging disabled")
            return
        try:
            import onnxruntime as ort
            import csv

            so = ort.SessionOptions()
            self.session = ort.InferenceSession(str(model_path), sess_options=so,
                                                 providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
            self._input_name = self.session.get_inputs()[0].name
            self._input_size = self.session.get_inputs()[0].shape[1]  # NHWC, e.g. 448
            with open(tags_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                self.tag_names = [row["name"] for row in reader]
            self.available = True
            print(f"[TAGGER] WD14 loaded ({len(self.tag_names)} tags)")
        except Exception as e:
            print(f"[TAGGER] failed to load: {e}")
            self.session = None

    def tag(self, image_bgr: np.ndarray, max_tags: int = 15) -> list:
        """Returns a list of tag strings above threshold, sorted by confidence."""
        if not self.available or image_bgr is None:
            return []
        try:
            size = self._input_size
            img = cv2.resize(image_bgr, (size, size), interpolation=cv2.INTER_AREA)
            img = img.astype(np.float32)[None, ...]  # NHWC, BGR (model was trained on BGR-order arrays)
            probs = self.session.run(None, {self._input_name: img})[0][0]
            tagged = [(self.tag_names[i], float(p)) for i, p in enumerate(probs) if p >= self.threshold]
            tagged.sort(key=lambda t: t[1], reverse=True)
            return [t[0].replace("_", " ") for t in tagged[:max_tags]]
        except Exception as e:
            print(f"[TAGGER] tagging failed: {e}")
            return []


def _is_blurry(image_bgr: np.ndarray) -> bool:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < BLUR_LAPLACIAN_THRESHOLD


def build_caption(image_bgr: np.ndarray, trigger_word: str, quality_score: float, tagger: Optional[WD14Tagger] = None) -> str:
    """
    Builds the caption using the idea.txt trick: trigger word + class first,
    then descriptive tags, then explicit quality-flag tags for low-quality or
    blurry sources so the LoRA learns those are photo defects, not identity.
    """
    parts = [f"{trigger_word} person"]

    if tagger is not None and tagger.available:
        parts.extend(tagger.tag(image_bgr))

    quality_flags = []
    if quality_score < QUALITY_THRESHOLD:
        quality_flags.append("low quality")
    if _is_blurry(image_bgr):
        quality_flags.append("blurry")
    parts.extend(quality_flags)

    return ", ".join(parts)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: Tasks 1-5 success lines printed, exit code 0. (`build_caption` is called with `tagger=None` in the test, so it exercises only the trigger-word + quality-flag path — that's intentional, since the WD14 model may not be downloaded on every dev machine; it still proves the core captioning trick works.)

- [ ] **Step 5: Commit**

```bash
git add lora_dataset.py test_lora_dataset.py
git commit -m "feat: add WD14 auto-captioning with quality-flag trick"
```

---

### Task 6: `lora_dataset.py` — dataset build orchestrator

**Files:**
- Modify: `lora_dataset.py`
- Test: `test_lora_dataset.py` (append)

Ties Tasks 1, 3, and 5 together: for a person, write out the `sd-scripts`-compatible folder layout.

- [ ] **Step 1: Write the failing test**

Edit `test_lora_dataset.py`: insert this block immediately after Task 5's `print("Task 5 verification successful! ...")` line and before `except ImportError as e:` (same indentation level as before):

```python
    # --- Task 6: build_dataset orchestrator ---
    from lora_dataset import build_dataset
    from database import add_face, get_faces_by_person

    pid2 = add_person("Dataset Build Test")
    fixture_dir2 = Path("temp_lora_test2")
    fixture_dir2.mkdir(exist_ok=True)
    for i in range(3):
        p = fixture_dir2 / f"src_{i}.jpg"
        cv2.imwrite(str(p), np.full((480, 640, 3), 150 + i * 10, dtype=np.uint8))
        add_face(
            embedding=[0.0] * 512,
            source_path=str(p),
            person_id=pid2,
            bbox={"x": 250, "y": 120, "w": 130, "h": 100},
            quality_score=0.9,
            image_path=str(p),
        )

    report = build_dataset(pid2, "Dataset Build Test", _FakeFaceApp(), output_root=Path("temp_lora_test2_out"))
    if report["image_count"] != 3:
        print(f"Expected 3 images written, got: {report}")
        exit(1)
    dataset_dir = Path(report["dataset_dir"])
    jpgs = list(dataset_dir.glob("*.jpg"))
    txts = list(dataset_dir.glob("*.txt"))
    if len(jpgs) != 3 or len(txts) != 3:
        print(f"Expected 3 jpg + 3 txt files in {dataset_dir}, found {len(jpgs)} jpg / {len(txts)} txt")
        exit(1)

    db.delete_person(pid2)
    _shutil.rmtree(fixture_dir2, ignore_errors=True)
    _shutil.rmtree(Path("temp_lora_test2_out"), ignore_errors=True)
    print("Task 6 verification successful! build_dataset writes the sd-scripts folder layout.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: FAIL with `ImportError: cannot import name 'build_dataset' from 'lora_dataset'`

- [ ] **Step 3: Implement `build_dataset`**

Append to `lora_dataset.py`:

```python
import re
import uuid

from database import get_faces_by_person, set_person_lora_info, get_person_lora_info

MIN_IMAGES_WARN = 15
MIN_IMAGES_BLOCK = 5
DEFAULT_REPEATS = 20


def _slugify(name: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", name).strip("_").lower()
    return slug or "person"


def _get_or_create_trigger_word(person_id: int) -> str:
    info = get_person_lora_info(person_id)
    if info.get("trigger_word"):
        return info["trigger_word"]
    trigger = f"sks{person_id}{uuid.uuid4().hex[:4]}"
    set_person_lora_info(person_id, trigger_word=trigger)
    return trigger


def build_dataset(person_id: int, person_name: str, face_app, output_root: Path = None,
                   repeats: int = DEFAULT_REPEATS, restorer: Optional[FaceRestorer] = None,
                   tagger: Optional["WD14Tagger"] = None) -> Dict:
    """
    Builds an sd-scripts-compatible dataset for one person:
        {output_root}/{slug}/{repeats}_{trigger} person/*.jpg + *.txt

    Returns {"dataset_dir": str, "image_count": int, "skipped_body_count": int,
             "warning": Optional[str], "blocked": bool}
    """
    if output_root is None:
        output_root = Path(__file__).parent / "lora_datasets"
    if restorer is None:
        restorer = FaceRestorer(model_name="codeformer", weight=0.5)
    if tagger is None:
        tagger = WD14Tagger()

    trigger_word = _get_or_create_trigger_word(person_id)
    slug = _slugify(person_name)
    dataset_dir = Path(output_root) / slug / f"{repeats}_{trigger_word} person"
    dataset_dir.mkdir(parents=True, exist_ok=True)

    faces = get_faces_by_person(person_id)
    image_count = 0
    skipped_body_count = 0

    for i, face in enumerate(faces):
        extracted = extract_face_and_body_crop(face, face_app, restorer=restorer)
        if extracted["skipped_body"]:
            skipped_body_count += 1

        for kind, crop in (("face", extracted["face_crop"]), ("body", extracted["body_crop"])):
            if crop is None:
                continue
            stem = f"{slug}_{i:04d}_{kind}"
            img_path = dataset_dir / f"{stem}.jpg"
            cv2.imwrite(str(img_path), crop)

            caption = build_caption(crop, trigger_word=trigger_word,
                                     quality_score=float(face.get("quality_score", 0.0)), tagger=tagger)
            (dataset_dir / f"{stem}.txt").write_text(caption, encoding="utf-8")
            image_count += 1

    warning = None
    blocked = False
    if image_count < MIN_IMAGES_BLOCK:
        blocked = True
        warning = f"Only {image_count} images available; need at least {MIN_IMAGES_BLOCK} to train."
    elif image_count < MIN_IMAGES_WARN:
        warning = f"Only {image_count} images available; {MIN_IMAGES_WARN}+ is recommended for a good LoRA."

    return {
        "dataset_dir": str(dataset_dir),
        "image_count": image_count,
        "skipped_body_count": skipped_body_count,
        "warning": warning,
        "blocked": blocked,
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_dataset.py`
Expected: Tasks 1-6 success lines printed, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add lora_dataset.py test_lora_dataset.py
git commit -m "feat: add build_dataset orchestrator for per-person LoRA datasets"
```

---

### Task 7: Dashboard — replace "📤 Export for LoRA" with "🧬 Character LoRA" Tab 1 (Dataset)

**Files:**
- Modify: `dashboard.py:449` (sidebar page list), `dashboard.py:2615-2670` (old export page block)

- [ ] **Step 1: Rename the sidebar entry**

In `dashboard.py:449`, change:

```python
        ["📊 Dashboard", "📁 Data Sources", "👥 Gallery", "🎭 Reface", "🎭 Reface V2", "✨ Magic Undress", "🔀 Merge People", "📤 Export for LoRA", "⚙️ Settings"]
```

to:

```python
        ["📊 Dashboard", "📁 Data Sources", "👥 Gallery", "🎭 Reface", "🎭 Reface V2", "✨ Magic Undress", "🔀 Merge People", "🧬 Character LoRA", "⚙️ Settings"]
```

- [ ] **Step 2: Replace the page block**

Replace the entire `elif page == "📤 Export for LoRA":` block (`dashboard.py:2615-2670`, ending right before `elif page == "🎭 Reface V2":`) with:

```python
elif page == "🧬 Character LoRA":
    st.title("🧬 Character LoRA")
    st.markdown("Build a face+body training set, train a per-person LoRA, and generate a clean reference portrait")

    tab_dataset, tab_train, tab_generate = st.tabs(["1) Dataset", "2) Train", "3) Generate"])

    persons = get_all_persons()

    with tab_dataset:
        if not persons:
            st.warning("No persons to build a dataset for. Create person groups first.")
        else:
            selected_person_id = st.selectbox(
                "Person",
                options=[p["id"] for p in persons],
                format_func=lambda x: next(p["name"] for p in persons if p["id"] == x),
                key="lora_dataset_person",
            )
            selected_person = next(p for p in persons if p["id"] == selected_person_id)
            face_count = len(get_faces_by_person(selected_person_id))
            st.caption(f"{face_count} saved face(s) for this person")

            if st.button("🛠️ Build Dataset", type="primary"):
                from lora_dataset import build_dataset

                with st.spinner("Building face+body dataset (restoring low-quality faces, auto-captioning)..."):
                    report = build_dataset(selected_person_id, selected_person["name"], get_face_analyzer())
                st.session_state["lora_dataset_report"] = report

            report = st.session_state.get("lora_dataset_report")
            if report:
                if report["blocked"]:
                    st.error(report["warning"])
                elif report["warning"]:
                    st.warning(report["warning"])
                else:
                    st.success(f"Built {report['image_count']} images in {report['dataset_dir']}")
                if report["skipped_body_count"]:
                    st.info(f"{report['skipped_body_count']} item(s) had no body crop (video-sourced or missing source image) — face-only was used for those.")

                dataset_dir = Path(report["dataset_dir"])
                image_files = sorted(dataset_dir.glob("*.jpg"))
                if image_files:
                    st.markdown("**Review captions before training:**")
                    rows = []
                    for img_path in image_files:
                        caption_path = img_path.with_suffix(".txt")
                        rows.append({
                            "file": img_path.name,
                            "caption": caption_path.read_text(encoding="utf-8") if caption_path.exists() else "",
                        })
                    edited = st.data_editor(rows, key="lora_caption_editor", width='stretch',
                                             column_config={"file": st.column_config.TextColumn(disabled=True)})
                    if st.button("💾 Save Caption Edits"):
                        for row in edited:
                            (dataset_dir / row["file"]).with_suffix(".txt").write_text(row["caption"], encoding="utf-8")
                        st.success("Captions updated.")
```

- [ ] **Step 3: Smoke-check the page loads without a Python error**

Run: `venv\Scripts\python.exe -c "import ast; ast.parse(open('dashboard.py', encoding='utf-8').read())"`
Expected: no output, exit code 0 (confirms the file is still syntactically valid Python after the edit).

- [ ] **Step 4: Manual check**

Run: `run_dashboard.bat`, open `http://localhost:8501`, select "🧬 Character LoRA" in the sidebar, confirm the three tabs render and "1) Dataset" lets you pick a person and click "Build Dataset" without a traceback.

- [ ] **Step 5: Commit**

```bash
git add dashboard.py
git commit -m "feat: replace Export-for-LoRA page with Character LoRA Dataset tab"
```

---

### Task 8: `job_manager.py` — `train_lora` job type

**Files:**
- Modify: `job_manager.py:250-277` (`run_single_job` dispatch)

- [ ] **Step 1: Add the dispatch branch**

In `job_manager.py`, inside `run_single_job`, right after the docstring and imports (before `manager = JobManager(jobs_dir)` at line 255), add a dedicated early-return path for `train_lora` so it doesn't fall into the reface-engine branching below it (which assumes `params['target_path']` and a faceset — neither applies to training):

```python
def run_single_job(job_id: str, jobs_dir: str):
    """Execute a single reface or LoRA-training job."""
    manager = JobManager(jobs_dir)
    job = manager.load_job(job_id)

    if not job:
        print(f"[ERROR] Job {job_id} not found!")
        return False

    if job.job_type == "train_lora":
        from lora_trainer import run_training
        return run_training(job, manager)

    from reface_engine import RefaceEngine
    from reface_engine_v2 import RefaceEngineV2, EnhancementConfig, OcclusionConfig, VideoConfig
```

Remove the now-duplicated original lines (the old `from reface_engine import ...` / `from reface_engine_v2 import ...` imports and the `manager = JobManager(jobs_dir)` / `job = manager.load_job(job_id)` / not-found check right after — they're folded into the block above). The rest of the function (`try: job.status = JobStatus.RUNNING ...`) is unchanged.

- [ ] **Step 2: Verify the file still parses and the reface path is untouched**

Run: `venv\Scripts\python.exe -c "import ast; ast.parse(open('job_manager.py', encoding='utf-8').read())"`
Expected: no output, exit code 0.

Run: `venv\Scripts\python.exe test_stats.py` (unrelated existing test — just confirms `database.py`/`job_manager.py` imports still work together after the edit)
Expected: `Verification successful! Stats keys are correct.`

- [ ] **Step 3: Commit**

```bash
git add job_manager.py
git commit -m "feat: dispatch train_lora jobs to lora_trainer.run_training"
```

---

### Task 9: `lora_trainer.py` — sd-scripts subprocess launcher

**Files:**
- Create: `lora_trainer.py`
- Test: `test_lora_trainer_smoke.py` (new)

`sd-scripts` itself lives in the isolated `venv_lora` (set up in Task 10) — this module only builds the CLI argument list and manages the subprocess from the main venv, mirroring how `dashboard.py` calls `undress_engine.py` inside `venv_ai`.

- [ ] **Step 1: Write the failing test**

Create `test_lora_trainer_smoke.py`:

```python
try:
    from lora_trainer import build_training_args, VENV_LORA_PYTHON, SD_SCRIPTS_TRAIN_SCRIPT

    args = build_training_args(
        dataset_dir="lora_datasets/example/20_sks1 person",
        output_dir="models/loras",
        output_name="example",
        base_checkpoint="models/sd15_realistic_base.safetensors",
        epochs=10,
        network_dim=32,
        network_alpha=16,
        learning_rate=0.0001,
        batch_size=1,
    )

    required_flags = [
        "--pretrained_model_name_or_path", "--train_data_dir", "--output_dir",
        "--output_name", "--network_module", "--network_dim", "--network_alpha",
        "--train_batch_size", "--max_train_epochs", "--learning_rate",
        "--mixed_precision", "--gradient_checkpointing", "--enable_bucket",
        "--save_model_as",
    ]
    missing = [f for f in required_flags if f not in args]
    if missing:
        print(f"build_training_args is missing required flags: {missing}")
        exit(1)

    if "networks.lora" not in args:
        print(f"Expected network_module 'networks.lora' in args: {args}")
        exit(1)
    if "safetensors" not in args:
        print(f"Expected --save_model_as safetensors in args: {args}")
        exit(1)

    print(f"VENV_LORA_PYTHON path configured as: {VENV_LORA_PYTHON}")
    print(f"SD_SCRIPTS_TRAIN_SCRIPT path configured as: {SD_SCRIPTS_TRAIN_SCRIPT}")
    print("Task 9 verification successful! build_training_args produces a well-formed CLI argument list.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_trainer_smoke.py`
Expected: FAIL with `Import failed: No module named 'lora_trainer'`

- [ ] **Step 3: Implement `lora_trainer.py`**

```python
"""
Antigravity Local - LoRA training dispatcher

Builds the sd-scripts (kohya-ss/sd-scripts) CLI invocation for a per-person
SD1.5 LoRA and runs it as a subprocess inside the isolated `venv_lora`
environment (Python 3.10), mirroring how undress_engine.py is invoked inside
venv_ai. Only the argument-building and subprocess/progress-parsing logic
lives in the main venv; the actual training code is sd-scripts itself.
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

from job_manager import JobStatus
from database import set_person_lora_info

APP_DIR = Path(__file__).parent
VENV_LORA_PYTHON = APP_DIR / "venv_lora" / "Scripts" / "python.exe"
SD_SCRIPTS_DIR = APP_DIR / "sd-scripts"
SD_SCRIPTS_TRAIN_SCRIPT = SD_SCRIPTS_DIR / "train_network.py"

# 6GB-VRAM-safe defaults (RTX 4050 Laptop reference hardware) — all overridable from the UI.
DEFAULT_EPOCHS = 10
DEFAULT_NETWORK_DIM = 32
DEFAULT_NETWORK_ALPHA = 16
DEFAULT_LEARNING_RATE = 0.0001
DEFAULT_BATCH_SIZE = 1
DEFAULT_MAX_RESOLUTION = 768

_EPOCH_RE = re.compile(r"epoch\s+(\d+)\s*/\s*(\d+)", re.IGNORECASE)
_STEP_RE = re.compile(r"steps:\s*\d+%\|.*\|\s*(\d+)/(\d+)")


def build_training_args(dataset_dir: str, output_dir: str, output_name: str, base_checkpoint: str,
                         epochs: int = DEFAULT_EPOCHS, network_dim: int = DEFAULT_NETWORK_DIM,
                         network_alpha: int = DEFAULT_NETWORK_ALPHA, learning_rate: float = DEFAULT_LEARNING_RATE,
                         batch_size: int = DEFAULT_BATCH_SIZE, max_resolution: int = DEFAULT_MAX_RESOLUTION) -> list:
    """Returns the CLI argument list (no interpreter/script) for sd-scripts' train_network.py."""
    # train_data_dir must be the PARENT of the "{repeats}_{trigger} person" folder.
    train_data_dir = str(Path(dataset_dir).parent)
    return [
        "--pretrained_model_name_or_path", base_checkpoint,
        "--train_data_dir", train_data_dir,
        "--output_dir", output_dir,
        "--output_name", output_name,
        "--network_module", "networks.lora",
        "--network_dim", str(network_dim),
        "--network_alpha", str(network_alpha),
        "--train_batch_size", str(batch_size),
        "--max_train_epochs", str(epochs),
        "--learning_rate", str(learning_rate),
        "--mixed_precision", "fp16",
        "--gradient_checkpointing",
        "--optimizer_type", "AdamW8bit",
        "--enable_bucket",
        "--min_bucket_reso", "256",
        "--max_bucket_reso", str(max_resolution),
        "--resolution", str(max_resolution),
        "--cache_latents",
        "--save_model_as", "safetensors",
    ]


def run_training(job, manager) -> bool:
    """Entry point called from job_manager.run_single_job for job_type == 'train_lora'."""
    from datetime import datetime

    params = job.params
    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.message = "Starting LoRA training..."
    manager.save_job(job)

    if not VENV_LORA_PYTHON.exists() or not SD_SCRIPTS_TRAIN_SCRIPT.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ venv_lora / sd-scripts not set up"
        job.error = (
            f"Expected {VENV_LORA_PYTHON} and {SD_SCRIPTS_TRAIN_SCRIPT} to exist. "
            "Run the one-time setup in docs/superpowers/plans/2026-08-02-character-lora-pipeline.md (Task 10)."
        )
        manager.save_job(job)
        return False

    output_dir = Path(params["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    args = build_training_args(
        dataset_dir=params["dataset_dir"], output_dir=str(output_dir), output_name=params["output_name"],
        base_checkpoint=params["base_checkpoint"], epochs=params.get("epochs", DEFAULT_EPOCHS),
        network_dim=params.get("network_dim", DEFAULT_NETWORK_DIM), network_alpha=params.get("network_alpha", DEFAULT_NETWORK_ALPHA),
        learning_rate=params.get("learning_rate", DEFAULT_LEARNING_RATE), batch_size=params.get("batch_size", DEFAULT_BATCH_SIZE),
        max_resolution=params.get("max_resolution", DEFAULT_MAX_RESOLUTION),
    )
    total_epochs = params.get("epochs", DEFAULT_EPOCHS)

    cmd = [str(VENV_LORA_PYTHON), str(SD_SCRIPTS_TRAIN_SCRIPT)] + args
    print(f"[JOB {job.id}] Launching: {' '.join(cmd)}")

    process = subprocess.Popen(cmd, cwd=str(SD_SCRIPTS_DIR), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, bufsize=1)

    log_lines = []
    current_epoch = 0
    for line in process.stdout:
        log_lines.append(line.rstrip("\n"))
        print(f"[JOB {job.id}] {line.rstrip()}")

        epoch_match = _EPOCH_RE.search(line)
        if epoch_match:
            current_epoch, total_epochs = int(epoch_match.group(1)), int(epoch_match.group(2))
            job.progress = min(0.99, current_epoch / max(total_epochs, 1))
            job.message = f"Training epoch {current_epoch}/{total_epochs}"
            manager.save_job(job)
            continue

        step_match = _STEP_RE.search(line)
        if step_match:
            step, total_steps = int(step_match.group(1)), int(step_match.group(2))
            epoch_fraction = (step / max(total_steps, 1)) / max(total_epochs, 1)
            job.progress = min(0.99, (current_epoch / max(total_epochs, 1)) + epoch_fraction)
            job.message = f"Training epoch {current_epoch}/{total_epochs} — step {step}/{total_steps}"
            manager.save_job(job)

    process.wait()

    if process.returncode != 0:
        job.status = JobStatus.FAILED
        job.message = "❌ sd-scripts training failed"
        job.error = "\n".join(log_lines[-50:])
        manager.save_job(job)
        print(f"[JOB {job.id}] ❌ FAILED (exit code {process.returncode})")
        return False

    trained_file = output_dir / f"{params['output_name']}.safetensors"
    if not trained_file.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ Training finished but no .safetensors was produced"
        job.error = "\n".join(log_lines[-50:])
        manager.save_job(job)
        return False

    if params.get("person_id") is not None:
        set_person_lora_info(params["person_id"], lora_path=str(trained_file))

    job.status = JobStatus.COMPLETED
    job.progress = 1.0
    job.completed_at = datetime.now().isoformat()
    job.message = f"✅ LoRA trained: {trained_file}"
    job.result_path = str(trained_file)
    manager.save_job(job)
    print(f"[JOB {job.id}] ✅ COMPLETED: {trained_file}")
    return True
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_trainer_smoke.py`
Expected: `Task 9 verification successful! build_training_args produces a well-formed CLI argument list.`

- [ ] **Step 5: Commit**

```bash
git add lora_trainer.py test_lora_trainer_smoke.py
git commit -m "feat: add sd-scripts training dispatcher (lora_trainer.py)"
```

---

### Task 10: `venv_lora` one-time setup

**Files:**
- Create: `setup_venv_lora.bat`

This is setup the user runs once, themselves — per the repo's standing rule, these commands are posted here, never executed automatically.

- [ ] **Step 1: Create the setup batch file**

```bat
@echo off
REM One-time setup for venv_lora (LoRA training via kohya-ss/sd-scripts).
REM Run this yourself from "the app" directory: setup_venv_lora.bat
REM Isolated from venv_ai on purpose: sd-scripts pins its own torch/diffusers/
REM transformers versions that could otherwise conflict with Magic Undress.

py -3.10 -m venv venv_lora
call venv_lora\Scripts\activate.bat

pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

if not exist sd-scripts (
    git clone https://github.com/kohya-ss/sd-scripts.git
)
cd sd-scripts
pip install -r requirements.txt
cd ..

echo.
echo Done. Verify with: venv_lora\Scripts\python.exe sd-scripts\train_network.py --help
```

- [ ] **Step 2: Post the setup instructions to the user**

Tell the user to run, from `the app\` directory:

```bash
setup_venv_lora.bat
```

This downloads PyTorch (CUDA 12.1 build) and clones/installs `sd-scripts` — expect it to take several minutes and a few GB of disk space. Do not run this step yourself; wait for the user to confirm it completed.

- [ ] **Step 3: Verify (user-run) once setup completes**

Run: `venv_lora\Scripts\python.exe sd-scripts\train_network.py --help`
Expected: `train_network.py`'s argparse help text prints (confirms the isolated env + sd-scripts are wired up correctly). Paste the output back so the next task's manual test can be attempted.

- [ ] **Step 4: Commit**

```bash
git add setup_venv_lora.bat
git commit -m "feat: add venv_lora one-time setup script"
```

(`venv_lora/` and `sd-scripts/` themselves are created by the user running the script, not by this commit — confirm they're covered by `.gitignore`'s existing `venv*/` pattern before committing; if `sd-scripts/` isn't ignored yet, add it alongside the other vendored-tool ignores.)

---

### Task 11: Dashboard — Tab 2 (Train)

**Files:**
- Modify: `dashboard.py` (inside the `🧬 Character LoRA` page added in Task 7, add the `with tab_train:` block)

- [ ] **Step 1: Add the Train tab body**

Inside the `🧬 Character LoRA` page block from Task 7, add (after the `with tab_dataset:` block, at the same indentation as `tab_dataset`/`tab_train`/`tab_generate` were unpacked):

```python
    with tab_train:
        if not persons:
            st.info("Build a dataset in the first tab before training.")
        else:
            train_person_id = st.selectbox(
                "Person", options=[p["id"] for p in persons],
                format_func=lambda x: next(p["name"] for p in persons if p["id"] == x),
                key="lora_train_person",
            )
            train_person = next(p for p in persons if p["id"] == train_person_id)

            from lora_dataset import _slugify, DEFAULT_REPEATS
            from lora_trainer import DEFAULT_EPOCHS, DEFAULT_NETWORK_DIM, DEFAULT_NETWORK_ALPHA, DEFAULT_LEARNING_RATE, DEFAULT_BATCH_SIZE, DEFAULT_MAX_RESOLUTION, VENV_LORA_PYTHON

            slug = _slugify(train_person["name"])
            dataset_root = Path(__file__).parent / "lora_datasets" / slug
            dataset_subdirs = list(dataset_root.glob("*person")) if dataset_root.exists() else []

            if not dataset_subdirs:
                st.warning(f"No dataset found for {train_person['name']}. Build one in the Dataset tab first.")
            elif not VENV_LORA_PYTHON.exists():
                st.error("venv_lora not set up yet. See setup_venv_lora.bat (Task 10 of the implementation plan).")
            else:
                base_checkpoint_path = Path(__file__).parent / "models" / "sd15_realistic_base.safetensors"
                if not base_checkpoint_path.exists():
                    st.warning(f"Base checkpoint not found at {base_checkpoint_path}. Run: python download_models.py sd15_realistic_base")

                epochs = st.number_input("Epochs", min_value=1, max_value=50, value=DEFAULT_EPOCHS)
                network_dim = st.number_input("Network Dim (rank)", min_value=4, max_value=128, value=DEFAULT_NETWORK_DIM)
                network_alpha = st.number_input("Network Alpha", min_value=1, max_value=128, value=DEFAULT_NETWORK_ALPHA)
                learning_rate = st.number_input("Learning Rate", min_value=0.00001, max_value=0.01, value=DEFAULT_LEARNING_RATE, format="%.5f")
                batch_size = st.number_input("Batch Size", min_value=1, max_value=4, value=DEFAULT_BATCH_SIZE)

                if st.button("🚀 Start Training", type="primary"):
                    from job_manager import add_job_to_queue

                    job = add_job_to_queue("train_lora", {
                        "person_id": train_person_id,
                        "dataset_dir": str(dataset_subdirs[0]),
                        "output_dir": str(Path(__file__).parent / "models" / "loras"),
                        "output_name": slug,
                        "base_checkpoint": str(base_checkpoint_path),
                        "epochs": int(epochs), "network_dim": int(network_dim), "network_alpha": int(network_alpha),
                        "learning_rate": float(learning_rate), "batch_size": int(batch_size),
                    }, jobs_dir=str(Path(__file__).parent / "jobs"))
                    st.success(f"Training job queued: {job.id}")

            st.markdown("**Recent training jobs:**")
            from job_manager import JobManager as _JM
            recent = [j for j in _JM(str(Path(__file__).parent / "jobs")).list_jobs(limit=20) if j.job_type == "train_lora"]
            for j in recent:
                st.write(f"`{j.id}` — {j.status.value} — {j.message} ({int(j.progress*100)}%)")
```

- [ ] **Step 2: Smoke-check syntax**

Run: `venv\Scripts\python.exe -c "import ast; ast.parse(open('dashboard.py', encoding='utf-8').read())"`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual check**

Run: `run_dashboard.bat`, go to "🧬 Character LoRA" → "2) Train", confirm it shows the "no dataset found" warning for a person without a built dataset, and (for one with a dataset) shows the hyperparameter form without a traceback. Don't click "Start Training" yet unless `venv_lora` (Task 10) is already set up and confirmed working.

- [ ] **Step 4: Commit**

```bash
git add dashboard.py
git commit -m "feat: add Character LoRA Train tab"
```

---

### Task 12: `lora_generate.py` — generation via `venv_ai`

**Files:**
- Create: `lora_generate.py`
- Test: `test_lora_trainer_smoke.py` (append)

Follows the exact stdin-JSON-in / stdout-JSON-out subprocess contract `undress_engine.py` already uses inside `venv_ai`.

- [ ] **Step 1: Write the failing test**

Append to `test_lora_trainer_smoke.py` (before the final print, or add as a new independent check — keep it simple by appending before the last print line):

```python
    # --- lora_generate.py: prompt template defaults ---
    from lora_generate import DEFAULT_PROMPT_TEMPLATE, DEFAULT_NEGATIVE_PROMPT

    if "{trigger}" not in DEFAULT_PROMPT_TEMPLATE:
        print(f"DEFAULT_PROMPT_TEMPLATE must contain a {{trigger}} placeholder: {DEFAULT_PROMPT_TEMPLATE!r}")
        exit(1)
    if "flat studio lighting" not in DEFAULT_PROMPT_TEMPLATE:
        print(f"DEFAULT_PROMPT_TEMPLATE should request flat studio lighting per the master-reference recipe: {DEFAULT_PROMPT_TEMPLATE!r}")
        exit(1)
    if not DEFAULT_NEGATIVE_PROMPT:
        print("DEFAULT_NEGATIVE_PROMPT should not be empty")
        exit(1)

    print("lora_generate.py verification successful! Prompt templates are well-formed.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `venv\Scripts\python.exe test_lora_trainer_smoke.py`
Expected: FAIL with `Import failed: No module named 'lora_generate'`

- [ ] **Step 3: Implement `lora_generate.py`**

```python
"""
Antigravity Local - LoRA reference-image generation

Runs in venv_ai (Python 3.10) as a subprocess, called by dashboard.py from
the main venv — same stdin/stdout JSON contract as undress_engine.py.
Loads the base SD1.5 checkpoint + a trained per-person LoRA and produces
"master reference" portraits per the idea.txt recipe: front-facing, neutral
expression, flat studio lighting, ready for Character Creator 4 / KeenTools.
"""
import sys
import json
import base64
from io import BytesIO

import torch
from diffusers import StableDiffusionPipeline, UniPCMultistepScheduler
from PIL import Image

DEFAULT_PROMPT_TEMPLATE = (
    "front view portrait of {trigger} person, neutral expression, closed mouth, "
    "looking straight at camera, flat studio lighting, no shadows on face, "
    "symmetrical face, highly detailed skin texture, 8k resolution, solid white background"
)
DEFAULT_NEGATIVE_PROMPT = (
    "smiling, teeth, side view, dramatic lighting, harsh shadows, glasses, "
    "hair covering forehead, blurry, deformed"
)


def main():
    input_data = json.loads(sys.stdin.read())

    base_checkpoint = input_data["base_checkpoint"]
    lora_path = input_data["lora_path"]
    trigger_word = input_data["trigger_word"]
    prompt = input_data.get("prompt") or DEFAULT_PROMPT_TEMPLATE.format(trigger=trigger_word)
    negative_prompt = input_data.get("negative_prompt") or DEFAULT_NEGATIVE_PROMPT
    num_images = int(input_data.get("num_images", 1))
    seed = input_data.get("seed", -1)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32

    print(f"Loading base checkpoint: {base_checkpoint}", file=sys.stderr)
    pipe = StableDiffusionPipeline.from_single_file(base_checkpoint, torch_dtype=dtype, safety_checker=None)
    pipe.scheduler = UniPCMultistepScheduler.from_config(pipe.scheduler.config)

    print(f"Loading LoRA: {lora_path}", file=sys.stderr)
    pipe.load_lora_weights(lora_path)

    if device == "cuda":
        pipe.enable_model_cpu_offload()
        try:
            pipe.enable_xformers_memory_efficient_attention()
        except Exception:
            pass

    generator = None
    if seed != -1:
        generator = torch.Generator(device).manual_seed(int(seed))

    print(f"Generating {num_images} image(s)...", file=sys.stderr)
    images = pipe(
        prompt, negative_prompt=negative_prompt, num_images_per_prompt=num_images,
        num_inference_steps=30, guidance_scale=7.5, generator=generator,
    ).images

    def img_to_b64(img: Image.Image) -> str:
        buf = BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode("utf-8")

    print(json.dumps({"success": True, "images": [img_to_b64(im) for im in images]}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        print(json.dumps({"success": False, "error": str(e), "traceback": traceback.format_exc()}))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `venv\Scripts\python.exe test_lora_trainer_smoke.py`
Expected: both the Task 9 and the `lora_generate.py` success lines printed, exit code 0. (This only checks the prompt-template constants from the main venv — `lora_generate.py`'s `diffusers`/`torch` imports are only exercised when it actually runs inside `venv_ai`, which the main venv doesn't have installed; that's expected and matches how `undress_engine.py` is never imported directly from the main venv either.)

- [ ] **Step 5: Commit**

```bash
git add lora_generate.py test_lora_trainer_smoke.py
git commit -m "feat: add LoRA reference-image generation script (venv_ai)"
```

---

### Task 13: Dashboard — Tab 3 (Generate)

**Files:**
- Modify: `dashboard.py` (inside the `🧬 Character LoRA` page, add the `with tab_generate:` block)

- [ ] **Step 1: Add the Generate tab body**

Inside the `🧬 Character LoRA` page block, after the `with tab_train:` block:

```python
    with tab_generate:
        from database import get_person_lora_info

        trained_persons = [p for p in persons if get_person_lora_info(p["id"]).get("lora_path")]
        if not trained_persons:
            st.info("No trained LoRAs yet. Train one in the previous tab first.")
        else:
            gen_person_id = st.selectbox(
                "Person", options=[p["id"] for p in trained_persons],
                format_func=lambda x: next(p["name"] for p in trained_persons if p["id"] == x),
                key="lora_generate_person",
            )
            lora_info = get_person_lora_info(gen_person_id)

            from lora_generate import DEFAULT_PROMPT_TEMPLATE, DEFAULT_NEGATIVE_PROMPT
            default_prompt = DEFAULT_PROMPT_TEMPLATE.format(trigger=lora_info["trigger_word"])
            prompt = st.text_area("Prompt", default_prompt, key="lora_gen_prompt")
            negative_prompt = st.text_area("Negative Prompt", DEFAULT_NEGATIVE_PROMPT, key="lora_gen_negative")
            num_images = st.slider("Number of images", 1, 8, 4)
            seed = st.number_input("Seed (-1 for random)", value=-1, step=1, key="lora_gen_seed")

            if st.button("🎨 Generate Reference Images", type="primary"):
                import subprocess

                venv_ai_python = Path(__file__).parent / "venv_ai" / "Scripts" / "python.exe"
                gen_script = Path(__file__).parent / "lora_generate.py"
                if not venv_ai_python.exists():
                    st.error("venv_ai not found. See the Magic Undress page for setup instructions.")
                else:
                    input_data = {
                        "base_checkpoint": str(Path(__file__).parent / "models" / "sd15_realistic_base.safetensors"),
                        "lora_path": lora_info["lora_path"],
                        "trigger_word": lora_info["trigger_word"],
                        "prompt": prompt, "negative_prompt": negative_prompt,
                        "num_images": num_images, "seed": seed,
                    }
                    with st.spinner("Generating..."):
                        process = subprocess.Popen(
                            [str(venv_ai_python), str(gen_script)],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                        )
                        stdout, stderr = process.communicate(input=json.dumps(input_data), timeout=1800)

                    if stderr:
                        st.caption(f"Model logs: {stderr[:500]}...")

                    if stdout:
                        result = json.loads(stdout)
                        if result.get("success"):
                            person_name = next(p["name"] for p in trained_persons if p["id"] == gen_person_id)
                            out_dir = Path(__file__).parent / "lora_output" / person_name.replace(" ", "_")
                            out_dir.mkdir(parents=True, exist_ok=True)

                            cols = st.columns(min(4, len(result["images"])))
                            for i, img_b64 in enumerate(result["images"]):
                                img_bytes = base64.b64decode(img_b64)
                                out_path = out_dir / f"reference_{i:02d}.png"
                                out_path.write_bytes(img_bytes)
                                with cols[i % len(cols)]:
                                    st.image(img_bytes, caption=out_path.name, width='stretch')
                            st.success(f"Saved {len(result['images'])} image(s) to {out_dir}")
                        else:
                            st.error(f"Generation failed: {result.get('error')}")
                            with st.expander("Traceback"):
                                st.code(result.get("traceback", "No traceback"))
```

- [ ] **Step 2: Smoke-check syntax**

Run: `venv\Scripts\python.exe -c "import ast; ast.parse(open('dashboard.py', encoding='utf-8').read())"`
Expected: no output, exit code 0.

- [ ] **Step 3: Manual check**

Run: `run_dashboard.bat`, go to "🧬 Character LoRA" → "3) Generate". Before any LoRA is trained, confirm it shows "No trained LoRAs yet." without a traceback. After Task 10-11's training has actually produced a `.safetensors` for a person, confirm the prompt fields pre-fill with that person's trigger word and clicking "Generate Reference Images" saves PNGs under `lora_output/`.

- [ ] **Step 4: Commit**

```bash
git add dashboard.py
git commit -m "feat: add Character LoRA Generate tab"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Tab 1/Dataset ↔ Tasks 1-3, 5-7; Tab 2/Train ↔ Tasks 8-11; Tab 3/Generate ↔ Tasks 12-13; error-handling requirements (missing source, video fallback, low image count, OOM, missing venv_lora) are each implemented at the point in Tasks 3, 6, 9, 11 where they apply, not deferred.
- **Out-of-scope items carried over unchanged from the spec:** SDXL support, the external Character Creator 4/Blender step, and wiring the LoRA into Magic Undress are not part of any task above.
- **Known follow-up (not a task here):** `frame_number` still isn't persisted on face records (Task 3's video fallback documents this as a permanent limitation, per the spec's "Out of Scope" section) — a future plan could add that column and a real frame-seek path if video-sourced datasets turn out to matter in practice.
