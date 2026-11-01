/// Roadmap section 2.3 - the pose similarity descriptor (replaces OKS).
///
/// 17 x (x, y) translated to the hip middle and divided by the scale, plus a 17-bit visibility mask.
/// Mirror invariant (a pose and its left-right flip are the same pose); NOT rotation invariant (standing
/// and lying must stay different). Two descriptors are compared only when they share the same
/// [PoseFeature.scaleSource] and at least [minSharedPoints] visible points.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'pose_geometry.dart';

const poseFeatureVersion = 1;
const minSharedPoints = 8;

/// Starting value of the Gaussian width in torso units; Phase 0 (`eval_pose_filters.py`) calibrates it.
const defaultPoseSigma = 0.35;

class PoseFeature {
  const PoseFeature(this.data, this.mask, this.scaleSource);

  /// 34 floats, (x0, y0, x1, y1, ...), 0 for a point that is not visible.
  final Float32List data;

  /// Bit i set = keypoint i is visible.
  final int mask;

  /// 'torso' | 'shoulder'.
  final String scaleSource;

  int get visibleCount => _bits(mask);

  Uint8List toBlob() =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  static PoseFeature fromBlob(Uint8List blob, int mask, String scaleSource) {
    final copy = Uint8List.fromList(blob);
    return PoseFeature(copy.buffer.asFloat32List(), mask, scaleSource);
  }
}

int _bits(int v) {
  var n = 0;
  for (var x = v; x != 0; x &= x - 1) {
    n++;
  }
  return n;
}

/// Null when the pose cannot be normalised ("not comparable"):
/// * `torso`: both hips and both shoulders visible, scale = the torso length;
/// * `shoulder`: hips missing, FRONTAL only (eyes and ears seen, shoulders wide), scale = 1.35 x the
///   shoulder width. Off-frontal the shoulders are foreshortened and the scale would blow up.
PoseFeature? buildPoseFeature(Pose pose) {
  late final Pt origin;
  late final double scale;
  late final String source;
  final torso = pose.torso;
  if (torso != null && torso > 1) {
    origin = pose.hipMid;
    scale = torso;
    source = 'torso';
  } else if (pose.hasShoulders &&
      pose.has(const [Kp.lEye, Kp.rEye, Kp.lEar, Kp.rEar]) &&
      (pose.faceYaw == null || pose.faceYaw!.abs() < 25)) {
    final width = pose.shoulderWidth!;
    if (width <= 1) return null;
    origin = pose.shoulderMid;
    scale = width * 1.35;
    source = 'shoulder';
  } else {
    return null;
  }
  final data = Float32List(34);
  var mask = 0;
  for (var i = 0; i < 17; i++) {
    final p = pose[i];
    if (!p.visible) continue;
    mask |= 1 << i;
    data[2 * i] = (p.x - origin.x) / scale;
    data[2 * i + 1] = (p.y - origin.y) / scale;
  }
  final feature = PoseFeature(data, mask, source);
  return feature.visibleCount >= minSharedPoints ? feature : null;
}

/// The left-right flip: swap the paired points and negate x.
PoseFeature mirrorFeature(PoseFeature f) {
  final data = Float32List(34);
  var mask = 0;
  for (var i = 0; i < 17; i++) {
    final j = Kp.mirror[i];
    data[2 * j] = -f.data[2 * i];
    data[2 * j + 1] = f.data[2 * i + 1];
    if (f.mask & (1 << i) != 0) mask |= 1 << j;
  }
  return PoseFeature(data, mask, f.scaleSource);
}

class PoseMatch {
  const PoseMatch({
    required this.similarity,
    required this.coverage,
    required this.shared,
  });

  /// exp(-d^2 / 2 s^2) of the mean distance over the shared points, best of straight / mirrored.
  final double similarity;

  /// shared / max(visible_a, visible_b): an upper-body pose never ties a full-body one.
  final double coverage;
  final int shared;

  /// What ranking uses.
  double get score => similarity * coverage;
}

/// Null = "not comparable" (different scale source, or fewer than [minSharedPoints] shared points).
PoseMatch? comparePoses(
  PoseFeature a,
  PoseFeature b, {
  double sigma = defaultPoseSigma,
}) {
  if (a.scaleSource != b.scaleSource) return null;
  final straight = _compare(a, b, sigma);
  final flipped = _compare(a, mirrorFeature(b), sigma);
  if (straight == null) return flipped;
  if (flipped == null) return straight;
  return flipped.similarity > straight.similarity ? flipped : straight;
}

PoseMatch? _compare(PoseFeature a, PoseFeature b, double sigma) {
  final both = a.mask & b.mask;
  final shared = _bits(both);
  if (shared < minSharedPoints) return null;
  var total = 0.0;
  for (var i = 0; i < 17; i++) {
    if (both & (1 << i) == 0) continue;
    final dx = a.data[2 * i] - b.data[2 * i],
        dy = a.data[2 * i + 1] - b.data[2 * i + 1];
    total += math.sqrt(dx * dx + dy * dy);
  }
  final d = total / shared;
  return PoseMatch(
    similarity: math.exp(-d * d / (2 * sigma * sigma)),
    coverage: shared / math.max(a.visibleCount, b.visibleCount),
    shared: shared,
  );
}
