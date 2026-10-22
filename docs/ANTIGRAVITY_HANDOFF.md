# Antigravity handoff — 2026-10-19

Read before continuing work. This is the current handoff for the local checkout,
including uncommitted changes. Older plans/reports describe earlier states.
The user's latest instructions take precedence. Check relevant source before
changing behaviour and update this handoff after material changes.

## 1. Start every task here

1. Identify whether the change concerns Flutter, the mobile API, the desktop
   dashboard, or shared inference. Use the file map below.
2. Inspect existing changes. There is substantial uncommitted and untracked work
   from earlier sessions. Do not reset, clean, discard, overwrite or mass-format
   unrelated files. Untracked files may be important implemented features.
3. Read relevant implementation/tests; make a focused change. Check whether the
   requested feature already exists before rebuilding it.
4. Preserve the existing terminal policy: give commands to the user to run unless
   execution is authorized in the active session. This file grants no new
   permission to install dependencies, change CUDA, deploy or message others.
5. Verify affected behaviour. Report actual passes, failures and untested cases
   separately. Do not claim historical tests were rerun or readiness proves inference.
6. Update this handoff with changed behaviour, actual verification, remaining work
   and any deliberately paused/running phone or server state.

## 2. Architecture and ownership

Workspace: `D:\AndroidScan\gallary` (Windows / PowerShell).

| Folder | Responsibility |
|---|---|
| `mobile/` | Flutter Android app; phone owns its library and results |
| `the app/mobile_api/` | Stateless HTTPS GPU service used by the phone |
| `the app/` | Streamlit desktop dashboard and shared inference modules |
| `python-services/` | Separate legacy FastAPI service, NOT the mobile backend |
| `DeepFaceLab_NVIDIA_RTX3000_series/` | Vendored tool, not application source |

Desktop storage: local JSON via `the app/database.py` (`JsonDatabase`).
Phone storage: Drift + SQLCipher, schema **6**, keys in Android Keystore.
These are separate systems. Do not reintroduce PostgreSQL or use the desktop
JSON database in mobile API request/job paths.

Mobile API scratch inputs live in `the app/mobile_workspace/`. The phone
validates artifact size/SHA-256, commits locally, then ACKs/purges PC scratch.
Preserve that order, device ownership, cancellation, stable job IDs, idempotency
and transactional checkpoints. No uploaded pickle or arbitrary server file paths.
Preserve TLS pin/server identity checks and loopback-only administration.

## 3. Existing environments

Paths relative to `the app/`; use these interpreters, not system Python.

| Interpreter | Purpose |
|---|---|
| `venv/Scripts/python.exe` | Main app, mobile API, ONNX Runtime GPU |
| `venv_ai/Scripts/python.exe` | Python 3.10, CUDA torch, Restyle, LoRA generation |
| `venv_lora/Scripts/python.exe` | LoRA training with existing `sd-scripts/` |

CPU-only torch in the main venv does not mean ONNX GPU is broken. Do not mix
environments or reinstall torch/onnxruntime/CUDA for a model-path issue. Keep
once-per-process DLL registration in `cuda_dll_dirs.py`.
Previously verified GPU: **RTX 4050 Laptop GPU**, 6 GB class.
Flutter: `C:\flutter`. Prefer existing cached SDK/dependencies.

## 4. Model installation is complete for configured capabilities

On **2026-10-19**, the user authorized the remaining download. **SDXL is installed**.
Older statements that it is missing are historical.

| Component | Location relative to `the app/` | Recorded evidence |
|---|---|---|
| Reface models | `models/*.onnx` | Existing PC GPU acceptance; readiness true |
| Body/pose ONNX | `models/body/` | Existing GPU scan acceptance; readiness true |
| LoRA base | `models/sd15_realistic_base.safetensors` | Existing train/generate acceptance |
| SD1.5 inpainting | `models/undress/Uminosachi--realisticVisionV51_v51VAE-inpainting/` | Hashes + base GPU smoke |
| OpenPose ControlNet | `models/undress/lllyasviel--control_v11p_sd15_openpose/` | Installed, hash-verified |
| OpenPose detectors | `models/undress/lllyasviel--Annotators/` | Body/hand reused, face installed; restricted load passed |
| IP-Adapter + encoder | `models/undress/h94--IP-Adapter/` | Base GPU loading passed |
| Clothes parser | Existing local Hugging Face cache | Base smoke executed it; do not duplicate |
| SDXL FP16 | `models/undress/diffusers--stable-diffusion-xl-1.0-inpainting-0.1/` | All 18 files hash-verified; offline app loading passed |

