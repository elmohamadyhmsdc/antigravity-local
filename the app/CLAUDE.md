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
- `python test_gallery.py` — quality scoring, grouping/linking, storage, scanner (uses temp data dirs, never the real `data/`)
- `python test_gallery_ui.py` — runs the Gallery page headlessly via `streamlit.testing.v1.AppTest` against a fixture library
- `python test_reface_v2.py`
- `python test_compositor.py` (one pre-existing failure: `test_feather_mask_keeps_a_solid_centre`)

**Check grouping accuracy against your own curated people** (read-only):
- `python eval_grouping.py`

## Architecture

### Storage (NO PostgreSQL — fully local JSON)
- `database.py` — `JsonDatabase` singleton, **source of truth for all data**
  - `data/persons.json` — person metadata + face_count (+ `distinct_from`: pairs the user said are different people)
  - `data/faces.json` — face embeddings (512-d InsightFace Buffalo_L) + metadata (+ `media_id`, `frame_number`, `timestamp`, `kps`, `pose`, quality v2 fields, `rejected_person_ids`)
  - `data/bodies.json` — person (body) detections: bbox, COCO keypoints, outfit descriptor, crop, and either `face_id` (identified through its face) or `person_id` + `link_method`
  - `data/media.json` — one record per scanned photo/video: file signature, scan status/version, and every detection in it (`[frame, t, "f"|"b", id, x, y, w, h]`) — this is what makes "which photos is this person in?" answerable
  - Vector search: brute-force cosine similarity via NumPy (fast enough up to ~100k faces); the embedding matrix is cached and appended to as faces are added
  - Atomic writes via temp files + `os.replace()`
  - `with db.batch(): ...` groups many changes into one write (scanning, grouping); `db.flush()` persists mid-batch so an interrupted scan can resume
  - `db.refresh_if_changed()` reloads when another process (the job worker) rewrote the files — without it, this process's next save silently reverts their changes. Mutating methods call it.
  - `JsonDatabase(data_dir=...)` returns a standalone instance (tests/sandboxes); the no-arg form is the process singleton
- `get_session()` / `get_db()` return `MockSession` for backward-compatibility — they are no-ops

### Core Modules
| File | Role |
|------|------|
| `database.py` | JsonDatabase singleton, all CRUD + vector search |
| `ffmpeg_utils.py` | Shared FFmpeg discovery, audio muxing, and segment concat commands |
| `library_scanner.py` | **Gallery ingest** — multi-scale face detection + body detection per photo/video, writes faces/bodies/media records. Resumable and incremental (skips files whose size+mtime are unchanged) |
| `face_quality.py` | Calibrated face quality score (embedding norm, size, sharpness, pose). Pure CPU maths |
| `body_detector.py` | YOLOX-m person detection + RTMPose-m 17-keypoint bodies, ONNX only. Auto-downloads ~145 MB into `models/body/` on first use |
| `person_linking.py` | **Grouping brain** — face↔body association, face→person matching, clustering, duplicate-person and outfit-based body suggestions. No models, no I/O |
| `gallery_grouping.py` | Runs person_linking over the database: `group_library()` (the "sort my gallery" action) and `review_state()` (what the Review tab shows) |
| `gallery_page.py` | The whole Gallery page UI (People / Review / Media / Insights) |
| `eval_grouping.py` | Measures grouping accuracy against the people you've already curated (read-only) |
| `face_miner.py` | Legacy face extraction (standalone CLI). The dashboard now ingests through `library_scanner.py` |
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
3. **👥 Gallery** — `gallery_page.py`, four views: **People** (person cards → faces, photos/videos, body shots, suggestions), **Review** (the decision queue: faces that match someone known, new groups, possible duplicate people, bodies matched by outfit), **Media** (every file, who's in it, inspector with drawn boxes), **Insights**. "Scan library" ingests new/changed files and groups them
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
- `generate_lora_images` jobs (Character LoRA → Generate tab): `lora_generate_job.run_generation` runs `lora_generate.py` inside venv_ai, one image at a time, each saved to `lora_output/{person}/reference_{job_id}_NN_seed{seed}.png` as soon as it's done. Progress comes back as `@@lora_generate {json}` lines on stdout and is folded into `job.details` (stage + per-stage startup timings, GPU, image/step, s/step, seeds); log in `jobs/{job_id}.log`. The tab polls it with the same `st.fragment` pattern as the Train tab and has Stop/Cancel. `lora_generate.py` keeps torch/diffusers imports inside `main()` because the dashboard imports its prompt defaults from the main venv, and loads the LoRA via `load_person_lora` (kohya text-encoder keys renamed for transformers 5's CLIPTextModel layout). An optional reference image (saved to `lora_uploads/_generate_references/`) is followed via img2img ("Pose & composition"; only `int(steps * strength)` steps run, which `denoising_steps` mirrors for progress/ETA), IP-Adapter plus from `models/undress` ("Style & look"), or both
- Character LoRA → Dataset → Upload New stages photos **and videos** in `lora_uploads/{slug}/` via `lora_staging.py`; that folder *is* the staged list (not session state), so refreshes/reconnects keep it. "From a folder on this PC" imports straight from disk (hard link on the same drive, else copy) and is the path for big batches — Streamlit's uploader holds a whole batch in RAM and rejects the rest of it with `400 Invalid session_id` once the websocket drops. Both paths skip already-staged files (size + first/last MiB fingerprint) and never overwrite. `build_dataset_from_uploads` samples up to 12 frames per video into `_frames/{video}/`. `.streamlit/config.toml` raises `maxUploadSize` to 2048 MB
- `job_type` picks the engine in `run_single_job`: base `reface_image`/`reface_video` (V1), plus `_v2`, `_v3`, `_dfm` suffixed variants (`_dfm` also implies V3), plus `train_lora`, `generate_lora_images` and `undress_image`

