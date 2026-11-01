# Instant Gallery Loading, Video Swipe Autoplay & Native Video Player Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the mobile gallery into an instant-loading gallery with zero-copy swipe-autoplay video playback and native Samsung video player handoff.

**Architecture:** Retain loaded MediaStore assets in a persistent Riverpod Notifier so gallery tab navigation is instant (0ms). Stream videos via direct Android `contentUri` without copying multi-hundred megabyte files to cache, automatically playing videos muted-by-default when swiped into view, with a quick mute toggle and a native Android `ACTION_VIEW` intent bridge to launch the device's native video player (e.g. Samsung Video Player).

**Tech Stack:** Flutter, Riverpod, `video_player: ^2.14.1`, `photo_manager: ^3.12.0`, Android Kotlin (`Intent.ACTION_VIEW`), Android Scoped Storage MediaStore Content URIs.

---

### Task 1: Native Video Player Bridge (Android Kotlin & Dart Service)

**Files:**
- Create: `mobile/lib/data/platform/native_video_player.dart`
- Modify: `mobile/android/app/src/main/kotlin/com/antigravity/antigravity_mobile/MainActivity.kt`
- Test: `mobile/test/data/native_video_player_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/data/native_video_player_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/platform/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NativeVideoPlayer invokes antigravity/video_player channel with uri', () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('antigravity/video_player'),
      (c) async {
        call = c;
        return true;
      },
    );

    final result = await NativeVideoPlayer.openVideo(
      'content://media/external/video/media/12345',
      title: 'Sample Video',
    );

    expect(result, isTrue);
    expect(call?.method, 'openNativePlayer');
    expect(call?.arguments['uri'], 'content://media/external/video/media/12345');
    expect(call?.arguments['title'], 'Sample Video');
  });
}
```

**Step 2: Run test to verify it fails**
Run: `flutter test test/data/native_video_player_test.dart`
Expected: FAIL (NativeVideoPlayer does not exist).

**Step 3: Implement NativeVideoPlayer and Kotlin channel handler**
1. Create `mobile/lib/data/platform/native_video_player.dart`:
```dart
import 'package:flutter/services.dart';

class NativeVideoPlayer {
  static const MethodChannel _channel = MethodChannel('antigravity/video_player');

  static Future<bool> openVideo(String uri, {String? title}) async {
    try {
      final success = await _channel.invokeMethod<bool>('openNativePlayer', {
        'uri': uri,
        'title': title ?? 'Video',
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }
}
```

2. Modify `mobile/android/app/src/main/kotlin/com/antigravity/antigravity_mobile/MainActivity.kt`:
Register `antigravity/video_player` channel in `configureFlutterEngine`:
```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "antigravity/video_player")
    .setMethodCallHandler { call, result ->
        if (call.method != "openNativePlayer") {
            result.notImplemented()
            return@setMethodCallHandler
        }
        val uriStr = call.argument<String>("uri")
        if (uriStr == null) {
            result.error("no_uri", "Video URI is required", null)
            return@setMethodCallHandler
        }
        val title = call.argument<String>("title") ?: "Video"
        try {
            val uri = android.net.Uri.parse(uriStr)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "video/*")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val chooser = Intent.createChooser(intent, title).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(chooser)
            result.success(true)
        } catch (e: Exception) {
            result.error("launch_failed", e.message, null)
        }
    }
```

**Step 4: Run test to verify it passes**
Run: `flutter test test/data/native_video_player_test.dart`
Expected: PASS.

---

### Task 2: Direct Content URI Resolution for Videos (Zero-Copy)

**Files:**
- Modify: `mobile/lib/data/media/media_library.dart`
- Modify: `mobile/test/support/fakes.dart`
- Test: `mobile/test/data/media_library_uri_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/data/media_library_uri_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import '../support/fakes.dart';

void main() {
  test('FakeMediaLibrary provides videoUri for assets', () async {
    final library = FakeMediaLibrary(uris: {'video_1': 'content://media/external/video/media/1'});
    expect(await library.videoUri('video_1'), 'content://media/external/video/media/1');
    expect(await library.videoUri('unknown'), isNull);
  });
}
```

**Step 2: Run test to verify it fails**
Run: `flutter test test/data/media_library_uri_test.dart`
Expected: FAIL (`videoUri` method does not exist on `VideoMediaLibrary`).

**Step 3: Implement `videoUri` on `VideoMediaLibrary` and `PhotoManagerLibrary`**
In `mobile/lib/data/media/media_library.dart`:
Add `videoUri(String assetId)` to `VideoMediaLibrary`:
```dart
abstract interface class VideoMediaLibrary {
  Future<File?> videoFile(String assetId);
  Future<String?> videoUri(String assetId);
}
```
In `PhotoManagerLibrary`:
```dart
@override
Future<String?> videoUri(String assetId) async {
  try {
    final entity = await AssetEntity.fromId(assetId);
    if (entity == null) return null;
    return await entity.getMediaUrl();
  } catch (_) {
    return null;
  }
}
```
Update `FakeMediaLibrary` in `mobile/test/support/fakes.dart` to support `uris`.

**Step 4: Run test to verify it passes**
Run: `flutter test test/data/media_library_uri_test.dart`
Expected: PASS.

---

### Task 3: Video Autoplay on Swipe & Mute Control in `VideoMediaView`

