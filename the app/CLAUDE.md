# Antigravity Local — Project Guide for Claude

## What This Is
A **local, single-user biometric gallery and dataset curation tool** built in Python.
It mines faces from videos/photos, deduplicates them, groups them by person, and supports:
- Face swapping ("Reface") in images and videos
- AI clothes transformation ("Magic Undress") via Stable Diffusion inpainting
- LoRA dataset export (Kohya_ss-compatible image + caption zips)

## Working With This Repo
**Don't run terminal commands yourself** — post the command and have the user run it and paste back the output. This is a standing rule from `.agent/rules/r.md` (`trigger: always_on`), kept because the GPU/CUDA/onnxruntime setup here is fragile and machine-specific; a wrong command against `venv`/`venv_ai` or the CUDA PATH can be hard to undo. Follow it unless told otherwise in chat.

## Environments
| Env | Python | Purpose |
|-----|--------|---------|
| `venv/` | 3.13 | Main app — Streamlit, InsightFace, OpenCV |
| `venv_ai/` | 3.10 | Magic Undress only — PyTorch CUDA 12.1, diffusers, IP-Adapter |

**Run the dashboard:** `run_dashboard.bat` → `http://localhost:8501`
Manual: `venv\Scripts\activate && streamlit run dashboard.py`

**Run tests (CPU-only, no models or GPU required):**
- `python test_reface_v2.py`
- `python test_compositor.py`

## Architecture

### Storage (NO PostgreSQL — fully local JSON)
- `database.py` — `JsonDatabase` singleton, **source of truth for all data**
  - `data/persons.json` — person metadata + face_count
  - `data/faces.json` — face embeddings (512-d InsightFace Buffalo_L) + metadata
  - Vector search: brute-force cosine similarity via NumPy (fast enough up to ~100k faces)
  - Atomic writes via temp files + `os.replace()`
- `get_session()` / `get_db()` return `MockSession` for backward-compatibility — they are no-ops

### Core Modules
| File | Role |
|------|------|
| `database.py` | JsonDatabase singleton, all CRUD + vector search |
| `ffmpeg_utils.py` | Shared FFmpeg discovery, audio muxing, and segment concat commands |
| `face_miner.py` | Extract faces from video/images using InsightFace |
| `reface_engine.py` | Face swap engine V1 |
| `reface_engine_v2.py` | Face swap engine V2 (legacy fallback) |
| `reface_engine_v3.py` | **Face swap engine V3 (HD, recommended)** — ONNX CodeFormer restore + BiSeNet parser/XSeg occluder masks + averaged identity; stable video |
| `face_compositor.py` | **Compositing core** — align → restore → mask → harmonize → paste, plus per-track temporal state. Takes the swapper's affine matrix as a parameter, so inswapper, DFM and future swappers share one realism path |
| `face_harmonize.py` | Pure image math used by the compositor: noise estimation, lighting gain, focus matching, skin detail transfer, grain synthesis. No models, no state — unit-testable on CPU |
| `identity.py` | Averaged source identity embedding for inswapper |
| `face_restore.py` | ONNX face restoration (CodeFormer / GFPGAN / GPEN) on the face crop |
| `face_masking.py` | ONNX face parser + occluder paste masks |
| `download_models.py` | Fetch reface ONNX models into `models/` (run once) |
| `undress_core.py` | Shared Magic Undress helpers (mask matting, tile planning, IPC, venv_ai worker client) |
| `undress_engine.py` | SD 1.5 inpaint worker (runs inside venv_ai). Native-res crop + tiled refine pass + optional IP-Adapter references. No ControlNet — it does not fit in 6 GB alongside the UNet and CLIP image encoder |
| `job_manager.py` | Background job queue (file-based persistence, sequential execution) |
| `dashboard.py` | Streamlit UI (~3750 lines), all 9 pages |
| `dfm_engine.py` | DeepFaceLab model support — scans `../DeepFaceLab_NVIDIA_RTX3000_series/workspace` (hardcoded, one level above this folder) for trained `.dfm` files |
| `dfl_metadata.py` | DFL metadata parsing |
| `mask_utils.py` | Body mask generation helpers |

