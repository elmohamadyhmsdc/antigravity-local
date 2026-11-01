/// Roadmap section 2.2 - the mandatory preprocessing for every pose rule.
///
/// `bodies.kpts` are `[[x, y, score] x17]` with x divided by the image WIDTH and y by the HEIGHT
/// (`PhotoResultStore._kpts`), so an angle computed on them is wrong on any picture that is not
/// square. [Pose] multiplies them back by `media.width/height` before anything is measured.
library;

import 'dart:convert';
import 'dart:math' as math;

/// COCO-17 indices. `l_` / `r_` are the SUBJECT's left / right: in a frontal view `l_` appears on the
/// image right. Rules never assume a side from the image x.
abstract final class Kp {
  static const nose = 0;
  static const lEye = 1, rEye = 2;
  static const lEar = 3, rEar = 4;
  static const lShoulder = 5, rShoulder = 6;
  static const lElbow = 7, rElbow = 8;
  static const lWrist = 9, rWrist = 10;
  static const lHip = 11, rHip = 12;
  static const lKnee = 13, rKnee = 14;
  static const lAnkle = 15, rAnkle = 16;

  /// Left <-> right partner of each index (the mirror image of a pose).
  static const mirror = [
    0,
    2,
    1,
    4,
    3,
    6,
    5,
    8,
    7,
    10,
    9,
    12,
    11,
    14,
    13,
    16,
    15,
  ];
}

/// Same threshold as `person_linking.KPT_VISIBLE`.
const keypointVisible = 0.3;

class Pt {
  const Pt(this.x, this.y, this.score);
  final double x, y, score;
  bool get visible => score >= keypointVisible;
}

double dist(Pt a, Pt b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

Pt mid(Pt a, Pt b) =>
    Pt((a.x + b.x) / 2, (a.y + b.y) / 2, math.min(a.score, b.score));

/// The flexion at [b] (degrees, 0..180) of the angle a-b-c.
double angle(Pt a, Pt b, Pt c) {
  final v1x = a.x - b.x, v1y = a.y - b.y, v2x = c.x - b.x, v2y = c.y - b.y;
  final n = math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y);
  if (n == 0) return 0;
  final cos = ((v1x * v2x + v1y * v2y) / n).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

class Pose {
  Pose(this.points, {this.extent, this.faceYaw, this.faceRoll})
    : assert(points.length == 17);

  /// In IMAGE PIXELS (y grows downward: "above" means a smaller y).
  final List<Pt> points;

  /// full | knee | upper | head (the body's `extent`); null = unknown.
  final String? extent;

  /// Of the linked face when one passed the quality gate (degrees, InsightFace); else null.
  final double? faceYaw, faceRoll;

  Pt operator [](int i) => points[i];
  bool has(Iterable<int> ids) => ids.every((i) => points[i].visible);
  int get visibleCount => points.where((p) => p.visible).length;

  /// Skips bodies with no image size or malformed keypoints (returns null).
  static Pose? fromJson(
    String? kpts,
    int? width,
    int? height, {
    String? extent,
    double? faceYaw,
    double? faceRoll,
  }) {
    if (kpts == null ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    try {
      final raw = jsonDecode(kpts) as List<dynamic>;
      if (raw.length != 17) return null;
      return Pose(
        [
          for (final k in raw)
            Pt(
              (k[0] as num).toDouble() * width,
              (k[1] as num).toDouble() * height,
              (k[2] as num).toDouble(),
            ),
        ],
        extent: extent,
        faceYaw: faceYaw,
        faceRoll: faceRoll,
      );
    } catch (_) {
      return null;
    }
  }

  bool get hasShoulders => has(const [Kp.lShoulder, Kp.rShoulder]);
  bool get hasHips => has(const [Kp.lHip, Kp.rHip]);

  Pt get shoulderMid => mid(points[Kp.lShoulder], points[Kp.rShoulder]);
  Pt get hipMid => mid(points[Kp.lHip], points[Kp.rHip]);

  /// `|M(5,6) - M(11,12)|`; null without both pairs.
  double? get torso =>
      hasShoulders && hasHips ? dist(shoulderMid, hipMid) : null;

  double? get shoulderWidth =>
      hasShoulders ? dist(points[Kp.lShoulder], points[Kp.rShoulder]) : null;

  /// Tilt of hip-mid -> shoulder-mid from the vertical, degrees: 0 = upright, 90 = horizontal.
  double? get spineTilt {
    if (!hasShoulders || !hasHips) return null;
    final dx = (shoulderMid.x - hipMid.x).abs(),
        dy = (shoulderMid.y - hipMid.y).abs();
    return math.atan2(dx, dy) * 180 / math.pi;
  }

  /// Leg rules need the knees (full / knee extent); ankle rules need a full body.
  bool get legsPossible => extent == 'full' || extent == 'knee';
  bool get ankleRulesPossible => extent == 'full';
}
