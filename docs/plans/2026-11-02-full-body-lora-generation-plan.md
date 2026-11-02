# Full-Body Pose-Guided LoRA Generation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the existing LoRA dataset extraction, training, and SD1.5 generation pipeline from headshot/portrait only to full-body person generation guided by OpenPose ControlNet and enhanced by an automated face-detailer pass.

**Architecture:** 
1. Extract full and upper body crops alongside face crops with shot-type tags (`close-up portrait`, `upper body`, `full length shot`) into the dataset.
2. Generate vertical aspect ratio images (512×768 / 512×896) conditioned on OpenPose skeletons via ControlNet (`control_v11p_sd15_openpose`).
3. Apply a secondary high-resolution face restoration / inpainting pass to preserve 100% facial fidelity on small full-body face regions.

**Tech Stack:** Python 3.10 / 3.13, Diffusers (SD 1.5, ControlNet OpenPose, IP-Adapter), Kohya sd-scripts (`AdamW8bit`, `fp16`, `sdpa`), OpenCV, MediaPipe / InsightFace, CodeFormer.

---

### Task 1: Full-Body & Upper-Body Dataset Extraction with Shot-Type Captioning

**Files:**
- Modify: `the app/lora_dataset.py:72-154, 214-250, 296-335`
- Test: `the app/test_lora_dataset_fullbody.py`

**Step 1: Write the failing test**

Create `the app/test_lora_dataset_fullbody.py`:
```python
"""Tests for full-body crop categorization and shot-type captioning in lora_dataset.py"""
import numpy as np
from lora_dataset import classify_shot_type, build_caption

def test_classify_shot_type():
    # Synthetic whole image (1000x800)
    image_shape = (1000, 800)
    
    # Small face box
    face_box = [350, 100, 450, 220]
    assert classify_shot_type(face_box, image_shape) == "close-up portrait"
    
    # Upper body box (from top to mid-torso)
    upper_box = [200, 80, 600, 550]
    assert classify_shot_type(upper_box, image_shape) == "upper body shot"
    
    # Full body box (height > 70% of image height)
    full_box = [150, 50, 650, 950]
    assert classify_shot_type(full_box, image_shape) == "full length shot"

def test_caption_contains_shot_type():
    crop = np.zeros((768, 512, 3), dtype=np.uint8)
    caption = build_caption(crop, trigger_word="sks1", shot_type="full length shot")
    assert "full length shot of sks1 person" in caption

if __name__ == "__main__":
    test_classify_shot_type()
    test_caption_contains_shot_type()
    print("Task 1 tests passed successfully!")
```

**Step 2: Run test to verify it fails**

Run:
```powershell
.\venv\Scripts\python.exe test_lora_dataset_fullbody.py
```
Expected: FAIL with `ImportError: cannot import name 'classify_shot_type' from 'lora_dataset'`

**Step 3: Write minimal implementation in `the app/lora_dataset.py`**

1. Implement `classify_shot_type(bbox, image_shape)`:
   - Calculate ratio of box height to image height: `ratio = (bbox[3] - bbox[1]) / image_shape[0]`.
   - If ratio >= 0.70: return `"full length shot"`.
   - If ratio >= 0.35: return `"upper body shot"`.
   - Else: return `"close-up portrait"`.
2. Update `build_caption`:
   - Accept optional parameter `shot_type: str = "portrait"`.
   - Prepend `f"{shot_type} of {trigger_word} person"` instead of generic `{trigger_word} person`.
3. In `extract_face_and_body_crop` and `_write_dataset_records`:
   - Tag crops as `("face", face_crop, "close-up portrait")` and `("body", body_crop, shot_type)`.
   - Write captions matching the extracted shot type so the UNet learns to associate full-body prompts with full-body anatomy.

**Step 4: Run test to verify it passes**

Run:
```powershell
.\venv\Scripts\python.exe test_lora_dataset_fullbody.py
```
Expected: `Task 1 tests passed successfully!`

