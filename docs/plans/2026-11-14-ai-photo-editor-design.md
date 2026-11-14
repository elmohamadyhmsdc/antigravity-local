# AI Photo Editor Design — Clothes & Object Inpainting (Removal & Prompt Replacement)

Date: 2026-11-14
Status: Approved

## 1. Overview & Objective

Enable interactive AI photo editing directly from the mobile app (Flutter) for any photo in the user's gallery or viewer.
Users can:
1. Select any object or any piece of clothing (using a hybrid approach: **Smart Tap-to-Select** + **Manual Brush/Eraser**).
2. Choose between two primary operations:
   - **Remove**: Erases the selected object or clothing and fills the background seamlessly using the high-fidelity Big-LaMa inpainting model.
   - **Replace via Prompt**: Replaces the selected clothing or object according to a text prompt (e.g. "classic black tuxedo", "red summer dress", "vintage wooden chair") using diffusion inpainting, while strictly preserving 100% of all unselected pixels outside the mask.

---

## 2. Architecture & Components

```
┌─────────────────────────────────────────────────────────────┐
│                       Flutter Mobile App                    │
│                                                             │
│  MediaViewerScreen (Menu: "AI Edit")                       │
│         │                                                   │
│         ▼                                                   │
│  PhotoEditScreen (Interactive Canvas)                      │
│   ├─ Smart Tap (Clothes/Object Segmentation)                │
│   ├─ Manual Brush & Eraser (Size slider, Undo/Redo/Clear)   │
│   ├─ Pinch-to-zoom & Pan                                    │
│   └─ Operation Panel (Remove / Replace + Prompt)            │
│         │                                                   │
│         ▼ Enqueue job 'edit_image' (image + mask)           │
│  StudioRepository / JobTracker                              │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTPS /v1/jobs
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      PC Mobile API Server                   │
│                                                             │
│  studio_jobs.py -> dispatch 'edit_image'                    │
│         │                                                   │
│         ▼                                                   │
│  photo_edit.py & photo_edit_worker.py                       │
│   ├─ Lift person/clothing restrictions                      │
│   ├─ Remove: Big-LaMa inpainting engine                     │
│   ├─ Replace: Realistic Vision Inpainting (Diffusion)       │
│   └─ Lossless Composite: Invariant check (100% match       │
│      on unmasked pixels)                                    │
│         │                                                   │
│         ▼ Returns edited_image.png                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Detailed Component Specifications

### 3.1 Mobile App UI (Flutter)

1. **Viewer Entry Point**:
   - Location: `mobile/lib/features/media/media_viewer_screen.dart` (and `media_chrome.dart` / Studio action sheet).
   - Added item: **AI Edit / تعديل بالذكاء الاصطناعي** (`Icons.auto_fix_high`).
   - Route: `/photo-edit?media=:id` (in `mobile/lib/core/router.dart`).

2. **PhotoEditScreen** (`mobile/lib/features/photo_edit/photo_edit_screen.dart`):
   - **Interactive Canvas**:
     - Gesture handling for 2-finger zoom and pan.
     - Single-finger draw/erase when brush or eraser tool is active.
     - Single-finger tap for Smart Tap when smart selection mode is active.
   - **Smart Tap (Segmentation)**:
     - Leverages existing detection outlines or SegFormer clothes parsing to instantly identify tapped garments (upper body, lower body, dress, accessories) or objects and convert them into mask strokes/polygons.
   - **Manual Tooling**:
     - Brush tool with adjustable stroke width slider (0.01 to 0.15 normalized).
     - Eraser tool for carving out or refining edges.
     - Undo, Redo, Clear all strokes.
   - **Operation Controls**:
     - Segmented control / filter chips: **Remove (إزالة)** vs **Replace (استبدال)**.
     - When **Replace** is selected: Prompt input text field (`OutlinedTextField`), supporting English and Arabic instructions.
     - "Generate" action button (`ElevatedButton`), disabled if mask is empty or prompt is missing when in replace mode.
   - **Progress & Cancellation**:
     - Linear progress indicator while processing.
     - Cancel button calling `POST /v1/jobs/{id}/cancel`.
   - **Result & Before/After**:
     - Comparison toggle button: "Show Before" / "Show After".
     - "Save a copy" button: Saves the resulting PNG to the device's MediaStore/Gallery via `photo_manager` or local file export without modifying the original.
     - "Edit again" button to adjust prompt or mask.

### 3.2 Server-Side Engine (`the app/`)

1. **Lifting Clothing/Person Selection Restriction**:
   - In `the app/photo_edit.py`:
     - Update `check_protection(mask, boxes)`:
       Allow selections over clothing, body, and objects. Ensure face geometry is preserved unless intentionally masked by the user.
     - Update instruction validation:
       Permit clothing style descriptions, garment replacements, and item modifications while maintaining core safety standards.

2. **Inpainting Execution**:
   - **Operation: `remove`**:
     - Runs `big-lama.pt` via `photo_edit_worker.py`.
     - Rebuilds background or underlying textures seamlessly.
   - **Operation: `replace`**:
     - Runs diffusion inpainting with the user's prompt (`instruction`).
     - Uses local inpainting model with steps (default 26) and cfg guidance.
   - **Edge Blending & Strict Invariance**:
     - Crop geometry calculation with padding.
     - Distance transform feathering strictly inside the mask boundaries.
     - Assert that `result[mask == 0] == photo[mask == 0]` (zero pixel corruption outside the mask).

---

## 4. Error Handling & Edge Cases

1. **Unpaired or Offline PC**:
   - Display a prompt banner informing the user that the PC GPU server is required, with a quick button to open connection settings.
2. **Empty Selection / Empty Prompt**:
   - Client-side validation prevents submission when no area is selected or when Replace is selected without a prompt.
3. **Orientation & Resolution**:
   - Normalized mask coordinates map to EXIF-upright photo dimensions, ensuring exact alignment regardless of photo rotation or aspect ratio.
4. **Memory Management**:
   - Mask is rendered at preview dimensions and upsampled on the server using `INTER_NEAREST` before compositing, preventing mobile OOM on high-resolution camera photos.

---

## 5. Verification Plan

1. **Backend Verification**:
   - Run unit tests in `the app/test_photo_edit.py`:
     - Verify clothes selection acceptance.
     - Verify Remove operation with Big-LaMa.
     - Verify Replace operation with Diffusion prompt.
     - Verify pixel invariance outside the mask.
2. **Flutter Verification**:
   - Run `flutter analyze` ensuring 0 warnings/errors.
   - Run `flutter test test/features/photo_edit_test.dart` for canvas interaction, tool toggles, and job submission.
3. **APK Release Build**:
   - Build `app-release.apk` with private release signing and install on Samsung Galaxy A72 for on-device validation.