October 19 readiness: `reface_v3`, `reface_v2`, `undress`, `restyle_refine`,
`lora_train`, `lora_generate`, `body_detection` are **true**;
`restyle_missing_models` is **[]**. `dfm_models` is **[]**: no installed custom
DFM was reported. This is not a missing required shared-model download.

SDXL transfer: **6,941,218,469 bytes**. Revision:
`115134f363124c53c7d878647567d04daf26e41e`.
Receipts: `models/undress/base-download-manifest.json` and
`models/undress/refine-download-manifest.json`. Models/environments/receipts are
local and Git-ignored; a Git clone alone does not reproduce the installation.

Download helpers: `mobile/tools/download_restyle_base.py` (base only),
`mobile/tools/download_restyle_refine.py` (SDXL only). Do not run routinely,
download whole repositories, or use `download_models.py --all` to diagnose
readiness: its approximate-size heuristic can redownload third-party files.
Completed download authorization does not authorize future downloads or package changes.

**Readiness, loading and inference are separate evidence.** SDXL GPU inference
and phone refinement have NOT been checked. October 19 loaded FP16 components
on CPU only, with expected warnings that CPU FP16 inference is unsupported.
No inference was performed. `get_sdxl_pipeline` currently calls `pipe.to(device)`
on CUDA; the base loader uses CPU offload. Measure memory/inference before
claiming SDXL fits this GPU or works at target resolution.

## 5. Important current-source differences

Read `the app/undress_engine.py`: `get_sd15_pipeline`, `get_sdxl_pipeline` and
the generation path. Actual code uses **SD1.5 + OpenPose ControlNet**, followed
by optional SDXL. Old comments claiming “no ControlNet” or describing all
refinement as tiled are stale. Presence of tile helpers does not prove they
are used in the current SDXL branch.

The base call currently hardcodes **20 steps and strength 1.0**; SDXL uses
payload-derived steps/strength. Do not assume all UI parameters reach every
stage unchanged. Behaviour changes here are separate from downloading models.

With IP-Adapter attached, preserve its attention processors. The base loader
avoids xformers/attention slicing in that case because they replace the adapter
processor and can break inference. Do not remove this guard as generic tuning.

## 6. Implemented work and recorded verification

Implemented: library/scan/grouping; resumable video upload/analysis; Studio
jobs/results; Reface; base Restyle; Character LoRA datasets/training/generation;
named identity sets; bounded job history/ETA; encrypted backups; app lock/private
viewers; connectivity recovery; private release signing.

- Latest recorded Flutter run: **373 tests passed**, analyzer clean, after the
  phone hashing fix. Evidence: `mobile/build/device-fix-tests.log`, device report.
  Earlier 348/370 counts are historical.
- October 18 completion: 44 server unittest cases, API contract 28/28,
  statelessness 5/5, OpenAPI/fixtures validation, native crypto and independent
  verification passed. See `mobile/build/completion-*.log` and completion report.
- Existing PC GPU round trips passed for Reface, dataset/caption building,
  tiny LoRA training/generation and base Restyle with synthetic inputs.
  Tiny/synthetic smoke tests do not establish production image quality.
- October 19: SDXL hashes + offline application loading passed. No broad suite,
  GPU inference or phone refinement test was performed in the download task.
- **Known recorded red suite: `the app/test_undress.py`: 58/65 passed.**
  Seven failures remain; do not erase or relabel them as passing:

```text
test_harmonize_moves_generated_skin_toward_original_skin
test_protection_preview_tints_background_keep_and_torso_restyle
test_garment_mask_inpaints_upper_ruffles_labeled_as_face
test_garment_mask_keeps_skin_cleavage_in_the_torso
test_garment_mask_inpaints_getty_on_the_dress_not_the_backdrop
test_restyle_body_mask_covers_the_torso_not_the_old_dress_silhouette
test_refine_mask_edges_snaps_a_blocky_mask_to_the_real_edge
```

Some assertions conflict with intentional implementation changes; others concern
mask boundaries. Review intended behaviour before editing code/expectations.
Log: `mobile/build/restyle-base-cpu-tests.log`.

## 7. Phone, signing and outstanding work

Samsung A72 / Android 14 received an in-place **Debug** update October 18,
preserving its SQLCipher library. Device checks covered USB endpoint recovery,
screen-off/task-removal upload continuation, interruption resume, encrypted
export/share cancellation, private crypto fixtures, video playback/seeking,
FLAG_SECURE, gallery export, credential app lock and a synthetic base Restyle
round trip. See the device report for the exact limits of each check.

