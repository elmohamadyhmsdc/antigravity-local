import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';

void main() {
  group('AutoDatasetCurator', () {
    test('prioritizes exposed body regions over clothed bodies', () {
      const clothedCandidate = CurationCandidate(
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

      const exposedCandidate = CurationCandidate(
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

      const curator = AutoDatasetCurator();
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

      const curator = AutoDatasetCurator(
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
        const CurationCandidate(
          detectionId: 1,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 1000,
          quality: 0.6,
          category: CurationCategory.face,
        ),
        const CurationCandidate(
          detectionId: 2,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 1400, // Only 400ms apart from #1
          quality: 0.9, // Higher quality, so #2 replaces #1
          category: CurationCategory.face,
        ),
        const CurationCandidate(
          detectionId: 3,
          mediaId: 50,
          assetId: 'vid_1',
          isVideo: true,
          timestampMs: 3500, // 2100ms apart, keep
          quality: 0.7,
          category: CurationCategory.face,
        ),
      ];

      const curator = AutoDatasetCurator(minVideoGapMs: 1500);
      final deduplicated = curator.deduplicateVideoFrames(candidates);

      expect(deduplicated.length, 2);
      expect(deduplicated.any((c) => c.detectionId == 2), isTrue);
      expect(deduplicated.any((c) => c.detectionId == 3), isTrue);
    });
  });
}
