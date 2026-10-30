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

- Latest recorded full Flutter run: **406 tests passed**, after direct target
  face discovery, gallery photo/video sources and multi-frame identity grouping.
  Evidence: `mobile/build/reface-final-identities-tests.log`. Earlier
  348/370/373/377 counts and phone hashing/device reports are historical.
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
- V3/DFM video Reface supports per-person reference selection and identity-aware
  tracking (October 25). Legacy video still swaps all detected faces. Arbitrary-step
  training resume remains future work; training currently resumes at epochs.

Latest documented APKs: `mobile/build/app/outputs/flutter-apk/app-release.apk`
(98,903,598 bytes, historical) and `app-debug.apk` (225,573,426 bytes, October 25 screen-capture-enabled build). Check current files
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

## Fix: qrcode save() unexpected keyword argument `format` — 2026-10-22

- **Issue**: Static analysis and runtime error `Unexpected keyword argument format in function qrcode.image.pure.PyPNGImage.save` in `the app/mobile_devices_page.py:L35` (and identical pattern in `the app/mobile_api/pair_ui.py:L26`).
- **Root Cause**: `qrcode.make()` returns a `BaseImage` instance (`PilImage` or `PyPNGImage`). Unlike PIL's raw `Image.save(fp, format="PNG")`, `BaseImage.save(stream, kind=None)` and `PyPNGImage.save(stream, kind=None)` do not accept a `format` keyword argument. Furthermore, `PilImage` already defaults its format to `self.kind = "PNG"`, making `format='PNG'` redundant for PIL and invalid for `PyPNGImage`.
- **Changes**: Removed `format='PNG'` argument from `.save()` calls in `the app/mobile_devices_page.py` and `the app/mobile_api/pair_ui.py`.
- **Verification**: Code statically inspects clean; preserved terminal policy to provide the verification command (`python -m unittest test_mobile_dashboard.py`) to the user. No phone or server state altered.

## Android TV Support & Network ADB Installation — 2026-10-22

- **Request**: Install the TV version on the TV connected to the local network ("اعمل انستول لفيجن التي في على التليفزيون اللي متوصل معانا في النتورك").
- **Changes**:
  - Configured Android TV compatibility in `mobile/android/app/src/main/AndroidManifest.xml`:
    - Added `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>` and `<uses-feature android:name="android.software.leanback" android:required="false"/>` so Android TV does not reject the application due to missing touch input hardware.
    - Added `<category android:name="android.intent.category.LEANBACK_LAUNCHER"/>` intent filter to `MainActivity` so the app is recognized by the Android TV Leanback launcher and shows up on the TV home screen.
- **Terminal Policy & Verification**: Preserved terminal policy; provided exact step-by-step ADB network connection and installation commands (`adb connect <TV_IP>:5555` and `adb install`) for the user to run. No phone, server, or TV state altered.



## Reface correctness, previews and identity improvements — 2026-10-25

- User requested all fixes/improvements from the Reface review. Implemented the seven findings: encoder failure/timeout and decode checks; identity-aware assignment and per-frame selection; current-frame occlusion protection; safe local full-frame compatibility; actual per-face outcomes; engine-specific phone controls. Added shared robust identity filtering, bounded generated-portrait influence, desktop/phone previews, reference-photo selection for V3/DFM phone video, effective quality reports, and stronger evaluation coverage/scenario splits.
- New shared helpers: the app/reface_tracking.py and reface_video_io.py. New regression scripts: test_reface_quality.py and opt-in test_reface_gpu_acceptance.py. Shared ffmpeg_utils concat lists accept exact part durations; this fixes fractional-rate drift in short MP4 segments. Contract/fixture/localizations and affected Flutter tests were updated.
- Actual verification: Flutter **377 tests passed**, analyzer **no issues**. Python: correctness **22/22**, compositor **52/52**, legacy **41/41**, identity builder **7/7**, desktop LoRA identity/persistence **7/7**, Studio **13/13**, API contract **28/28**, statelessness **5/5**; OpenAPI + **30 fixtures**/negative cases passed, changed Python modules compiled. Real CUDA image API round trip passed; a two-person PNG changed only the selected person, and a 3+6 frame pause/resume video joined to **9 frames at 29.97002997 fps**.
- Important: phone V3/DFM video can now select people using reference embeddings/indices; older statements that all video Reface always swaps every face are superseded for those engines. Legacy video still swaps all faces. Preview renders up to three seconds. Resumed V3 segments warm up preceding frames to restore temporal state.
- Evidence, usage, changed behaviour and limits: [Reface implementation report](reface-improvements-2026-10-25.md). Logs: mobile/build/reface-*.log; GPU report: mobile/build/reface-acceptance/gpu-report.json. Initial sandbox access failures were resolved with local temp paths/runtime access before reporting passes.
- No downloads, dependency/CUDA changes, phone/server deployment or real library/queue mutations. Existing unrelated handoff/Android TV manifest edits were preserved. Broad visual A/B evaluation, long-video/phone acceptance, LoRA inpainting refinement and new identity-specific DFM training remain unverified/separate model experiments. Previously recorded Restyle failures remain recorded.

- Final Android verification for this change: Gradle **offline assembleDebug succeeded** in 2m 11s. Updated Debug APK: mobile/build/app/outputs/flutter-apk/app-debug.apk (**225,524,452 bytes**), also at build/app/outputs/apk/debug/app-debug.apk. Log: mobile/build/reface-debug-build.log. No device installation was performed.

## Reface mobile selection, stateless cleanup and Wi-Fi transfer performance — 2026-10-25