**Step 5: Commit**

```bash
git add "the app/lora_dataset.py" "the app/test_lora_dataset_fullbody.py"
git commit -m "feat(lora): support full-body and upper-body extraction with shot-type captions"
```

---

### Task 2: Vertical Aspect Ratios & Full-Body Prompt Templates in Generator

**Files:**
- Modify: `the app/lora_generate.py:30-70, 130-137`
- Test: `the app/test_lora_generate_prompts.py`

**Step 1: Write the failing test**

Create `the app/test_lora_generate_prompts.py`:
```python
"""Tests for vertical aspect ratio calculation and full body prompts in lora_generate.py"""
from lora_generate import (
    FULL_BODY_PROMPT_TEMPLATE,
    FULL_BODY_NEGATIVE_PROMPT,
    FULL_BODY_ANGLES,
    resolve_generation_dimensions
)

def test_full_body_templates():
    assert "{trigger}" in FULL_BODY_PROMPT_TEMPLATE
    assert "full length" in FULL_BODY_PROMPT_TEMPLATE or "full body" in FULL_BODY_PROMPT_TEMPLATE
    assert "feet" in FULL_BODY_PROMPT_TEMPLATE or "shoes" in FULL_BODY_PROMPT_TEMPLATE
    assert "bad anatomy" in FULL_BODY_NEGATIVE_PROMPT
    assert len(FULL_BODY_ANGLES) >= 4

def test_resolve_dimensions():
    # Square portrait default
    assert resolve_generation_dimensions("portrait_square") == (512, 512)
    # Vertical portrait
    assert resolve_generation_dimensions("portrait_vertical") == (512, 768)
    # Full body vertical (8:5 ratio)
    assert resolve_generation_dimensions("full_body") == (512, 768)
    # Full body tall
    assert resolve_generation_dimensions("full_body_tall") == (512, 896)

if __name__ == "__main__":
    test_full_body_templates()
    test_resolve_dimensions()
    print("Task 2 tests passed successfully!")
```

**Step 2: Run test to verify it fails**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_generate_prompts.py
```
Expected: FAIL with `ImportError: cannot import name 'FULL_BODY_PROMPT_TEMPLATE' from 'lora_generate'`

**Step 3: Write minimal implementation in `the app/lora_generate.py`**

1. Define full-body constants:
```python
FULL_BODY_PROMPT_TEMPLATE = (
    "full length photo of {trigger} person, full body shot, standing naturally, head to toe visible, "
    "sharp focus, natural lighting, highly detailed clothing, authentic skin texture, realistic proportions, "
    "35mm photography, clean background"
)
FULL_BODY_NEGATIVE_PROMPT = (
    "cropped, cut off, bad anatomy, deformed legs, extra limbs, extra feet, missing legs, bad hands, "
    "blurry, cartoon, 3d render, disfigured, floating limbs, malformed limbs"
)
FULL_BODY_ANGLES = [
    "front view standing, centered full body shot",
    "three-quarter view standing, looking towards camera",
    "walking pose, candid full body photo",
    "side profile standing, natural posture"
]
```
2. Implement `resolve_generation_dimensions(preset: str) -> tuple[int, int]`:
   - Map `"portrait_square"` -> `(512, 512)`
   - Map `"portrait_vertical"` / `"full_body"` -> `(512, 768)`
   - Map `"full_body_tall"` -> `(512, 896)`
   - Default fallback: `(512, 512)` (guarantee multiples of 8).

**Step 4: Run test to verify it passes**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_generate_prompts.py
```
Expected: `Task 2 tests passed successfully!`

**Step 5: Commit**

```bash
git add "the app/lora_generate.py" "the app/test_lora_generate_prompts.py"
git commit -m "feat(lora): add full-body prompt templates and vertical aspect ratio presets"
```

---

### Task 3: OpenPose ControlNet Conditioning in `lora_generate.py`