## Key Constants / Thresholds
- Embedding dim: **512** (InsightFace Buffalo_L)
- Duplicate threshold: **0.05** cosine distance (very strict) — a detection this close to a stored face is *linked* to it, not stored again
- Detector scales: `[(128,128), (640,640)]`, plus `(1280,1280)` for images ≥1600px. The single 640 scale the app used before missed faces that fill the frame (119 of 290 existing crops weren't re-detectable at 640 alone)
- Face quality (`face_quality.py`, v2): `0.35·norm + 0.20·size + 0.20·sharpness + 0.25·pose`; gate for storing a face **0.40** (`FACE_MIN_QUALITY`), det_score ≥ 0.5, ≥ 24px. Correlates with identity reliability at ρ=0.56 (the old `det_score × size-ratio` score: 0.40)
- Grouping (`person_linking.STRICTNESS`, default **balanced**): auto-assign to a known person at identity score **0.40** with a **0.10** lead over the runner-up; suggest at 0.25; average-linkage cut **0.70**; groups of ≥3 cohesive faces become a person; duplicate people suggested at 0.40, folded automatically at 0.60; faceless bodies linked by outfit at **0.86** within the same file
- Measured on the curated library (2026-09-19): matching 98% auto with 0 wrong and 0 false matches for an unseen person; regrouping 3 people into 6 groups at 100% pairwise precision (the old greedy 0.35 pass made 17)
- **One person can't appear twice in the same photo/frame** — enforced in matching (Hungarian assignment), clustering (cannot-link) and body linking

## GPU Setup Notes
- ONNX Runtime GPU: requires CUDA DLLs on PATH — `cuda_dll_dirs.add_nvidia_dll_dirs()` registers the `venv/.../nvidia/*/bin` dirs (called by `dashboard.py`, the reface engines, `face_restore.py`, `face_masking.py`); `face_miner.py` separately adds the CUDA Toolkit bin. Registration must stay once-per-process: `dashboard.py` re-runs on every Streamlit rerun, and repeated `os.add_dll_directory` calls exhaust the DLL search list (~150 reruns) → `[WinError 206]` on `import torch`
- `NvOptimusEnablement=1` env var set for Advanced Optimus/MUX laptops
- Magic Undress downloads ~5 GB of models on first run, plus ~1 GB for the optional IP-Adapter + CLIP image encoder
- Undress pipeline targets a 6 GB card: `enable_model_cpu_offload()` stays ON, generation caps at 768, and the high-res refine pass is tiled so VRAM stays flat regardless of photo size

## Data Directories (gitignored)
- `data/` — persons.json, faces.json, bodies.json, media.json
- `extracted_faces/` — saved face image crops
- `extracted_bodies/` — saved body crops (gallery body shots)
- `uploads/` — uploaded files
- `facesets/` — saved faceset directories
- `jobs/` — background job JSON files
- `gfpgan/` — GFPGAN model weights
- `models/` — other AI model weights
