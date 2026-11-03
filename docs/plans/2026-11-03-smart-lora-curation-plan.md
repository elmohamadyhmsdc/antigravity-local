# Smart LoRA Dataset Auto-Curation & Review Screen Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement automated smart curation of training datasets for Character LoRA on mobile, prioritizing minimal clothing / exposed body visibility for anatomical accuracy, with an interactive, categorized mobile review screen (close-ups, upper body, full body & minimal clothes) supporting instant deletion, Undo, and manual additions.

**Architecture:**
- Domain Layer: `AutoDatasetCurator` scoring algorithm implementing hierarchical body ranking (`sensitive_regions` exposed -> high `skin_mask` ratio -> full extent fallback), face quality, and video keyframe de-duplication into 3 quota buckets.
- Data Layer: `CurationQueries` querying Drift SQLite across `media`, `media_detections`, `faces`, `bodies`, and `sensitive_regions`.
- Feature Layer: `CurationController` managing reactive state, item removals with reversible Undo, and `CurationReviewScreen` providing a thumb-zone mobile UI with segmented category tabs, live quality indicator, settings drawer, and sticky submit bar.
- Router & Studio Integration: Connect `/studio/curation/:personId` to Person Detail and Studio screens.

**Tech Stack:** Flutter, Dart, Riverpod, Drift (SQLite), Material 3, PhotoManager.

---

### Task 1: Curation Domain Models & Hierarchical Scoring Algorithm

**Files:**
- Create: `mobile/lib/domain/curation/auto_dataset_curator.dart`
- Test: `mobile/test/domain/curation/auto_dataset_curator_test.dart`

**Step 1: Write the failing test**

Create `mobile/test/domain/curation/auto_dataset_curator_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';

void main() {
  group('AutoDatasetCurator', () {
    test('prioritizes exposed body regions over clothed bodies', () {
      final clothedCandidate = CurationCandidate(
        detectionId: 1,
        mediaId: 101,
        assetId: 'asset_1',
        isVideo: false,
        category: CurationCategory.body,
        quality: 0.8,
        extent: 'full',
        hasExposedRegion: false,
        skinRatio: 0.15,
      );

      final exposedCandidate = CurationCandidate(
        detectionId: 2,
        mediaId: 102,
        assetId: 'asset_2',
        isVideo: false,
        category: CurationCategory.body,
        quality: 0.8,
        extent: 'full',
        hasExposedRegion: true,
        skinRatio: 0.65,
      );

      final curator = AutoDatasetCurator();
      final scoreClothed = curator.scoreCandidate(clothedCandidate);
      final scoreExposed = curator.scoreCandidate(exposedCandidate);

      expect(scoreExposed, greaterThan(scoreClothed));
      expect(scoreExposed - scoreClothed, greaterThanOrEqualTo(50.0));
    });

    test('allocates candidates into balanced category buckets up to target count', () {
      final candidates = <CurationCandidate>[];
      // 10 face candidates
      for (int i = 0; i < 10; i++) {
        candidates.add(CurationCandidate(
          detectionId: 100 + i,
          mediaId: 1000 + i,
          assetId: 'asset_face_$i',
          isVideo: false,
          category: CurationCategory.face,
          quality: 0.7 + (i * 0.02),
        ));
      }
      // 8 upper body candidates
      for (int i = 0; i < 8; i++) {
        candidates.add(CurationCandidate(
          detectionId: 200 + i,
          mediaId: 2000 + i,
          assetId: 'asset_upper_$i',
          isVideo: false,
          category: CurationCategory.upper,
          quality: 0.75,
          extent: 'upper',
        ));
      }
      // 10 full body candidates
      for (int i = 0; i < 10; i++) {
        candidates.add(CurationCandidate(
          detectionId: 300 + i,
          mediaId: 3000 + i,
          assetId: 'asset_body_$i',
          isVideo: false,
          category: CurationCategory.body,
          quality: 0.8,
          extent: 'full',
          hasExposedRegion: i < 4,
          skinRatio: i < 4 ? 0.7 : 0.2,
        ));
      }

      final curator = AutoDatasetCurator(
        targetFaceCount: 7,
        targetUpperCount: 5,
        targetBodyCount: 8,
      );

      final result = curator.curate(candidates);

      expect(result.faces.length, 7);
      expect(result.upper.length, 5);
      expect(result.body.length, 8);
      expect(result.totalCount, 20);
      // All 4 exposed bodies should be included in body bucket
      expect(result.body.where((b) => b.hasExposedRegion).length, 4);
    });

    test('deduplicates video keyframes closer than minimum time gap', () {
      final candidates = <CurationCandidate>[
        CurationCandidate(
          detectionId: 1,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 1000,
          quality: 0.6,
          category: CurationCategory.face,
        ),
        CurationCandidate(
          detectionId: 2,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 1400, // Only 400ms apart from #1, should be dropped
          quality: 0.9,      // Higher quality, so #2 replaces #1
          category: CurationCategory.face,
        ),
        CurationCandidate(
          detectionId: 3,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 3500, // 2100ms apart, keep
          quality: 0.7,
          category: CurationCategory.face,
        ),
      ];

      final curator = AutoDatasetCurator(minVideoGapMs: 1500);
      final deduplicated = curator.deduplicateVideoFrames(candidates);

      expect(deduplicated.length, 2);
      expect(deduplicated.any((c) => c.detectionId == 2), isTrue);
      expect(deduplicated.any((c) => c.detectionId == 3), isTrue);
    });
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test mobile/test/domain/curation/auto_dataset_curator_test.dart
```
Expected: FAIL with compilation error: `auto_dataset_curator.dart` not found.

