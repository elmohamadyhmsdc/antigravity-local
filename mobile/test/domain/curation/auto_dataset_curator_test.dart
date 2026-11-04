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

      const curator = AutoDatasetCurator(preferExposed: true);
      final scoreClothed = curator.scoreCandidate(clothedCandidate);
      final scoreExposed = curator.scoreCandidate(exposedCandidate);

      expect(scoreExposed, greaterThan(scoreClothed));
      expect(scoreExposed - scoreClothed, greaterThanOrEqualTo(50.0));
    });

    test(
      'allocates candidates into balanced category buckets up to target count',
      () {
        final candidates = <CurationCandidate>[];
        // 10 face candidates
        for (int i = 0; i < 10; i++) {
          candidates.add(
            CurationCandidate(
              detectionId: 100 + i,
              mediaId: 1000 + i,
              assetId: 'asset_face_$i',
              isVideo: false,
              category: CurationCategory.face,
              quality: 0.7 + (i * 0.02),
            ),
          );
        }
        // 8 upper body candidates
        for (int i = 0; i < 8; i++) {
          candidates.add(
            CurationCandidate(
              detectionId: 200 + i,
              mediaId: 2000 + i,
              assetId: 'asset_upper_$i',
              isVideo: false,
              category: CurationCategory.upper,
              quality: 0.75,
              extent: 'upper',
            ),
          );
        }
        // 10 full body candidates
        for (int i = 0; i < 10; i++) {
          candidates.add(
            CurationCandidate(
              detectionId: 300 + i,
              mediaId: 3000 + i,
              assetId: 'asset_body_$i',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
              hasExposedRegion: i < 4,
              skinRatio: i < 4 ? 0.7 : 0.2,
            ),
          );
        }

        const curator = AutoDatasetCurator(
          preferExposed: true,
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
      },
    );

    test(
      'spreads the faces over head poses and photos instead of seven copies of the best',
      () {
        final candidates = <CurationCandidate>[
          // five near-identical frontal shots of one sitting (one photo, different crops), very high quality
          for (var i = 0; i < 5; i++)
            CurationCandidate(
              detectionId: i,
              mediaId: 1,
              assetId: 'sitting',
              isVideo: false,
              category: CurationCategory.face,
              quality: 0.95,
              yaw: 2.0 + i,
              pitch: 1.0,
            ),
          // less perfect but different: profile, tilted-up, tilted-down, three-quarter
          for (final (i, pose) in [
            (40.0, 0.0),
            (-35.0, 5.0),
            (0.0, 25.0),
            (10.0, -20.0),
          ].indexed)
            CurationCandidate(
              detectionId: 100 + i,
              mediaId: 10 + i,
              assetId: 'other_$i',
              isVideo: false,
              category: CurationCategory.face,
              quality: 0.7,
              yaw: pose.$1,
              pitch: pose.$2,
            ),
        ];

        final faces = const AutoDatasetCurator(
          targetFaceCount: 5,
        ).curate(candidates).faces;

        expect(
          faces.where((c) => c.mediaId == 1).length,
          1,
          reason: 'one pick per sitting',
        );
        expect(
          faces.map((c) => c.detectionId).toSet().containsAll([
            100,
            101,
            102,
            103,
          ]),
          isTrue,
        );
      },
    );

    test(
      'one face seen again in other photos is a single training picture',
      () {
        final candidates = [
          for (var i = 0; i < 4; i++)
            CurationCandidate(
              detectionId: i,
              mediaId: 1 + i,
              assetId: 'dup_$i',
              isVideo: false,
              category: CurationCategory.face,
              quality: 0.9,
              yaw: 0,
              refId: 7, // the same stored face, linked from four photos
            ),
          const CurationCandidate(
            detectionId: 50,
            mediaId: 60,
            assetId: 'another',
            isVideo: false,
            category: CurationCategory.face,
            quality: 0.6,
            yaw: 30,
            refId: 8,
          ),
        ];

        final faces = const AutoDatasetCurator().curate(candidates).faces;

        expect(faces.where((c) => c.refId == 7), hasLength(1));
        expect(faces, hasLength(2));
      },
    );

    test('a low-quality face is not padded in just to reach the target', () {
      final faces = const AutoDatasetCurator().curate([
        const CurationCandidate(
          detectionId: 1,
          mediaId: 1,
          assetId: 'a',
          isVideo: false,
          category: CurationCategory.face,
          quality: 0.9,
        ),
        const CurationCandidate(
          detectionId: 2,
          mediaId: 2,
          assetId: 'b',
          isVideo: false,
          category: CurationCategory.face,
          quality: 0.3,
        ),
      ]).faces;

      expect(faces.map((c) => c.detectionId), [1]);
    });

    test(
      'bodies are not all one outfit and exposed ones never fill every slot',
      () {
        List<double> outfit(int hue) =>
            List.generate(80, (i) => i % 40 == hue ? 1.0 : 0.0);
        final candidates = [
          for (var i = 0; i < 6; i++)
            CurationCandidate(
              detectionId: i,
              mediaId: 100 + i,
              assetId: 'red_$i',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
              hasExposedRegion: true,
              skinRatio: 0.7,
              appearance: outfit(3),
            ),
          for (var i = 0; i < 4; i++)
            CurationCandidate(
              detectionId: 50 + i,
              mediaId: 200 + i,
              assetId: 'clothed_$i',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
              appearance: outfit(10 + i * 7),
            ),
        ];

        final bodies = const AutoDatasetCurator(
          targetBodyCount: 5,
        ).curate(candidates).body;

        // switch off (the default): nothing is preferred - the outfits are what spreads the picks
        expect(bodies.length, 5);
        expect(
          bodies.where((c) => !c.hasExposedRegion).length,
          greaterThanOrEqualTo(3),
        );
      },
    );

    test(
      'the switch ON ranks exposed bodies first, up to 90% of the slots - not every slot',
      () {
        List<double> outfit(int hue) =>
            List.generate(80, (i) => i % 40 == hue ? 1.0 : 0.0);
        final candidates = [
          for (var i = 0; i < 12; i++)
            CurationCandidate(
              detectionId: i,
              mediaId: 100 + i,
              assetId: 'exposed_$i',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
              hasExposedRegion: true,
              skinRatio: 0.7,
              appearance: outfit(i),
            ),
          for (var i = 0; i < 4; i++)
            CurationCandidate(
              detectionId: 50 + i,
              mediaId: 200 + i,
              assetId: 'clothed_$i',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
              appearance: outfit(20 + i),
            ),
        ];

        final on = const AutoDatasetCurator(
          targetBodyCount: 10,
          preferExposed: true,
        ).curate(candidates).body;

        expect(
          on.where((c) => c.hasExposedRegion).length,
          9,
          reason: '90% of 10 slots',
        );
        // and the score itself: off = no bonus at all
        const same = CurationCandidate(
          detectionId: 1,
          mediaId: 1,
          assetId: 'a',
          isVideo: false,
          category: CurationCategory.body,
          quality: 0.8,
          extent: 'full',
          hasExposedRegion: true,
          skinRatio: 0.7,
        );
        expect(
          const AutoDatasetCurator().scoreCandidate(same),
          const AutoDatasetCurator().scoreCandidate(
            const CurationCandidate(
              detectionId: 2,
              mediaId: 2,
              assetId: 'b',
              isVideo: false,
              category: CurationCategory.body,
              quality: 0.8,
              extent: 'full',
            ),
          ),
        );
      },
    );

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
