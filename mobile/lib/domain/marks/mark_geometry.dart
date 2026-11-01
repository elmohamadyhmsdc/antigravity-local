/// Roadmap section 7.4: where a marked tattoo sits relative to the body skeleton, so the same place can be cut
/// out of ANOTHER photo of the same body. Pure geometry on [Pose] (image pixels).
///
/// A segment has two anchor points A and B (each the mean of one or two keypoints). A mark is stored in the
/// segment's local frame: origin A, axis A->B (its length L is the unit), a perpendicular axis; the patch is
/// (centre, size) in units of L. Another photo of the body, at any scale, rotation or crop, then gives the
/// matching rotated rectangle in pixels.
library;

import 'dart:math' as math;

import '../pose/pose_geometry.dart';

/// Limbs use a joint pair; torso areas use the spine axis shoulder-middle -> hip-middle (or the shoulder
/// span when the hips are outside the frame); the pelvis uses the hip pair.
const _segments = <String, (List<int>, List<int>)>{
  'r_upper_arm': ([Kp.rShoulder], [Kp.rElbow]),
  'l_upper_arm': ([Kp.lShoulder], [Kp.lElbow]),
  'r_forearm': ([Kp.rElbow], [Kp.rWrist]),
  'l_forearm': ([Kp.lElbow], [Kp.lWrist]),
  'r_thigh': ([Kp.rHip], [Kp.rKnee]),
  'l_thigh': ([Kp.lHip], [Kp.lKnee]),
  'r_lower_leg': ([Kp.rKnee], [Kp.rAnkle]),
  'l_lower_leg': ([Kp.lKnee], [Kp.lAnkle]),
  'chest': ([Kp.lShoulder, Kp.rShoulder], [Kp.lHip, Kp.rHip]),
  'abdomen': ([Kp.lShoulder, Kp.rShoulder], [Kp.lHip, Kp.rHip]),
  'ribs': ([Kp.lShoulder, Kp.rShoulder], [Kp.lHip, Kp.rHip]),
  'upper_back': ([Kp.lShoulder, Kp.rShoulder], [Kp.lHip, Kp.rHip]),
  'lower_back': ([Kp.lShoulder, Kp.rShoulder], [Kp.lHip, Kp.rHip]),
  'hips': ([Kp.lHip], [Kp.rHip]),
};

const markSegments = [
  'r_upper_arm',
  'l_upper_arm',
  'r_forearm',
  'l_forearm',
  'r_thigh',
  'l_thigh',
  'r_lower_leg',
  'l_lower_leg',
  'chest',
  'abdomen',
  'ribs',
  'upper_back',
  'lower_back',
  'hips',
];

/// The same place on the other side of the body (a mirror selfie shows the tattoo on the opposite limb).
/// Torso segments and the pelvis are their own opposite: the server also tries the flipped patch.
String oppositeSegment(String segment) {
  if (segment.startsWith('r_')) return 'l_${segment.substring(2)}';
  if (segment.startsWith('l_')) return 'r_${segment.substring(2)}';
  return segment;
}

class MarkRect {
  const MarkRect({
    required this.cx,
    required this.cy,
    required this.width,
    required this.height,
    required this.angleDegrees,
  });

  /// Centre and size in image pixels; the rectangle is turned by [angleDegrees] around its centre.
  final double cx, cy, width, height, angleDegrees;
}

({double x, double y})? _anchor(Pose pose, List<int> ids) {
  if (!pose.has(ids)) return null;
  var x = 0.0, y = 0.0;
  for (final i in ids) {
    x += pose[i].x / ids.length;
    y += pose[i].y / ids.length;
  }
  return (x: x, y: y);
}

/// Both anchors of [segment], or null when a keypoint is not visible (a candidate body must show the
/// segment's anchors to be searched). The torso falls back to the shoulder span when the hips are outside.
({({double x, double y}) a, ({double x, double y}) b})? anchorsOf(
  Pose pose,
  String segment,
) {
  final spec = _segments[segment];
  if (spec == null) return null;
  final a = _anchor(pose, spec.$1);
  var b = _anchor(pose, spec.$2);
  if (a != null && b == null && spec.$1.length == 2 && spec.$2.length == 2) {
    // hips outside the frame: the shoulder span is the unit and the axis, perpendicular to it, points down
    final l = pose[spec.$1[0]], r = pose[spec.$1[1]];
    b = (x: a.x - (r.y - l.y), y: a.y + (r.x - l.x));
  }
  if (a == null || b == null) return null;
  if (math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2)) < 1) {
    return null;
  }
  return (a: a, b: b);
}

bool segmentVisible(Pose pose, String segment) =>
    anchorsOf(pose, segment) != null;

/// The stored position of a mark: [box] (x, y, w, h in image pixels, axis-aligned) on [pose]'s [segment].
/// Null when the segment is not measurable on that pose.
Map<String, dynamic>? anchorFor(
  Pose pose,
  String segment,
  ({double x, double y, double w, double h}) box,
) {
  final anchors = anchorsOf(pose, segment);
  if (anchors == null) return null;
  final (:a, :b) = anchors;
  final ux = b.x - a.x, uy = b.y - a.y;
  final length = math.sqrt(ux * ux + uy * uy);
  final ex = ux / length, ey = uy / length; // axis along A->B
  final fx = -ey, fy = ex; // perpendicular
  final dx = box.x + box.w / 2 - a.x, dy = box.y + box.h / 2 - a.y;
  // box size along the local axes (an axis-aligned box seen in the rotated frame)
  final along = (box.w * ex).abs() + (box.h * ey).abs();
  final across = (box.w * fx).abs() + (box.h * fy).abs();
  return {
    'c': [_r((dx * ex + dy * ey) / length), _r((dx * fx + dy * fy) / length)],
    'size': [_r(along / length), _r(across / length)],
  };
}

/// The rotated rectangle of a stored mark on another photo's [pose] (the same segment, or its opposite).
MarkRect? rectFor(Pose pose, String segment, Map<String, dynamic> anchor) {
  final anchors = anchorsOf(pose, segment);
  if (anchors == null) return null;
  final (:a, :b) = anchors;
  final ux = b.x - a.x, uy = b.y - a.y;
  final length = math.sqrt(ux * ux + uy * uy);
  final ex = ux / length, ey = uy / length;
  final fx = -ey, fy = ex;
  final c = (anchor['c'] as List<dynamic>).cast<num>();
  final size = (anchor['size'] as List<dynamic>).cast<num>();
  return MarkRect(
    cx: a.x + (c[0] * ex + c[1] * fx) * length,
    cy: a.y + (c[0] * ey + c[1] * fy) * length,
    width: size[0] * length,
    height: size[1] * length,
    angleDegrees: math.atan2(uy, ux) * 180 / math.pi,
  );
}

double _r(double v) => (v * 10000).roundToDouble() / 10000;

/// What a match is worth. Until Phase 0 measures precision a mark is a SUGGESTION, never an automatic link.
enum MarkEvidence { none, weak, strong }

const strongInliers = 25;
const strongRatio = 0.5;
const weakInliers = 12;

MarkEvidence markEvidence({required int inliers, required double inlierRatio}) {
  if (inliers >= strongInliers && inlierRatio >= strongRatio) {
    return MarkEvidence.strong;
  }
  if (inliers >= weakInliers) return MarkEvidence.weak;
  return MarkEvidence.none;
}
