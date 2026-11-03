import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Drawn (anime, cartoon, manga) and other non-human faces, told apart by the face embedding.
///
/// The detector fires on drawn faces and scores many of them as good faces, but the recogniser
/// maps them near one shared direction that real faces stay away from: every usable real face
/// measured <= 0.13 on it, drawn faces 0.13-0.62 (95% >= 0.18). Such a face is never a person,
/// so it is not stored, grouped or reviewed. Kept identical to `the app/drawn_faces.py`
/// (measurements there; `test_drawn_faces.py` checks both files agree).
const drawnFaceMinScore = 0.20;

/// The test is only trusted on a face at least this big (tiny / blurred real faces drift toward the
/// drawn direction); same as `analysis.DRAWN_TEST_MIN_PX`.
const drawnTestMinPx = 48.0;

const _directionB64 =
    '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';

/// Unit mean of the drawn faces' embeddings.
final Float32List drawnFaceDirection = Uint8List.fromList(
  base64Decode(_directionB64),
).buffer.asFloat32List();

/// Cosine between [embedding] (any length scale) and the drawn-face direction.
double drawnFaceScore(List<double> embedding) {
  if (embedding.length != drawnFaceDirection.length) return 0;
  var dot = 0.0, norm = 0.0;
  for (var i = 0; i < embedding.length; i++) {
    dot += embedding[i] * drawnFaceDirection[i];
    norm += embedding[i] * embedding[i];
  }
  if (norm == 0 || !norm.isFinite) return 0;
  return dot / math.sqrt(norm);
}

/// True for a drawn or non-human face: never a person.
bool isDrawnFace(List<double> embedding) =>
    drawnFaceScore(embedding) >= drawnFaceMinScore;