- User requested verification from a fresh phone/empty server with no personal payload retained after return, then one photo/video target picker, visible video range selection and faster transfers on the same Wi-Fi. Previously authorized tests/checks were run using existing environments. The user did not supply an identity for custom LoRA/DFM experiments; no identity-specific training or new model download was attempted.
- Phone UI: reface_media.dart uses the existing combined system picker and detects the selected type. reface_video_trimmer.dart shows video, range handles, readable times, playback and one-second boundary nudges. RefaceScreen submits the selected range automatically; raw seconds fields are gone. Six focused regressions cover selection/dragging/seeking/playback on a narrow viewport. Native phone picker/codec acceptance remains untested this session.
- Server retention: Workspace registers pinned job input hashes, removes input-cache blobs only after their last registered job is deleted, and fails ACK on deletion errors so cleanup retries safely. Studio/video managers register references and release personal request/detail state on deletion. ScratchJanitor expires abandoned uploads/partials after six hours and inactive jobs after 24 hours, sweeps every 60 seconds without polling and protects active jobs. Startup wipes ephemeral workspace files. Multipart analysis files close before inference; ordinary API access logging is disabled. TLS/device pairing and generic model weights persist.
- Phone cleanup: JobTracker retains completed results/pending ACK on cleanup errors and closes SSE safely. StudioRepository preserves cleanup when local outputs are deleted. A completed result is never re-downloaded just because ACK failed.
- Transfers: binary upload streams use zero-copy 256 KiB views instead of Dio's copied 1 KiB blocks, preserving 4 MiB resumable requests. ResultFileResponse reads 1 MiB blocks and keeps authenticated byte ranges/no-store. The phone batches disk writes, resumes partial Studio downloads, safely handles ignored/invalid ranges and preserves auth/retry errors. TCP_NODELAY is set on pinned connections. Original media bytes/quality and SHA-256/commit-before-ACK are preserved.
- Measured, three-run median with identical synthetic 32 MiB transfers over real pinned HTTPS **on desktop loopback**: upload 0.878141 → 0.682083 seconds (**22.3% less time**); download 0.919255 → 0.795932 seconds (**13.4% less time**). These are not phone/Wi-Fi throughput measurements. Benchmark: mobile/tools/transfer_benchmark_test.dart; logs mobile/build/transfer-{baseline,optimized}.log. Selected video ranges still upload the full source video before server-side trimming.
- Actual final checks: **395 Flutter tests passed**, analyzer **no issues**; server Studio 13 + video 9 + retention 6 = **28 passed**; stateless database/data isolation **5/5**; OpenAPI + 30 fixtures/negative cases passed; changed Python modules compiled. The real Flutter HTTPS/GPU test was repeated after transfer changes: verified local commit followed by ACK left **zero server payload files**. Logs: mobile/build/reface-transfer-final-{tests,analyze}.log, transfer-server-tests.log, stateless-transfer-live-gpu.log and transfer-stateless-isolation.log.
- The new network tests include abrupt TLS interruption, persisted partial resume, full binary integrity, range fallbacks, invalid ranges and HTTP auth/retry errors. Early disconnect simulation errors were test-fixture misuse of HTTP socket detachment; corrected to a deliberately truncated raw response. Initial analyzer findings were fixed; no findings were suppressed. Previously recorded unrelated Restyle failures remain unmodified/unrerun.
- Reports: [stateless workflow and target UI](mobile-stateless-workflow-2026-10-25.md), [transfer changes/measurements](mobile-transfer-performance-2026-10-25.md). No physical device was attached, no installation/deployment occurred, and the user's library/paused scan/checkpoints and unrelated Android TV manifest edits were preserved. Isolated test servers shut down; no user server was stopped or restarted.
- Final offline Debug APK build succeeded in **1m 26s** (498 tasks; 26 executed). Both mobile/build/app/outputs/flutter-apk/app-debug.apk and mobile/build/app/outputs/apk/debug/app-debug.apk are **225,544,259 bytes**, SHA-256 **353497f1806b848e85a83384a590f9573065148f5999dde29d9d098cf4888446**. Log: mobile/build/reface-transfer-debug-build.log. It has not been installed. Apply both the updated APK and backend code for all transfer/retention improvements to take effect; no running user server was restarted during this task.

## Reface target opens Files instead of Google Photos — 2026-10-25

- User requested the device file explorer directly. Changed mobile/lib/features/reface/reface_media.dart from ImagePicker.pickMedia to existing FilePicker.pickFile with FileType.custom and image/video extension filters. Inspection of the installed Android plugin confirms custom filters use ACTION_OPEN_DOCUMENT; media/image/video picker modes can use ACTION_GET_CONTENT and open gallery providers. The single target button, automatic type detection and video preview/trimmer are preserved. No dependencies or Android permissions were changed.
- Existing Reface trimmer + Studio tests: **16 passed** (mobile/build/reface-files-picker-tests.log). The previous 395-test full-suite/GPU evidence remains historical; backend/transfer code was not changed or retested for this picker-only task. Physical Android picker acceptance remains a device check; no installation or real phone/library/server mutation was performed. Existing unrelated handoff/manifest changes were preserved.
- Flutter analyzer: **no issues** (mobile/build/reface-files-picker-analyze.log). Offline Debug build: **successful in 52s**, 498 tasks/29 executed (mobile/build/reface-files-picker-build.log). Updated APK at mobile/build/app/outputs/flutter-apk/app-debug.apk, also build/app/outputs/apk/debug/app-debug.apk: **225,543,839 bytes**. This supersedes the earlier APK size; it has not been installed on a device.

## Explicit Gallery and Files source choices — 2026-10-25

