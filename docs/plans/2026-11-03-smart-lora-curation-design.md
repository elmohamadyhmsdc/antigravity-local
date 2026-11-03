# Smart LoRA Dataset Auto-Curation & Review Design

**Date**: 2026-11-03  
**Status**: Approved & Ready for Planning  
**Target Surface**: Mobile Studio (`mobile/lib/features/lora/`), Curation Domain (`mobile/lib/domain/curation/`), Backend Dataset Job (`the app/lora_dataset.py`)

---

## 1. Problem & Goal

Currently, creating a training dataset for a Character LoRA requires the user to manually select and upload individual photos or falls back to an unranked sequential pass of detected faces. For full-body generation, training requires an optimal balance between:
1. High-fidelity facial identity (close-up portraits).
2. Upper body & neck/shoulder continuity.
3. True body proportions and anatomical geometry (full-body shots).

When users train models on photos with bulky, loose, or heavy clothing, the model learns the clothing silhouette rather than the person's true body proportions. To solve this, the system must **automatically curate the optimal 15–25 training crops**, giving **top priority to images with minimal clothing / exposed skin**, while presenting a streamlined mobile review screen where users can inspect, delete, or add photos before training starts.

---

## 2. Mobile User Experience (Categorized Grid & Progressive Disclosure)

The interface is optimized for mobile ergonomics (Thumb-Zone, $\ge 44\text{px}$ touch targets, fast gestures):

### 2.1 Header & Status Pill
- **Header**: Person avatar, name, close button, and training settings gear (`⚙️`).
- **Live Quality Indicator**: Floating pill displaying selection health:
  - *Ready (15–25 items)*: Green pulse indicator (`"جاهز: 20 صورة مختارة تلقائياً • جودة ممتازة"`).
  - *Low (< 15 items)*: Amber prompt encouraging the user to add more photos.
  - *Blocked (< 5 items)*: Red error blocking dataset build.

### 2.2 Segmented Category Tabs
Allows instant one-tap switching between categories without overwhelming vertical scrolling:
- **All (الكل - 20)**
- **👤 Close-up Portraits (ملامح - 7)**: Square 1:1 crops focusing on facial details and multi-angle poses.
- **👕 Upper Body (نصف جسم - 5)**: 4:5 crops covering head, neck, shoulders, and skin tone.
- **🔥 Full Body & Minimal Clothes (كامل وأقل لبس - 8)**: 9:16 vertical crops capturing full anatomical proportions with highest body visibility.

### 2.3 Photo Cards & Quick Interactions
- **One-Tap Remove (`✕`)**: Instantly removes the item from the dataset.
- **Undo SnackBar**: 4-second reversible toast (`"تم استبعاد الصورة من التدريب • تراجع ↩"`).
- **Descriptive Badges**:
  - `كشف عالي` (High exposure / minimal clothing).
  - `🎬 00:23` (Keyframe from video; tap to preview video at timestamp).
  - `أمامي / 45°` (Head angle indicator).
- **Card Tap**: Opens full-screen zoom preview with quality metrics.

### 2.4 Progressive Disclosure: Settings Drawer (`⚙️`)
Hides advanced parameters to keep the primary screen uncluttered:
- `Trigger Word`: Defaults to `sks_<person_name>`.
- `Face Detailer Pass`: Toggle for post-generation high-res face inpainting.
- `Resolution & Estimated Time`: 512×768 (~8 minutes on RTX 4050 6GB under 5.0 GB VRAM).

### 2.5 Sticky Bottom Action Bar
- **`+ إضافة` (Add More)**: Opens `MediaPicker` pre-filtered to this person's remaining photos, with a toggle for "All Gallery" or device import.
- **`بدء تدريب الموديل الآن ⚡`**: Primary gradient action button with duration badge (`~8 دقائق`).

---

## 3. Auto-Curator Scoring & Ranking Heuristics

The `AutoDatasetCurator` algorithm scores and ranks every media item where the person appears:

### 3.1 Close-up Portrait Scoring ($Score_{face}$)
Target: 6–8 items.
$$\text{Score}_{face} = \text{Quality} \times \text{IdentityCosine} + (\text{FaceArea} \times 0.05)$$
- Enforces pose diversity across yaw/pitch bins (Frontal, Left 45°, Right 45°, Smile, Neutral).

### 3.2 Upper Body Scoring ($Score_{upper}$)
Target: 4–6 items.
$$\text{Score}_{upper} = (\text{FaceQuality} \times 0.4) + (\text{BodyScore} \times 0.4) + (\text{SkinRatio} \times 0.2)$$

### 3.3 Full Body & Minimal Clothes Scoring ($Score_{body}$) — Hierarchical Priority
Target: 6–8 items.
1. **Tier 1 (+100.0 base score - Top Priority)**:
   Detected sensitive/exposed regions in `sensitive_regions` table with `exposed == true` (chest, buttocks, bare skin contours).
2. **Tier 2 (+50.0 max score - High Priority)**:
   High bare-skin ratio (`skin_mask` area divided by body bounding box area, covering swimwear, athletic wear, minimal clothing).
3. **Tier 3 (+20.0 base score - Standard Fallback)**:
   Head-to-toe visibility (`extent == 'full'`) even if clothed, ensuring the 6–8 target quota is met without stalling.
4. **Deprioritized (-30.0 penalty)**:
   Heavy coats, winter clothing, baggy silhouettes, or severe occlusions.

### 3.4 Video Keyframe Extraction & De-duplication
- Candidate frames from videos must have minimum time separation $\Delta t \ge 1.5\text{ s}$.
- For each interval, only the sharpest keyframe (highest Laplacian variance) is kept.
- Bursts of near-identical photos are filtered (embedding cosine similarity $> 0.95$ drops the lower-quality item).

---

## 4. Architecture & Data Contracts

```
[Mobile Drift Database]
  ├── Media (photos & videos)
  ├── Faces (bboxes, quality_score, yaw, pitch, embeddings)
  ├── Bodies (bboxes, extent, score, morphology)
  └── SensitiveRegions (exposed, label, outline, score)
             │
             ▼
[AutoDatasetCurator (Dart)]
  ├── Evaluates queries & computes composite scores
  ├── Allocates items into 3 quota buckets
  └── Yields CurationState(personId, selectedItems, triggerWord)
             │
             ▼
[CurationReviewScreen (Flutter)]
  ├── Renders segmented categories & interactive cards
  ├── Manages additions (+ MediaPicker) and removals (with Undo)
  └── Dispatches JobCreate
             │
             ▼
[Backend Mobile API (artifact_jobs.py / lora_dataset.py)]
  ├── Receives curated media references + crop coordinates
  ├── Builds sd-scripts dataset folder (repeats, captions via Florence-2/WD14)
  └── Dispatches training job to Kohya sd-scripts
```

---

## 5. Verification & Testing Strategy

1. **Unit Tests (`mobile/test/domain/curation/`):**
   - Verify `AutoDatasetCurator` prioritizes `exposed=true` and high `skin_mask` bodies over clothed bodies.
   - Verify 3-bucket quota fulfillment (e.g. 7 portraits, 5 upper, 8 full body).
   - Verify video keyframe de-duplication ($\ge 1.5\text{s}$ spacing).
2. **Widget Tests (`mobile/test/features/lora/`):**
   - Verify `CurationReviewScreen` renders cards with category tabs.
   - Verify removing an item updates the count and shows the Undo toast.
   - Verify tapping Undo restores the item to its original category.
   - Verify settings drawer opens and updates Trigger Word.
3. **Backend Contract Tests (`the app/test_mobile_studio.py`):**
   - Verify job submission accepts curated items payload without schema error.