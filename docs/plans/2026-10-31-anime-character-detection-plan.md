# Anime & Character Unified Detection Implementation Plan

> **For Claude / Agent:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable seamless, automatic detection of anime/cartoon faces and bodies across all photos and videos without requiring special album tagging, routing real humans to `People` and anime characters to `Characters` with complete profile management.

**Architecture:** A dual-detector server pipeline (`SCRFD` for humans + YOLOv8 `AnimeFaceDetector` for anime) with an overlap veto rule (IoU $\ge 0.5$ or containment $\ge 0.6$) to protect infants, geometry gates to drop text/stickers, and CCIP character identity embedding for robust profile clustering. The mobile app scans all media uniformly and stores character profiles in SQLCipher/Drift with full naming and merging support.

**Tech Stack:** Python 3.10, ONNX Runtime (CUDA), NumPy, OpenCV, YOLOv8, CCIP, Flutter/Dart, Drift (SQLCipher).

---

### Task 1: Stage Models & Implement Python Anime Face Detector (`anime_detector.py`)

**Files:**
- Create: `the app/models/anime_face_detect.onnx` (copy from `d:\test\face gallary\app\src\main\assets\models\anime_face_detect.onnx`)
- Create: `the app/models/ccip_character.onnx` (copy from `d:\test\face gallary\app\src\main\assets\models\ccip_character.onnx`)
- Create: `the app/anime_detector.py`
- Test: `the app/test_anime_detector.py`

