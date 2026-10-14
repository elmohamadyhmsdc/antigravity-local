# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This is a monorepo of five independent, loosely-coupled projects — there is no shared build system, dependency file, or test runner across them. (`mobile/` talks to `the app/` only through the HTTP contract in `the app/mobile_api/contract/`.)

| Folder | What it is | Status |
|---|---|---|
| `the app/` | **Antigravity Local** — the main product. A single Streamlit dashboard for mining faces from video/photos, deduping/clustering them into people, face-swapping ("Reface"), AI clothes transformation ("Magic Undress"), and LoRA dataset export. | Actively developed — see [`the app/CLAUDE.md`](the%20app/CLAUDE.md) for its internal module map |
| `python-services/` | A standalone FastAPI service that re-implements face detection/clustering/swap as an HTTP API. | Runs independently — **not called by `the app/`**; treat as a separate codebase unless asked to wire them together |
| `DeepFaceLab_NVIDIA_RTX3000_series/` | A vendored, portable DeepFaceLab distribution (third-party tool), driven by numbered `.bat` files. | Not a codebase to edit — a tool the workflow depends on |
| `RTM WF faceset/` | DeepFaceLab workspace data (aligned face frames) for an in-progress model. | Data, not code |
| `mobile/` | **Antigravity Mobile** — Flutter (Android) phone app exposing the same features. **All user data lives on the phone**; the PC is a stateless GPU server reached over the same Wi-Fi. | In progress — plan: [`docs/plans/2026-10-11-mobile-app-plan.md`](docs/plans/2026-10-11-mobile-app-plan.md) (P0, P1 done and device-verified; P2 Library & People built — photo scan, people/review/merge screens, backup & restore — awaiting the user's run on the phone; P3 videos & bodies next) |

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
python test_gallery.py      # gallery: quality score, grouping/linking, storage, scanner (temp data dirs, no GPU)
python test_gallery_ui.py   # gallery page rendered headlessly via streamlit's AppTest, on a fixture library
python eval_grouping.py     # read-only: grouping accuracy against the people already curated in data/
python test_v3_smoke.py     # RefaceEngineV3 + real ONNX model I/O (needs models/ downloaded + a saved faceset)
python test_imports.py
python test_onnx.py
python test_recursion.py
python test_compositor.py           # compositing core (face_compositor.py/face_harmonize.py), no GPU or models needed
python test_compositor.py grain     # or filter by test name
python test_identity_builder.py     # identity builder (which face is the person, filters, save) - fake faces, no GPU
python eval_reface.py               # GPU, read-only: scores swappers/restorers/occluders/identity boost on lora_datasets people + DFL sample videos with an independent recogniser; picks the defaults in reface_engine_v3.py
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

### `mobile/` — Flutter phone app, and the API contract it shares with `the app/`
```
cd mobile
flutter pub get
flutter analyze
flutter test                      # includes contract_fixtures_test.dart
flutter build apk --debug         # needs Android SDK licenses accepted: flutter doctor --android-licenses
dart run build_runner build       # only after editing lib/data/db/tables.dart (regenerates the committed app_database.g.dart)
flutter gen-l10n                  # after editing lib/l10n/app_en.arb (the generated app_localizations*.dart are committed). Placeholders are passed in the ORDER they are declared in the ARB's @key block
dart format lib test && dart fix --apply   # the analyzer is kept at zero issues (infos included)
```
Flutter lives at `C:\flutter` (3.44), Android SDK at `%LOCALAPPDATA%\Android\sdk`. The phone ↔ PC contract is `the app/mobile_api/contract/openapi.yaml`, with golden fixtures in `contract/fixtures/` shared by the server tests and the Flutter tests. After editing the contract or a fixture generator:
```
cd "the app"
venv\Scripts\python mobile_api\contract\make_fixtures.py       # regenerate fixtures (deterministic)
venv\Scripts\python mobile_api\contract\validate_contract.py   # openapi.yaml valid + every fixture matches its schema
```
The server half is the `the app/mobile_api/` FastAPI package (HTTPS on 8443, plus a pairing page on `http://127.0.0.1:8444/pair` that only this PC can reach). Its extra packages (`requirements_mobile_api.txt`: fastapi, cryptography, zeroconf, qrcode) were installed into `venv` on 2026-10-11 with the user's explicit OK — a dry-run first showed the only existing package that changed was `typing_extensions` 4.15 → 4.16; never add packages to `venv` silently.
```
cd "the app"
run_mobile_api.bat                                  # or: venv\Scripts\python -m mobile_api --help   (e.g. --bind 127.0.0.1 --no-mdns --no-browser)
venv\Scripts\python test_mobile_api_contract.py     # auth, pairing, blobs (409/resume/LRU), analyze, error envelope, shapes vs fixtures - fake engines, no GPU
venv\Scripts\python test_mobile_stateless.py        # mobile_api never imports database (even transitively), never refers to data/, never unpickles; data/ byte-identical after a round trip
venv\Scripts\python test_grouping_core.py            # grouping_core == the pre-refactor gallery_grouping (embedded reference) on every library/strictness/flag, the phone's 3 rounds == group_library, golden GroupingPlan fixtures byte-identical (also regenerated into a temp dir), bad requests refused
venv\Scripts\python eval_member_cap.py [data_dir]    # read-only: how many members per person the phone must send (300/200/150/100/75/50 vs the PC's 300) on a curated library; prints the smallest cap that keeps accuracy -> mobile/lib/domain/grouping/grouping_config.dart
venv\Scripts\python test_analysis.py                # analysis.analyze_frame with fake models
```
The server never changes Windows Firewall rules: a phone on the Wi-Fi needs python.exe allowed on "Private networks" (Windows asks on the first run, or run the `netsh` line printed in `run_mobile_api.bat` yourself). Over USB, `adb reverse tcp:8443 tcp:8443` plus `--bind 127.0.0.1` reaches the server without touching the firewall (that is how P1 was tested on a real phone; the Android emulator reaches it at `10.0.2.2`). The phone pairs with `agmobile://pair?h=&p=&fp=&c=` (QR, or a tapped link that asks for confirmation, or typing the address and comparing the certificate fingerprint).

Android build quirks already handled in `mobile/android/`: `compileSdk = 37` (permission_handler needs it; AGP 9.0.1 only recommends 36, hence `android.suppressUnsupportedCompileSdk=37`), `kotlin.incremental=false` (the pub cache is on `C:` and the project on `D:`, which breaks Kotlin's incremental compilation), `minSdk = 26`. The Dart `sqlite3` package is configured through `hooks: user_defines: sqlite3: source: sqlcipher` in `mobile/pubspec.yaml`; the app refuses to open its database if `PRAGMA cipher_version` is empty (that would be unencrypted SQLite).

## Architecture

### Mobile in one paragraph
The phone is the **source of truth** for every user record (people, faces, bodies, media, jobs, results, LoRAs); `the app/mobile_api/` is a **stateless** compute API over the existing engines (`analysis.analyze_frame` is the shared detect → embed → quality → bodies core, also used by `library_scanner.py`) — it never imports `database.JsonDatabase`, never reads `data/`, and keeps only an evictable blob cache plus per-job scratch dirs under `the app/mobile_workspace/` (gitignored). Face-swap sources are 512-d identity embeddings (inswapper consumes nothing else), grouping is a pure function over embeddings the phone sends (`grouping_core.plan()` - the very code `gallery_grouping.py` now delegates to - over `person_linking`, which stays the single source of truth for thresholds; the phone calls `POST /v1/grouping/plan` in three rounds: apply [match, cluster] -> apply [bodies] -> review [all], each applied in one transaction), and LoRA identities are built on the phone from real + generated-portrait embeddings. Magic Undress and LoRA training/generation are thin job wrappers over `undress_core` / `lora_trainer` / `lora_generate_job`.

On the phone (P2): the **scan queue is the `media` table** (`scan_status` pending/scanning/done/failed/skipped), so a killed app resumes by itself; per photo `photo_manager` -> `flutter_image_compress` (<= 2560 px) -> `/v1/analyze/image` -> dedupe against the isolate-held `EmbeddingIndex` (cosine >= 0.95) -> faces, bodies, crops and `media_detections` in ONE transaction (`domain/scan/photo_result_store.dart`); a foreground service keeps it alive. Crop paths in the DB are relative (`faces/12.jpg`) so a `.agbackup` (zip: `db/<table>.NNNN.jsonl` + crops + manifest with row counts and SHA-256s) restores anywhere; `servers`, tokens and upload bookkeeping never travel. The PC's last review plan is stored in the `review_*` tables so the Review screen works offline.

### `the app/` in one paragraph
`dashboard.py` (~4,400 lines, one file, no page-routing framework — a sidebar radio over 9 emoji-named pages, each an `elif page == "..."` block) is the only entry point users touch. Everything else is a library module it imports directly: `database.py` (storage), the gallery stack (`library_scanner.py` ingest → `face_quality.py` + `body_detector.py` + `person_linking.py` → `gallery_grouping.py` → `gallery_page.py`, which owns the whole Gallery page — see below), three generations of reface engine, `job_manager.py` (background queue for long-running swaps, LoRA training, and `undress_image` jobs), `undress_core.py` / `undress_engine.py` (persistent `venv_ai` worker — CUDA torch cannot share the main venv; SD1.5 inpaint at <=768 on a native-res crop, then a tiled full-res refine pass, with optional IP-Adapter reference images), and `dfm_engine.py`/`dfl_metadata.py` (DeepFaceLab interop). The full per-module table lives in `the app/CLAUDE.md`.

### Gallery: scan → group → review
Ingest and identity grouping are separate layers, all driven from the Gallery page's "Scan library" button (Data Sources' Process button runs the same code):
- `library_scanner.py` walks photos/videos and writes three record types: **faces** (embedding + quality metadata), **bodies** (box, 17 COCO keypoints, outfit histogram, crop; tied to its face when the face is usable) and **media** (per-file scan signature + every detection, so "which photos is this person in?" is answerable). It's incremental (skips unchanged files) and resumable mid-video.
- `person_linking.py` is the pure-logic core: face↔body association, matching faces to known people, average-linkage clustering, duplicate-person and outfit-based body suggestions. It never touches models or files, so it's unit-tested on CPU.
- `gallery_grouping.py` binds the two to the database: `group_library()` applies only confident decisions, `review_state()` returns everything else for the Review tab.
- Corrections are remembered: `rejected_person_ids` on a face/body and `distinct_from` on a person, so auto-grouping never re-does a correction the user made.
- Detection is deliberately onnxruntime-only (`venv`'s torch is CPU-only): InsightFace for faces, YOLOX-m + RTMPose-m for bodies (auto-downloaded to `models/body/`, ~145 MB).

### Storage: local JSON, despite what the top-level docs say
`the app/README.md` and `the app/.env.template` both describe a PostgreSQL + pgvector setup. That's stale — the project migrated to a local JSON store (migration record in `the app/.agent/memory.md`), and `database.py`'s `JsonDatabase` singleton is the actual source of truth: `data/persons.json` + `data/faces.json` + `data/bodies.json` + `data/media.json`, brute-force NumPy cosine similarity, atomic writes (temp file + `os.replace`), `db.batch()` to group writes and `db.refresh_if_changed()` so the Streamlit process and the job worker don't overwrite each other. `get_session()`/`get_db()` still exist but return a no-op `MockSession` for backward compatibility only. Don't reintroduce SQLAlchemy/pgvector on the strength of the README.

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
| Duplicate threshold | 0.05 cosine distance (links the detection to the existing face) | — |
| Person grouping | `person_linking.STRICTNESS` (balanced): match a known person at score ≥ 0.40 with a 0.10 lead; average-linkage cut 0.70; folds alike groups at 0.60 | DBSCAN `eps=0.28`, `min_samples=2` |
| Quality | `face_quality` v2: norm/size/sharpness/pose, store at ≥ 0.40 | 0.6 default |

`database.auto_assign_to_person()` (the old per-face 0.35 greedy rule) is still there for `face_miner.py`, but the dashboard no longer uses it — the Gallery groups through `gallery_grouping.group_library()`.