- User clarified that the device gallery must also be available. The single Reface target button now opens a source menu with **Gallery** and **Files**. Gallery invokes native MediaPickerBridge.kt via antigravity/media_picker; Intent.createChooser wraps GET_CONTENT with image/video MIME filters so installed gallery apps are offered instead of silently following a saved Photos default. Files retains the custom ACTION_OPEN_DOCUMENT picker. Cancelling the menu preserves the current target; both sources still accept image/video and preserve trimming.
- MainActivity registers/closes the bridge and forwards its distinct activity-result code without disturbing SecurityBridge. Selected content is copied into app-private cache on an IO worker with a 1 MiB buffer; cancellation/errors clean incomplete copies. No dependency or permission changes. Source labels/localizations regenerated; existing TestEnv and Reface/Studio tests updated for the source choice.
- Actual checks: **16 focused tests passed** including both Gallery/Files routing and cancellation; Flutter analyzer **no issues**. Offline Debug APK/native Kotlin build **succeeded in 46s** (498 tasks/26 executed). Logs: mobile/build/reface-gallery-chooser-{tests,analyze,build}.log. The earlier 395 full-suite/GPU results were not rerun for this UI task; known unrelated Restyle failures remain recorded.
- A physical **Samsung SM-A556E (A55), API 36** is now attached. Read-only package-manager queries confirm Samsung Gallery (com.sec.android.gallery3d/com.samsung.android.gallery.app.activity.external.GalleryExternalActivity) handles the exact GET_CONTENT/OPENABLE/image-video selection. No serial/token was written here. No new APK was installed, no picker UI was opened on the device, and no library/queue/server state was changed. Native visual acceptance remains unverified.
- Latest APK: mobile/build/app/outputs/flutter-apk/app-debug.apk, also build/app/outputs/apk/debug/app-debug.apk, **225,546,612 bytes**. This supersedes earlier picker builds. Existing unrelated handoff/manifest edits were preserved.

## Direct media source identities and grouped video targets — 2026-10-25

- User corrected the Reface flow: select target people from faces in the actual photo/video, then choose replacement identity from a library person **or multiple gallery photos/videos**. Removed the separate target-reference-photo UI. Video target analysis samples its selected trim locally, sends JPEGs to the existing stateless analysis API and displays grouped people. Photo targets retain boxes and now also show face crops. Source imports are ephemeral form state, require a chosen person when multiple identities are found, and never create library people/faces. Backend payloads keep target identities separate from source embeddings. Legacy video is excluded because it cannot honour selected-person replacement; Legacy photo and V3/DFM behaviour remain available.
- Native MediaPickerBridge now supports multiple gallery files and frame sampling. New VideoFrameSampler.kt reads bounded 1920-pixel JPEGs on an IO worker, falls back from exact to sync seeks, skips unreadable frames and responds to superseded requests/activity shutdown. Dart ignores stale scans after trim changes; sampling has a visible 90-second timeout and errors beside the action. A current-preview-frame action can discover a person missed by interval sampling without replacing the trim or existing selections.
- User reported an empty scan, then confirmed face discovery worked and reported one identity per frame. The 1280-pixel preview cap excluded the server's finer detection pass. Raised preview resolution and added one same-threshold finer-grid retry in shared analysis.detect_faces when ordinary passes return no faces. User-confirmed discovery is not evidence that every difficult video codec/clip has been accepted.
- Replaced the initial 0.55/0.08 grouping gate with normalized embeddings, a quality-weighted multi-pose identity and balanced 0.40 matching/0.06 ambiguity. Clear-view bridges and repeated evidence consolidate fragments; hard frame co-occurrence constraints and competing-identity checks protect distinct people. Selection indices survive consolidation. Cards show appearance counts; at most 20 distinct source poses are kept, and video wire references remain within 32. Details and limits: [direct media identity report](reface-direct-media-identities-2026-10-25.md).
- Actual verification: **406 full Flutter tests passed**, including real HTTPS/synthetic-compute commit-before-ACK/purge; eleven new identity/flow tests cover poses, fragment consolidation, co-occurring lookalikes, ambiguity, request limits, mixed photos/video with an empty people library, selected target/source payloads, stale scans, current-frame recovery and local error/retry. Shared analysis **7/7**, API contract **28/28**, stateless isolation **5/5** passed. Logs: mobile/build/reface-final-identities-tests.log, reface-grouped-identities-focused.log, reface-empty-scan-server.log and reface-identities-{api-contract,stateless}.log.
- Early test failures were corrected rather than suppressed: file-staging tests now allow real IO to settle, scroll helpers wait for layout, grouping consolidation now rejects ambiguous evidence against co-occurring known people. Previously recorded unrelated Restyle failures remain recorded and were not rerun.
- No dependencies/models/CUDA were changed. This task did not install an APK, restart the user's server, access a real library/queue/checkpoint or save private media to the PC. Read-only device package metadata was checked; when Your Gallery was not foreground, no other app UI was inspected. Final visual acceptance of grouping on the user's actual clip remains unverified. Server finer-grid fallback requires updated backend execution; source/target selection uses the existing API contract.
- Final analyzer **no issues** (mobile/build/reface-final-identities-analyze.log). Final offline Debug build **succeeded in 17s** (498 tasks/22 executed; mobile/build/reface-final-identities-build.log). Both build/app/outputs/flutter-apk/app-debug.apk and build/app/outputs/apk/debug/app-debug.apk under mobile/ are **225,571,223 bytes**. This supersedes the intermediate APKs. No installation was performed by this task.

## Screenshots and screen recording enabled — 2026-10-25

