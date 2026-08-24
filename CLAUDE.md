# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a monorepo of four independent, loosely-coupled projects — there is no shared build system, dependency file, or test runner across them.

| Folder | What it is | Status |
|---|---|---|
| `the app/` | **Antigravity Local** — the main product. A single Streamlit dashboard for mining faces from video/photos, deduping/clustering them into people, face-swapping ("Reface"), AI clothes transformation ("Magic Undress"), and LoRA dataset export. | Actively developed — see [`the app/CLAUDE.md`](the%20app/CLAUDE.md) for its internal module map |
| `python-services/` | A standalone FastAPI service that re-implements face detection/clustering/swap as an HTTP API. | Runs independently — **not called by `the app/`**; treat as a separate codebase unless asked to wire them together |
| `DeepFaceLab_NVIDIA_RTX3000_series/` | A vendored, portable DeepFaceLab distribution (third-party tool), driven by numbered `.bat` files. | Not a codebase to edit — a tool the workflow depends on |
| `RTM WF faceset/` | DeepFaceLab workspace data (aligned face frames) for an in-progress model. | Data, not code |

Older docs (root `.gitignore`, `the app/.agent/dependencies.md.resolved`) refer to `the app/` by its former folder name, `antigravity-local/`. That folder no longer exists — everything is under `the app/` now.

## Working in this repo

**Don't run terminal commands yourself — post the command and let the user run it and paste back the output.** This was an explicit standing rule from prior agent sessions (`the app/.agent/rules/r.md`, `trigger: always_on`), put in place because the GPU/CUDA/onnxruntime setup here is fragile and machine-specific (see below), and a wrong command against a venv or the CUDA PATH is hard to undo. Carry it forward unless the user says otherwise in chat.

## Commands

### `the app/` — main dashboard
```
cd "the app"
venv\Scripts\activate
streamlit run dashboard.py
```
→ http://localhost:8501. Or double-click `run_dashboard.bat`. `setup.bat` creates `venv` from scratch and installs `requirements.txt` + `onnxruntime-gpu`.

There's no pytest suite — "tests" are standalone scripts that print results and `exit(1)` on failure; run them directly with the venv active:
```
python test_stats.py        # database.py sanity check
python test_v3_smoke.py     # RefaceEngineV3 + real ONNX model I/O (needs models/ downloaded + a saved faceset)
python test_imports.py
python test_onnx.py
python test_recursion.py
python test_compositor.py           # compositing core (face_compositor.py/face_harmonize.py), no GPU or models needed
python test_compositor.py grain     # or filter by test name
python test_undress.py              # Magic Undress core (parse/mask/age/worker kill), no GPU
python compare_v3.py <img> <faceset>  # legacy vs realism preset A/B, side-by-side PNG
```

GPU diagnostics: `python check_gpu.py`, `python check_cuda_dlls.py`, `python check_legacy.py`. `fix_onnx.bat` / `install_onnx.bat` reinstall `onnxruntime-gpu` if CUDA DLLs aren't resolving (error 126).

Magic Undress needs a second, separate environment (Python 3.10 — not the main `venv`):
```
py -3.10 -m venv venv_ai
venv_ai\Scripts\activate
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements_ai.txt
```

Reface model weights aren't in git — fetch them once with `venv\Scripts\python download_models.py` (`--extras` / `--all` for optional restorers).

### `python-services/` — standalone FastAPI service
```
cd python-services
python main.py
```
→ http://localhost:8000, Swagger UI at `/docs`. (Or `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`.)

### `DeepFaceLab_NVIDIA_RTX3000_series/`
No shell commands — run the numbered `.bat` files in that folder in order against the workspace in `RTM WF faceset/workspace/`: extract frames → extract faceset → train (SAEHD/AMP/Quick96) → merge → export video.

## Architecture

