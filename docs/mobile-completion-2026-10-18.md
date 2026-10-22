# Mobile completion — 2026-10-18

> Later follow-up: remaining SDXL FP16 weights were installed and hash-verified
> on October 19; the application's offline loader passed on CPU. GPU/phone
> refinement remains untested. Read [the current handoff](ANTIGRAVITY_HANDOFF.md)
> before continuing; historical missing-SDXL statements below describe October 18.

The user requested completion of work that does not require phone acceptance,
with all checks deferred until the implementation is finished. No model or
dependency downloads are authorized unless the user separately selects them.

## Implemented

- Password-encrypted backups by default. The existing ZIP service produces a
  private temporary archive; the Android JCA bridge encrypts it before sharing.
  Restore detects encrypted files, prompts for the password and verifies the
  complete envelope before the database is touched. Old ZIP backups remain
  readable; plaintext export is an explicit option. Decrypted restore scratch
  files and temporary plaintext export archives are removed in `finally`.
- Named source-face identity sets in schema v6. Sets contain references to
  1–100 real faces from one person and embedding model. Selection is checked
  against current records when saved, loaded and submitted. Person merges move
  the sets; deleting people/faces cascades; backups include the sets.
- A durable local history of the latest 100 changes per Studio job, deduplicated
  across polls/SSE and excluded from backups. Details show the server message,
  labelled training metadata and an approximate remaining time only when real
  step counts and measured seconds per step are available. The server's training
  parser speed is mapped to the correct wire field.
- Basic Restyle readiness is independent of optional SDXL refinement. The
  optional `engines.restyle_refine` capability controls the switch; the API
  refuses a refinement request when only the base engine is ready. Legacy
  servers without the field retain their existing behaviour.
- Production signing configuration replaces the debug signing fallback.
  `mobile/tools/setup_release_signing.ps1` creates a local RSA-3072 signing key
  and random password without printing it. The keystore and properties are
  Git-ignored and restricted to the current Windows user. It refuses to replace
  existing signing files. Release tasks fail clearly if signing is missing.
- A repeatable 100,000-face index benchmark for host memory/load/search timings.
  This is not a replacement for phone startup, scrolling, battery or thermal
  acceptance.

## Backup envelope v2

The inner ZIP format remains v1, with its normal schema version. The encrypted
outer envelope begins with `AGBAK02\n`. Its 40-byte header contains big-endian
iteration count (600,000), chunk size (1,048,576), 16 random salt bytes and an
8-byte random nonce prefix. PBKDF2-HMAC-SHA256 derives a 256-bit key. Each record
contains a big-endian plaintext length followed by AES-256-GCM ciphertext and
a 128-bit tag. Its 96-bit nonce is the prefix plus the 32-bit record index;
additional authenticated data is the complete header, index and length.
An authenticated empty record is mandatory at EOF, and trailing bytes are
rejected. Header parameters and record sizes are bounded; files are limited to
64 GiB. The implementation uses bounded buffers, writes a private temporary
file and publishes it only after all tags and EOF have been checked.
Passwords are never persisted, sent to the PC or included in a backup.

## Signing and installation

Back up `mobile/android/upload-keystore.jks` and `mobile/android/key.properties`
together in secure storage. Both are local secrets and must stay out of Git.
They are required to issue updates signed by the same identity. A release
signed with this key cannot be installed as an update over an app signed with
the public debug key. Export and verify a library backup before any intentional
uninstall/reinstall; this task does not uninstall, install or replace the phone
app.

## Model download inventory awaiting the user's selection

Approximate decimal transfer sizes, selecting one weight format per component:

| Model | Required files | Transfer |
|---|---|---:|
| RealisticVision V5.1 inpainting | UNet safetensors + text encoder + VAE | 2.13 GB |
| ControlNet SD1.5 OpenPose | Full-precision safetensors + config, as loaded by the current engine | 1.45 GB |
| OpenPose face annotator | `facenet.pth`; body and hand files already exist | 154 MB |
| SDXL inpainting, optional | FP16 UNet, both text encoders, VAE, tokenizer/config files | 6.94 GB |

Base total is approximately 3.74 GB; including SDXL approximately 10.68 GB.
Repository totals include duplicate formats and precision variants; downloading
whole repositories would transfer more. Metadata was inspected without fetching
weights. IP-Adapter and its image encoder already exist locally.