- User explicitly requested removing capture protection throughout the app. Removed SensitiveSurface route wrappers from Reface, Restyle, media and result viewers, and from the backup password dialog. Removed the route-lease implementation and unused PrivacyService.secure Dart API/FakePrivacy method. SecurityBridge no longer stores a secure flag or adds FLAG_SECURE: MainActivity startup clears it via allowScreenCapture. The legacy native secure channel method also only clears the flag, so an old request cannot re-enable blocking.
- Authentication/app-lock, encrypted storage/backups, export controls and all prior Reface/transfer changes were preserved. No dependencies, permissions, models or server code were changed by this task. Native OS-owned credential screens are not part of the app window policy.
- Actual verification: **21 affected Flutter tests passed** (privacy/app lock, Studio, media/video and backup password); analyzer **no issues**. Offline Debug/native Kotlin build **succeeded in 22s**, 498 tasks/25 executed. Logs: mobile/build/screen-capture-enabled-{tests,analyze,build}.log. A source search confirms no SensitiveSurface, secureEnabled, Dart capture-activation call or FLAG_SECURE addFlags remains; only explicit clearFlags is retained.
- The first compile exposed the backup password dialog's additional wrapper; it was removed before passing verification. The previous 406-test full run is historical and was not rerun for this focused change. Existing unrelated Restyle failures remain recorded.
- Latest Debug APK: mobile/build/app/outputs/flutter-apk/app-debug.apk and mobile/build/app/outputs/apk/debug/app-debug.apk, **225,573,426 bytes**. This supersedes the grouped-identities APK. No installation, screen capture/recording on a real device, library/queue mutation or server restart was performed by this task; the updated APK must be installed for the new capture policy to apply.

## Release APK Build & Device Installation Status — 2026-10-27

- **Request**: User requested building a release version of the mobile app and installing it onto the connected phone without running any tests ("اعمل install للابلكيشن الموبايل، اعمل release version واعملها install على الموبايل المتوصل، ومتقعدش تعمل أي tests").
- **Release Build**: Executed `flutter build apk --release` in `mobile/`. Build succeeded in 389.8s. Fresh signed Release APK generated at `mobile/build/app/outputs/flutter-apk/app-release.apk` (**98,716,394 bytes**).
- **Test Policy**: Strictly respected the user's explicit instruction not to run any tests; zero tests were run.
- **Device & Installation Status**:
  - The physical device (Samsung Galaxy A72 / `Abdallah's A72`, USB VID:04E8 PID:6860, serial `R58R30QA3KZ`) is physically plugged into USB and recognized by Windows PnP (`SAMSUNG Android ADB Interface`, `oem46.inf`).
  - ADB daemon initially reported `(no serial number) offline transport_id:1` and subsequently empty device list (`error: no devices/emulators found`).
  - Required device actions for USB ADB: unlock the phone screen, ensure USB mode is "Transferring files" (MTP), toggle USB Debugging in Developer Options (or tap "Revoke USB debugging authorizations"), and accept the "Allow USB debugging?" dialog.
  - Critical signing note: per Section 7, the installed app on this device was previously a Debug build. Installing a Release build over an existing Debug build triggers `INSTALL_FAILED_UPDATE_INCOMPATIBLE` due to the private RSA-3072 signature mismatch. Do not uninstall without an encrypted backup, as uninstalling deletes the SQLCipher Keystore key and app database.

## Continuous mobile Reface and V2 default — 2026-10-30

- User clarified that the problem is intermittent unswapped frames across a video, not a request to sample or freeze video frames. The mobile screen previously defaulted to V3 and excluded V2 video. V2 is now the default when available, explicitly labelled V2, and supports selected video identities; V3 remains selectable and the API contract documents reference selection for all video engines.
- Found a concrete matching bug: the phone sends several pose references for one person, but the selector rejected a near-tie between any two references, including two selected poses of the same person. Shared reface_selection now measures ambiguity against unselected people only. Selected poses can agree without cancelling a swap; competing unselected identities still require the same confidence margin. Both engines use this selector.
- Shared current-frame recovery searches an expanded last-known region when a selected person is missed, translates fresh detections back to video coordinates and verifies their current identity. Search history expires after three misses and clears at scene cuts. No old faces or rendered frames are replayed. Detection skips unused age/gender and 106-point models; V2 keeps the 68-point pose/occlusion model. Empty detector results receive a scale retry. Actual GPU latency and difficult real-video coverage have not been measured.
- V2 video now retains fractional FPS instead of rounding it, uses unique segment names, restores detection context on resume, and selects embedding-only source poses by the actual source item instead of their shared empty path. Mobile V2 uses landmark smoothing without whole-frame temporal blending. V2 selected-person parameters reach the engine; zero-swap V2 video jobs fail instead of publishing an unchanged result. Result metadata identifies the engine and recovered detections.
- Actual verification: 27 affected Flutter tests passed; analyzer reports no issues. CPU/synthetic suites: 42 continuity/Studio/quality tests, 41 existing V2 tests, 28 API contract tests, and two focused compositor selection tests passed. Tests cover multiple selected poses, unselected lookalikes, fresh ROI coordinates, missing detections, every rendered frame, source-pose selection with empty paths, fractional FPS and pause/resume without missing output frames. Logs: mobile/build/reface-continuity-{flutter-tests,server-tests,v2-tests,contract-tests,selector-tests,analyze}.log. Initial sandbox temp/cache restrictions were resolved by using an in-workspace temp folder and approved test execution; a real InsightFace Face-container copy incompatibility found during verification was fixed and included in final tests. Previously recorded unrelated Restyle failures remain unchanged and were not rerun.
- Offline signed Release build succeeded in 2m 55s, 586 tasks/95 executed. APK signature verification passed. Both mobile/build/app/outputs/apk/release/app-release.apk and mobile/build/app/outputs/flutter-apk/app-release.apk are 99,264,166 bytes; SHA-256 8D6EBEC464D2A371888C599ADEE0F89BB95EA24941F43DE6462EF42EEA97DFAA. Build log: mobile/build/reface-continuity-release-build.log. This supersedes earlier Release APK artifacts.
- No APK installation, user-server restart, private media/library/queue mutation, model download or dependency/CUDA change occurred. Apply the APK and run the updated backend together for V2 selected-video support. Actual phone/video acceptance and speed measurement remain required; synthetic continuity tests do not prove every real face/occlusion can be recovered.

## Explicit all-faces mode on mobile — 2026-10-30