**Files:**
- Modify: `the app/lora_generate.py:140-270`
- Test: `the app/test_lora_generate_controlnet.py`

**Step 1: Write the failing test**

Create `the app/test_lora_generate_controlnet.py`:
```python
"""Tests for loading and preparing ControlNet OpenPose in lora_generate.py"""
import numpy as np
from PIL import Image
from lora_generate import prepare_pose_condition, is_controlnet_available

def test_controlnet_readiness():
    assert is_controlnet_available() is True

def test_prepare_pose_condition():
    # Synthetic RGB pose image (768x512)
    dummy_pose = Image.fromarray(np.zeros((768, 512, 3), dtype=np.uint8))
    cond_image = prepare_pose_condition(dummy_pose, target_size=(512, 768))
    assert cond_image.size == (512, 768)

if __name__ == "__main__":
    test_controlnet_readiness()
    test_prepare_pose_condition()
    print("Task 3 tests passed successfully!")
```

**Step 2: Run test to verify it fails**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_generate_controlnet.py
```
Expected: FAIL with `ImportError: cannot import name 'is_controlnet_available' from 'lora_generate'`

**Step 3: Write minimal implementation in `the app/lora_generate.py`**

1. Implement `is_controlnet_available() -> bool`:
   - Check if `APP_DIR / "models" / "undress" / "lllyasviel--control_v11p_sd15_openpose"` exists.
2. Implement `prepare_pose_condition(pose_image: Image.Image, target_size: tuple) -> Image.Image`:
   - Run `OpenposeDetector` (from installed annotators) if the image is a regular photo.
   - Resize to `target_size` with `Image.Resampling.LANCZOS`.
3. In `main()` of `lora_generate.py`:
   - When request contains `pose_image_path`:
     - Load `ControlNetModel.from_pretrained(OPENPOSE_DIR, torch_dtype=torch.float16)`
     - Instantiate `StableDiffusionControlNetPipeline` instead of basic `StableDiffusionPipeline`
     - Pass `image=cond_image` and `controlnet_conditioning_scale=float(request.get("pose_strength", 1.0))` to pipe.

**Step 4: Run test to verify it passes**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_generate_controlnet.py
```
Expected: `Task 3 tests passed successfully!`

**Step 5: Commit**

```bash
git add "the app/lora_generate.py" "the app/test_lora_generate_controlnet.py"
git commit -m "feat(lora): integrate ControlNet OpenPose conditioning into generation pipeline"
```

---

### Task 4: Automated Face-Detailer Pass for Full-Body Generations

**Files:**
- Modify: `the app/lora_generate.py:220-275`
- Test: `the app/test_lora_face_detailer.py`

**Step 1: Write the failing test**

Create `the app/test_lora_face_detailer.py`:
```python
"""Tests for face-detailer post-processing pass on full-body images"""
import numpy as np
from PIL import Image
from lora_generate import apply_face_detailer

def test_face_detailer_preserves_full_image_dimensions():
    # Create synthetic full-body canvas (512 x 768)
    canvas = np.zeros((768, 512, 3), dtype=np.uint8)
    # Draw a synthetic face blob at head position (x: 230-280, y: 50-110)
    canvas[50:110, 230:280] = 180
    pil_img = Image.fromarray(canvas)
    
    enhanced = apply_face_detailer(pil_img, face_restorer=None)
    assert enhanced.size == (512, 768)

if __name__ == "__main__":
    test_face_detailer_preserves_full_image_dimensions()
    print("Task 4 tests passed successfully!")
```