### `the app/` in one paragraph
`dashboard.py` (~3,750 lines, one file, no page-routing framework — a sidebar radio over 9 emoji-named pages, each an `elif page == "..."` block) is the only entry point users touch. Everything else is a library module it imports directly: `database.py` (storage), `face_miner.py` (ingest), three generations of reface engine, `job_manager.py` (background queue for long-running swaps, LoRA training, and `undress_image` jobs), `undress_core.py` / `undress_engine.py` (persistent `venv_ai` worker — CUDA torch cannot share the main venv; SD1.5 inpaint at <=768 on a native-res crop, then a tiled full-res refine pass, with optional IP-Adapter reference images), and `dfm_engine.py`/`dfl_metadata.py` (DeepFaceLab interop). The full per-module table lives in `the app/CLAUDE.md`.

### Storage: local JSON, despite what the top-level docs say
`the app/README.md` and `the app/.env.template` both describe a PostgreSQL + pgvector setup. That's stale — the project migrated to a local JSON store (migration record in `the app/.agent/memory.md`), and `database.py`'s `JsonDatabase` singleton is the actual source of truth: `data/persons.json` + `data/faces.json`, brute-force NumPy cosine similarity, atomic writes (temp file + `os.replace`). `get_session()`/`get_db()` still exist but return a no-op `MockSession` for backward compatibility only. Don't reintroduce SQLAlchemy/pgvector on the strength of the README.

### Reface: three engine generations, both reachable from one confusingly-named page
- `reface_engine.py` (V1) and `reface_engine_v2.py` (V2 — adds occlusion handling, GFPGAN enhancement, temporal smoothing; imports V1's classes) power the original **🎭 Reface** page.
- `reface_engine_v3.py` (`RefaceEngineV3`, **recommended**) lives on the **🎭 Reface V2** page, which has an engine radio ("✨ HD V3 (recommended)" vs "Legacy V2") — so that page can run either V2 or V3 depending on the radio, not just V2. Pipeline: detect → inswapper_128 swap using a quality-weighted averaged identity embedding (`identity.py`) → align to 512 (FFHQ template) → CodeFormer ONNX restore on the crop (`face_restore.py`, fidelity `w=0.5` default) → BiSeNet parser ∩ XSeg occluder mask (`face_masking.py`) → LAB color-match + feathered paste-back. Deliberately pure onnxruntime-gpu, no torch — `venv`'s torch build is CPU-only and facexlib/basicsr aren't installed there, so V2's GFPGAN enhancement path doesn't actually accelerate.
- A DFM ("pro") path swaps `dfm_engine.DFMEngine` in for inswapper inside the same V3 pipeline (pass `dfm_path=`). It finds trained `.dfm` files by scanning `DeepFaceLab_NVIDIA_RTX3000_series/workspace` **one directory above `the app/`** — a hardcoded relative path in `dfm_engine.py`. Moving either folder breaks DFM model discovery silently.
- Model weights live in `the app/models/*.onnx` (+ one GFPGAN `.pth`), fetched via `download_models.py`, not committed to git.

### Background jobs
`job_manager.py`'s `JobManager` writes each job to `jobs/{uuid}.json` and runs a sequential single-worker queue (`.queue.lock` file lock). `Job.job_type` picks the engine inside `run_single_job`: base `reface_image`/`reface_video` (V1), plus `_v2`, `_v3`, and `_dfm`-suffixed variants (a `_dfm` job also implies V3), plus `train_lora` and `undress_image`. `last_frame` on the job record is what lets a paused video job resume mid-way instead of restarting.

### `python-services/` duplicates part of this, independently
It exposes `/api/faces/detect|cluster|merge|find-match|find-matching-group|compare-similarity` and `/api/faceswap/process` (`main.py`, backed by `services/face_detection.py`, `face_clustering.py`, `face_swap.py`, `deepfacelab_utils.py`) — a second, REST-shaped implementation of face detection/clustering that `the app/` does not call at runtime. The two use different clustering parameters (below), so don't assume behavioral parity between them.

## Constants that differ between the two face-processing codebases

| Constant | `the app/database.py` | `python-services/services/face_clustering.py` |
|---|---|---|
| Embedding | 512-d, InsightFace Buffalo_L | same model |
| Duplicate threshold | 0.05 cosine distance | — |
| Person-clustering threshold | 0.35 cosine distance (`auto_assign_to_person`) | DBSCAN `eps=0.28`, `min_samples=2` |
| Quality threshold | 0.6 default | 0.6 default |
