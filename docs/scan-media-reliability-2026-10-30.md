# Scan reliability and live media preview — 2026-10-30

## Changes

- Native image/video decoding runs in disposable processes, separate from the
  HTTPS API and its already-isolated inference worker. Pipe writes, reads and
  FFmpeg calls have timeouts. Video decoding uses two codec threads; images are
  bounded before being sent back to the API. Image decoding shares inference's
  admission lock so concurrent requests cannot decode several originals at once.
- Pillow handles JPEG, PNG, BMP, WebP, GIF, TIFF and AVIF, with EXIF orientation.
  `pillow-heif` adds HEIC/HEIF and was installed in the project's existing venv
  without changing CUDA/ONNX packages. Animated/multipage image files use their
  first frame/page. Android falls back to MediaStore's bounded JPEG conversion
  when the original-file compressor cannot decode an asset.
- Video decoding first uses isolated OpenCV, then local FFmpeg for unreadable
  frames/codecs. FFprobe supplies metadata when OpenCV cannot. Extensionless
  uploaded files are supported. The current installed FFmpeg is preferred over
  the older DeepFaceLab bundle; `ANTIGRAVITY_FFMPEG` remains an explicit override.
- An unreadable video sample is counted and skipped; other detections survive.
  Eight consecutive unreadable samples stop an unproductive decoder. Earlier
  results remain downloadable with an explicit incomplete-scan warning; a video
  with no readable samples fails with a useful file/codec error. Warnings are
  saved on the phone and displayed in the media viewer.
- Available RAM below 1 GiB, or system RAM usage of at least 97%, temporarily
  blocks new API compute even without custom limits enabled. Videos recheck
  resources between samples, release inference models on resource pauses and
  resume at the next uncommitted sample. Temporary inference-worker failures
  pause a video; repeated failures pause the phone scan rather than looping.
- Scan progress shows the current photo, then the actual server sample and its
  timestamp for videos. Server previews are JPEGs at most 480px on the longest
  side and are returned only through device-owned job endpoints. A phone thumbnail
  is used during video preparation/upload. Preview state clears between assets.
- Failed video requests no longer permanently reuse their failed server job.
  The progress sheet scrolls on smaller screens. The Windows launcher appends
  both stdout and stderr as UTF-8, including native crash traces.

## Verification

- Flutter analysis: no issues. Full phone suite: **465 passed**.
- Python video, codecs, inference isolation, supervisor and resources: **53 passed**.
- API contract: **28/28**; stateless/library protection: **5/5**.
- Real generated files decoded successfully: JPEG, PNG, BMP, TIFF, GIF, WebP,
  AVIF, HEIF; MP4/H.264, MKV/HEVC and WebM/VP9. Both the normal isolated video
  reader and forced FFmpeg fallback were checked, including bounded dimensions.
- Decoder exits, hangs and a large upload to a worker that never reads stdin
  were contained. Corrupt samples, resource changes during a video and resume
  checkpoints were covered by regression tests.
- The two cached source videos from the reported errors were read without
  modifying their inputs or existing jobs. Frame **675** of
  `vid_c157a402be6943ce838b475b92faa896` decoded successfully. Samples near its
  end and frame **40500** of `vid_b306ed5403b24764b6ccf05cdcc3d58c` remained
  unreadable. Isolated production scan jobs over the final seconds of **both**
  videos completed, skipped one unreadable sample each and retained the preceding
  detection result. These were tail checks with fixture inference, not full
  rescans of the videos.

The supplied traces show caught decode errors, not the cause of the latest
server process exit. The saved exit record reports an older 2026-10-27 access
violation; the current launcher had omitted stderr from its file log. Decoder
isolation and RAM admission reduce these failure paths; complete diagnostics
will now be retained if another process crash occurs.

## Android update

- Signed release APK: `mobile/build/scan-preview-1.1.1.apk`.
- Package: `com.antigravity.antigravity_mobile`, version **1.1.1**, code **3**.
- SHA-256: `4b08f70e1524dd0aab868dc0738e8a59db17a8781df2fd760fa14ed808721bb1`.
- Release signature verified. Install as an update, then restart the PC server
  to activate its new backend. The phone's existing library/pairing schema is
  unchanged. The server's normal startup clears ephemeral uploads/jobs, and the
  phone resubmits interrupted work using its imported-frame checkpoints.

The production phone and stopped server were not replaced or restarted as part
of the isolated tests. Their cached jobs and original inputs remain available.

After the user's explicit request, the release APK was installed on the connected
phone with `adb install -r`, without uninstalling the app or clearing its data.
Installation returned `Success`; Android package manager confirmed version
**1.1.1**, code **3**, with last update time **2026-10-30 21:20:42**. The PC server
was not started by this installation step.
