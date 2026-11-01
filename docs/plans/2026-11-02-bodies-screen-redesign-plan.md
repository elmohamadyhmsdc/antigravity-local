# Implementation Plan: Bodies Screen Modernization, High-Precision Pose Matching & Universal Naming

**Target:** `mobile/lib/features/bodies/` & `mobile/lib/domain/pose/`  
**Date:** 2026-11-02  
**Prerequisites:** All prior tasks verified.

---

### Task 1: High-Precision Pose Matching Engine
- **Files to Modify/Create:**
  - `mobile/lib/domain/pose/pose_descriptor.dart`
  - `mobile/lib/domain/pose/pose_index.dart`
  - `mobile/test/domain/pose_matching_precision_test.dart` (New Test)
- **Changes:**
  - In `pose_index.dart`:
    - Include `tags` and `spineTilt` in `_Candidate` records and query from `body_pose_features`.
    - In `_rankIsolated`:
      - **Orientation Gating:** If query has `back`, exclude any candidate with `frontal` or `profile` (and vice versa).
      - **Posture Gating:** If query is `standing`, reject candidates tagged `sitting`, `lying`, or with contradictory posture.
      - **Bending / Torso Angle Gating:** If query is upright standing (`spineTilt < 22°`), reject candidates that are bent over (`spineTilt > 35°`). If query is bent over, reject candidates that are upright standing.
    - Tighten `sigma` from `0.35` to `0.22`.
    - Enforce similarity cutoff: `similarity >= 0.65` and `coverage >= 0.70`.
- **Verification:**
  - `cd mobile; flutter test test/domain/pose_matching_precision_test.dart`

---

### Task 2: Interactive Body Crop Skeleton & Area Overlay
- **Files to Modify/Create:**
  - `mobile/lib/features/bodies/pose_visuals.dart`
  - `mobile/test/features/body_overlay_painter_test.dart` (New Test)
- **Changes:**
  - Implement `BodyCropAnnotatedView`:
    - Wraps `CropImage` with `CustomPaint` overlays.
    - Paints normalized 17-keypoint skeleton lines and joint dots (`x_crop = (kp.x - bboxX) / bboxW`, `y_crop = (kp.y - bboxY) / bboxH`).
    - Paints soft geometric highlight over active area (`chest`, `lower`, `torso`, `limbs`, or equipment rect).
    - Exposes controls for `showSkeleton` and `showArea`.
- **Verification:**
  - `cd mobile; flutter test test/features/body_overlay_painter_test.dart`

---

### Task 3: Modern Body Inspection Sheet (`BodyInspectionSheet`)
- **Files to Modify/Create:**
  - `mobile/lib/features/bodies/body_inspection_sheet.dart` (New Widget)
  - `mobile/lib/features/bodies/bodies_screen.dart` (Integrate with tap)
  - `mobile/test/features/body_inspection_sheet_test.dart` (New Test)
- **Changes:**
  - Create `BodyInspectionSheet`:
    - Prominent `BodyCropAnnotatedView` with on-screen toggle buttons:
      - Toggle Pose Skeleton (`Icons.accessibility_new`).
      - Toggle Area Highlight (`Icons.highlight_alt`).
    - Info card showing detected orientation (`Frontal`, `Back`, `Profile`), posture (`Standing`, `Sitting`), and confidence.
    - Quick actions: Similar Pose (strict), Similar Outfit, Name Pose, Name Outfit, Mark Tattoo, Open Photo.
- **Verification:**
  - `cd mobile; flutter test test/features/body_inspection_sheet_test.dart`

---

### Task 4: Universal Naming & In-Place Renaming
- **Files to Modify/Create:**
  - `mobile/lib/features/bodies/body_naming.dart`
  - `mobile/lib/features/bodies/body_areas.dart`
  - `mobile/lib/features/bodies/equipment_screens.dart`
  - `mobile/test/features/body_universal_naming_test.dart` (New Test)
- **Changes:**
  - Add `renamePoseCategory(db, id, newName)` and inline edit button on pose cards in `_CategoryList`.
  - Add `renameOutfitCategory(db, id, newName)` and inline edit button on outfit cards in `_CategoryList`.
  - Add `renameGroupPose(db, id, newName)` on group pose cards.
  - Add direct `Rename Label` on equipment cards in `EquipmentTab`.
  - In `BodyAreasTab`:
    - Add custom cluster naming persisted in `settings` table (`cluster.name.<id>`).
    - Add `Rename` button on cluster cards allowing users to give friendly names like "Dragon Chest Tattoo" or whatever they choose for chest, buttocks, or any exposed region.
    - Add direct Person assignment/re-linking button with `pickPerson` to link/change the person this area belongs to.
- **Verification:**
  - `cd mobile; flutter test test/features/body_universal_naming_test.dart`

---

### Task 5: 6-Tab Screen UI/UX Overhaul
- **Files to Modify/Create:**
  - `mobile/lib/features/bodies/bodies_screen.dart`
  - Update `test/features/bodies_screen_test.dart`
- **Changes:**
  - Complete Material 3 visual polish: 16dp rounded cards, clear count badges, streamlined chips.
  - Wire up the 6 tabs seamlessly (`All`, `Poses`, `Outfits`, `Group poses`, `Equipment`, `Areas`).
  - Wire all body tile taps to `BodyInspectionSheet`.
- **Verification:**
  - `cd mobile; flutter test test/features/bodies_screen_test.dart`

---

### Task 6: Static Analysis, Regressions & Handoff Update
- **Files to Modify:**
  - `docs/ANTIGRAVITY_HANDOFF.md`
- **Changes:**
  - Run `flutter analyze` across `mobile/`.
  - Run existing test suites (`test/features/`, `test/domain/`).
  - Record changed files, exact verification results, and state in `ANTIGRAVITY_HANDOFF.md`.