**Step 3: Write minimal implementation in `mobile/lib/domain/curation/auto_dataset_curator.dart`**

```dart
enum CurationCategory { face, upper, body }

class CurationCandidate {
  const CurationCandidate({
    required this.detectionId,
    required this.mediaId,
    required this.assetId,
    required this.isVideo,
    required this.category,
    this.quality = 0.5,
    this.extent,
    this.hasExposedRegion = false,
    this.skinRatio = 0.0,
    this.timestampMs,
    this.frameNumber,
    this.yaw,
    this.pitch,
    this.boxW,
    this.boxH,
  });

  final int detectionId;
  final int mediaId;
  final String assetId;
  final bool isVideo;
  final CurationCategory category;
  final double quality;
  final String? extent;
  final bool hasExposedRegion;
  final double skinRatio;
  final int? timestampMs;
  final int? frameNumber;
  final double? yaw, pitch;
  final double? boxW, boxH;

  double get boxArea => (boxW ?? 0.3) * (boxH ?? 0.3);
}

class CurationResult {
  const CurationResult({
    required this.faces,
    required this.upper,
    required this.body,
  });

  final List<CurationCandidate> faces;
  final List<CurationCandidate> upper;
  final List<CurationCandidate> body;

  int get totalCount => faces.length + upper.length + body.length;
  List<CurationCandidate> get all => [...faces, ...upper, ...body];
}

class AutoDatasetCurator {
  const AutoDatasetCurator({
    this.targetFaceCount = 7,
    this.targetUpperCount = 5,
    this.targetBodyCount = 8,
    this.minVideoGapMs = 1500,
  });

  final int targetFaceCount;
  final int targetUpperCount;
  final int targetBodyCount;
  final int minVideoGapMs;

  double scoreCandidate(CurationCandidate c) {
    switch (c.category) {
      case CurationCategory.face:
        final angleWeight = c.yaw != null ? (1.0 - (c.yaw!.abs() / 180.0)) : 0.8;
        return (c.quality * 50.0) + (angleWeight * 30.0) + (c.boxArea * 20.0);

      case CurationCategory.upper:
        return (c.quality * 40.0) + (c.skinRatio * 30.0) + (c.boxArea * 30.0);

      case CurationCategory.body:
        double score = c.quality * 20.0;
        if (c.hasExposedRegion) {
          score += 100.0; // Top Tier: sensitive/exposed regions detected
        } else if (c.skinRatio > 0.4) {
          score += 50.0 + (c.skinRatio * 30.0); // High Tier: swimwear / light clothes
        } else if (c.skinRatio > 0.2) {
          score += 30.0 + (c.skinRatio * 20.0);
        }
        if (c.extent == 'full') {
          score += 20.0;
        } else if (c.extent == 'knee') {
          score += 10.0;
        }
        return score;
    }
  }

  List<CurationCandidate> deduplicateVideoFrames(List<CurationCandidate> candidates) {
    final nonVideo = candidates.where((c) => !c.isVideo).toList();
    final videoByMedia = <int, List<CurationCandidate>>{};
    for (final c in candidates.where((c) => c.isVideo)) {
      videoByMedia.putIfAbsent(c.mediaId, () => []).add(c);
    }

    final keptVideo = <CurationCandidate>[];
    for (final list in videoByMedia.values) {
      list.sort((a, b) => (a.timestampMs ?? 0).compareTo(b.timestampMs ?? 0));
      CurationCandidate? lastKept;
      for (final item in list) {
        if (lastKept == null) {
          lastKept = item;
          keptVideo.add(item);
        } else {
          final diff = (item.timestampMs ?? 0) - (lastKept.timestampMs ?? 0);
          if (diff >= minVideoGapMs) {
            lastKept = item;
            keptVideo.add(item);
          } else if (item.quality > lastKept.quality) {
            // Replace with higher quality frame in same window
            keptVideo.removeLast();
            lastKept = item;
            keptVideo.add(item);
          }
        }
      }
    }
    return [...nonVideo, ...keptVideo];
  }

  CurationResult curate(List<CurationCandidate> allCandidates) {
    final clean = deduplicateVideoFrames(allCandidates);

    final facePool = clean.where((c) => c.category == CurationCategory.face).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final upperPool = clean.where((c) => c.category == CurationCategory.upper).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final bodyPool = clean.where((c) => c.category == CurationCategory.body).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final selectedFaces = facePool.take(targetFaceCount).toList();
    final selectedUpper = upperPool.take(targetUpperCount).toList();
    final selectedBody = bodyPool.take(targetBodyCount).toList();

    return CurationResult(
      faces: selectedFaces,
      upper: selectedUpper,
      body: selectedBody,
    );
  }
}
```

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test mobile/test/domain/curation/auto_dataset_curator_test.dart
```
Expected: All tests pass.

**Step 5: Commit**

```bash
git add mobile/lib/domain/curation/auto_dataset_curator.dart mobile/test/domain/curation/auto_dataset_curator_test.dart
git commit -m "feat(curation): implement AutoDatasetCurator with hierarchical body ranking and video deduplication"
```

---

### Task 2: Database Query Provider for Curation Candidates

**Files:**
- Create: `mobile/lib/data/repositories/curation_queries.dart`
- Test: `mobile/test/data/curation_queries_test.dart`

**Step 1: Write the failing test**

Create `mobile/test/data/curation_queries_test.dart` testing candidate extraction from SQLite across `media`, `faces`, `bodies`, and `sensitive_regions`.

**Step 2: Run test to verify it fails**

Run: `flutter test mobile/test/data/curation_queries_test.dart`  
Expected: FAIL (file missing).

**Step 3: Implement `CurationQueries`**

In `mobile/lib/data/repositories/curation_queries.dart`:
- Implement `loadCandidatesForPerson(int personId)`:
  - Query faces for person (mapping to `CurationCategory.face`).
  - Query upper bodies (`extent == 'upper'`, mapping to `CurationCategory.upper`).
  - Query full bodies (`extent == 'full' | 'knee'`), joining with `sensitive_regions` to detect `hasExposedRegion` and estimating `skinRatio`.
  - Exclude items where `hidden == 1` or `ownership == 'none'`.

**Step 4: Run test to verify it passes**

Run: `flutter test mobile/test/data/curation_queries_test.dart`  
Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/data/repositories/curation_queries.dart mobile/test/data/curation_queries_test.dart
git commit -m "feat(curation): implement CurationQueries repository joining faces, bodies, and sensitive regions"
```

