# Media Viewer Swipe Navigation, Face Box Toggle & Google Lens Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable horizontal swipe navigation (swiping left/right between photos) in the media viewer across both Person Details and Main Gallery based on active filter, add a toggle button in the top AppBar to show/hide face detection circles/boxes, and add a Google Lens search button.

**Architecture:** 
1. `MediaQueries.ids(MediaFilter filter)` provides the ordered list of media IDs matching any filter (`ORDER BY COALESCE(m.taken_at, m.modified_at) DESC, m.id DESC`).
2. `MediaScreen` is upgraded with a `PageView.builder` backed by `PageController`, initialized at the tapped media's index, allowing smooth left/right swiping while keeping `InteractiveViewer` zoom intact.
3. Top AppBar adds a Face detection toggle button next to the existing Body toggle (`_showFaces`), and a Google Lens action button calling native `antigravity/lens` with `FileProvider` URI and graceful fallback.

**Tech Stack:** Flutter, Dart, Drift, Android Kotlin (FileProvider, MethodChannel, Intent).

---

### Task 1: Add `ids(MediaFilter)` to `MediaQueries` and update route parameters

**Files:**
- Modify: `mobile/lib/data/repositories/media_queries.dart`
- Modify: `mobile/lib/core/router.dart`
- Modify: `mobile/lib/features/library/media_grid.dart`
- Modify: `mobile/lib/features/people/person_detail_screen.dart`
- Test: `mobile/test/data/media_queries_test.dart` (or new test)

**Step 1: Write test for `MediaQueries.ids`**
Verify `ids(filter)` returns ordered media IDs according to `MediaFilter` (by taken_at / modified_at descending, then id descending).

**Step 2: Implement `ids` in `MediaQueries`**
Execute customSelect querying `m.id` with the filter's WHERE clause and standard ordering.

**Step 3: Update `MediaGrid` & `person_detail_screen.dart`**
Pass the active `MediaFilter` parameters in query strings when pushing `Routes.media`.

**Step 4: Update `router.dart`**
Parse `personId`, `scan`, `hasFaces`, and `kind` query parameters into `MediaFilter` and pass to `MediaScreen`.

---

### Task 2: Implement Face Box Toggle in `MediaScreen` & `VideoMediaView`

**Files:**
- Modify: `mobile/lib/features/media/media_screen.dart`
- Modify: `mobile/lib/features/media/video_media_view.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_localizations.dart`
- Modify: `mobile/lib/l10n/app_localizations_en.dart`
- Test: `mobile/test/features/media_screen_test.dart`

**Step 1: Add localization strings**
Add `showFaces` ("Show faces") and `hideFaces` ("Hide faces").

**Step 2: Add `_showFaces` state and AppBar toggle button**
In `MediaScreen`, add `var _showFaces = true;` and `IconButton(key: Key('toggle-faces'), icon: Icon(_showFaces ? Icons.face : Icons.face_outlined))`.

**Step 3: Wire `_showFaces` into photo and video view**
In `_AnnotatedPhoto`, conditionally render face detections based on `showFaces`.
In `VideoMediaView`, pass `showFaces` and filter face detections accordingly.

---

### Task 3: Implement Google Lens native channel and action button

**Files:**
- Create: `mobile/android/app/src/main/res/xml/file_paths.xml`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Modify: `mobile/android/app/src/main/kotlin/com/antigravity/antigravity_mobile/MainActivity.kt`
- Modify: `mobile/lib/features/media/media_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_localizations.dart`
- Modify: `mobile/lib/l10n/app_localizations_en.dart`

**Step 1: Configure FileProvider and Package Queries**
Add `file_paths.xml`, register `androidx.core.content.FileProvider`, and add `<package android:name="com.google.ar.lens"/>` in `AndroidManifest.xml`.

**Step 2: Implement `antigravity/lens` in `MainActivity.kt`**
Receive `path`, generate FileProvider URI, attempt `com.google.ar.lens`, then `com.google.android.googlequicksearchbox`, then generic chooser.

**Step 3: Add Google Lens button in `MediaScreen`**
Add `IconButton(key: Key('google-lens'), icon: Icon(Icons.camera_alt_outlined))` that resolves the image file and invokes `antigravity/lens`.

---

### Task 4: Implement Swipe Navigation (`PageView`) in `MediaScreen`

**Files:**
- Modify: `mobile/lib/features/media/media_screen.dart`
- Test: `mobile/test/features/media_screen_test.dart`

**Step 1: Upgrade `MediaScreen` to load ID list and build `PageView.builder`**
- Asynchronously load `_mediaIds` from `mediaQueriesProvider.ids(filter)`.
- Maintain active `_currentIndex`, update `_currentMediaId` on swipe.
- Dynamically bind AppBar timestamp, detections, and `_WhoIsHere` to the current photo.
- Keep `InteractiveViewer` zoom functional without interfering with page swiping when unzoomed.

**Step 2: Verify with widget tests**
Test swiping between multiple photos, toggling face and body boxes, and tapping the Google Lens button.
