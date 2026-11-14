# AI Photo Editor (Clothes & Object Inpainting) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement interactive AI photo editing on mobile (Flutter) and PC server, allowing users to select any object or clothes via smart tap or brush, and perform seamless inpainting removal (Big-LaMa) or prompt-guided replacement (Diffusion Inpainting) while preserving 100% of unselected pixels.

**Architecture:** The Flutter mobile app adds a dedicated `PhotoEditScreen` with an interactive drawing canvas (pinch/zoom, brush, eraser, undo/redo, smart tap) accessible from the media viewer. It submits an `edit_image` job containing the upright photo and PNG mask to the PC server. The PC server lifts historical person/clothing restrictions in `photo_edit.py` and `photo_edit_worker.py` to support object and clothing edits, executing Big-LaMa for removal and Diffusion Inpainting for prompt replacements with lossless boundary compositing.

**Tech Stack:** 
- Mobile: Flutter (Dart), CustomPainter, Riverpod, GoRouter, Drift SQLite.
- Server: Python 3.10, PyTorch, Big-LaMa, Realistic Vision / Stable Diffusion Inpainting, OpenCV, Pillow.

---

### Task 1: Server-side Photo Edit Engine Update (`photo_edit.py` & `photo_edit_worker.py`)

**Files:**
- Modify: `the app/photo_edit.py:52-78, 133-150`
- Modify: `the app/photo_edit_worker.py:72-80`
- Test: `the app/test_photo_edit.py`

**Step 1: Write the failing server test**
Add a test in `the app/test_photo_edit.py` asserting that clothing/person mask overlapping does NOT raise `PhotoEditError`, and that replacement prompt validation permits clothing/garment descriptions.

```python
def test_clothing_and_person_selection_is_permitted():
    from photo_edit import check_protection, validate_options
    # Dummy body/face boxes
    boxes = [[50.0, 50.0, 200.0, 300.0]]
    mask = np.zeros((400, 400), dtype=np.uint8)
    mask[100:200, 100:200] = 1 # overlapping body/clothes
    # Must not raise PhotoEditError
    check_protection(mask, boxes)
    
    # Prompt with garment replacement must be accepted
    opts = validate_options({'operation': 'replace', 'instruction': 'elegant red silk evening dress'})
    assert opts['operation'] == 'replace'
    assert 'red silk evening dress' in opts['instruction']
```

**Step 2: Run test to verify it fails**
Command:
```powershell
$galleryPython = 'D:\AndroidScan\gallary\the app\venv\Scripts\python.exe'
& $galleryPython 'D:\AndroidScan\gallary\the app\test_photo_edit.py'
```
Expected: FAIL with `PhotoEditError: The selection overlaps a protected person.`

**Step 3: Implement minimal engine changes**
1. In `the app/photo_edit.py`:
   - In `validate_options`: Allow clothing replacement phrases (remove clothing-related keywords from blocking regex).
   - In `check_protection`: Remove blanket body rejection. Only check for invalid geometries, allowing user to mask clothes or objects.
2. In `the app/photo_edit_worker.py`:
   - Update prompt formatting to avoid prepending "inanimate objects only" or putting "people, person, human, face, body" into the negative prompt when replacing clothes or objects. Use a neutral high-quality prompt and standard negative prompt (`'deformed, bad anatomy, artifacts, blurry, low quality, distorted, watermark, text'`).

**Step 4: Run test to verify it passes**
Command:
```powershell
& $galleryPython 'D:\AndroidScan\gallary\the app\test_photo_edit.py'
```
Expected: PASS (all tests pass).

**Step 5: Commit changes**
```bash
git add "the app/photo_edit.py" "the app/photo_edit_worker.py" "the app/test_photo_edit.py"
git commit -m "feat(engine): permit clothing and object selection in photo editor"
```

---

### Task 2: Flutter Drawing Canvas & Selection State (`mobile/lib/features/photo_edit/`)

**Files:**
- Create: `mobile/lib/features/photo_edit/selection_model.dart`
- Create: `mobile/lib/features/photo_edit/mask_builder.dart`
- Test: `mobile/test/features/photo_edit_canvas_test.dart`

