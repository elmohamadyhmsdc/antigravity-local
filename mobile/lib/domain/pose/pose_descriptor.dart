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

const poseFeatureVersion = 2;
const minSharedPoints = 8;

/// Starting value of the Gaussian width in torso units; Phase 0 (`eval_pose_filters.py`) calibrates it.
const defaultPoseSigma = 0.22;
const minimumPoseSimilarity = 0.65;
const minimumPoseCoverage = 0.70;

class PoseFeature {
  const PoseFeature(this.data, this.mask, this.scaleSource);

  /// 34 floats, (x0, y0, x1, y1, ...), 0 for a point that is not visible.
  final Float32List data;

  /// Bit i set = keypoint i is visible.
  final int mask;

  /// 'torso' | 'shoulder'.
  final String scaleSource;

  int get visibleCount => _bits(mask);

  bool get isValid =>
      data.length == 34 &&
      data.every((v) => v.isFinite) &&
      mask > 0 &&
      mask < (1 << 17) &&
      visibleCount >= minSharedPoints;

  Uint8List toBlob() =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  static PoseFeature fromBlob(Uint8List blob, int mask, String scaleSource) {
    if (blob.lengthInBytes != 34 * 4) {
      return PoseFeature(Float32List(0), 0, scaleSource);
    }
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
  if (pose.points.any(
    (p) => !p.x.isFinite || !p.y.isFinite || !p.score.isFinite,
  )) {
    return null;
  }
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

  /// Gaussian similarity using global and worst limb squared error.
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
  bool allowMirror = true,
}) {
  if (a.scaleSource != b.scaleSource ||
      !a.isValid ||
      !b.isValid ||
      !sigma.isFinite ||
      sigma <= 0) {
    return null;
  }
  final straight = _compare(a, b, sigma);
  if (!allowMirror) return straight;
  final flipped = _compare(a, mirrorFeature(b), sigma);
  if (straight == null) return flipped;
  if (flipped == null) return straight;
  return flipped.score > straight.score ? flipped : straight;
}

PoseMatch? _compare(PoseFeature a, PoseFeature b, double sigma) {
  final both = a.mask & b.mask;
  final shared = _bits(both);
  if (shared < minSharedPoints) return null;
  var total = 0.0;
  var weight = 0.0;
  final errors = List<double>.filled(17, 0);
  for (var i = 0; i < 17; i++) {
    if (both & (1 << i) == 0) continue;
    final dx = a.data[2 * i] - b.data[2 * i],
        dy = a.data[2 * i + 1] - b.data[2 * i + 1];
    final w = i < Kp.lShoulder ? 0.25 : 1.0;
    errors[i] = dx * dx + dy * dy;
    total += errors[i] * w;
    weight += w;
  }
  // Five almost identical face points must not hide a changed arm or leg.
  var worstRegion = 0.0;
  for (final region in const [
    [5, 7, 9],
    [6, 8, 10],
    [11, 13, 15],
    [12, 14, 16],
    [5, 6, 11, 12],
  ]) {
    var count = 0;
    var sum = 0.0;
    for (final i in region) {
      if (both & (1 << i) == 0) continue;
      sum += errors[i];
      count++;
    }
    if (count >= 2) worstRegion = math.max(worstRegion, sum / count);
  }
  final squaredError = 0.45 * total / weight + 0.55 * worstRegion;
  return PoseMatch(
    similarity: math.exp(-squaredError / (2 * sigma * sigma)),
    coverage: shared / _bits(a.mask | b.mask),
    shared: shared,
  );
}
