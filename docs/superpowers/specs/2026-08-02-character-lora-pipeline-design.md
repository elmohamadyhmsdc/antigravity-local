# Character LoRA Pipeline — Design Spec

**Date:** 2026-08-02
**Status:** Approved by user, pending implementation plan
**Origin:** Continuation of an external chat (saved as `idea.txt`) exploring how to build an animation-ready 3D character from a person's photo collection when photos vary in quality and span multiple years. That conversation converged on: don't feed raw photos into 3D tools; train a per-person LoRA to synthesize one clean "master reference image," then feed that into external 3D tools (Character Creator 4 / Blender KeenTools FaceBuilder). This spec covers building that LoRA training + generation step **inside `the app/`**, reusing its existing face pipeline. The external 3D step stays manual and out of scope.

## Goal

Given a person's existing face records in `the app/` (photos of varying quality, spanning years), produce:
1. A per-person LoRA model capturing their timeless identity (face + body), trained end-to-end inside the app.
2. One or more clean "master reference" images generated from that LoRA, suitable for import into Character Creator 4 / KeenTools FaceBuilder.

## Hardware Constraint

User's GPU: **NVIDIA GeForce RTX 4050 Laptop, 6 GB VRAM** (confirmed via `nvidia-smi`). This rules out SDXL training as a default — **SD 1.5 only**. This also happens to match the base model family Magic Undress already uses in `venv_ai`.

## Repo Standing Rule

Per `CLAUDE.md`, Claude does not run terminal commands in this repo — it posts commands for the user to run and paste back output. This applies fully to all new setup steps below (venv creation, `sd-scripts` clone, model downloads).

## Current State (reused, not rebuilt)

| Existing piece | File | Reused for |
|---|---|---|
| Face records with `source_path`, `bbox`, `quality_score` | `database.py` (`get_faces_by_person`) | Dataset source enumeration |
| CodeFormer/GFPGAN restoration | `face_restore.py` | Restoring low-quality face crops |
| MediaPipe person segmentation | `mask_utils.py` (`generate_body_mask`) | Body-region cropping |
| Background job queue | `job_manager.py` | Training job scheduling |
| Isolated-venv-per-capability pattern | `undress_engine.py` → `venv_ai` | Model for the new `venv_lora` |
| Model download-on-first-use pattern | `download_models.py` | Model for base SD1.5 checkpoint download |
| Existing (minimal) export page | `dashboard.py` — "📤 Export for LoRA" | Replaced by the new page below |

## Architecture

### Page: 🧬 Character LoRA (replaces "📤 Export for LoRA")

Three tabs in one page, matching the existing single-page-multi-mode pattern (like the Reface V2 engine radio):

```
Tab 1: Dataset   — build + review the training set for a person
Tab 2: Train     — launch/monitor LoRA training as a background job
Tab 3: Generate  — produce master reference images from a trained LoRA
```

### New modules

```
lora_dataset.py    — face+body crop extraction, restoration, captioning
lora_trainer.py     — builds sd-scripts config, dispatches training job, parses progress
lora_generate.py    — loads base checkpoint + LoRA, generates reference images
```

### New environment: `venv_lora`

