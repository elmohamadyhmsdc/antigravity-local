import 'dart:math' as math;

const characterModelId = 'character-appearance@1';
const characterDescriptorDim = 160;
const characterAutoMatch = .93;
const characterMatchMargin = .06;

/// Versioned appearance evidence, separate from human face embeddings.
/// Mirrors character_detection.similarity on the PC.
double characterSimilarity(List<double> a, List<double> b) {
  if (a.length != characterDescriptorDim ||
      b.length != characterDescriptorDim ||
      a.any((v) => !v.isFinite || v < 0) ||
      b.any((v) => !v.isFinite || v < 0)) {
    return 0;
  }
  double cosinePart(int start, int end) {
    var dot = 0.0, aa = 0.0, bb = 0.0;
    for (var i = start; i < end; i++) {
      dot += a[i] * b[i];
      aa += a[i] * a[i];
      bb += b[i] * b[i];
    }
    final den = math.sqrt(aa * bb);
    return den > 0 ? dot / den : 0;
  }

  final scores = <double>[];
  for (final start in [0, 48, 96]) {
    var sa = 0.0, sb = 0.0, overlap = 0.0;
    for (var i = start; i < start + 32; i++) {
      sa += a[i];
      sb += b[i];
      overlap += math.sqrt(a[i] * b[i]);
    }
    if (sa < .5 || sb < .5) return 0;
    scores.add(
      .8 * overlap / math.sqrt(sa * sb) +
          .2 * cosinePart(start + 32, start + 48),
    );
  }
  if (scores[0] < .80 || scores[1] < .75) return 0;
  return (.35 * scores[0] +
          .30 * scores[1] +
          .20 * scores[2] +
          .15 * cosinePart(144, 160))
      .clamp(0, 1);
}
