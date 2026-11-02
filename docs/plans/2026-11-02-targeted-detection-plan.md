# Targeted Detection & In-Viewer Correction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable on-demand, high-accuracy detection and in-place correction directly inside the media viewer for exposed areas (user-named), bodies (overcoming 640 downsampling weaknesses), faces (native ROI), and objects (open-vocabulary), with interactive box resizing and video track scope support.

**Architecture:** A unified `POST /v1/analyze/targeted` endpoint on the PC FastAPI server leverages Florence-2 grounding, NudeNet 640m, RTMPose, and InsightFace. On Flutter, an interactive ROI drawing overlay and targeted detection sheet communicate with `TargetedDetectionService`, persisting results to Drift database Schema v19 (`Bodies`, `Faces`, `SensitiveRegions`, `EquipmentObjects`, and override tables) with instant Undo and video ScopePicker.

**Tech Stack:** Python 3 (FastAPI, PyTorch, Florence-2, OpenCV, NudeNet, RTMPose, InsightFace) and Flutter 3 (Dart, Riverpod, Drift, GoRouter).

---

### Task 1: Server API & Engine for Targeted Analysis

**Files:**
- Create: `the app/test_targeted_analysis.py`
- Modify: `the app/mobile_api/routes_analyze.py`
- Modify: `the app/mobile_api/schemas.py`
- Modify: `the app/mobile_api/engines.py`

**Step 1: Write the failing test**
Create `the app/test_targeted_analysis.py` verifying `POST /v1/analyze/targeted` for `body`, `area`, `face`, and `object` with and without an `roi` parameter.

**Step 2: Run test to verify it fails**
Run: `python -m unittest the\ app/test_targeted_analysis.py`
Expected: FAIL with 404 Not Found or missing endpoint.

**Step 3: Write minimal implementation**
Implement `POST /v1/analyze/targeted` in `the app/mobile_api/routes_analyze.py`, parse options in `schemas.py`, and wire targeted inference handlers in `engines.py`.

**Step 4: Run test to verify it passes**
Run: `python -m unittest the\ app/test_targeted_analysis.py`
Expected: PASS

**Step 5: Commit**
```bash
git add "the app/mobile_api" "the app/test_targeted_analysis.py"
git commit -m "feat(api): add targeted analysis endpoint with multi-engine routing"
```

---

### Task 2: Mobile DTOs & API Client

**Files:**
- Create: `mobile/lib/data/api/dtos/targeted.dart`
- Modify: `mobile/lib/data/api/mobile_api.dart`
- Test: `mobile/test/data/api/targeted_api_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/data/api/targeted_api_test.dart` asserting request construction, multipart form-data serialization (with normalized `roi`), and parsing of `TargetedAnalysisResponse`.

**Step 2: Run test to verify it fails**
Run: `cd mobile ; flutter test test/data/api/targeted_api_test.dart`
Expected: FAIL (types not defined).

**Step 3: Write minimal implementation**
Define `TargetedRequest` and `TargetedAnalysisResponse` in `dtos/targeted.dart` and add `analyzeTargeted(...)` to `MobileApi`.

**Step 4: Run test to verify it passes**
Run: `cd mobile ; flutter test test/data/api/targeted_api_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add mobile/lib/data/api/ mobile/test/data/api/
git commit -m "feat(mobile): implement targeted analysis DTOs and API client method"
```

---

### Task 3: Domain Service & Database Integration (Schema v19)

**Files:**
- Create: `mobile/lib/domain/corrections/targeted_detection_service.dart`
- Modify: `mobile/lib/library_providers.dart`
- Test: `mobile/test/domain/corrections/targeted_detection_service_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/domain/corrections/targeted_detection_service_test.dart` testing persisting a new targeted body/area/face/object into `AppDatabase`, recording entries in `body_overrides`/`face_overrides`, and rolling back via snapshot Undo.

**Step 2: Run test to verify it fails**
Run: `cd mobile ; flutter test test/domain/corrections/targeted_detection_service_test.dart`
Expected: FAIL.