- Added a Replace all faces switch in Reface's target step for both photos and video. It starts off so existing person selections retain their meaning. Turning it on hides target selection, cancels/discards pending target-video discovery, skips unnecessary target analysis, and omits target_faces, target_embeddings and target_indices from the job request. The existing server interprets that omission as swapping every detected face, including people appearing later in a video. The replacement source identity and valid video trim are still required. The review step shows the chosen mode.
- Turning all-faces mode off restores existing selections or starts missing photo/video discovery. Source identity model checks remain active; target model/selection checks apply only to selected-person mode. No backend/API changes were needed in this follow-up; the preceding V2/continuity fixes remain preserved.
- Verification: 33 affected Flutter tests passed, including six new all-faces tests for V2/V3 photos and videos, omitted selection payloads, no target analysis, resuming selected-photo discovery and cancelling/resuming a pending video scan. Focused analyzer of the Reface screen and its new tests reports no issues. Logs: mobile/build/reface-all-faces-{tests,analyze}.log. Test fixtures use a real synthetic PNG and mocked platform temp directory for photo staging. Concurrent workspace interface/label edits were preserved; localization was regenerated from the combined ARB, and the existing Studio navigation test now scrolls to its result link in the changed layout.
- Offline signed Release build succeeded in 47s (586 tasks, 28 executed); signature verification passed. A stable delivery copy is mobile/build/reface-all-faces-release.apk: 99,264,166 bytes, SHA-256 6297E78BFB91223EDE2F714FB46A955B4E7A4C0DFB73AA1BA738E972C9846A3B. All three ABI libapp.so entries were inspected and contain the new all-faces toggle/label. The APK also contains the concurrent current workspace UI changes. Build log: mobile/build/reface-all-faces-release-build.log. This artifact supersedes the preceding Release build.
- No phone installation, server restart, model/dependency changes or real library/media/queue access occurred. Real-device acceptance remains unperformed. Earlier Python/GPU evidence and unrelated Restyle failures were not rerun for this Flutter-only follow-up.


## Mobile UX redesign preparation — 2026-10-30

- User requested a mobile-screen redesign with a function inventory for every screen and a strong emphasis on ease of use. After an explicit clarification, the user selected **prepare changes and provide verification commands**, rather than executing Flutter validation. No Flutter/Python command, analyzer, test, build, installation or application/server action was run for this redesign. Initial repository discovery was read-only; subsequent file work used filesystem tools.
- Added docs/mobile-ux-redesign-2026-10-30.md: source-based inventory of all **32 GoRoute screens**, primary/secondary functions, error/empty/offline states, Reface flow, design decisions, prepared changes, outstanding work and exact local verification commands. Read that report before treating this preparation as tested.
- Prepared a green/neutral Material theme for light/dark appearance, larger clear actions, input/sheet/navigation styling, and shared ScreenIntro / SectionHeading / ActionRow / StickyActionBar / GuidedWorkflow components in mobile/lib/core/theme.dart and features/shared/screen_layout.dart. Shared empty states can scroll with constrained space. No fonts, dependencies, schemas, API contracts, engines, model defaults or inference environments were changed.
- Reworked Home and Studio hierarchy; moved Home status out of the title bar; added direct settings/results access, content-sized statistics, actionable empty-filter/search/results states, larger People tiles, horizontally scrollable media-kind selection and expanded form dropdowns. Settings now have clear groups; training's technical fields are collapsed. Jobs uses In progress for mixed active stages and the navigation shows a pending count. Affected files are features/{home,studio,shell,library,people,settings,jobs,results} plus the shared components.
- Reface now shows one visible step and a fixed primary action. GuidedWorkflow uses IndexedStack and TickerMode to retain inactive form/video state while hiding it; the trimmer's active flag still pauses playback. This avoids recreating the video controller and losing its trim when returning to Target. The existing Reface controller, direct identities, V2 defaults, selected-video behaviour, validation and request construction were preserved. Existing unrelated edits in this file/localizations/handoff and all backend work remain in place.
- Sources, Restyle, dataset building, training and generation now have bottom actions; form bars account for the keyboard, while the workflow's bar relies on its already resized body. Sources/options, Reface and Studio processing contracts remain the existing ones.
- Added **six unexecuted** regressions in mobile/test/features/redesign_ux_test.dart for narrow/large-text action access, photo back navigation, video controller/trim retention, library-filter recovery, people-search recovery and advanced training disclosure. No passing-test claim is made. The official gen-l10n and Dart formatter were also not run: 23 ARB messages and matching abstract/English implementations were prepared manually, preserving earlier entries; regenerate them using the report's commands.
- Actual review was source-only: all 32 route declarations were matched to the inventory; the prepared changed files' localization references/import targets exist and new localization declarations have matching implementations. This is **not Dart compilation or widget/visual verification**. Flutter analyze, focused UI regressions, real rendering, keyboard/large-text/dark-mode acceptance and any APK build remain outstanding. Previous historical Flutter/GPU passes and the seven previously recorded Restyle failures are unchanged and were not rerun.
- A separate conversation-only interactive design preview uses synthetic data; it is a conceptual HTML mockup, not a Flutter screenshot or evidence of runtime acceptance. It is stored in this chat's visualization directory, outside the application.
- No user's library, private media, queue, checkpoint, phone installation, running/paused server or app-lock/capture policy was accessed or changed. No new APK exists for these UI changes.

## One public mobile Reface pipeline and model explanations — 2026-10-30