**Step 1: Copy models into local models folder**
Copy `anime_face_detect.onnx` (44.5 MB) and `ccip_character.onnx` (150 MB) into `D:\AndroidScan\gallary\the app\models\`.

**Step 2: Write failing test for `anime_detector.py`**
Create `the app/test_anime_detector.py` with tests for:
- Static/dynamic input size handling
- Letterbox image scaling and padding
- Aspect ratio filtering ($0.35 \le w/h \le 1.8$)
- Minimum size filtering ($\ge 20$ px)
- NMS filtering of duplicate boxes

**Step 3: Implement `the app/anime_detector.py`**
Implement `AnimeFaceDetector`:
- Letterbox preprocessing (padding with 114/255)
- ONNX Runtime session execution on CUDA (with CPU fallback)
- YOLOv8 channel-major / anchor-major output decoder
- Geometry filters (`MIN_FACE_AR`, `MAX_FACE_AR`, `MIN_FACE_PX`)
- NMS suppression and bounding box un-letterbox conversion

**Step 4: Run test to verify it passes**
Run: `.\venv\Scripts\python.exe -m unittest test_anime_detector.py`
Expected: PASS

**Step 5: Commit task**
Git commit Task 1.

---

### Task 2: Implement Face Overlap & Baby-Face Veto (`face_routing.py`)

**Files:**
- Create: `the app/face_routing.py`
- Test: `the app/test_face_routing.py`

**Step 1: Write failing test for `face_routing.py`**
Test cases:
- `overlaps_real_face`: IoU $\ge 0.5$ triggers veto.
- `overlaps_real_face`: Containment $\ge 0.6$ triggers veto even when IoU $< 0.5$.
- Independent non-overlapping boxes do not veto.
- Real infant simulation: SCRFD detection at veto threshold ($0.40$) suppresses overlapping anime detection.

**Step 2: Implement `the app/face_routing.py`**
Implement:
- `box_iou(box1, box2)`
- `box_containment(box1, box2)`
- `overlaps_real_face(real_box, anime_box, iou_thresh=0.5, containment_thresh=0.6)`
- `route_detections(real_dets, anime_dets)` separating human detections from anime detections.

**Step 3: Run test to verify it passes**
Run: `.\venv\Scripts\python.exe -m unittest test_face_routing.py`
Expected: PASS

**Step 4: Commit task**
Git commit Task 2.

---

### Task 3: Character Appearance & CCIP Embedder (`character_embedder.py`)

**Files:**
- Create: `the app/character_embedder.py`
- Test: `the app/test_character_embedder.py`

**Step 1: Write failing test for `character_embedder.py`**
Test cases:
- Output dimension is 768-d (or 792-d with hue features) L2-normalized.
- Graceful fallback if `ccip_character.onnx` is missing.
- Crop extraction above head (hat/hair) and below face (torso outfit).

**Step 2: Implement `the app/character_embedder.py`**
Implement:
- `CcipEmbedder` using `ccip_character.onnx`
- Asymmetric character portrait cropping ($0.8h$ above, $1.2h$ below, $0.5w$ sides)
- Outfit and hat hue histogram extraction
- L2-normalization of combined feature vector

**Step 3: Run test to verify it passes**
Run: `.\venv\Scripts\python.exe -m unittest test_character_embedder.py`
Expected: PASS

**Step 4: Commit task**
Git commit Task 3.

---

### Task 4: Integrate Dual-Detector Pipeline in `the app/analysis.py`

**Files:**
- Modify: `the app/analysis.py`
- Modify: `the app/mobile_api/engines.py`
- Test: `the app/test_character.py` and `the app/test_analysis.py`

**Step 1: Update `analyze_frame()` in `the app/analysis.py`**
- Always run `AnimeFaceDetector` in addition to `SCRFD`.
- Apply `FaceDedup.overlaps_real_face` veto against SCRFD detections at threshold $0.40$.
- Pair surviving anime face boxes with body detections (from HumanArt or YOLOX).
- Generate CCIP appearance vector for each character.
- Populate `FrameAnalysis.characters` with `DetectedCharacter` (bbox, face crop, appearance vector, score, body_bbox).

**Step 2: Run server regression tests**
Run: `.\venv\Scripts\python.exe -m unittest test_character.py test_analysis.py`
Expected: PASS

**Step 3: Commit task**
Git commit Task 4.

---

### Task 5: Mobile Unified Scan & Always-On Character Detection (`mobile/`)

**Files:**
- Modify: `mobile/lib/domain/scan/scan_engine.dart`
- Modify: `mobile/lib/features/scan/sources_screen.dart`
- Modify: `mobile/lib/domain/scan/photo_result_store.dart`
- Test: `mobile/test/domain/scan_engine_test.dart` and `mobile/test/domain/photo_result_store_test.dart`

**Step 1: Update `scan_engine.dart`**
- Set `detectCharacters: true` unconditionally for all analyzed media.
- Remove check requiring albums to be in `characterAlbums`.

**Step 2: Update `sources_screen.dart`**
- Clean up album-specific illustrated toggle so users simply pick what folders to scan.

**Step 3: Update `photo_result_store.dart`**
- Ensure `newCharacters` are stored directly into `CharacterRepository` with their face and body boxes.

**Step 4: Run flutter tests**
Run: `flutter test test/domain/photo_result_store_test.dart`
Expected: PASS

**Step 5: Commit task**
Git commit Task 5.

---

### Task 6: Mobile Characters UI & Profile Features (`mobile/`)

**Files:**
- Modify: `mobile/lib/features/characters/characters_screen.dart`
- Modify: `mobile/lib/features/characters/character_detail_screen.dart` (if needed)
- Modify: `mobile/lib/features/people/people_screen.dart`
- Test: `mobile/test/features/characters_test.dart`

**Step 1: Verify and polish `CharactersScreen`**
- Ensure character cards display cover, name (or "Unnamed"), and photo/video count.
- Ensure tapping opens the detail screen with rename, merge, and photo grid.
- Prominent navigation button in `people_screen.dart` to open `Characters`.

**Step 2: Run Flutter tests and analyzer**
Run: `flutter analyze` and `flutter test test/features/`
Expected: 0 issues, PASS.

**Step 3: Commit task**
Git commit Task 6.

---

### Task 7: End-to-End Verification & Handoff Update

**Files:**
- Update: `docs/ANTIGRAVITY_HANDOFF.md`

**Step 1: Verify whole pipeline**
Run Python backend and Flutter test suites.

**Step 2: Update handoff**
Document changed files, added models, verification results, and limits.