- Python 3.10, isolated from `venv_ai`.
- Holds [`kohya-ss/sd-scripts`](https://github.com/kohya-ss/sd-scripts) (the CLI training engine behind the Kohya_ss GUI — no GUI installed, just `train_network.py` and its requirements).
- Isolated specifically because `sd-scripts` pins its own torch/diffusers/transformers versions that could conflict with `venv_ai`'s Magic Undress stack.

## Data Flow

### 1. Dataset building (`lora_dataset.py`, driven from Tab 1)

For a selected person, iterate `get_faces_by_person(person_id)`:

- **Source resolution:** if `source_path` is a still image, load it directly. If `source_path` is a video file (`face.frame_number` was captured during mining but is **not persisted** to `faces.json` today — confirmed in `database.py add_face()` — so the original frame can't be re-seeked), skip body-crop for that item and fall back to the already-saved face-only crop (`image_path`). Same fallback if the source file is missing/moved.
- **Face crop:** `bbox` + margin from the source image; run through `face_restore.py` CodeFormer when `quality_score` is below the project's existing quality threshold (0.6).
- **Body crop:** reuse the MediaPipe SelfieSegmentation call from `mask_utils.py` to get the person mask; crop the bounding region of (person mask ∪ face bbox).
- **No forced square resize.** `sd-scripts` supports aspect-ratio bucketing (`enable_bucket`), so mixed face/body aspect ratios are handled by the trainer, not by pre-cropping.
- **Trigger word:** auto-generated once per person (a short random token unlikely to collide with real vocabulary, e.g. `sks{person_id}`), stored alongside the LoRA path on the person record so Tab 2/3 reuse the same token consistently.
- **Captioning (the core trick from idea.txt):** auto-tag each image with a WD14 tagger (ONNX, runs in the existing main `venv` — it already has `onnxruntime-gpu`, no need to add it to `venv_lora`). Prepend the trigger word + class (e.g. `"{trigger} person, "`), then append the WD14 tags, then append quality-flag tags (`old photo`, `low quality`, `blurry`) derived from `quality_score` and a Laplacian-variance blur check when they're below threshold — so the model learns those are photo defects, not identity features.
- **Review step:** `st.data_editor` table (thumbnail + editable caption) before training is allowed to start.
- **Guardrails:** warn if fewer than 15 usable images; block training outright below 5.
- **Output layout:** `lora_datasets/{person_name}/{repeats}_{trigger} person/*.jpg` + matching `.txt` captions, matching `sd-scripts`' expected folder convention.

### 2. Training (`lora_trainer.py` + `job_manager.py`, driven from Tab 2)

- New `job_type`: `"train_lora"`.
- Job payload: `person_id`, `dataset_dir`, `output_path`, `base_checkpoint`, `epochs`, `network_dim`, `network_alpha`, `learning_rate`, `batch_size`.
- **6GB-VRAM-safe defaults:** `batch_size=1`, `mixed_precision=fp16`, `gradient_checkpointing=true`, `network_dim=32`, `network_alpha=16`, `max_resolution=768`, `optimizer=AdamW8bit`. All exposed as overridable fields in the UI, not hardcoded.
- `run_single_job` dispatches `train_lora` jobs to `lora_trainer.run_training(job)`, which spawns `venv_lora`'s python running `sd-scripts/train_network.py --config_file <generated toml>` — same subprocess pattern `undress_engine.py` already uses for `venv_ai`.
- **Progress:** parse `sd-scripts` stdout for epoch/step lines, write into the job's JSON record (new field alongside the existing `last_frame` pattern) so Tab 2 can poll and display it like existing job statuses.
- **On success:** copy the resulting `.safetensors` to `models/loras/{person_name}.safetensors`; store that path on the person record in `persons.json` so Tab 3 can find it without manual lookup.
- **Base checkpoint:** one-time download of a realistic SD1.5 checkpoint, following `download_models.py`'s existing pattern; path overridable in Settings.

### 3. Generation (`lora_generate.py`, driven from Tab 3)

- Runs in `venv_ai` (already has `diffusers`/`torch`) via subprocess, same pattern as `undress_engine.py`.
- Loads base SD1.5 checkpoint + the person's LoRA via `diffusers.StableDiffusionPipeline` + `load_lora_weights`.
- Default prompt (editable in UI):
  `"front view portrait of {trigger} person, neutral expression, closed mouth, looking straight at camera, flat studio lighting, no shadows on face, symmetrical face, highly detailed skin texture, 8k resolution, solid white background"`
- Default negative prompt (editable):
  `"smiling, teeth, side view, dramatic lighting, harsh shadows, glasses, hair covering forehead, blurry, deformed"`
- Batch count selector (1–8 images per generation).
- Output: `lora_output/{person_name}/*.png`.
- **Explicitly out of scope:** importing the generated image into Character Creator 4 / Blender — remains a manual step outside this app, exactly as in the original idea.txt plan.

## Error Handling

- Missing/relocated source image → skip body crop for that item only, surface a count of affected items in the UI; never abort the whole dataset build.
- Video-sourced face (no persisted frame number) → always face-only, no body crop, by design (see Data Flow §1).
- Fewer than 15 images → warning, training still allowed. Fewer than 5 → training blocked with an explanation.
- Training OOM → full `sd-scripts` error surfaced verbatim in the job's status, plus a suggested next step (lower `network_dim` or `max_resolution`) rather than a silent failure.
- `venv_lora` not yet set up → detected before a training job is queued; the UI prints the one-time setup commands for the user to run themselves (per the repo's standing no-Claude-terminal-commands rule), same as `setup.bat`/`fix_onnx.bat` today.

## Testing

Following this repo's existing convention (standalone scripts that print results and `exit(1)` on failure, no pytest suite):

- `test_lora_dataset.py` — builds a dataset for a fixture person and asserts face crop, body crop, and caption file all exist and are non-empty.
- `test_lora_trainer_smoke.py` — verifies the `venv_lora` subprocess call and generated `sd-scripts` config are well-formed (dry-run / `--help`-style invocation), without requiring a full real training run, mirroring `test_v3_smoke.py`'s style for the reface engine.

## Out of Scope (this spec)

- SDXL support — insufficient VRAM on the current GPU.
- The 3D generation step itself (Character Creator 4 / Blender / KeenTools) — stays a manual external step.
- Wiring the trained per-person LoRA into the existing Magic Undress SD1.5 pipeline — a natural future extension, not built now.
- Persisting `frame_number` on face records to enable body-crop extraction from video-sourced faces — noted as a limitation, not fixed here.