### Dashboard Pages (sidebar radio)
1. **📊 Dashboard** — stats, source analytics
2. **📁 Data Sources** — add folder paths or upload files
3. **👥 Gallery** — browse persons/faces, assign unassigned faces
4. **🎭 Reface** — Quick Swap + Build Faceset + Background Jobs
5. **🎭 Reface V2** — engine radio: ✨ HD V3 (recommended) or Legacy V2, plus occlusion/enhancement options
6. **✨ Magic Undress** — clothes restyle via JobManager + persistent venv_ai worker
7. **🔀 Merge People** — merge duplicate person clusters
8. **📤 Export for LoRA** — export facesets as zips for training
9. **⚙️ Settings** — thresholds, paths, config

### Job System
- `job_manager.py` / `JobManager` class
- Jobs stored as JSON files in `jobs/` directory
- Sequential queue — one job runs at a time
- Statuses: `pending → queued → running → completed/failed/paused`
- Supports video resume via `last_frame` field
- `train_lora` jobs train into `models/loras/runs/{job_id}/` (per-epoch LoRA snapshots + sd-scripts `--save_state` folders). The LoRA Train tab's Resume button re-queues a failed/interrupted job; `lora_trainer.run_training` continues from the newest fully saved epoch state (via `--resume` + `--initial_epoch`), then moves the finished LoRA up to `models/loras/` and deletes the states. While it runs, `run_training` folds sd-scripts' output into `job.details` (stage, epoch/step, loss, s/step — see `update_training_state`) and appends it to `runs/{job_id}/train.log`; the Train tab polls both every 2 s via an `st.fragment` only while a worker is alive and a training job is queued/running
- `generate_lora_images` jobs (Character LoRA → Generate tab): `lora_generate_job.run_generation` runs `lora_generate.py` inside venv_ai, one image at a time, each saved to `lora_output/{person}/reference_{job_id}_NN_seed{seed}.png` as soon as it's done. Progress comes back as `@@lora_generate {json}` lines on stdout and is folded into `job.details` (stage + per-stage startup timings, GPU, image/step, s/step, seeds); log in `jobs/{job_id}.log`. The tab polls it with the same `st.fragment` pattern as the Train tab and has Stop/Cancel. `lora_generate.py` keeps torch/diffusers imports inside `main()` because the dashboard imports its prompt defaults from the main venv, and loads the LoRA via `load_person_lora` (kohya text-encoder keys renamed for transformers 5's CLIPTextModel layout)
- `job_type` picks the engine in `run_single_job`: base `reface_image`/`reface_video` (V1), plus `_v2`, `_v3`, `_dfm` suffixed variants (`_dfm` also implies V3), plus `train_lora`, `generate_lora_images` and `undress_image`

## Key Constants / Thresholds
- Embedding dim: **512** (InsightFace Buffalo_L)
- Duplicate threshold: **0.05** cosine distance (very strict)
- Auto-cluster similarity: **0.35** cosine distance
- Quality threshold default: **0.6**

## GPU Setup Notes
- ONNX Runtime GPU: requires CUDA DLLs on PATH — `cuda_dll_dirs.add_nvidia_dll_dirs()` registers the `venv/.../nvidia/*/bin` dirs (called by `dashboard.py`, the reface engines, `face_restore.py`, `face_masking.py`); `face_miner.py` separately adds the CUDA Toolkit bin. Registration must stay once-per-process: `dashboard.py` re-runs on every Streamlit rerun, and repeated `os.add_dll_directory` calls exhaust the DLL search list (~150 reruns) → `[WinError 206]` on `import torch`
- `NvOptimusEnablement=1` env var set for Advanced Optimus/MUX laptops
- Magic Undress downloads ~5 GB of models on first run, plus ~1 GB for the optional IP-Adapter + CLIP image encoder
- Undress pipeline targets a 6 GB card: `enable_model_cpu_offload()` stays ON, generation caps at 768, and the high-res refine pass is tiled so VRAM stays flat regardless of photo size

## Data Directories (gitignored)
- `data/` — persons.json, faces.json
- `extracted_faces/` — saved face image crops
- `uploads/` — uploaded files
- `facesets/` — saved faceset directories
- `jobs/` — background job JSON files
- `gfpgan/` — GFPGAN model weights
- `models/` — other AI model weights
