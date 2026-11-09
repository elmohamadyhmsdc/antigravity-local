# Protected photo editor — 2026-11-09

Implemented on the PC Mobile API and the current native Android app at `D:/test/face gallary`. Flutter and video editing are unchanged. Entry: open a still photo, overflow menu → **Edit photo / تعديل الصورة**.

## Delivered behavior

- Manual brush, rectangle and eraser selection, brush size, undo/redo/clear, pan and pinch zoom. Selection coordinates follow the EXIF-upright image and ignore letterboxing. Arabic and English resources, existing Compose theme and navigation shell, minimum 48dp controls.
- **Remove** reconstructs a background with Big-LaMa. **Replace** uses a description and the existing local SD1.5 inpainting checkpoint. Long descriptions that exceed the actual text encoder budget fail with an actionable message instead of silently losing the end of the instructions.
- Selection work stays on the phone; generation uses its paired PC over the existing pinned-TLS LAN API. An offline paired computer can receive a durable queued request on reconnect. No media is sent to an external service.
- The native request snapshots the original file and preview-resolution PNG mask, records `client_job_id`, and joins the existing serial WorkManager/Studio queue. A mask at preview resolution is mapped back to native upright coordinates on the PC, avoiding a full-resolution Android bitmap allocation.
- Progress, background continuation, cancellation, paused-job resumption, verified result download/import before ACK, and before/after preview. Activity and Studio Results use localized photo-editor labels. The original snapshot is resolved by the **image blob slot**, never the unordered first input (which could be the mask).
- Save a copy streams the verified PNG into `Pictures/Face Gallery/Edited` through MediaStore pending publication. Originals are never overwritten. The result retains original upright dimensions, alpha outside the selection and the input ICC profile. Every unselected decoded RGBA pixel must remain byte-identical before publication.

## Scope and safeguards

This is a nonsexual background/object editor. It does not remove clothing, retrieve nude references, edit protected people, or create sexual imagery. The PC independently runs CPU body, face and sensitive-region detection and rejects selection overlap, including a padding margin. Missing/erroring protection models fail closed. The client cannot supply protection boxes, disable checks or choose arbitrary worker/model/output paths.

Both engines run in an isolated offline subprocess with the output safety checker enabled. A flagged or unchecked output is discarded; the checker can also reject benign images. A tan synthetic removal test was rejected and no image was published. Cancellation kills and reaps the subprocess; inference has a ten-minute deadline. Selected area is limited to 60%, still photos to 40 MP. This is manual selection, not a new automatic item segmentation feature. Generative instructions guide the appearance; exact semantic compliance and quality on arbitrary photos are not guaranteed.

## Local assets

No packages, Python/CUDA settings or existing base model weights were changed.

- Existing local base: `the app/models/undress/Uminosachi--realisticVisionV51_v51VAE-inpainting` (used directly by a separate protected worker, not by the legacy clothing-edit pipeline).
- CompVis output checker: `the app/models/photo_edit/safety_checker`, pinned revision `9e7bda5882659ee2f75d255807a9f2f7feb61fc3`; weights SHA256 `11cfe53105625af8c00faac32a430626641cce686454f3c39d837f14397d858b`. [Publisher artifact](https://huggingface.co/CompVis/stable-diffusion-safety-checker/blob/9e7bda5882659ee2f75d255807a9f2f7feb61fc3/model.safetensors).
- Big-LaMa: `the app/models/photo_edit/big-lama.pt`, FASHN artifact revision `da55aaf971ce271b42eddca79831e0f646c7711e`, SHA256 `7ba7aa7ac37a4d41fdbbeba3a2af7ead18058552997e3a3cd1a3b2210c9e6b4c`. The worker verifies this hash before loading TorchScript. [Pinned artifact](https://huggingface.co/fashn-ai/LaMa/blob/da55aaf971ce271b42eddca79831e0f646c7711e/big-lama.pt), [LaMa research/code](https://github.com/advimman/lama), [IOPaint inference adapter reference](https://github.com/Sanster/IOPaint/blob/main/iopaint/model/lama.py). The FASHN serialization differs from IOPaint's original release; it is pinned to its own SHA256, not represented as matching IOPaint's original MD5. GitHub downloads failed certificate verification; TLS verification was never disabled and system trust settings were unchanged.

Setup helpers: `download_photo_edit_safety.py` and `download_photo_edit_removal.py`. Assets are installed and excluded from Git like the existing models. Readiness is exposed as `engines.photo_edit`.

## Verification actually executed

| Check | Result |
|---|---|
| Photo editor + shared Studio unittest suites | 32 passed (18 photo-editor, 14 existing Studio) |
| Standalone API contract runner | 32/32 passed after adding `photo_edit` to capability goldens |
| Standalone stateless server runner | 5/5 passed |
| Contract validation | All 72 component schemas, 74 distinct references and 61 fixtures passed |
| Native full `:app:testDebugUnitTest :app:assembleDebug` | 194 suites, 734 tests, zero failures/errors/skips; APK built |
| Final focused native suite after adding two cancellation tests | 8/8 passed, including executor/tracker POST stop before DELETE ACK |
| Python syntax and CRLF-aware whitespace check | Passed |

The native build used existing offline dependencies with incremental compilation disabled only for that invocation after a stale KAPT cache error. The first compile also caught two missing resource labels and an implicit Compose scope error; both were corrected. Existing unrelated Gradle/Kotlin warnings remain. Native changes were applied from a reviewable staged patch only after SHA256 checks against all touched live files. Existing dirty source and data were preserved; no commit/reset/clean operation was used.

Actual local-model tests used an artificial 960×640 still life with a red object, a blue wall/table and a 65,311-pixel selection, seed 123. Mandatory person detection and output checking ran on both paths:

| Operation | Elapsed including startup | Changed selected pixels | All unselected pixels |
|---|---:|---:|---|
| Remove (LaMa) | 46.75 s | 64,400 | Exactly equal |
| Replace (26 diffusion steps, blue ceramic vase) | 56.35 s | 65,310 | Exactly equal |

Both outputs were visually inspected. Removal reconstructed the wall/table and removed the red object; replacement generated a blue ceramic vase. Earlier diffusion-only removal experiments invented scenery/texture and were rejected in favor of the dedicated removal engine. These are execution and synthetic quality checks, not a real-library benchmark. Results/reports: `the app/build/photo-edit-2026-11-09/{remove,replace}/`. The optional reproducible harness is `test_photo_edit_gpu.py --operation remove|replace`.

Native APK: `D:/test/face gallary/app/build/outputs/apk/debug/app-debug.apk`. No APK was installed, no phone library or live jobs were changed, and the live PC server was not restarted. Install the APK and reload the PC Mobile API process to expose the new route/capability. Actual device gestures, MediaStore save on the user's phone, real-photo visual acceptance, and cancellation during actual CUDA inference remain unmeasured; geometry, masks, ownership, lifecycle, rejection, immutable pixels and cancellation request ordering have automated coverage. Existing unrelated failures in earlier handoff entries were not rerun or reclassified.
