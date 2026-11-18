import 'dart:typed_data';

import 'package:antigravity_mobile/data/platform/crop_source.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';
import 'package:antigravity_mobile/domain/curation/training_view.dart';
import 'package:antigravity_mobile/domain/export/crop_math.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements CropSource {
  int? time;
  PxRect? rect;
  (int, int)? output;
  @override
  Future<SourceFrame?> open({
    required String assetId,
    required bool video,
    int? timeMs,
  }) async {
    time = timeMs;
    return const SourceFrame(rawWidth: 2000, rawHeight: 1000, orientation: 6);
  }

  @override
  Future<Uint8List?> crop(
    SourceFrame frame,
    PxRect rect, {
    required int outWidth,
    required int outHeight,
    int quality = 95,
  }) async {
    this.rect = rect;
    output = (outWidth, outHeight);
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> close() async {}
}

void main() {
  CurationCandidate candidate({
    int? time = 3750,
    bool manual = false,
    String? outline,
    CurationCategory category = CurationCategory.body,
  }) => CurationCandidate(
    detectionId: 12,
    mediaId: 17,
    assetId: 'source',
    isVideo: true,
    refId: 7,
    category: category,
    timestampMs: time,
    boxX: 0.1,
    boxY: 0.2,
    boxW: 0.4,
    boxH: 0.7,
    manualBody: manual,
    outline: outline,
  );

  test(
    'use the chosen time, upright pixels, aspect and aligned silhouette',
    () async {
      final source = _Source();
      final result = await readTrainingView(
        source,
        candidate(manual: true, outline: '[0,0,1,0,0.5,1]'),
      );
      expect(source.time, 3750);
      expect(source.rect, const PxRect(76, 316, 448, 1568));
      expect(source.output, (439, 1536));
      expect(result!.view, 'confirmed_body');
      const near = 3 / 56, far = 1 - near;
      for (final (i, expected) in [near, near, far, near, 0.5, far].indexed) {
        expect(result.outline![i], closeTo(expected, 1e-6));
      }
    },
  );

  test('missing video time does not train on frame zero', () async {
    final source = _Source();
    expect(await readTrainingView(source, candidate(time: null)), isNull);
    expect(source.rect, isNull);
  });

  test(
    'ordinary body stays face-verified and portrait uses no body mask',
    () async {
      final source = _Source();
      final body = await readTrainingView(
        source,
        candidate(outline: 'bad json'),
      );
      expect(body!.view, 'body');
      expect(body.outline, isNull);
      final face = await readTrainingView(
        source,
        candidate(category: CurationCategory.face, outline: '[0,0,1,0,0,1]'),
      );
      expect(face!.view, 'portrait');
      expect(face.outline, isNull);
    },
  );
}
