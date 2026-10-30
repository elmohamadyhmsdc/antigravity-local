# Antigravity Mobile

Flutter (Android) phone client for the Antigravity Local GPU server. **All user data lives on the phone**
(encrypted SQLite - SQLCipher - with the key in the Android Keystore); the Windows PC only computes.

Plan: [`docs/plans/2026-10-11-mobile-app-plan.md`](../docs/plans/2026-10-11-mobile-app-plan.md).
Contract with the PC: [`the app/mobile_api/contract/openapi.yaml`](../the%20app/mobile_api/contract/openapi.yaml)
(golden fixtures in `contract/fixtures/` are parsed by both the server tests and `test/data/dto_test.dart`).

## Status

Current continuation guide: [Antigravity handoff](../docs/ANTIGRAVITY_HANDOFF.md)
(2026-10-19). Read before changes; it supersedes historical status paragraphs
below. All configured shared weights are installed, including SDXL FP16. SDXL
GPU inference/phone refinement still require acceptance. Latest recorded Flutter
run: 373 tests passed. No dependency or Python/CUDA installation was performed.

| Phase | State |
|---|---|
| P0 Foundations | done |
| P1 Server core + pairing | done - S01 Welcome/Pair (QR, tapped link, typed address + fingerprint check), S02 Permissions, S03 Home (PC status chip, library stats from the local DB), "Detect faces in a photo" (the end-to-end check against the PC) |
| P2 Library & People | built - photo scan with foreground service, People / Person / Face picker / Review / Merge, photo viewer with boxes, Settings (grouping strictness, quality gate), backup & restore; awaiting verification on the phone |
| P3 Videos & bodies | implemented - resumable video uploads, device-owned analysis jobs, frame checkpoints, local video playback with sampled detection boxes, photo/video filters, body-only person sightings, offline Insights; automated checks pass, real-phone acceptance still required |
| P4 Reface | implemented - photo face selection, V3/V2/available DFM, video trim and checkpoints, durable uploads, Jobs with SSE/polling, private Results with comparison, favourites, share and explicit gallery export |
| P5 Clothes restyle | implemented - protected face, prompts, references, strength/seed/refine; base and SDXL weights installed and hash-verified; base CUDA smoke and phone round trip passed; SDXL offline loading passed, GPU/phone refinement untested |
| P6 Character LoRA | implemented - identity-matched photo/video datasets, caption/include editor, zip export, epoch-resumable training, safetensors import, portrait generation and LoRA identity augmentation for Reface |
| P7 Hardening | app lock using phone credentials, FLAG_SECURE viewers, completion notifications, storage cleanup and expanded backup implemented; release signing configured; device performance/acceptance pending |

## Layout

```
lib/
  app.dart main.dart providers.dart      router/session wiring, start-up (opens the encrypted DB or shows an error screen)
  core/                                  router (with the agmobile:// deep link), theme
  data/db/                               Drift schema (tables.dart), migrations (app_database.dart), SQLCipher opening
  data/api/                              pinned Dio client, VideoApi + StudioApi (resumable blobs, jobs and SSE), DTOs, pairing payload, LAN-only host check
  data/secrets/ data/repositories/       Keystore wrapper, which PC we are paired with (token in Keystore, rest in the DB)
  data/platform/                         permissions / photo picker / device name behind small interfaces
  data/{files,index,media}/              FileStore (relative crop paths), EmbeddingIndex (isolate), MediaStore access (photo_manager)
  data/repositories/                     library queue, people + manual corrections, review plan, media queries, typed settings
  domain/{scan,grouping,backup,jobs}/    scan, grouping, .agbackup, persistent Studio tracker and verified artifact import
  features/{onboarding,home,analyze}/    screens S01-S03 and the detection check
  features/{library,media,people,review,merge,scan,settings,backup,insights}/   S04-S11, S23, S24, S26
  features/{studio,reface,restyle,lora,jobs,results,privacy,storage}/          Studio and private artifact workflows
  l10n/app_en.arb                        all user-visible strings
```

## Commands

```
flutter pub get
flutter analyze
flutter test                              # DB (SQLCipher on the host), pinned HTTPS against a local server, DTOs vs fixtures, widgets
dart run build_runner build               # after editing lib/data/db/tables.dart (app_database.g.dart is committed)
flutter gen-l10n                          # after editing lib/l10n/app_en.arb
flutter build apk --debug                 # needs the Android SDK licences accepted
```

## Trying it against the PC