The hashing fix uses 1 MiB blocks in an isolate, reports preparation progress
and supports cancellation; the recorded phone fixture cancelled in **283 ms**.
Do not replace it with a blocking whole-file hash.

Last RECORDED device state, not live: six-item scan queue explicitly paused,
uploaded video/checkpoint retained, private synthetic Restyle job/result kept,
app lock restored to disabled, USB API available. Recheck before acting. Never
automatically resume a user pause or clear real library/queue/checkpoint data.

Outstanding acceptance/work; choose the user's requested task:

- SDXL GPU memory/inference and phone refinement round trip.
- Full long-video analysis/import/restart and long-duration vendor limits.
- Release performance at scale and camera QR acceptance.
- Phone Reface/LoRA job round trips beyond previously opened forms.
- Restore using a disposable library. No destructive real-library restore was
  attempted; back up before any explicitly requested real-library replacement.
- Per-person video tracking and arbitrary-step training resume are future engine
  work. Current video Reface swaps all detected faces; training resumes at epochs.

Latest documented APKs: `mobile/build/app/outputs/flutter-apk/app-release.apk`
(98,903,598 bytes) and `app-debug.apk` (225,517,671 bytes). Check current files
before relying on historical sizes. Release uses a private RSA-3072 key and
cannot update the differently signed installed Debug app. Do not uninstall to
solve that mismatch or lose the library. No Release installation occurred.
Keep `mobile/android/upload-keystore.jks` and `key.properties` private, backed
up together and out of Git. Never print their contents.

An offline Profile build failed because its Gradle embedding was not cached.
That does not mean Debug/Release is broken; do not silently download dependencies.
Arabic UI and iOS remain outside the current scope.

## 8. File map and focused checks

Paths below are relative to the repository root. Brace notation lists separate
files in the same folder (for example `{scan_worker,video_jobs}.py` means
`scan_worker.py` and `video_jobs.py`); it is not a literal filename.

| Change | Start with | Verification |
|---|---|---|
| Connectivity | `mobile/lib/data/api/`, `the app/mobile_api/{pairing,lan_discovery,admin}.py` | connection tests, `test_mobile_connectivity.py`, `test_mobile_dashboard.py` |
| Scan/video | `mobile/lib/domain/scan/{video_scan,video_hash}.dart`, `the app/mobile_api/{scan_worker,video_jobs}.py` | hash/scan tests, `test_mobile_scan_worker.py`, `test_mobile_video.py` |
| Grouping/identity | `mobile/lib/data/repositories/{people_repository,identity_repository}.dart`, `the app/{grouping_core,person_linking}.py` | repository/identity tests, `test_grouping_core.py` |
| Studio/results | `mobile/lib/data/repositories/studio_repository.dart`, `mobile/lib/domain/jobs/`, `the app/mobile_api/{studio_jobs,artifact_jobs}.py` | job tests, `test_mobile_studio.py`, `test_mobile_artifacts.py` |
| Restyle | `mobile/lib/features/restyle/`, `the app/{undress_core,undress_engine}.py`, `the app/mobile_api/{model_readiness,engines}.py` | readiness, relevant mask/artifact tests, synthetic GPU acceptance when authorized |
| LoRA | `the app/{lora_dataset,lora_trainer,lora_generate,lora_generate_job}.py`, `mobile/lib/features/lora/` | corresponding LoRA scripts and artifact tests |
| Backup/crypto | `mobile/lib/domain/backup/backup_service.dart`, `mobile/lib/data/platform/backup_crypto.dart`; Android files listed below | Dart/native crypto tests, `mobile/tools/verify_backup_vector.py` |
| Schema | `mobile/lib/data/db/{tables,app_database}.dart` | migrations, regenerate committed `app_database.g.dart` |
| Contract | `the app/mobile_api/contract/openapi.yaml`, DTOs/fixtures | validate both server/phone; regenerate fixtures when needed |
| UI strings | `mobile/lib/l10n/app_en.arb` | regenerate localization files, analyze |

Android crypto bridge:
`mobile/android/app/src/main/kotlin/com/antigravity/antigravity_mobile/BackupBridge.kt`.
Cipher implementation:
`mobile/android/app/src/main/java/com/antigravity/antigravity_mobile/BackupCipher.java`.
Python test names in the table are relative to `the app/`; Flutter tests are in
`mobile/test/`. Use the names to locate the relevant existing test before running it.

