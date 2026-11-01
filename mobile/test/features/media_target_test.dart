import 'dart:typed_data';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/features/shared/media_target.dart';
import 'package:flutter_test/flutter_test.dart';

DetectedFace face(BBox box) => DetectedFace(
  bbox: box,
  kps: const [],
  detScore: 1,
  embedding: Float32List(512),
  quality: const FaceQuality(
    score: 1,
    version: 1,
    parts: {},
    detScore: 1,
    facePx: 100,
    sharpness: 1,
    embeddingNorm: 1,
    pose: null,
  ),
  passesGate: true,
);
AnalyzeImageResponse response(List<DetectedFace> faces) => AnalyzeImageResponse(
  modelId: 'test',
  imageW: 100,
  imageH: 100,
  faces: faces,
  bodies: const [],
  pairs: const [],
);
const target = MediaDetection(
  id: 1,
  kind: 'f',
  refId: 2,
  x: .5,
  y: .1,
  w: .3,
  h: .3,
  personId: 8,
  cropPath: null,
);
void main() {
  test('matches only the explicitly selected occurrence', () {
    expect(
      matchTargetFace(
        response([
          face(const BBox(x: 0, y: 10, w: 30, h: 30)),
          face(const BBox(x: 50, y: 10, w: 30, h: 30)),
        ]),
        target,
      ),
      1,
    );
  });
  test('leaves uncertain and ambiguous matches for the user', () {
    expect(
      matchTargetFace(
        response([face(const BBox(x: 0, y: 0, w: 20, h: 20))]),
        target,
      ),
      isNull,
    );
    expect(
      matchTargetFace(
        response([
          face(const BBox(x: 50, y: 10, w: 30, h: 30)),
          face(const BBox(x: 50, y: 10, w: 30, h: 30)),
        ]),
        target,
      ),
      isNull,
    );
  });
}
