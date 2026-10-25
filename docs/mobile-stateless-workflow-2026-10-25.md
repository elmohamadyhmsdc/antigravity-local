# Mobile Reface workflow and temporary server storage — 2026-10-25

The phone can submit Reface inputs to a server without a desktop library, receive
the processed result and keep the only durable personal copy locally. This was
verified using the actual Flutter HTTP client, pinned HTTPS, a fresh phone test
database, an empty server workspace and the installed GPU models. A physical
Android phone was not connected during this task.

## Target selection and trimming

- One **Choose photo or video** button opens the system's combined media picker.
  The chosen media type determines the next controls.
- Videos show a playable preview and a two-handle range bar. Dragging either end
  seeks the preview to that boundary. Time appears as minutes:seconds or
  hours:minutes:seconds; one-second adjustment buttons help with long videos.
- Playback stays within the chosen range and pauses when leaving the step or
  backgrounding the app. Invalid/empty videos show an error. The form waits for
  the video duration before accepting the selection.
- The API still receives exact numeric start/end seconds, calculated by the UI;
  the user no longer enters or calculates them. The selected source file is
  uploaded in full; trimming currently happens on the server.

Implementation starts at mobile/lib/features/reface/{reface_media,
reface_video_trimmer,reface_screen}.dart. Existing video_player/image_picker
dependencies are reused. No media compression or video re-encoding was added.

## Commit and deletion order

1. The phone stages its inputs privately and uploads hash-verified blobs.
2. The server pins job inputs, processes them in its temporary job directory and
   exposes a size/SHA-256 result manifest.
3. The phone downloads and verifies the complete result, then commits its private
   files and database result row.
4. Only after that commit does it send DELETE/ACK. The server removes job inputs,
   intermediates, output and any input-cache blobs with no other registered job
   using them. A different queued/running/paused job keeps its own references.
5. Failed cleanup remains pending and is retried. A completed local result never
   becomes a failed rendering or gets downloaded again just because ACK failed.
   Deleting a local result also preserves pending server cleanup.

Deletion errors fail the ACK instead of silently reporting success. The input
reference registration is retained until deletion succeeds, including a retry
after the job directory has already been removed. SSE shutdown errors cannot
prevent the cleanup request. Image-analysis multipart files are closed before
inference. Ordinary API access logging is disabled so blob-hash URLs are not
written by the default access logger.

## If the connection disappears

Temporary files exist on server disk while processing and until acknowledgement.
Unclaimed uploads and partial uploads expire after six idle hours. Inactive
unacknowledged jobs expire after 24 hours. A cleaner runs every 60 seconds even
without client polling and protects active registered jobs. Startup wipes the
workspace's ephemeral files. TLS credentials, paired-device identity and generic
installed model weights persist. Existing desktop data is outside this workspace.

This is application-level deletion, not a claim that processing is RAM-only or
that deleted disk blocks, OS paging or external backups are securely erased.

## Evidence

- Actual Flutter HTTPS/GPU round trip: source analysis → upload → V3 processing
  → phone SHA-256 verification/local commit → ACK → **zero remaining server
  payload files**. Repeated after the transfer improvements; latest log:
  mobile/build/stateless-transfer-live-gpu.log.
- Default synthetic-compute HTTPS round trip is part of the normal Flutter suite;
  it verifies empty initial databases/workspace, commit-before-ACK, final cleanup
  and no desktop data/database dependency.
- Six retention regressions cover sharing, deletion failures/retries, autonomous
  expiry, protected live jobs and startup wiping. Studio 13 and video 9 server
  tests also passed. Log: mobile/build/transfer-server-tests.log (28 total).
- The six new picker/trimmer tests cover unified selection, media identification,
  handle dragging on a 320-pixel screen, readable times, seeks and playback limits.
- Final full Flutter suite: **395 passed**, analyzer **no issues**. Logs:
  mobile/build/reface-transfer-final-{tests,analyze}.log.
- Connection speed improvements and measured limits are recorded in
  [the transfer report](mobile-transfer-performance-2026-10-25.md).

No existing phone library, paused queue, desktop database or running user server
was changed. The isolated test servers shut down and remove their temporary roots.
Native Android gallery/codec acceptance and real Wi-Fi speed remain device checks.