**Step 2: Run test to verify it fails**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_face_detailer.py
```
Expected: FAIL with `ImportError: cannot import name 'apply_face_detailer' from 'lora_generate'`

**Step 3: Write minimal implementation in `the app/lora_generate.py`**

1. Implement `apply_face_detailer(full_image: Image.Image, face_restorer=None, padding: float = 0.3) -> Image.Image`:
   - Detect face bounding box using OpenCV Haar cascade or MediaPipe.
   - If face area < 0.25 of full image (typical full body):
     - Crop face bbox with `padding`.
     - Enhance crop using `FaceRestorer(model_name="codeformer", weight=0.6)`.
     - Blend back into `full_image` using feathered elliptical alpha mask to avoid harsh cut lines.
   - Return detailed `full_image`.
2. Hook into the image output loop in `lora_generate.py`:
   - If `request.get("enable_face_detailer", True)` is active and `mode == "full_body"`, run `apply_face_detailer` before saving the final image.

**Step 4: Run test to verify it passes**

Run:
```powershell
.\venv_ai\Scripts\python.exe test_lora_face_detailer.py
```
Expected: `Task 4 tests passed successfully!`

**Step 5: Commit**

```bash
git add "the app/lora_generate.py" "the app/test_lora_face_detailer.py"
git commit -m "feat(lora): add automated face-detailer post-pass for full-body generations"
```

---

### Task 5: Mobile API & Studio Job Schema Integration

**Files:**
- Modify: `the app/mobile_api/studio_jobs.py`
- Modify: `the app/mobile_api/contract/openapi.yaml`
- Test: `the app/test_mobile_studio.py`

**Step 1: Write the failing test**

Add test case in `the app/test_mobile_studio.py`:
```python
def test_full_body_lora_request_schema():
    payload = {
        "person_id": 1,
        "generation_mode": "full_body",
        "aspect_ratio": "vertical_768",
        "pose_media_id": 42,
        "enable_face_detailer": True,
        "num_images": 2
    }
    # Validate payload accepted by schema parser without validation error
    from mobile_api.studio_jobs import validate_generate_lora_request
    parsed = validate_generate_lora_request(payload)
    assert parsed["generation_mode"] == "full_body"
    assert parsed["aspect_ratio"] == "vertical_768"
    assert parsed["pose_media_id"] == 42
```

**Step 2: Run test to verify it fails**

Run:
```powershell
.\venv\Scripts\python.exe test_mobile_studio.py
```
Expected: FAIL with `ImportError: cannot import name 'validate_generate_lora_request'` or schema field rejection.

**Step 3: Write minimal implementation**

1. In `the app/mobile_api/studio_jobs.py`:
   - Update job payload validator to accept:
     - `generation_mode: Literal["portrait", "full_body"] = "portrait"`
     - `aspect_ratio: Literal["square", "vertical_768", "tall_896"] = "square"`
     - `pose_media_id: Optional[int] = None`
     - `enable_face_detailer: bool = True`
   - If `pose_media_id` is supplied, resolve its file path on disk and forward as `pose_image_path` in `lora_generate_job.py`.
2. Update `openapi.yaml` with the new optional fields.

**Step 4: Run test to verify it passes**

Run:
```powershell
.\venv\Scripts\python.exe test_mobile_studio.py
```
Expected: PASS.

**Step 5: Commit**

```bash
git add "the app/mobile_api/studio_jobs.py" "the app/mobile_api/contract/openapi.yaml" "the app/test_mobile_studio.py"
git commit -m "feat(api): expose full-body and pose options in Studio generate_lora endpoints"
```

---

## Verification & Done Criteria

1. **CPU/Unit Regression Suites:**
   - `the app/venv/Scripts/python.exe test_lora_dataset_fullbody.py` -> PASS
   - `the app/venv_ai/Scripts/python.exe test_lora_generate_prompts.py` -> PASS
   - `the app/venv_ai/Scripts/python.exe test_lora_generate_controlnet.py` -> PASS
   - `the app/venv_ai/Scripts/python.exe test_lora_face_detailer.py` -> PASS
   - `the app/venv/Scripts/python.exe test_mobile_studio.py` -> PASS
2. **Inference Smoke Test (Opt-in with user permission):**
   - Run a single-image 512×768 generation test using an existing trained LoRA with OpenPose ControlNet to verify VRAM usage stays safely under 5.0 GB on the RTX 4050.