---

### Task 3: Curation State Controller & Reversible Undo

**Files:**
- Create: `mobile/lib/features/lora/curation_controller.dart`
- Test: `mobile/test/features/curation_controller_test.dart`

**Step 1: Write the failing test**

Test `CurationNotifier`:
- `removeItem` decreases count and pushes item to undo stack.
- `undoLastRemoval` pops item and restores it to its specific category.
- `addItems` appends new items.
- `updateTriggerWord` updates trigger word.

**Step 2: Run test to verify it fails**

Run: `flutter test mobile/test/features/curation_controller_test.dart`  
Expected: FAIL.

**Step 3: Implement `CurationController`**

In `mobile/lib/features/lora/curation_controller.dart`:
- Define `CurationState`:
  - `faces`: List<CurationCandidate>
  - `upper`: List<CurationCandidate>
  - `body`: List<CurationCandidate>
  - `triggerWord`: String
  - `faceDetailerEnabled`: bool
  - `resolutionMode`: String ('512x768')
  - `lastRemoved`: CurationCandidate?
- Methods: `removeItem(CurationCandidate)`, `undoRemove()`, `addItems(List<CurationCandidate>, CurationCategory)`, `setTriggerWord(String)`.

**Step 4: Run test to verify it passes**

Run: `flutter test mobile/test/features/curation_controller_test.dart`  
Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/features/lora/curation_controller.dart mobile/test/features/curation_controller_test.dart
git commit -m "feat(curation): implement CurationController with category management and reversible undo"
```

---

### Task 4: Mobile Curation & Review Screen (`CurationReviewScreen`)

**Files:**
- Create: `mobile/lib/features/lora/curation_review_screen.dart`
- Test: `mobile/test/features/curation_review_screen_test.dart`

**Step 1: Write the failing test**

Create `mobile/test/features/curation_review_screen_test.dart`:
- Pump `CurationReviewScreen` with mock candidates.
- Verify status pill displays total item count.
- Verify category segmented filter taps switch visible cards.
- Verify tapping `✕` removes a card and displays SnackBar with "تراجع ↩".
- Verify tapping settings gear opens drawer.

**Step 2: Run test to verify it fails**

Run: `flutter test mobile/test/features/curation_review_screen_test.dart`  
Expected: FAIL.

**Step 3: Implement `CurationReviewScreen`**

In `mobile/lib/features/lora/curation_review_screen.dart`:
- Match the validated interactive prototype:
  - Header with title, close button, settings gear button (`Key('curation-settings')`).
  - Live Quality Pill (`Key('curation-status-pill')`).
  - Segmented Category Filter Bar: `الكل`, `👤 ملامح`, `👕 نصف جسم`, `🔥 كامل وأقل لبس`.
  - Photo grid with responsive aspect ratios, badges (`كشف عالي`, `🎬 mm:ss`), and delete button (`Key('curation-delete-$id')`).
  - Floating SnackBar for Undo (`Key('curation-undo')`).
  - Settings Bottom Sheet (`Key('curation-settings-sheet')`).
  - Sticky bottom action bar with `+ إضافة` (`Key('curation-add')`) and `بدء تدريب الموديل الآن ⚡` (`Key('curation-submit')`).

**Step 4: Run test to verify it passes**

Run: `flutter test mobile/test/features/curation_review_screen_test.dart`  
Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/features/lora/curation_review_screen.dart mobile/test/features/curation_review_screen_test.dart
git commit -m "feat(ui): implement CurationReviewScreen with live quality pill, segmented tabs, and bottom drawer"
```

