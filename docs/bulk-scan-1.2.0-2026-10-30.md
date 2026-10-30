# Bulk mobile scanning — 1.2.0

Implemented directly for the existing Wi-Fi workflow, without a USB media-copy
mode or a performance-measurement phase.

- Videos deliver complete, SHA-256-verified NDJSON batches during analysis.
  Batches contain up to eight frames, normally at most 4 MiB; a single larger
  frame can be up to 16 MiB. The first result is committed immediately;
  subsequent output commits after eight samples or three seconds, checked
  between samples. The phone polls every two seconds and drains available batches.
- The phone commits each frame with its imported-frame checkpoint. Its byte cursor
  advances only after all frames in the batch commit. Interrupted batches replay
  safely without duplicate detections. Old PCs retain the verified final-file
  fallback. ACK/delete follows successful local persistence.
- Expiring video journals and uploads survive normal server restarts. Journals
  preserve ownership, idempotency keys and the exact sampling grid; recovery
  truncates an incomplete output line and resumes at the uncommitted sample.
  Unacknowledged results remain subject to the existing 24-hour idle TTL and
  temporary-cache policy. Explicit workspace resets still remove scratch.
- Automatic sampling defaults on for new video requests. The interval is
  `clamp(duration_seconds / 480, 0.5, 10)` seconds, rounded to whole frames.
  Examples: 20 seconds → 0.5 s; 10 minutes → 1.25 s; 40 minutes → 5 s;
  two hours → 10 s. Unknown durations use 1 s until decoded metadata is available.
  A resumed job retains its original FPS/grid instead of changing mid-video.
  Manual sampling remains available in Sources when automatic sampling is off.
- Photo preparation overlaps current analysis with at most one next JPEG in
  memory. Look-ahead does not claim the next queue item, and pause/backup waits
  for preparation to settle. Cache clearing waits for native preparation.
- In-scan grouping uses face matching/clustering after 100 new faces or 200 files.
  Body linking and the full review run happen at completion or pause. Final and
  manual grouping cannot accidentally join an incomplete in-scan pass.

## Validation and activation

- Flutter analysis: no issues. All 470 phone cases were verified through the full
  suite and focused reruns. Initial settings-scroll failure was corrected; a full
  run also hit the intentional low-RAM guard in fixture compute. The fake HTTPS
  fixture now uses deterministic resource readings, while real-GPU runs retain
  actual admission checks. Its isolated rerun passed.
- Python scan/recovery/retention/worker/supervisor/resources: 58 passed. The final
  video-only rerun passed all 17 cases. The additional dashboard/control suite
  previously passed 32 cases including overlapping video/retention coverage.
- API contract: 28/28; stateless/desktop-library protection: 5/5.
- Tests cover live batches before completion, hashes, ownership, cursor bounds,
  replay after an interrupted phone cursor, fresh-workspace recovery, incomplete
  output truncation, retained results, adaptive intervals and preserved grids.
- Signed release: `mobile/build/bulk-scan-1.2.0.apk`, 45,796,079 bytes.
  Package `com.antigravity.antigravity_mobile`, version 1.2.0, code 4.
  SHA-256: `2e91aa3deeb3ea6e316ba9d0222eeaebfadb703f5a14ed651621c7a56ace7f34`.
  Release certificate matches the preceding 1.1.1 update.
- The production PC server was gracefully restarted after confirming zero active
  queued/video/Studio jobs. It reports running on 8443 with preserved identity and
  scratch. No production library scan was triggered by the validation scripts.
- After the user reconnected the Samsung A72 (`R58R30QA3KZ`), the signed release
  was installed with `adb install -r`, preserving app data. Installation returned
  `Success`; package manager confirmed version **1.2.0**, code **4**, updated at
  **2026-10-30 23:16:22**. The separately connected Mi TV was left untouched.