Readiness command, from **`D:\AndroidScan\gallary\the app`**:

```powershell
.\venv\Scripts\python.exe -m mobile_api --check-models
```

From the wrong directory, `No module named mobile_api` is a working-directory
error, not missing packages. Server tests are mostly standalone scripts; some
use unittest. Flutter commands run from `mobile/`. Follow the terminal policy,
use relevant checks and record exact outcomes. Documentation-only updates do
not require reinstalling packages or rerunning the whole app suite.

## 9. Supporting reports

- [October 19 model installation and limits](local-model-installation-2026-10-19.md)
- [Device acceptance and remaining cases](mobile-device-acceptance-2026-10-18.md)
- [Implementation, signing, crypto and base installation](mobile-completion-2026-10-18.md)
- [Connectivity architecture](mobile-connectivity.md)
- [Historical model audit](local-model-audit-2026-10-14.md) — missing list superseded
- [Original mobile plan](plans/2026-10-11-mobile-app-plan.md) — planning, not current status

After the next task, record: requested change; files/behaviour changed; actual
checks; unresolved failures/acceptance; deliberately paused/running state.
Do not include secrets or personal photo contents.

## Rules follow-up — 2026-10-19

At the user's request, the workflow is now written directly into the always-on
Antigravity rules in the repository root, `the app/` and `mobile/`. Each requires
reading this entire handoff before work, inspecting affected code/tests,
preserving existing changes and updating this handoff with actual outcomes
before finishing. All three rule headers and references were checked; the
existing terminal policy was preserved. This was a documentation/rules change;
no application tests were rerun and no phone/server state was changed.

## Application rebranding to "Your Gallery" — 2026-10-22

At the user's request ("اسم الابليكيشن Your Gallery مش antigravity.. شيل antigravity دي من كل حتة وخليها Your Gallery"), all user-facing application titles, labels, and branding were renamed from "Antigravity" to "Your Gallery":

- **Android App & Manifest**: `android:label="Your Gallery"` in `mobile/android/app/src/main/AndroidManifest.xml`.
- **Flutter UI Strings**: Updated `appTitle` and all 9 user-facing UI messages in `mobile/lib/l10n/app_en.arb`, `mobile/lib/l10n/app_localizations_en.dart`, and `mobile/lib/l10n/app_localizations.dart` (`welcomeBody`, `scanNotPairingCode`, `permissionsIntro`, `startupErrorTitle`, `backupShareSubject`, `noPhotoAccessBody`, `privateResultsHint`, `appLockHint`, `unlockApp`).
- **Foreground & Background Notifications**: Updated `mobile/lib/domain/jobs/job_tracker.dart` (`Your Gallery Studio`) and `mobile/lib/data/platform/foreground_keep_alive.dart` (`Your Gallery`).
- **Error Messages**: Updated `mobile/lib/domain/backup/backup_service.dart` (backup inspection error strings) and `mobile/lib/data/api/pinned_http.dart` (handshake error string).
- **Mobile Tests**: Updated assertions in `mobile/test/widget_test.dart`, `mobile/test/features/privacy_and_lora_test.dart`, `mobile/test/features/onboarding_test.dart`, and `mobile/test/domain/backup_service_test.dart`.
- **Desktop Dashboard & Mobile API**: Updated page title, sidebar brand, mobile bar, and footer in `the app/dashboard.py`; updated instructions and caption in `the app/mobile_devices_page.py`; updated QR hint in `the app/mobile_api/pairing.py`; updated FastAPI title in `the app/mobile_api/app.py`; updated contract title/description in `the app/mobile_api/contract/openapi.yaml`; updated module docstrings and server banner in `the app/mobile_api/__init__.py`, `server.py`, `workspace.py`, `tls.py`, `auth.py`, `discovery.py`, and `the app/README.md`.
- **Preserved Internals**: Preserved `applicationId "com.antigravity.antigravity_mobile"` to prevent breaking existing phone installations, SQLCipher database keys, or package imports. Preserved internal admin header (`X-Antigravity-Admin`), environment variable (`ANTIGRAVITY_FFMPEG`), and mDNS service type (`_antigravity._tcp.local.`).
- **State & Verification**: Verified zero remaining user-facing references to "Antigravity" in `mobile/lib/` and `the app/` UI layers. Preserved terminal policy; provided test execution commands to the user. No phone or server state altered.