1. PC: open the regular dashboard at `http://localhost:8501/?page=mobile` → **Mobile Devices** → **Start mobile server**. The page shows the QR, one-time code, address and certificate fingerprint. The standalone `the app/run_mobile_api.bat` and `http://127.0.0.1:8444/pair` remain available.
2. Phone on the same Wi-Fi: Scan QR code (or Enter address manually and compare the fingerprint shown with the PC's page).
3. Home shows the PC as connected; "Detect faces in a photo" sends one downscaled photo and draws what the PC found.
4. Sources: choose albums, enable **Scan videos too**, select a sampling interval and start scanning. Videos use the original file (server upload limit: 2 GB by default); image analysis still sends downscaled JPEGs.
5. Library: use **Photos / Videos**, open a video, then tap a timestamp to pause at a detected frame. Face/body boxes appear only within 150 ms of their sampled frame. Home → **Library insights** works without the PC.

The dashboard's **Mobile Devices** page refreshes every 3 seconds and lists each paired phone, pairing time, last activity and active job count. **Rename** changes its PC-side label. **Disconnect** revokes its token, invalidates the current pairing code and pauses that phone's jobs; **Disconnect all phones** applies this to every device. **Stop server** shuts down mobile processing while preserving pairing records and the certificate. “Active recently” means a request within the last 2 minutes, not a continuously open socket.

Device administration is available from a browser on this PC via `localhost`. The dashboard talks to the separate loopback control listener using an ephemeral local secret; these controls are never served by the phone-facing HTTPS API. Starting and pairing need no Internet download, package installation or manual terminal command.

### Background work and scan server recovery

For phone hotspots, PC hotspots, changing DHCP addresses, VPN/guest isolation and USB, see [Mobile connectivity](../docs/mobile-connectivity.md). The PC refreshes adapter addresses and its QR, and a paired phone can rediscover and verify the same PC without discarding credentials. **Connection help** is reachable before pairing and from Settings/the offline banner. Local discovery uses UDP 8445; certificate pinning and server identity are checked before credentials are used. Active client objects follow verified endpoint changes, and reconnect cannot override a user pause or library maintenance.

Permissions and Settings → **Background work** explain and request Android notifications and a battery-optimization exemption. The first user-started scan or Studio submission offers this setup once; declining continues the work. The screen refreshes permission/service status when returning from Android settings. A shared foreground service holds wake/Wi-Fi locks and displays scan/Studio progress only while work is active. Finishing one workload cannot stop another workload's notification. The main Flutter engine survives Activity removal, and a small service guard checks that real phone work still exists before retaining a restarted notification.

Force stop, shutdown, vendor restrictions and Android's data-sync time limit can still interrupt work. Reopening restores the saved queue. Long-duration screen-lock/task-removal acceptance on a phone remains required; this pass does not install or replace the user's running phone build. Validation: zero Dart analyzer issues, **348 Flutter tests passed**, including service start/stop races, denied-service recovery, permission status refresh and the optional first-work prompt.

Scan inference now runs in a disposable local process, with bounded JSON/pixel pipe messages and no temporary photo files or executable serialization. A native inference failure returns a retryable error while the HTTPS API and device controls remain online; the next request recreates the worker. Shutdown/unload releases it. Existing local face/body weights are required; the mobile scan path never downloads them. The dashboard exposes unexpected server termination and its diagnostic log. A real GPU face/body/pose scan at 512, 1600 and 2560 pixels and process-failure recovery are covered by the scan acceptance scripts.

### Video checkpoints

Uploads use 4 MB chunks and the PC's authoritative `Upload-Offset`. A stable client job ID is saved before submission. Video jobs restore their device-owned, expiring checkpoints after a PC restart; missing/expired jobs restart from the phone's last committed frame. New servers deliver bounded SHA-256-verified NDJSON batches during analysis. Each frame commits with its media checkpoint, and the batch cursor advances only after all its frames commit, so interrupted delivery can safely replay. Older servers retain the verified final-file download. The phone ACKs/purges the PC job only after local storage succeeds.

Automatic sampling is enabled by default: `clamp(duration_seconds / 480, 0.5, 10)` seconds, rounded to whole video frames. For example, short clips use about 0.5 seconds and a 40-minute video uses about 5 seconds. The server saves the actual sampling grid and preserves it on resume. Manual intervals remain available when automatic sampling is switched off. While scanning, one next photo may be prepared ahead; GPU analysis stays serial. Lightweight face grouping runs after 100 new faces or 200 files; body/review grouping runs on completion or pause.

Video scan reuses the existing frame/timestamp/checkpoint columns. Schema v6 stores Studio Jobs, Results, Datasets, DatasetItems, LoRAs, reusable identity sets and bounded local job activity history, including per-input recovery and model-stamped generated identities. Ephemeral video job references live under private `video.job.*` settings and never enter backups. Scan preferences do travel in backups. Studio progress uses SSE with polling as a fallback.

Restoring a backup also clears stale video job references on the destination phone. An older restored checkpoint therefore starts a fresh PC job rather than skipping ahead to a newer job's starting point.

Real-phone acceptance: scan a short video, pause/resume, close/reopen during upload and import, restart the PC while a job is active, then check playback, sampled boxes, grouping and backup/restore. GPU execution and actual Android playback still need this device check.

USB alternative without any firewall rule: `adb reverse tcp:8443 tcp:8443`, start the server with `--bind 127.0.0.1`,
pair with address `127.0.0.1`. The Android emulator reaches the PC at `10.0.2.2`.

## Security notes

- Certificate pinning: the client trusts exactly one certificate (SHA-256 from the QR / confirmed by the user); a wrong pin aborts the TLS handshake before the bearer token is sent.
- Pairing only accepts private-network addresses (192.168.x.x, 10.x, 172.16-31.x, link-local, `.local`, loopback).
- A tapped `agmobile://pair` link never pairs silently; it shows the address and asks.
- `allowBackup=false` plus data-extraction rules exclude everything from Android backups. Cleartext traffic is disabled.
- Settings → App lock uses the phone's PIN/pattern/password and relocks when the app backgrounds. Media/result viewers block screenshots. The database is SQLCipher encrypted; result files remain in private app storage until explicitly shared or saved.
- Backups include saved results, datasets, captions and models, and omit active jobs, scratch inputs and PC credentials. Backup/restore waits for scan and Studio writes to settle. Backup exports are password-encrypted by default, with an explicit unencrypted option and compatibility with older ZIP backups. Passwords are never stored or sent to the PC.

## Studio verification and remaining acceptance

On 2026-10-14: zero analyzer issues and 343 Flutter tests passed. CPU suites cover Studio lifecycle, artifacts, video jobs, API contract and statelessness; fixtures validate against OpenAPI. Real GPU API round trips passed for V3 Reface, identity-matched dataset building/captioning, a tiny one-epoch LoRA train, and generation with an existing LoRA. Each round trip verified the returned file before ACK/purge. A tiny training run verifies the integration, not production identity quality.

Both installed secondary environments have CUDA. Base Restyle models were installed and hash-verified on 2026-10-18; an offline CUDA smoke test passed with the local parser, OpenPose and IP-Adapter. On 2026-10-19, the remaining SDXL FP16 files (6.941 GB) were downloaded with separate user authorization, hash-verified and loaded offline through the application loader on CPU. Readiness reports `restyle_refine: true` and no missing Restyle models. SDXL GPU inference and phone refinement are not yet verified. No package or Python/CUDA changes were made. See [the current installation report](../docs/local-model-installation-2026-10-19.md). Run the read-only model probe from `the app/`, as shown in the handoff.

Still requiring phone acceptance: Android export/notifications/device credential UI, long-video interruption recovery and foreground/background behaviour. Video Reface currently swaps all detected faces; photo targets support individual selection. LoRA training resumes at the last saved epoch, not an arbitrary step. Named identity sets and password-encrypted backups are implemented. Per-person video tracking remains future engine work.

Release signing uses a local private RSA key, with no debug-key fallback. Keep `android/upload-keystore.jks` and `android/key.properties` backed up together and out of Git. Device acceptance and performance measurements remain required before distribution. See [the completion report](../docs/mobile-completion-2026-10-18.md) for implementation and validation details.

## October 18 completion

Backup exports now prompt for a password by default; encrypted restores authenticate before changing the library, and older unencrypted archives still work. Reface source faces can be saved as named identity sets. Studio jobs retain the latest 100 activity changes locally and show approximate training time remaining when measured speed is available. The optional SDXL refinement stage is independent of basic Restyle readiness. See [completion and validation](../docs/mobile-completion-2026-10-18.md).

Validation on 2026-10-18: 370 Flutter tests, 77 server regression cases, valid OpenAPI fixtures, zero analyzer issues, 16 native backup-cipher cases plus independent Python verification, and offline Debug/Release APK builds. Release signature verification passed with the local RSA-3072 key. The signed APK is `build/app/outputs/flutter-apk/app-release.apk` (98.90 MB); no phone installation was performed.

Base-model follow-up on 2026-10-18: 3,731,511,233 bytes of missing files installed, existing OpenPose body/hand files reused, all published hashes matched, and a two-step synthetic GPU inference passed on the RTX 4050 Laptop GPU. A separate legacy Restyle CPU suite passed 58/65 tests; seven assertions about masks, previews, skin matching and edge alignment fail in unchanged existing engine/test code. They are recorded in the completion report and are not represented as passing. Phone acceptance remains deferred.

Real-phone follow-up on 2026-10-18: the Samsung A72 / Android 14 Debug app was updated in place with its existing library preserved. USB endpoint recovery, screen-off/task-removal upload continuation, interrupted-upload recovery, encrypted export/cancelled sharing, private-file crypto checks, video playback/seeking, FLAG_SECURE, device-credential app lock, gallery export and a complete synthetic Restyle job passed. A 2 GB video exposed misleading upload text and slow Pause during hashing; preparation now reports progress and cancels cooperatively (283 ms on the device fixture). All 373 Flutter tests pass and the analyzer reports no issues. See [device acceptance and its remaining limits](../docs/mobile-device-acceptance-2026-10-18.md).