**Files:**
- Modify: `mobile/lib/features/media/video_media_view.dart`
- Modify: `mobile/test/features/video_media_view_test.dart` (or create if absent)

**Step 1: Write the failing test**
Create/update `mobile/test/features/video_media_view_test.dart` checking that:
- `VideoMediaView` accepts `isActive` parameter (defaults to `false`).
- Mute toggle is present and toggles volume.
- Responds to `widget.isActive` changes.

**Step 2: Run test to verify it fails**
Run: `flutter test test/features/video_media_view_test.dart`
Expected: FAIL.

**Step 3: Update `VideoMediaView` implementation**
1. Add `final bool isActive;` to `VideoMediaView` (default `false`).
2. Add `bool _muted = true;` in `_VideoMediaViewState`.
3. In `_load()`:
   - Query `source.videoUri(widget.assetId)`.
   - If URI is available, construct `VideoPlayerController.contentUri(Uri.parse(uri))`.
   - Otherwise fall back to `VideoPlayerController.file(file)`.
   - Set `player.setVolume(_muted ? 0.0 : 1.0)`.
   - If `widget.isActive`, call `player.play()`.
4. In `didUpdateWidget(VideoMediaView oldWidget)`:
   - If `oldWidget.isActive != widget.isActive`:
     - If `widget.isActive`: call `_player?.play();`
     - If `!widget.isActive`: call `_player?.pause();`
5. Add Mute/Unmute IconButton (`Key('video-mute-toggle')`) overlaid on the video and in the control row.

**Step 4: Run test to verify it passes**
Run: `flutter test test/features/video_media_view_test.dart`
Expected: PASS.

---

### Task 4: Integrate Swipe Autoplay & Native Player Action in `MediaScreen`

**Files:**
- Modify: `mobile/lib/features/media/media_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`, `mobile/lib/l10n/app_localizations.dart`, `mobile/lib/l10n/app_localizations_en.dart`
- Test: `mobile/test/features/media_screen_native_player_test.dart`

**Step 1: Write the failing test**
Test that `MediaScreen` displays "Open with player" action when viewing a video, and tapping it calls `NativeVideoPlayer.openVideo`.

**Step 2: Run test to verify it fails**
Run: `flutter test test/features/media_screen_native_player_test.dart`
Expected: FAIL.

**Step 3: Implement `MediaScreen` updates**
1. In `_MediaPageViewItem`:
   - Pass `isActive: i == _currentIndex` to `_MediaPageViewItem` and down to `VideoMediaView`.
2. Add `openWithPlayer` action in `MediaScreen`:
   - In AppBar actions, when `media.kind == 'video'`, add `IconButton(key: Key('media-open-native-player'), icon: Icon(Icons.smart_display_outlined), tooltip: 'Open with native player', onPressed: _openNativePlayer)`.
   - In bottom action bar, add `TextButton.icon(icon: Icon(Icons.smart_display_outlined), label: Text('Player'), onPressed: _openNativePlayer)`.
   - `_openNativePlayer`: pauses in-app video and calls `NativeVideoPlayer.openVideo(uri, title: ...)`.

**Step 4: Run test to verify it passes**
Run: `flutter test test/features/media_screen_native_player_test.dart`
Expected: PASS.

---

### Task 5: Instant Gallery Loading with In-Memory Riverpod State

**Files:**
- Modify: `mobile/lib/features/library/native_gallery.dart`
- Modify: `mobile/lib/library_providers.dart`
- Test: `mobile/test/features/native_gallery_instant_test.dart`

**Step 1: Write the failing test**
Test that `NativeGallery` renders cached assets instantly on initial build without showing `LoadingBox` when the provider already holds assets.

**Step 2: Run test to verify it fails**
Run: `flutter test test/features/native_gallery_instant_test.dart`
Expected: FAIL.

**Step 3: Implement `nativeGalleryProvider`**
1. Create `NativeGalleryNotifier` and `nativeGalleryProvider` in `mobile/lib/library_providers.dart` holding:
   - `List<AssetInfo> assets`
   - `bool hasMore`
   - `bool isLoading`
   - `StreamIterator<List<AssetInfo>>? pages`
2. Update `NativeGallery` in `mobile/lib/features/library/native_gallery.dart`:
   - Read `ref.watch(nativeGalleryProvider)`:
   - If `assets.isNotEmpty`, immediately render `CustomScrollView` (zero loading spinner).
   - If `assets.isEmpty` and not loading, trigger initial page load.
   - When scrolling reaches near end (`extentAfter < 900`), trigger `notifier.loadNextPage()`.
   - Retain list across unmounts / tab switches.

**Step 4: Run test to verify it passes**
Run: `flutter test test/features/native_gallery_instant_test.dart`
Expected: PASS.

---

### Task 6: Static Analysis, Regression Verification & Documentation Update

**Files:**
- Modify: `docs/ANTIGRAVITY_HANDOFF.md`

**Step 1: Run `flutter analyze`**
Run: `flutter analyze`
Expected: 0 issues.

**Step 2: Run full test suite**
Run: `flutter test test/features test/data test/domain`
Expected: All tests pass.

**Step 3: Update `ANTIGRAVITY_HANDOFF.md`**
Record the exact changes, components, verified behaviors, and status in `docs/ANTIGRAVITY_HANDOFF.md`.