**Step 3: Write minimal implementation**
Implement `TargetedDetectionService` saving entities with appropriate ownership and linking, recording override records, and providing undo snapshots.

**Step 4: Run test to verify it passes**
Run: `cd mobile ; flutter test test/domain/corrections/targeted_detection_service_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add mobile/lib/domain/corrections/ mobile/lib/library_providers.dart mobile/test/domain/corrections/
git commit -m "feat(domain): implement TargetedDetectionService with Schema v19 persistence and undo"
```

---

### Task 4: Interactive ROI Selection & Box Adjustment Overlay

**Files:**
- Create: `mobile/lib/features/media/roi_selection_overlay.dart`
- Modify: `mobile/lib/features/media/detection_overlay.dart`
- Test: `mobile/test/features/media/roi_selection_overlay_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/features/media/roi_selection_overlay_test.dart` verifying drag-to-draw ROI, dragging corner and edge handles to resize, and normalized coordinate conversion.

**Step 2: Run test to verify it fails**
Run: `cd mobile ; flutter test test/features/media/roi_selection_overlay_test.dart`
Expected: FAIL.

**Step 3: Write minimal implementation**
Implement `RoiSelectionOverlay` with custom gesture recognizers, visual handles, and callback returning normalized `BBox`.

**Step 4: Run test to verify it passes**
Run: `cd mobile ; flutter test test/features/media/roi_selection_overlay_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add mobile/lib/features/media/ mobile/test/features/media/
git commit -m "feat(viewer): implement interactive ROI selection and box resizing overlay"
```

---

### Task 5: Targeted Detection Sheet, Naming & In-Viewer Integration

**Files:**
- Create: `mobile/lib/features/inspector/targeted_detect_sheet.dart`
- Modify: `mobile/lib/features/media/media_chrome.dart`
- Modify: `mobile/lib/features/media/media_viewer_screen.dart`
- Modify: `mobile/lib/features/inspector/media_inspector.dart`
- Test: `mobile/test/features/media/targeted_detect_ux_test.dart`

**Step 1: Write the failing test**
Create `mobile/test/features/media/targeted_detect_ux_test.dart` verifying:
1. Tapping "Detect" opens category selection (Areas, Bodies, Faces, Objects).
2. Choosing "Draw Box" engages ROI overlay.
3. Submitting triggers detection and opens naming sheet for custom area or person assignment.
4. Box is rendered, added to inspector, and adjustable.
5. In video, ScopePicker appears.

**Step 2: Run test to verify it fails**
Run: `cd mobile ; flutter test test/features/media/targeted_detect_ux_test.dart`
Expected: FAIL.

**Step 3: Write minimal implementation**
Implement `TargetedDetectSheet`, add `Detect` button to `MediaChromeBottomBar`, connect ROI overlay to `MediaViewerScreen`, and add custom naming/ScopePicker dialogs.

**Step 4: Run test to verify it passes**
Run: `cd mobile ; flutter test test/features/media/targeted_detect_ux_test.dart`
Expected: PASS

**Step 5: Commit**
```bash
git add mobile/lib/features/ mobile/test/features/media/
git commit -m "feat(viewer): wire targeted detection sheet, naming dialog, and viewer chrome"
```

---

### Task 6: Final Verification & Documentation

**Files:**
- Modify: `docs/ANTIGRAVITY_HANDOFF.md`

**Step 1: Run static analysis**
Run: `cd mobile ; dart analyze lib test`
Expected: No issues found!

**Step 2: Run full test suite**
Run: `cd mobile ; flutter test`
Expected: All tests pass.

**Step 3: Update documentation**
Update `docs/ANTIGRAVITY_HANDOFF.md` with targeted detection capabilities, endpoints, and test verification evidence.

**Step 4: Commit**
```bash
git add docs/ANTIGRAVITY_HANDOFF.md
git commit -m "docs(handoff): document targeted detection and in-viewer editing release"
```
