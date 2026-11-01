# Design Document: Bodies Screen Modernization, High-Precision Pose Matching & Universal Naming

**Date:** 2026-11-02  
**Context:** Redesign of the Bodies & Discovery screen (`BodiesScreen`) and its sub-features, elevating body/pose/outfit/equipment/area discovery to first-class parity with Faces and People.

---

## 1. Problem Statement & User Needs

1. **Lack of Visual Inspection & Parity with Faces:**
   - In `MediaScreen`, faces have interactive bounding boxes, names, and inspection.
   - In `BodiesScreen`, bodies are displayed only as raw static crops. Users cannot see the skeleton wireframe (COCO-17 keypoints and bones) or visual highlights of the detected/selected body area (chest, lower body, limbs, torso, equipment) overlaid on the body.
2. **Sloppy / Inaccurate Pose Similarity ("المقارنة بالويام"):**
   - The current pose similarity search (`PoseIndex.findSimilar`) only computes a generic distance on 8+ points without orientation gating or posture angle gating.
   - Consequently:
     - A person facing away from the camera (Back) gets matched with someone facing forward (Frontal).
     - A person bending over from the back gets matched with someone standing upright from the back.
     - Unrelated poses match because of loose Gaussian sigma (`0.35`) and zero minimum score cutoff.
3. **Fragmented & Incomplete Naming ("والـ user يقدر يسمي كل حاجة"):**
   - Users cannot easily rename existing saved poses, outfits, group poses, equipment labels, or body area clusters.
   - Area clusters have robotic system titles like `Chest cluster #1` with no custom naming.
4. **Scope & Structure Decisions:**
   - **Decision 1 (Option B):** The interactive inspection toggle (Pose skeleton wireframe & Area highlight) will be in the individual body details/inspection view (keeping the main grid clean and uncluttered).
   - **Decision 2:** Retain all 6 tabs in `BodiesScreen`:
     - `All` (الكل)
     - `Poses` (الوضعيات)
     - `Outfits` (الملابس)
     - `Group poses` (الوضعيات الجماعية)
     - `Equipment` (الأدوات)
     - `Areas` (المناطق)

---

## 2. Architecture & Detailed Specifications

### A. High-Precision Pose Matching Engine (`pose_descriptor.dart` & `pose_index.dart`)
1. **Orientation Compatibility Gating:**
   - `PoseTag.orientation`: `frontal`, `profile`, `back`.
   - Rule: Two poses with conflicting orientation tags MUST NEVER match (e.g., `back` query rejects `frontal` or `profile` candidates; `frontal` query rejects `back`).
2. **Posture & Torso Angle Compatibility Gating:**
   - `PoseTag.posture`: `standing`, `sitting`, `lying`.
   - Torso spine tilt & bending guard:
     - Compare spine tilt (`spineTilt`) and torso flexion angle between query and candidate.
     - If query is upright standing (`tilt < 20°`), reject candidates with bent torso (`tilt > 35°` or flexion angle `< 150°`).
     - If query is bending over (`tilt > 35°`), reject candidates that are standing upright.
3. **Calibrated Distance & Strict Score Threshold:**
   - Tighten `sigma` from `0.35` to `0.22` for precision.
   - Enforce minimum similarity cutoff: `similarity >= 0.65` and `coverage >= 0.70`. Poses below this threshold are strictly pruned.

### B. Interactive Body Inspection & Overlay (`pose_visuals.dart` & `body_inspection_sheet.dart`)
1. **Interactive Inspection Modal:**
   - When tapping any body card/tile across all tabs, open the redesigned `BodyInspectionSheet`.
   - Features:
     - Zoomable high-resolution body crop preview.
     - **Pose Skeleton Toggle (`Icons.accessibility_new`):** Paints COCO-17 keypoints and connected bones with glowing theme-aware lines directly aligned on the body crop (`(x - bboxX) / bboxW`, `(y - bboxY) / bboxH`).
     - **Area Highlight Toggle (`Icons.highlight_alt`):** Overlays soft semitransparent geometric highlight on the detected area (Chest, Lower body / Buttocks, Torso, Limbs, or Equipment bounding box).
     - **Pose & Detection Info Card:** Displays exact orientation (`Frontal`, `Back`, `Profile`), posture (`Standing`, `Sitting`, `Lying`), arm positions, and confidence metrics.
2. **Integrated Quick Actions:**
   - `Find Exact Similar Pose` (high-precision).
   - `Find Matching Outfit`.
   - `Name / Rename Pose`.
   - `Name / Rename Outfit`.
   - `Mark Tattoo / Scar / Mark`.
   - `Open Full Media / Photo`.

### C. Universal Naming & In-Place Renaming
1. **Pose Categories (`PoseCategories`):**
   - Add inline `Rename` action (`Icons.edit_outlined`) on every pose card in the Poses tab.
   - Update `poseCategories.name` in database with instant UI reload.
2. **Outfit Categories (`OutfitCategories`):**
   - Add inline `Rename` action on every outfit card in the Outfits tab.
   - Update `outfitCategories.name` in database with instant UI reload.
3. **Group Poses:**
   - Add inline `Rename` action on group pose cards.
4. **Equipment (`EquipmentObjects`):**
   - Add direct `Rename Label` on equipment cards to rename any detected item (e.g., from generic label to "Wilson Tennis Racket").
5. **Body Area Clusters & Exposed Regions (`BodyAreasTab` / `BodyClusters`):**
   - **Custom Naming at User's Will:** Allow users to freely name any detected area/cluster (Chest, Buttocks, or any detected exposed region) according to their own preference (e.g., "تاتو التنين على الصدر", "منطقة الصدر", "أرداف رياضية", "ندبة الظهر").
   - Persist custom names in `settings` table (`cluster.name.<id>`) and display prominently as the primary title on the card with a localized badge for the anatomical region (`Chest`, `Buttocks`, etc.).
   - **Person Assignment & Re-linking ("ربط المناطق ببني آدم"):** Prominent person chip on the card showing who the area belongs to (`Belongs to: Name`), with an interactive button to assign, change, or re-link the area to any person via `pickPerson()`, which propagates to all cluster member bodies.

### D. UI/UX Overhaul (Material 3 & 6-Tab Streamlining)
- Consistent card styling: 16dp rounded corners, subtle elevation, clear typographic hierarchy.
- Responsive grid and card sizing (respecting large text scale and screen boundaries).
- Smooth tab switching with preserved state and instant in-memory rendering.

---

## 3. Verification Plan
- Unit tests for strict pose matching (orientation mismatch rejection, bending mismatch rejection, threshold filtering).
- Widget tests for the inspection sheet (pose skeleton toggle, area highlight toggle).
- Widget/Integration tests for universal renaming across Poses, Outfits, Equipment, and Clusters.
- Static analysis clean (`flutter analyze`).