---

### Task 5: Router & Studio Navigation Integration

**Files:**
- Modify: `mobile/lib/core/router.dart`
- Modify: `mobile/lib/features/studio/studio_screen.dart`
- Modify: `mobile/lib/features/people/person_detail_screen.dart`
- Test: `mobile/test/core/router_test.dart`

**Step 1: Write the failing test**

Add route test verifying `/studio/curation/:personId` navigates to `CurationReviewScreen`.

**Step 2: Run test to verify it fails**

Run: `flutter test mobile/test/core/router_test.dart`  
Expected: FAIL.

**Step 3: Implement route and navigation wiring**

- In `router.dart`: Add `Routes.studioCuration = '/studio/curation/:id'` pointing to `CurationReviewScreen(personId: id)`.
- In `studio_screen.dart`: When tapping "Train/LoRA", if person selected, open `Routes.studioCuration`.
- In `person_detail_screen.dart`: Add "Train Character LoRA" action navigating directly to `Routes.studioCuration`.

**Step 4: Run test to verify it passes**

Run: `flutter test mobile/test/core/router_test.dart`  
Expected: PASS.

**Step 5: Commit**

```bash
git add mobile/lib/core/router.dart mobile/lib/features/studio/studio_screen.dart mobile/lib/features/people/person_detail_screen.dart mobile/test/core/router_test.dart
git commit -m "feat(router): register studio curation route and wire navigation from Studio and Person Detail"
```

---

## Final Verification Checklist

1. **Static Analysis:**
   - `flutter analyze mobile/` reports 0 issues.
2. **Unit & Widget Tests:**
   - `flutter test mobile/test/domain/curation/` passes 100%.
   - `flutter test mobile/test/data/curation_queries_test.dart` passes 100%.
   - `flutter test mobile/test/features/curation_review_screen_test.dart` passes 100%.
   - `flutter test mobile/test/core/router_test.dart` passes 100%.
3. **Regression Safety:**
   - Baseline suite preserved with no regressions.
4. **Handoff Documentation:**
   - Update `docs/ANTIGRAVITY_HANDOFF.md` with verification metrics and results.
