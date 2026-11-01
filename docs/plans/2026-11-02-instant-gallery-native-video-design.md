# Instant Gallery Loading, Video Swipe Autoplay & Native Video Player Design

## 1. Goal & Overview
Improve the mobile gallery experience to match native smartphone responsiveness:
1. **Instant Gallery Loading**: Keep loaded MediaStore assets cached in a Riverpod `NotifierProvider` so navigating to the Gallery tab (and switching tabs) renders instantly with 0ms delay and zero loading spinners.
2. **Video Swipe Autoplay (Zero-Copy)**: Stream videos directly using their native `contentUri` without copying multi-hundred megabyte files to the app cache. Autoplay the video when swiped into view in `MediaScreen`, muted by default, with a quick mute/unmute control.
3. **Open with Native Player**: Add a direct bridge to launch the device's native video player (e.g. Samsung Video Player) via Android `ACTION_VIEW` intent from the media viewer AppBar and bottom action bar.

---

## 2. Root Cause Analysis

### Issue A: Gallery Reloads on Every Open
In [`NativeGallery`](file:///d:/AndroidScan/gallary/mobile/lib/features/library/native_gallery.dart), asset list state (`_assets`, `_assetIds`, `_pages`) is stored in a local `_NativeGalleryState` (`StatefulWidget`). When navigating away from the Gallery tab or opening a photo and returning, the widget unmounts. Upon remounting, `initState()` resets `_assets` to empty and triggers a fresh `MediaStore` query through `photo_manager` via the MethodChannel, causing an unnecessary loading spinner every time.

### Issue B: Clunky Video Playback & Slow Initial Load
In [`video_media_view.dart`](file:///d:/AndroidScan/gallary/mobile/lib/features/media/video_media_view.dart) and [`media_library.dart`](file:///d:/AndroidScan/gallary/mobile/lib/data/media/media_library.dart):
1. `videoFile` calls `AssetEntity.originFile`. On modern Android (Scoped Storage), this copies the entire video into the application cache directory (`cache/...`), blocking playback for seconds on large videos.
2. Videos do not autoplay on swipe in `PageView.builder` because individual page items are not notified whether they are currently the active page (`isActive: index == currentIndex`).
3. There are no native playback gestures or easy handoff to the device's specialized hardware video player (e.g. Samsung One UI Video Player).

---

## 3. Architecture & Key Decisions

```
+------------------------------------------------------------------------+
|                            Your Gallery                                |
+------------------------------------------------------------------------+
                               |
       +-----------------------+-----------------------+
       |                                               |
       v                                               v
[Native Gallery Screen]                       [Media Viewer (Swipe)]
       |                                               |
       v                                               v
[nativeGalleryProvider]                       [MediaScreen PageView]
 - In-memory list cache                                |
 - Initialized once, kept alive                        |-- isActive: i == currentIndex
 - 0ms tab switching & return                          |
                                                       v
                                            [VideoMediaView]
                                             - Direct contentUri
                                             - Autoplay when active
                                             - Pause when inactive
                                             - Muted by default
                                             - Mute / unmute overlay
                                                       |
                                                       | [Open with Player]
                                                       v
                                            [NativeVideoPlayer Bridge]
                                                       |
                                                       v
                                            [Android ACTION_VIEW Intent]
                                             -> Samsung Video Player / Chooser
```

### Component 1: `nativeGalleryProvider` (Instant Gallery)
- Defined in `mobile/lib/library_providers.dart` (or `native_gallery.dart`).
- Manages `NativeGalleryState`: `assets`, `assetIds`, `loading`, `more`, `albumId`, `pages`.
- When `NativeGallery` mounts:
  - If state is already loaded, it immediately renders the grid without showing `LoadingBox()`.
  - When scrolling reaches `extentAfter < 900`, `loadMore()` requests the next batch of 120 items in the background.

### Component 2: `VideoMediaView` with Direct URI & Swipe Autoplay
- In `media_screen.dart`, `_MediaPageViewItem` receives `isActive: i == _currentIndex`.
- `VideoMediaView` receives `isActive: widget.isActive`.
- When `isActive == true`:
  - Resolves `contentUri` from `AssetEntity.getMediaUrl()` or `content://media/external/video/media/<id>`.
  - Initializes `VideoPlayerController.contentUri(Uri.parse(uri))` directly (fallback to `videoFile` if URI resolution is unavailable).
  - Sets `player.setVolume(_muted ? 0.0 : 1.0)` with `_muted = true` by default.
  - Automatically starts playback with `player.play()`.
- When `isActive == false`:
  - Pauses playback with `player.pause()`.
- Adds a mute toggle icon overlay on the video view with visual feedback.

### Component 3: Native Video Player Bridge
- MethodChannel: `antigravity/video_player` in `MainActivity.kt`.
- Method: `openNativePlayer(uriString, mimeType, title)`.
- Implements `Intent(Intent.ACTION_VIEW)` with:
  - `setDataAndType(Uri.parse(uri), "video/*")`
  - `addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)`
  - `addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)`
  - Wraps in `Intent.createChooser(intent, "Play video")` (or targets Samsung Video if explicitly available).
- Exposes Dart helper: `NativeVideoPlayer.openVideo(assetId, uri: ...)`.
- Adds an AppBar icon button (`Icons.smart_display_outlined` / `Icons.open_in_new`) and a button in the bottom tools row of `MediaScreen`.

---

## 4. Error Handling & Guardrails
- **URI Resolution Failure**: If `getMediaUrl()` returns null, fallback gracefully to `originalFile()`.
- **Corrupt / Unplayable Videos**: Catch playback initialization errors and show `EmptyState` without breaking swipe navigation.
- **Hardware Decoder Conservation**: When pages scroll away, inactive controllers pause immediately; disposed pages release controllers cleanly.
- **App Lifecycle**: Inactive app backgrounding pauses player.

---

## 5. Verification Plan
- Unit & Widget tests:
  - `native_gallery_test.dart`: verify state retention on rebuild/remount.
  - `video_media_view_test.dart`: verify muted default, autoplay on active, pause on inactive, mute toggle.
  - `native_video_player_test.dart`: verify method channel dispatch for native player opening.
- Static analysis: `flutter analyze` clean with 0 issues.
- Full regression suite: ensure all existing library and media screen tests pass.
