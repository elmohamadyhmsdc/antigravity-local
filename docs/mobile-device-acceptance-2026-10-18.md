# Android device acceptance — 2026-10-18

Device: Samsung Galaxy A72 (SM-A725F), Android 14 / API 34, USB ADB.
The existing Debug application was updated in place; it was not uninstalled and
its storage was not cleared. Its SQLCipher library opened successfully after the
schema-6 upgrade: 74 people, 1,612 faces, 450 photos and 15 videos. These counts
are a migration smoke check, not a complete row-by-row data comparison.

## Verified

- Existing pairing moved from the saved LAN endpoint to `127.0.0.1:8443` over
  `adb reverse`. The client verified the same certificate/server identity and
  retained its pairing and library. No re-pair or token extraction was needed.
- Notifications are granted, battery optimization is exempted, and the Android
  foreground service becomes active while the existing queue is running.
- With the display dozing/locked, the existing video upload advanced from
  613,384,191 to 796,917,760 bytes while the same process remained alive.
  Swiping only Antigravity out of Recents also retained the process/service and
  advanced the upload from 60% to 67%; the reopened UI showed 69%. Warm Activity
  recreation took 306 ms in Debug; this is not a Release startup benchmark.
- An interrupted USB listener plus refreshed connection pool produced a real
  connection-refused/waiting state. Restoring the listener resumed from the
  saved upload offset (57%), without restarting the transfer. The 2 GB upload
  later completed and video analysis began; the scan was explicitly paused
  without dropping its six pending items. Full long-video analysis/import is
  still a separate acceptance case.
- Real-library encrypted export reached Android's share sheet. Cancelling it
  reported cancellation and left the last-backup indicator at “No backup yet”.
  The plaintext archive had been removed; only the encrypted file remained in
  private cache. No file was sent to another app or copied to public storage.
- Native crypto was also exercised through the installed Debug app using only
  synthetic files under its private cache: multi-chunk encryption/decryption,
  byte-for-byte comparison, rejection of an incorrect password and a changed
  final authentication tag, and absence of partial plaintext. Fixtures were
  deleted after the checks. The real library was never restored/replaced.
- Android's restore document picker opened and cancelled correctly after
  Activity recreation, returning to the unchanged backup screen. No archive
  was selected or restored.
- Android decoded, played and sought a private synthetic 320x240, three-second
  MP4: playback advanced 897 ms and seeking reached 1,800 ms. The existing
  three-second library video also played, and its detected-frame chip sought
  to 0:02 with a person box. The live viewer window had FLAG_SECURE set
  (`fl=81812100`). No protected screenshot was taken.
- A synthetic PNG exported through MediaStore with the expected size/dimensions,
  Pictures/Antigravity destination and `is_pending=0`. Only the identified test
  gallery item was deleted afterwards. A real phone pinned-HTTPS request also
  completed GPU face/body analysis of the synthetic image and parsed the
  expected empty detection result.
- The user confirmed Android credentials on the phone. App lock enabled,
  backgrounding/reopening displayed the lock gate, and authentication opened
  the app again. The setting was restored to its original disabled state.
- Restyle's advanced UI correctly disables optional SDXL refinement and explains
  that the installed base stage remains usable.
- A complete Restyle job used the synthetic clothed mannequin, five diffusion
  steps, seed 7 and no refinement. Phone staging/upload, server GPU execution,
  result download/import and ACK/purge completed. The 50,841-byte local result
  matched its saved SHA-256; the PC scratch job was removed after ACK. The phone
  displayed queued/running/saving/completed history and a PRIVATE completion
  notification. Before/after dragging, a persisted favourite, gallery saving
  and cancelled sharing worked. The identified gallery test copy was removed;
  the private mannequin result and its job remain for review. No image-quality
  claim follows from a five-step synthetic smoke test.

## Issue found and fixed

A queued video was 2,042,145,491 bytes. The app displayed “Uploading video · 0%”
while calculating its SHA-256, and Pause waited for that calculation to finish.
`video_hash.dart` now hashes bounded 1 MiB blocks in a dedicated isolate, reports
preparation progress, and accepts cooperative cancellation between blocks. The
worker closes its source before acknowledging cancellation. VideoScan maps that
cancellation to its existing durable queue pause.

On this phone, a private 64 MiB synthetic fixture cancelled in **283 ms**, at 6%
progress; the source length was unchanged and the file could be deleted as soon
as the operation returned. Host tests cover hash parity, empty input,
cancellation/closed handles and unreadable input. All **373 Flutter tests pass**;
Debug and signed Release APKs rebuilt offline successfully. No dependency,
Python/CUDA or model changes were made during device testing.

## Remaining acceptance

Full long-video analysis/import/restart, long-duration vendor background limits,
Release performance at scale and camera QR remain. Reface and LoRA forms opened;
LoRA's person selector loaded the existing encrypted library and Android's
training-photo picker opened/cancelled successfully after Activity recreation.
No new phone Reface or LoRA-training job was submitted. Their earlier PC GPU
acceptance does not by itself verify every phone interaction. An actual
destructive restore onto the user's library has not been attempted.

An offline Profile build was attempted for more representative performance
measurements. The engine files were present in the Flutter SDK, but Gradle did
not have the matching `io.flutter:flutter_embedding_profile` dependency cached.
The build refused to proceed offline; nothing was downloaded or installed, and
the working Debug build remained on the device. Debug timing/memory observations
are not presented as Release performance results.

Final working state: USB mobile API remains available; the six-item scan queue
is explicitly paused with its uploaded video/checkpoint retained. The private
synthetic Restyle result/job remains for review. Synthetic gallery copies,
private fixture inputs, test backup/share copies and remote inspection files
were cleaned up. App lock is back to its original disabled setting. No package,
SDK dependency, Python/CUDA component or further model was downloaded.
The seven existing legacy Restyle CPU failures remain as documented in the
completion report; these phone checks do not mark them resolved.
