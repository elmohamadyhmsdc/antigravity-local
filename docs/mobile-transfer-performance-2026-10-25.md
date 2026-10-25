# Faster mobile transfers — 2026-10-25

The user reported very slow uploads and downloads on the same Wi-Fi network.
Inspection found avoidable copying and scheduling in both directions. The
following improvements preserve the original bytes and existing TLS identity,
upload-resume, SHA-256 verification and commit-before-ACK guarantees.

## Changes

- Uploads now pass bounded, zero-copy views as a stream with an explicit
  Content-Length. The installed Dio version otherwise splits each 4 MiB binary
  request into 4096 separately copied 1 KiB pieces. The new path sends 16 views
  of 256 KiB. The existing 4 MiB resumable request boundaries remain unchanged.
- Result responses read up to 1 MiB per operation instead of 64 KiB, reducing
  Windows thread-pool scheduling. Starlette still handles byte ranges and the
  existing authenticated result-file allowlist. Responses request no HTTP cache.
- The phone batches small TLS records into bounded disk writes. It retains a
  partial Studio download across connection failures and requests only the
  remaining bytes on the next attempt. A full response from a server ignoring
  Range safely replaces the partial file. Invalid ranges cannot append bytes.
- An already complete partial is verified by the caller rather than downloaded
  again. Oversized partials restart. Full manifest size/SHA-256 verification
  remains mandatory before any local result commit or server ACK.
- Pinned connections enable TCP_NODELAY to avoid Nagle delays for small requests.

Primary files: mobile/lib/data/api/{bulk_transfer,mobile_api,pinned_http}.dart and
the app/mobile_api/{transfers,routes_jobs}.py. No dependencies, CUDA, codecs,
image quality, video resolution or model settings changed.

## Measured result

Three runs per version transferred identical-size synthetic **32 MiB in each
direction**, with the real Flutter client and real local Python API over pinned
HTTPS. GPU computation, hashing and server startup are outside the timed sections.
Every output was hash verified and each job/input was removed after ACK.

| Median | Before | After | Time reduction |
|---|---:|---:|---:|
| Upload | 0.878141 s / 36.44 MiB/s | 0.682083 s / 46.92 MiB/s | 22.3% |
| Download | 0.919255 s / 34.81 MiB/s | 0.795932 s / 40.20 MiB/s | 13.4% |

These are **desktop loopback measurements**, not measured phone/Wi-Fi throughput.
They establish reduced software overhead; radio speed, phone storage/CPU, source
file size and processing time still determine the user's total wait. Selected
video ranges currently upload the full source video before server-side trimming.
Media is not recompressed or reduced silently.

Logs: mobile/build/transfer-{baseline,optimized}.log. Reproduction with existing
dependencies, from mobile/: Flutter test tools/transfer_benchmark_test.dart
--no-pub. The tool creates only disposable synthetic inputs and its own temporary
server/workspace; it does not connect to a paired phone or the user's server.

## Verification

Eight new Flutter tests cover exact binary upload length/range and reconstruction,
complete HTTPS downloads, persisted partials, an abruptly closed TLS socket,
Range-ignoring servers, complete/oversized partials, invalid response ranges and
preservation of authentication/retry error envelopes without writing error bodies.
The abrupt-disconnect test confirms that the next request starts at the actual
persisted offset and the final binary SHA-256 is unchanged. Log:
mobile/build/transfer-resume-tests.log.

The initial disconnect fixture incorrectly tried detaching a socket after HTTP
headers had been sent. It was corrected to send a deliberately truncated raw
HTTP response over a detached TLS socket; all eight tests then passed.
Studio/video/retention server tests: **28 passed**.

Final verification: **395 Flutter tests passed**, including the HTTPS round trip;
Flutter analyzer **no issues**. The real GPU HTTPS round trip was repeated with
the optimized transfer path and left **zero server payload files** after ACK
(mobile/build/stateless-transfer-live-gpu.log). The existing five database/data
isolation checks and OpenAPI/fixture validation also passed. No phone was connected
for a hardware or Wi-Fi throughput test.

Final Debug APK: mobile/build/app/outputs/flutter-apk/app-debug.apk,
**225,544,259 bytes**. Offline Gradle build passed in **1m 26s**; log:
mobile/build/reface-transfer-debug-build.log. The APK has not been installed.
Both the mobile APK and backend code must be updated to receive all changes;
the existing user server was not restarted during this task.