Sources: [RealisticVision components](https://huggingface.co/Uminosachi/realisticVisionV51_v51VAE-inpainting/tree/main),
[ControlNet](https://huggingface.co/lllyasviel/control_v11p_sd15_openpose/tree/main),
[facenet](https://huggingface.co/lllyasviel/Annotators/blob/main/facenet.pth),
[SDXL components](https://huggingface.co/diffusers/stable-diffusion-xl-1.0-inpainting-0.1/tree/main).

## Validation

All checks were run after implementation, as requested:

- Flutter: 370 tests passed, including v5/v6 migrations, identity-set backup and
  merge semantics, password validation, bounded history and ETA validation.
- Dart analyzer: no issues across the app, tests and benchmark tool.
- Server: 44 unittest cases passed, API contract script 28/28, statelessness
  script 5/5; OpenAPI schemas and all 29 fixtures passed validation.
- Native backup cipher: 16 local JDK cases passed with a 64 MiB heap, including
  empty/chunk-boundary/multi-chunk inputs, wrong password, changed header/tag,
  truncation, appended data, randomized encryption and partial-file cleanup.
  Python cryptography independently authenticated and decrypted all four native
  round-trip vectors.
- Host index benchmark: 100,000 faces / 512 dimensions loaded in 2,406 ms;
  median query 66.024 ms, max 84.583 ms; RSS increase 235.76 MiB and process peak
  RSS 495.46 MiB. These are host Dart VM measurements, not Android results.
- Debug and signed Release APKs built successfully with Gradle `--offline`,
  including all Release vital-lint checks. The video-player plugin's old AndroidX
  collection 1.2.0 request was aligned to the compatible cached 1.4.2 version;
  no dependency downloads or lint exclusions were needed.
- Release APK: `mobile/build/app/outputs/flutter-apk/app-release.apk`,
  98,903,598 bytes (98.90 decimal MB). Debug APK: the same directory's
  `app-debug.apk`, 225,520,620 bytes.
- `apksigner verify --verbose --print-certs` passed for the Release APK:
  APK signature scheme v2, RSA-3072, `CN=Antigravity Mobile`.
  Certificate SHA-256:
  `d6bd247e4861ce5e045ccc56c8741167fa3a906807ba4368b1f3bac4cc9e4928`.
- After the subsequently authorized base installation, local readiness reports
  Reface/LoRA and basic Restyle available. Only optional SDXL refinement remains
  unavailable.

Validation logs are under `mobile/build/completion-*.log` (Git-ignored).
The complete 370-test Flutter suite passed again after the final backup-share
cancellation/cleanup adjustment. Cancelling the share sheet does not mark a
backup as saved, and temporary-file cleanup failure cannot leave scan/Studio
maintenance suspended. No phone app was installed, replaced or uninstalled.

Phone-only acceptance remains: locked-screen/task-removal recovery, notifications,
credential prompts, gallery export, actual share/file-picker integrations,
camera QR, long-video/network interruption and performance on the target device.
Per-person video tracking and step-level training checkpoints remain separate
engine work; the current video swap applies to all faces and training resumes
from completed epochs. Arabic translation and iOS remain outside the agreed
English/Android scope.


## Authorized base-model installation

The user subsequently selected **base models only, approximately 3.74 GB**.
That authorization excludes SDXL, package installations and Python/CUDA changes.
Published Hugging Face metadata resolves the missing transfer to 3,731,511,233
bytes, including the small ControlNet configuration file. Existing configuration
files and the local body/hand OpenPose tensors matched their published hashes.
The body/hand files are reused locally instead of downloaded again.

`mobile/tools/download_restyle_base.py` uses an explicit file allow-list,
pinned repository revisions, resumable private partial files and published
SHA-256 checks for weights (Git blob checks for small configuration files).
It never downloads whole repositories or the optional SDXL model. Up to three
transfers run concurrently; incomplete downloads remain resumable. The receipt
is written to `the app/models/undress/base-download-manifest.json` only after
all selected files verify. Its network-byte count covers the final downloader
invocation; previously saved partials/verified files are reused without transfer.

`mobile/tools/check_restyle_base.py` ran with the existing
`venv_ai` and Hugging Face/Transformers explicitly offline. Its synthetic input
checks model loading, clothes parsing, OpenPose, IP-Adapter wiring and two GPU
diffusion steps without reading or changing personal photos. It is a runtime
smoke test, not an image-quality or phone-acceptance claim.

Installation is complete. All selected files matched their published hashes;
the three repository revisions are pinned in the local receipt. The selected
missing files total 3,731,511,233 bytes (3.732 decimal GB). The final invocation
transferred 3,452,860,513 bytes; 278,650,720 bytes had already been saved and were
reused after resuming. Existing OpenPose body and hand weights were linked
locally, with matching hashes. No SDXL weights, packages or Python/CUDA changes
were downloaded or installed.

Final readiness output: `undress: true`, `restyle_refine: false`; the only
remaining missing model is `diffusers/stable-diffusion-xl-1.0-inpainting-0.1`.
The offline runtime test passed on **NVIDIA GeForce RTX 4050 Laptop GPU**:
clothes parser execution, restricted weights-only checks of body/hand/face
PyTorch files, OpenPose execution, IP-Adapter loading and two genuine diffusion
steps. Synthetic outputs are under `mobile/build/restyle-base-check/`.
This smoke test does not assess photographic quality or the complete phone flow.

A broader existing CPU suite (`the app/test_undress.py`) was also run offline:
**58/65 passed**. The following seven tests fail in existing engine/test code
that was not modified during this work:

- `test_harmonize_moves_generated_skin_toward_original_skin`
- `test_protection_preview_tints_background_keep_and_torso_restyle`
- `test_garment_mask_inpaints_upper_ruffles_labeled_as_face`
- `test_garment_mask_keeps_skin_cleavage_in_the_torso`
- `test_garment_mask_inpaints_getty_on_the_dress_not_the_backdrop`
- `test_restyle_body_mask_covers_the_torso_not_the_old_dress_silhouette`
- `test_refine_mask_edges_snaps_a_blocky_mask_to_the_real_edge`

Several assertions conflict with intentional existing implementation comments
(removal of guided edge snapping, skin-color correction and the red preview
rectangle). Others concern masking boundaries. Resolving them requires review
of intended image behaviour; this download task does not silently restore old
behaviour or change assertions to claim a passing suite. They remain outstanding.

Logs: `mobile/build/restyle-base-download.log`, `restyle-base-gpu-check.log`
and `restyle-base-cpu-tests.log`. No personal photos or phone installation were
used for these checks.

## Subsequent real-device pass

The user then connected the Samsung A72. See
[Android device acceptance](mobile-device-acceptance-2026-10-18.md) for the
in-place Debug update, preserved library, actual background/connection tests,
native integrations and complete synthetic phone-to-GPU Restyle round trip.
The pass fixed progress/cancellation while hashing large videos. The updated
Debug APK is 225,517,671 bytes; signed Release is 98,903,598 bytes. Both rebuilt
offline, the analyzer is clean and all 373 Flutter tests pass. The Release
was not installed over the existing differently signed Debug application.