**Step 1: Write failing Flutter unit test**
Create `mobile/test/features/photo_edit_canvas_test.dart` testing:
- Stroke addition, undo, redo, clear.
- MaskBuilder converts strokes on canvas to a valid 8-bit PNG mask of matching aspect ratio with white (255) foreground and black (0) background.

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/photo_edit/selection_model.dart';
import 'package:mobile/features/photo_edit/mask_builder.dart';

void main() {
  test('SelectionModel supports stroke recording, undo, redo, and clear', () {
    final model = SelectionModel();
    expect(model.canUndo, isFalse);
    model.addStroke(const SelectionStroke(points: [Offset(0.1, 0.1), Offset(0.2, 0.2)], radius: 0.05));
    expect(model.canUndo, isTrue);
    expect(model.strokes.length, 1);
    model.undo();
    expect(model.strokes.length, 0);
    expect(model.canRedo, isTrue);
    model.redo();
    expect(model.strokes.length, 1);
  });

  test('MaskBuilder generates valid normalized PNG mask bytes', () async {
    final model = SelectionModel();
    model.addStroke(const SelectionStroke(points: [Offset(0.5, 0.5)], radius: 0.1));
    final pngBytes = await MaskBuilder.buildMaskPng(model, width: 200, height: 200);
    expect(pngBytes, isNotNull);
    expect(pngBytes.length, greaterThan(50));
    // Verify PNG magic signature
    expect(pngBytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
```

**Step 2: Run test to verify it fails**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_canvas_test.dart
```
Expected: FAIL (compilation error, missing files).

**Step 3: Implement `selection_model.dart` and `mask_builder.dart`**
1. Implement `SelectionStroke` (points, stroke width/radius, isEraser flag).
2. Implement `SelectionModel` (undo stack, redo stack, strokes list, bounding boxes).
3. Implement `MaskBuilder` using Flutter's `PictureRecorder` and `Canvas` to render the strokes into an `ui.Image` and encode as PNG bytes (`toByteData(format: ui.ImageByteFormat.png)`).

**Step 4: Run test to verify it passes**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_canvas_test.dart
```
Expected: PASS.

**Step 5: Commit changes**
```bash
git add mobile/lib/features/photo_edit/selection_model.dart mobile/lib/features/photo_edit/mask_builder.dart mobile/test/features/photo_edit_canvas_test.dart
git commit -m "feat(mobile): add photo edit selection model and mask builder"
```

---

### Task 3: Flutter Interactive Photo Edit Screen (`PhotoEditScreen`)

**Files:**
- Create: `mobile/lib/features/photo_edit/photo_edit_screen.dart`
- Test: `mobile/test/features/photo_edit_screen_test.dart`

**Step 1: Write failing widget test**
Create `mobile/test/features/photo_edit_screen_test.dart`:
- Verifies initial rendering with photo.
- Verifies tool switching between Brush, Eraser, and Pan/Zoom.
- Verifies operation switching between Remove and Replace.
- Verifies prompt field appearance when Replace is selected.
- Verifies Generate button disabled when mask is empty, enabled when mask has strokes.

**Step 2: Run test to verify it fails**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_screen_test.dart
```
Expected: FAIL (missing `photo_edit_screen.dart`).

**Step 3: Implement `PhotoEditScreen`**
1. Custom interactive canvas:
   - Uses `InteractiveViewer` with `TransformationController` for pinch-to-zoom and pan.
   - Drawing overlay intercepts touch events when Brush or Eraser tool is active.
   - Smart Tap: detects tapped position and seeds selection contour.
2. Bottom action bar:
   - Tool selection: Brush, Eraser, Pan/Move mode.
   - Brush radius slider.
   - Undo, Redo, Clear buttons.
   - Segmented buttons: Remove / Replace.
   - Prompt `TextField` (when Replace is selected) with hint/placeholder.
   - "Generate" button invoking `studioRepository.enqueueInputs` with `edit_image` job.
3. Result overlay:
   - Shows Before/After toggle.
   - Save copy button (saves edited image to gallery).
   - Re-edit button.

**Step 4: Run test to verify it passes**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_screen_test.dart
```
Expected: PASS.

**Step 5: Commit changes**
```bash
git add mobile/lib/features/photo_edit/photo_edit_screen.dart mobile/test/features/photo_edit_screen_test.dart
git commit -m "feat(mobile): implement interactive AI photo edit screen"
```

---

### Task 4: Flutter Routing, Viewer Menu Integration & Localization

**Files:**
- Modify: `mobile/lib/core/router.dart:45-120, 200-300`
- Modify: `mobile/lib/features/media/media_viewer_screen.dart:303-349`
- Modify: `mobile/lib/features/jobs/jobs_screen.dart:27-35`
- Test: `mobile/test/features/photo_edit_navigation_test.dart`

**Step 1: Write failing navigation test**
Create `mobile/test/features/photo_edit_navigation_test.dart`:
- Verifies `media_viewer_screen.dart` Studio menu contains the "AI Edit" action tile.
- Verifies clicking "AI Edit" routes to `/photo-edit?media=:id`.

**Step 2: Run test to verify it fails**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_navigation_test.dart
```
Expected: FAIL.

**Step 3: Implement route and menu changes**
1. In `mobile/lib/core/router.dart`:
   - Add `Routes.photoEdit = '/photo-edit'`.
   - Add route entry for `/photo-edit` instantiating `PhotoEditScreen(mediaId: mediaId)`.
2. In `mobile/lib/features/media/media_viewer_screen.dart`:
   - Inside `_showStudioMenu`, add ListTile:
     - Leading: `Icon(Icons.auto_fix_high)`
     - Title: `Text('AI Edit / تعديل الصورة')`
     - Action: `context.push('${Routes.photoEdit}?media=${media.id}')`
3. In `mobile/lib/features/jobs/jobs_screen.dart`:
   - Update `jobTypeLabel` to return `'AI Edit · ' + l10n.resultPhoto` for `'edit_image'`.

**Step 4: Run test to verify it passes**
Command:
```powershell
cd mobile
flutter test test/features/photo_edit_navigation_test.dart
```
Expected: PASS.

**Step 5: Commit changes**
```bash
git add mobile/lib/core/router.dart mobile/lib/features/media/media_viewer_screen.dart mobile/lib/features/jobs/jobs_screen.dart mobile/test/features/photo_edit_navigation_test.dart
git commit -m "feat(mobile): wire AI photo edit route and viewer menu entry"
```

---

### Task 5: End-to-End Verification & Handoff Update

**Files:**
- Modify: `docs/ANTIGRAVITY_HANDOFF.md`

**Step 1: Run comprehensive verification**
1. Run `flutter analyze` on the mobile project:
   ```powershell
   cd mobile
   flutter analyze
   ```
   Must pass with 0 errors and 0 warnings.
2. Run full mobile test suite:
   ```powershell
   cd mobile
   flutter test test/features/photo_edit_canvas_test.dart test/features/photo_edit_screen_test.dart test/features/photo_edit_navigation_test.dart
   ```
3. Run server validation tests:
   ```powershell
   $galleryPython = 'D:\AndroidScan\gallary\the app\venv\Scripts\python.exe'
   & $galleryPython 'D:\AndroidScan\gallary\the app\test_photo_edit.py'
   ```

**Step 2: Update `docs/ANTIGRAVITY_HANDOFF.md`**
Record:
- Date: 2026-11-14.
- Implemented AI Photo Editor in Flutter app with smart tap and brush selection for clothing and objects.
- Updated `the app/photo_edit.py` and `photo_edit_worker.py` to lift blanket person/clothing restrictions and support clothing inpainting with prompts and LaMa removal.
- Exact tests run and results.
- Instructions to build `app-release.apk` for the Samsung Galaxy A72.

**Step 3: Commit handoff update**
```bash
git add docs/ANTIGRAVITY_HANDOFF.md
git commit -m "docs: update handoff with AI photo editor implementation"
```
