# Mobile Reface workflow and temporary server storage — 2026-10-25

The phone can submit Reface inputs to a server without a desktop library, receive
the processed result and keep the only durable personal copy locally. This was
verified using the actual Flutter HTTP client, pinned HTTPS, a fresh phone test
database, an empty server workspace and the installed GPU models. A physical
Android phone was not connected during that round-trip acceptance. A later
picker follow-up used read-only package queries on a connected Samsung A55.

## Target selection and trimming

- One **Choose photo or video** button offers **Gallery** and **Files**. Gallery
  launches an explicit Android app chooser for image/video GET_CONTENT requests,
  allowing the installed device gallery instead of silently using a saved Photos
  default. Files uses the document browser with custom image/video filters.
  Cancelling the source menu preserves the previous selection. The chosen media
  type determines the next controls.
- Videos show a playable preview and a two-handle range bar. Dragging either end
  seeks the preview to that boundary. Time appears as minutes:seconds or
  hours:minutes:seconds; one-second adjustment buttons help with long videos.
- Target people are now detected directly from video frames and grouped by
  identity. A current-preview-frame action can add a person missed by interval
  sampling. Source identity can come from multiple gallery photos/videos without
  creating a library person. See the [direct media identity report](reface-direct-media-identities-2026-10-25.md).
- Playback stays within the chosen range and pauses when leaving the step or
  backgrounding the app. Invalid/empty videos show an error. The form waits for
  the video duration before accepting the selection.
- The API still receives exact numeric start/end seconds, calculated by the UI;
  the user no longer enters or calculates them. The selected source file is
  uploaded in full; trimming currently happens on the server.

Implementation starts at mobile/lib/features/reface/{reface_media,
reface_video_trimmer,reface_screen}.dart. Existing file_picker/video_player
dependencies are reused. Files are read from the picker-provided local copy;
videos are not re-encoded. Android Gallery uses MediaPickerBridge.kt and copies
the selected URI into private cache on a worker thread with a bounded buffer.

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

Latest picker follow-up: **16 focused tests passed**, analyzer **no issues**, and
the native Android bridge compiled in an offline Debug build (**46 seconds**).
On the connected SM-A556E / Android API 36, a read-only package-manager query
confirmed Samsung Gallery's exported GalleryExternalActivity handles the exact
GET_CONTENT + OPENABLE + image/video MIME selection. The new APK was not installed
or opened on that phone; this query does not establish visual on-device acceptance.
Logs: mobile/build/reface-gallery-chooser-{tests,analyze,build}.log.