- User first requested explanations of model purpose/speed/likeness, then asked to combine numbered Reface versions into one. Work follows the current mobile/phone-server context; an optional scope question about also changing the desktop UI was unanswered. Desktop version selectors and desktop job-manager dispatch were deliberately not changed. This section supersedes the earlier mobile V2-default instruction: new mobile work uses the unified pipeline.
- Added the public the app/reface.py RefaceEngine and model-free reface_config.py. Fast, Balanced and More detail configure this same inherited current-frame pipeline; profiles never dispatch to V1/V2. It reuses source/face-set handling, averaged identity, identity-aware tracking, current-frame detection recovery, protected compositing, fractional FPS and resumable encoding. Public image/video methods and result settings use Reface naming. Older modules and API aliases remain for compatibility with already-saved work; no queued request is rewritten or migrated mid-render.
- New phone job types are reface_image and reface_video, with quality_profile. The API accepts these alongside old v2/v3/DFM aliases. A trained DFM identity is an optional source method via dfm_model, not an engine version. The adapter calls canonical image/video methods for new types, preserving selection, all-faces mode, trim, preview, checkpoints and commit-before-ACK behavior. Existing numbered requests retain their old dispatch paths.
- Capabilities add engines.reface and reface_profiles. The latter reports the available automatic model for each profile: Fast disables restoration/parser by default; Balanced prefers GPEN 512; More detail prefers GPEN 1024, then GPEN 512, then another installed restorer. Explicit restoration/parser choices can override profile defaults. No model availability means restoration Off. Larger native GPEN crops use 1024-pixel compositing; other restorers use 512. Masker initialization now skips disabled parser/occluder sessions, retaining occlusion protection in the default Fast profile. No downloads or dependency/environment changes.
- Removed engine-version pickers from the mobile source and quality steps. Source identity methods distinguish photos/videos from a trained identity only when trained models exist. Quality profiles and every known restorer have readable menu subtitles plus changing descriptions below the selected choice. Automatic shows the PC-reported starting model. Labels explain restoration cost, native crop size versus video resolution, and the distinction between restored detail and likeness; no unmeasured FPS, star ratings or universal accuracy rankings are shown. Unknown future model names get a neutral preview explanation. Job labels no longer append version numbers. An older server without unified support is identified before submission.
- Actual checks: **62 affected Flutter tests passed**, including all three quality profiles submitting the same canonical photo/video types, all-faces and selected identities, model explanations, 320px/1.8x-text menu scrolling and selection, unknown model labels, DTO capability negotiation and the six concurrent redesign regressions. Focused analyzer: **no issues**. Backend: **50** unified/profile/Studio/continuity/quality cases, **28** API contract cases and **5** stateless cases passed; OpenAPI/fixtures and negative schema checks passed. New schema example has a distinct canonical request ID and Automatic restoration. Logs: mobile/build/reface-unified-{flutter-tests,options-tests,analyze,server-tests,contract-tests,stateless-tests,schema-tests}.log. Two test helpers were corrected rather than suppressed: long dropdowns await scroll/layout completion, and the redesign trim test moves one handle per gesture, matching the actual trimmer contract.
- Source references for model-purpose/fidelity descriptions: [CodeFormer](https://github.com/sczhou/CodeFormer), [GFPGAN](https://github.com/TencentARC/GFPGAN), [GPEN](https://github.com/yangxy/GPEN), [RestoreFormer++](https://github.com/wzhouxiff/RestoreFormerPlusPlus). Automatic selection/profile defaults follow local code and installed-model metadata. Actual GPU latency, real-video coverage and likeness for these new profile combinations were not measured; historical GPU evidence is not represented as a new run. The whole Flutter suite and unrelated recorded Restyle failures were not rerun.
- Offline Release build succeeded in **47s**, 586 tasks/28 executed; signature verification passed. Stable artifact: mobile/build/reface-unified-release.apk, **99,329,702 bytes**, SHA-256 **B38350D110C577899BB6DB7A80DBA0512CA420C34D96F4D6F90DD27762B31EFE**. All three ABI libapp.so entries contain the new quality/description markers and no old quality-engine picker marker. Build log: mobile/build/reface-unified-release-build.log. This supersedes previous delivery APKs and includes the preserved concurrent workspace UI changes.
- No installation, running-server restart, real media/library/queue mutation or deployment occurred. Install this APK and run the updated PC API together to enable the canonical jobs/capability negotiation. Existing user modifications and the concurrent mobile UX work were preserved.

## Unified desktop and mobile Reface — confirmed scope, 2026-10-30

- User explicitly answered that consolidation includes **both mobile and desktop**, then asked to continue. This supersedes the unanswered-scope limitation in the preceding section. New desktop and mobile work now calls the same public `reface.RefaceEngine`; Fast/Balanced/More detail configure one pipeline. Mobile implementation and the signed APK from the preceding section remain unchanged.
- Consolidated the two desktop pages into one Reface page and removed the V2/V3 engine selector and legacy configuration tree. The single page retains multiple source uploads, saved facesets, identity building/management, trained LoRA identities, trained DFM exports/tools, previews, trimming, history/downloads, and background-job controls. Gallery people and configured-folder targets were integrated into this workflow; the Gallery action preselects the person. Historical training restrictions remain in place.
- Desktop options use the same profile defaults as the phone server, describe each available restorer and automatic selection, and send identical constructor settings to direct and queued processing. Trained exports use the same engine with separate restoration disabled. The existing and former result prefixes are included in one history; previews are paged in groups of 12 and large downloads remain explicitly prepared.
- Added an explicit Replace all faces control. It bypasses old target ticks and processes people appearing later. Selected-person mode requires valid current-target embeddings (including bystander references), so new work cannot silently fall back to detection order. Target changes, including different uploads with the same filename, discard old references. Desktop target uploads reuse staged bytes on UI reruns instead of rewriting large videos after every option change.
- New desktop queue requests use `reface_image`/`reface_video` plus `quality_profile`. That field distinguishes new unified requests from already-saved unversioned V1 jobs. Saved V1/V2/V3/DFM requests keep their original dispatch for checkpoint compatibility; no user job was migrated. New jobs use the public image/video methods and the existing validated video-part finalizer. Corrected pause persistence so segment counters/effective settings survive the reload in `pause_job` and accumulate after resume.
- There is one Reface navigation entry. Former versioned titles/slugs and numeric bookmarks resolve to it; numeric bookmarks for other pages retain their original meanings. Previously open sessions are normalized before the navigation widget is created.
- Actual final verification: **61 combined CPU-only desktop/UI/worker/profile/continuity/quality/phone-Studio tests passed**, including Streamlit AppTest rendering the real Reface page against a temporary app directory and synthetic gallery fixtures. All three profiles and both photo/video paths were checked for identical direct/queue options; selection/all-faces, gallery reuse, combined-history paging, trained identity dispatch, legacy dispatch and pause/resume counts were covered. **41/41 legacy Reface regressions** and **6 routing tests** also passed. Compilation and the opt-in GPU script's `--help` passed. The sandboxed combined run stopped making progress during server testing; only its two verified test processes were stopped, and the full 61-case run completed outside the sandbox in 16.034 seconds. Logs: `mobile/build/reface-desktop-{final-tests,server-tests,legacy-tests}.log`.
- The opt-in GPU acceptance script now targets the public pipeline and accepts `--quality-profile`; its real GPU/media check was **not run**. No fresh GPU latency, likeness, or real-video coverage claim is made. No model downloads, CUDA/dependency changes, phone installation, application-server restart, deployment, or access to the user's live library/media/jobs occurred. Existing concurrent mobile work was preserved.
- Delivery APK remains `mobile/build/reface-unified-release.apk`, SHA-256 **B38350D110C577899BB6DB7A80DBA0512CA420C34D96F4D6F90DD27762B31EFE** (rechecked). Activate by running the updated desktop/API code and installing that APK; neither activation step was performed here.


## Approved mobile redesign implementation — 2026-10-30

- User approved the interactive design and explicitly requested implementation, then asked to continue. The earlier choice to prepare source and user-run verification commands remains in force. No terminal, Flutter command, generator, formatter, analyzer, test, build, installation or running-server action was executed for this implementation. Work used source/file tools only.
- Extended the approved design into storage, backup, welcome/QR/manual pairing/permissions, connection/background, merge/review/insights, media/video, person details, face selection, detection, dataset editing, job details and result details. Existing Home/Studio/theme/Reface redesign changes were retained. The current canonical unified Reface pipeline and quality-profile work from the concurrent task were read and preserved; no old V2/V3 selector or dispatch was restored.
- Added SurfaceSection, StatusNotice and AdaptivePair in features/shared/screen_layout.dart and RetryState in empty_state.dart. Headings have semantics; confirmations and lock content can scroll, and field hints/errors can wrap. The current fixed-action component is reused, including its distinct keyboard handling inside an already resized workflow.
- Storage uses actual category byte counts, sorted usage rows and a total; model folders are labelled as models. Temporary cleanup is separate from collapsed removal of saved results/datasets/LoRAs. Confirmation titles identify the selected category. Cleanup, maintenance suspension and all existing deletion guards remain the existing handlers. No cleanup was performed by the agent.
- Backup, manual pairing, background enablement, merge decisions, dataset train/export, job pause/resume/retry/result, and result save/share actions are now fixed in the appropriate action bars. Export/authentication/crypto/merge/job request bodies and repository transaction behavior were not changed.
- FaceGrid adds explicit Select faces mode so users can choose faces with ordinary taps; long-press and normal open behavior remain. Successful assign/reject/delete/cover operations and Clear selection exit the mode. Person details have a direct Studio action. Video seeking is full width, and media/sample chips account for text scale. Dataset video sources show a video placeholder instead of trying to decode the file as an image.
- MediaGrid now catches count/page errors and offers retry. Count queries use a generation counter to ignore old filter responses; retry feedback does not clear a normally updating populated grid. Shared person picking handles keyboard insets, clear-search and loading/error/empty states. Stream-backed detail screens use the same current record for content and fixed actions.
- Added six unexecuted cases in mobile/test/features/redesign_screens_test.dart: actual storage categories and confirmation gating; large-text backup actions; manual-pair keyboard clearance; job Retry visibility; result Share visibility; explicit normal-tap face selection. Existing tests, including the six redesign cases verified by the concurrent unified-Reface task, were not overwritten or rerun here. Historical passing counts are not new evidence for this batch.
- Added mobile/tools/verify_ui_redesign.ps1 for the user to run. It uses the existing SDK, regenerates localization, formats an explicit list of changed UI Dart files, analyzes with --no-pub and runs test/features unless -SkipTests is supplied. It does not build/install, change Python/CUDA or run automatically. Its referenced file paths were inspected; the script itself has not been executed.
- Updated docs/mobile-ux-redesign-2026-10-30.md from preparation to approved implementation, including current unified Reface descriptions and the one-command verification handoff. New UI strings and matching generated declarations/English implementations were prepared manually; official generation/formatting remain user-run tasks.
- Actual verification was limited to read-only source consistency: localization references/declarations/implementations, actual relative import targets, local Material icon names, verification-script paths, and balanced string/delimiter inspection across 51 Dart files. No missing actual import, icon, localization declaration/implementation or unbalanced source structure remained in that inspection. This is not Dart type analysis, compilation, widget rendering or test execution. Device/large-text/keyboard/dark-theme acceptance and Flutter validation remain outstanding. Previously recorded unrelated Restyle failures remain recorded and were not rerun.
- No backend/API/schema/model/dependency changes, real-library/media/queue/checkpoint access, user data mutation, screen-capture-policy changes, device installation or server start/stop occurred. No APK was built for this redesign batch; the earlier unified-Reface artifact is historical and does not contain these later source changes.

## Persistent face deletion, hiding and merging — 2026-10-30

- User reported that deleted/hidden faces return, clarified that “mirror” meant **Merge people**, and explicitly requested fixing/persisting the actions rather than removing their controls. Work covers the mobile library and the corresponding desktop scanner/grouping store. Later the user said **“لا خلاص متنزلش”**: no download/installation or new mobile release is authorized. Changes remain **source only**; no APK was built or installed for this section. The earlier Reface APK does not include these new fixes.
- Root causes: hard deletion removed the detection with no rescan exclusion; hidden faces were excluded from review clusters but still participated in automatic matching/group creation; delayed plans/cached suggestions did not consistently recheck manual rejections/distinct-person decisions. Deleting a person also left their unsorted faces eligible to immediately recreate a profile.
- Mobile schema v7 adds `face_suppressions`, retaining deletion provenance and comparison embeddings, with no crop. Deletion records the original asset and every known linked occurrence before deleting rows/crops/index entries in the same transaction. Scan storage checks those decisions inside its write transaction and before matching can consume another person's detection. Original occurrences/known copies stay excluded, including video frames and removal/reimport of a media row; this is not a blanket identity ban for unrelated new photos. Deleted faces are not repurposed as weak body evidence. The desktop stores the corresponding suppression metadata atomically with the remaining faces in `faces.json`, and consults it on rescan. Actual corrections are created only when a user invokes the actions; no live records were migrated or edited here.
- Hiding now applies in both apply/review modes, to matching as well as clustering. The phone sends hidden IDs on every grouping request; stale apply/review plans recheck current hidden flags and face/body rejections. Review lists and counts respect those decisions and distinct-person pairs. Explicit manual assignment clears the hidden flag. Deleting a profile keeps its faces available for manual assignment while excluding automatic recreation; its confirmation text reflects this behavior.
- Merging preserves migrated rejections/distinct decisions, removes obsolete/rejected cached matches and newly forbidden duplicate cards, and keeps body assignments consistent. A delayed suggestion cannot undo those decisions or resurrect the removed source profile. Backup export/restore now includes suppression records. A reproducible Windows restore failure was fixed with a bounded retry for temporary access/sharing errors while renaming the restored crop folder.
- Actual verification: **127 affected Flutter tests passed**, including seven new correction regressions, v1–v6 database upgrades, UI deletion/merge/review flows, scan deduplication, grouping rounds and backup round trips. Static analysis of 12 affected files: **no issues**. **50 Python checks passed**: 6 new correction regressions, 11 shared-grouping cases and 33 gallery/scanner cases. Final Python runs used an isolated cwd because importing `database.py` creates a default store; all test data was synthetic and temporary. One old review-oracle expectation was updated to the intentional persistent-hide policy; merge assertions now ensure rejected matches are removed rather than recycled.
- A locked original test DLL required an isolated source copy at `mobile/build/face-corrections-check/mobile`; no other process was stopped. That copy uses the same affected application sources. Logs: `mobile/build/face-corrections-{flutter-final-tests,backup-tests,python-tests,grouping-tests,gallery-tests,analyze,codegen}.log`. Database/locale code was regenerated using installed tools, and existing concurrent workspace/UI changes were preserved. No real-media/GPU run, phone operation, server restart or deployment was performed for these changes.

## Mobile server no longer stays down after a crash — 2026-10-30

- User report: the mobile server "sometimes disconnects by itself". `logs/mobile_api_exit.json` recorded exit **0xC0000005** (access violation) on 2026-10-27; `logs/mobile_api.log` shows the fatal fault on an AnyIO request thread inside `grouping_core.plan_request -> person_linking._average_linkage -> import sklearn -> pandas -> pyarrow` (a native extension being loaded), in a process that already had the CUDA/onnxruntime Reface models loaded. 24 earlier fault dumps in the same thread, during the same import, preceded the fatal one. A Python handler cannot catch this, so the server just disappeared.
- Fix 1 (cause): `mobile_api/__main__.py` imports `sklearn.cluster` and `scipy.optimize` on the main thread at startup, before any GPU library, instead of lazily on a request thread. This is a strong hypothesis, not a proven root cause (the exact faulting DLL is not identified). The venv bundles four msvcp140 copies (numpy/pandas 14.40, pyarrow 14.44, sklearn 14.51, system 14.51).
- Fix 2 (safety net): `mobile_api/supervisor.py`. `python -m mobile_api` (dashboard Start and `run_mobile_api.bat`) is now a stdlib-only parent that runs the real server as a child and restarts it after any non-clean exit, with backoff 2/5/10/30/60 s that resets after 5 min of healthy uptime. Clean exits (Stop/Ctrl+C) are never restarted. Neither is a first launch that never came up (port clash, broken env), so that failure is still reported. "Came up" means the child wrote `control.json` with its per-launch token (`launch` field). Restarts reuse devices.json/tls, so phones reconnect. Work running inside the crashed process is lost, the scratch workspace is wiped as on any start, and helper workers exit on stdin EOF. The admin status adds `recovery` (restart count, last code/time), which the Mobile Devices page shows as a caption. Stop is now enabled while the server is starting. If no server answers (between a crash and its restart), the controller terminates the supervisor it started and removes the stale control file, and that is recorded as a requested stop. `--check-models`/`--help` and child processes (`AG_MOBILE_API_CHILD=1`) bypass supervision.
- Known limit: if a dashboard-started supervisor is killed mid-restart, a just-spawned child can outlive it. The venv launcher's job allows breakaway, so the child is not killed with it.
- New `test_mobile_supervisor.py` (fake children, CPU only): clean stop, Ctrl+C code, never-came-up failure, crash restart with recovery env/`--no-browser`/fresh token, crash-loop backoff, backoff reset, stale control file, entry-point selection, stdlib-only imports, control-file token, controller Stop fallback. **Only `py_compile` was run on the changed files. No test, server start/restart or GPU run was executed** (standing user rule). The user should run `test_mobile_supervisor.py`, `test_mobile_dashboard.py` (real lifecycle through the supervisor), `test_mobile_stateless.py` and `test_mobile_connectivity.py`, then restart the mobile server from the dashboard so the new launcher is used.
