# Gallery loading and image decoder memory — 2026-11-04

The photo viewer previously loaded and decoded each image again after its page was disposed. The server also expanded uploaded images and decoded pixels into Base64 strings and JSON pipe messages. The reported `MemoryError` occurred in the first of those expansions.

## Changes

- Viewer previews share a cache across page lifetimes. Concurrent requests for the same asset share one read. The cache holds at most 12 encoded previews and 24 MiB; failed reads remain retryable.
- Dimensions come from encoded image metadata rather than decoding an entire frame just to measure it and decoding it again for display.
- The current photo and its immediate neighbours are warmed sequentially, including Flutter's decoded image cache. Prefetch stops advancing when the user changes pages. Cached thumbnails appear while larger previews load.
- Videos show their poster while the player initializes. Offscreen players retain the existing pause/dispose lifecycle.
- Image decoder requests now exchange small metadata messages pointing to private temporary binary files. Image input and output no longer pass through Base64 or large JSON messages. Scratch files are removed on completion, codec errors and timeouts. The worker releases its previous image after returning metadata; the API releases encoded upload bytes before constructing response crops.
- Worker memory exhaustion propagates as memory pressure, allowing the existing retryable HTTP 503 response instead of classifying a valid image as corrupt.

## Verification

- 39 distinct Flutter regression tests pass across cache reuse/eviction/retry, an actual two-photo swipe-and-return interaction, video playback, image previews and the 24-screen walkthrough. The swipe test verifies each photo is read only once.
- Seven real codec tests pass: JPEG/PNG/BMP/TIFF/GIF/WebP/AVIF/HEIF, EXIF rotation, limits, malformed files, worker exit/timeout recovery and MP4/MKV/WebM video fallback. Added tests prohibit Base64 encoding in the parent image path, check temporary-file cleanup and verify worker memory-pressure propagation.
- Seven analyze API contract tests pass, including image response compatibility and retryable out-of-memory responses.
- Flutter analysis has no errors or warnings; two existing informational brace findings remain in unrelated curation files.
- Android debug APK builds successfully at `mobile/build/app/outputs/flutter-apk/app-debug.apk`.

These checks use generated media and fake phone storage. Device scrolling latency and memory use have not been measured on the user's phone. The server must be restarted to load the Python changes, and the mobile build must be updated for the viewer changes. Other applications or loaded models can still exhaust system RAM; this change removes avoidable image-transfer allocations rather than guaranteeing available memory.
