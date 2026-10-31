# Detailed mobile video scan progress — 1.2.1

Long videos now show their actual operation instead of only “Scanning”. The
progress card on Home, Sources and the scrolling progress sheet includes:

- Preparation, resumable upload, PC waiting/analysis, result download,
  verification, local import and finalization, with a four-step overview.
- Source filename, size, resolution and duration; separate percentages for the
  current stage and completed library items.
- Bytes read/sent/received, measured average transfer speed, elapsed video/stage
  time and estimated remaining time for the current stage when measurements are
  available. Waiting, verification and finalization do not invent percentages or
  completion times. Transfer measurements exclude previously uploaded bytes.
- Actual analyzed video position, processed/total sampled positions, sampling
  interval, unreadable samples and warnings. The preview position is distinct
  from the last successfully analyzed position.
- Samples and new detections committed on the phone during this video session,
  before the whole video completes. Live saving retains analysis progress.
- Time since the last PC response, an explanation after an operation has supplied
  no updates for 15 seconds, and frozen-state labeling while waiting or paused.
  Notifications include the current video stage and live face count.

The PC adds optional `details.stage` (`decode`, `inference`, `finalize`) and
`details.total_samples` to existing device-owned video job responses. Existing
servers still work; unavailable measurements are omitted. No database schema
change is required. Existing upload/job/import checkpoints remain in use.

## Verification

- Full Flutter suite: **477 passed**, including the real HTTPS fixture round trip.
- Focused checks cover resumed upload offsets, stage percentages, verified
  imports, live saving before completion, optional server metadata, transfer
  integrity and narrow layouts with 150% text scaling.
- Final telemetry/widget/render checks after the finalization correction:
  **21 passed**.
- Flutter analysis: no issues.
- Python video lifecycle/recovery tests: **17 passed**.
- API contract: **28/28**; stateless checks: **5/5**; OpenAPI schemas/fixtures valid.
  An initial stateless run encountered the existing low-RAM admission protection
  while the Flutter suite was running; it passed when rerun after that suite.
- Upload and analysis cards were rendered with the Flutter renderer and visually
  inspected. This is fixture-based verification, not a new long-video phone run.

## Android update

Version **1.2.1**, code **5**, package `com.antigravity.antigravity_mobile`.
Signed arm64 APK: `mobile/build/video-progress-1.2.1.apk`.
APK signature verification passed; Android metadata confirms version/code above.
Size: **45,796,107 bytes**. SHA-256:
`4c1c0feb8cdf7d014afbb58bc721faebe756f094ccfa10283efb9037e0c1f92d`.

Install the APK as an update and restart the PC mobile server after its current
work has settled to enable the additional server measurements. This change does
not install the APK on a phone or restart the running server automatically.
