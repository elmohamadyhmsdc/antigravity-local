/// Roadmap sections 3.1 - 3.4: the TIER-A single-person rules (the ones a filter chip may use once
/// Phase 0 shows precision >= 0.85). Tier B / C poses are not rules: they are "find similar" or a
/// named pose from an example (section 6).
///
/// Every rule is gated by the body's extent and by the visibility of exactly the keypoints it reads;
/// a rule that cannot be evaluated yields nothing (never "false and recorded").
library;

import 'dart:math' as math;

import 'pose_geometry.dart';

abstract final class PoseTag {
  static const lying = 'lying';
  static const standing = 'standing';
  static const sitting = 'sitting';
  static const bent = 'bent';
  static const armsUp = 'arms_up';
  static const oneArmUp = 'one_arm_up';
  static const armsSpread = 'arms_spread';
  static const handsOnHips = 'hands_on_hips';
  static const frontal = 'frontal';
  static const profile = 'profile';
  static const back = 'back';

  static const all = [
    lying,
    standing,
    sitting,
    bent,
    armsUp,
    oneArmUp,
    armsSpread,
    handsOnHips,
    frontal,
    profile,
    back,
  ];

  /// Posture / arms / orientation, the three groups of the filter UI.
  static const posture = [lying, standing, sitting, bent];
  static const arms = [armsUp, oneArmUp, armsSpread, handsOnHips];
  static const orientation = [frontal, profile, back];
}

/// All Tier-A tags that hold for [pose]. [guardRotatedStanding] is the optional section 3.1 guard
/// (only when EXIF orientation cannot be fixed at the source): a body that is Standing after a 90 degree
/// rotation is a sideways photo, not a lying person.
Set<String> tierATags(Pose pose, {bool guardRotatedStanding = false}) {
  final tags = <String>{};
  if (isLying(pose, guardRotatedStanding: guardRotatedStanding)) {
    tags.add(PoseTag.lying);
  }
  if (isStanding(pose)) tags.add(PoseTag.standing);
  if (isSitting(pose)) tags.add(PoseTag.sitting);
  if (isBent(pose)) tags.add(PoseTag.bent);
  final torso = pose.torso;
  if (torso != null) {
    final up = _raisedArms(pose, torso);
    if (up.left == true && up.right == true) tags.add(PoseTag.armsUp);
    if ((up.left == true && up.right == false) ||
        (up.left == false && up.right == true)) {
      tags.add(PoseTag.oneArmUp);
    }
    if (_armsSpread(pose, torso)) tags.add(PoseTag.armsSpread);
    if (_handsOnHips(pose, torso)) tags.add(PoseTag.handsOnHips);
  }
  // Orientation to the camera is not asked of a body lying across the frame (decision: roadmap 3.4 is silent).
  final tilt = pose.spineTilt;
  if (tilt == null || tilt <= 60) {
    if (isFrontal(pose)) tags.add(PoseTag.frontal);
    if (isProfile(pose)) tags.add(PoseTag.profile);
    if (isBack(pose)) tags.add(PoseTag.back);
  }
  return tags;
}

// ---- 3.1 basic postures ---------------------------------------------------------------------------

/// phi > 60 degrees with shoulders and hips visible.
bool isLying(Pose pose, {bool guardRotatedStanding = false}) {
  final tilt = pose.spineTilt;
  if (tilt == null || tilt <= 60) return false;
  if (guardRotatedStanding && _standingAfterRotation(pose)) return false;
  return true;
}

/// Body leaning / bending over with spine tilt >= 25 degrees and not lying down.
bool isBent(Pose pose) {
  final tilt = pose.spineTilt;
  return tilt != null && tilt >= 25 && tilt <= 60;
}

/// Standing needs the whole leg: phi < 25, both knees straight, hip above knee above ankle, thigh not
/// foreshortened.
bool isStanding(Pose pose) {
  if (!pose.ankleRulesPossible) return false;
  final tilt = pose.spineTilt;
  if (tilt == null || tilt >= 25) return false;
  for (final (hip, knee, ankle) in _legs) {
    if (!pose.has([hip, knee, ankle])) return false;
    final h = pose[hip], k = pose[knee], a = pose[ankle];
    if (angle(h, k, a) <= 155) return false;
    if (!(h.y < k.y && k.y < a.y)) return false;
    if (dist(h, k) < 0.7 * dist(k, a)) return false;
  }
  return true;
}

/// phi < 35 and either (a) a side-ish seat: the knee bent between 70 and 135 degrees with the thigh
/// near horizontal, or (b) a frontal seat: the thigh foreshortened and the knee below the hip.
bool isSitting(Pose pose) {
  if (!pose.legsPossible) return false;
  final tilt = pose.spineTilt, torso = pose.torso;
  if (tilt == null || torso == null || tilt >= 35) return false;
  for (final (hip, knee, ankle) in _legs) {
    if (!pose.has([hip, knee, ankle])) continue;
    final h = pose[hip], k = pose[knee], a = pose[ankle];
    final bend = angle(h, k, a);
    final side = bend >= 70 && bend <= 135 && (h.y - k.y).abs() < 0.35 * torso;
    final frontal = dist(h, k) < 0.6 * dist(k, a) && k.y > h.y;
    if (side || frontal) return !isStanding(pose);
  }
  return false;
}

const _legs = [(Kp.lHip, Kp.lKnee, Kp.lAnkle), (Kp.rHip, Kp.rKnee, Kp.rAnkle)];

/// The Standing rule after turning the keypoints 90 degrees (a sideways photo of a standing person).
bool _standingAfterRotation(Pose pose) {
  for (final turn in [1.0, -1.0]) {
    final turned = Pose([
      for (final p in pose.points) Pt(-turn * p.y, turn * p.x, p.score),
    ], extent: pose.extent);
    if (isStanding(turned)) return true;
  }
  return false;
}

// ---- 3.2 arms -------------------------------------------------------------------------------------

/// Per arm: true raised, false lowered (visible, not raised), null unknown (wrist / shoulder missing).
({bool? left, bool? right}) _raisedArms(Pose pose, double torso) {
  bool? side(int shoulder, int wrist) {
    if (!pose.has([shoulder, wrist])) return null;
    return pose[wrist].y < pose[shoulder].y - 0.25 * torso;
  }

  return (
    left: side(Kp.lShoulder, Kp.lWrist),
    right: side(Kp.rShoulder, Kp.rWrist),
  );
}

/// Wrists at shoulder height (within 0.25 torso), elbows straight, the wrist span wider than 2.2 shoulder widths.
bool _armsSpread(Pose pose, double torso) {
  const ids = [
    Kp.lShoulder,
    Kp.rShoulder,
    Kp.lElbow,
    Kp.rElbow,
    Kp.lWrist,
    Kp.rWrist,
  ];
  if (!pose.has(ids)) return false;
  for (final (s, e, w) in const [
    (Kp.lShoulder, Kp.lElbow, Kp.lWrist),
    (Kp.rShoulder, Kp.rElbow, Kp.rWrist),
  ]) {
    if ((pose[w].y - pose[s].y).abs() > 0.25 * torso) return false;
    if (angle(pose[s], pose[e], pose[w]) <= 150) return false;
  }
  return dist(pose[Kp.lWrist], pose[Kp.rWrist]) > 2.2 * pose.shoulderWidth!;
}

/// Each wrist within 0.3 torso of its own hip, elbows bent under 120 degrees, each elbow farther from
/// the body midline than its shoulder (distances, not image-x signs).
bool _handsOnHips(Pose pose, double torso) {
  const ids = [
    Kp.lShoulder,
    Kp.rShoulder,
    Kp.lElbow,
    Kp.rElbow,
    Kp.lWrist,
    Kp.rWrist,
    Kp.lHip,
    Kp.rHip,
  ];
  if (!pose.has(ids)) return false;
  final top = pose.shoulderMid, bottom = pose.hipMid;
  double fromMidline(Pt p) {
    final dx = bottom.x - top.x, dy = bottom.y - top.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return 0;
    return ((p.x - top.x) * dy - (p.y - top.y) * dx).abs() / len;
  }

  for (final (s, e, w, h) in const [
    (Kp.lShoulder, Kp.lElbow, Kp.lWrist, Kp.lHip),
    (Kp.rShoulder, Kp.rElbow, Kp.rWrist, Kp.rHip),
  ]) {
    if (dist(pose[w], pose[h]) > 0.3 * torso) return false;
    if (angle(pose[s], pose[e], pose[w]) >= 120) return false;
    if (fromMidline(pose[e]) <= fromMidline(pose[s])) return false;
  }
  return true;
}

// ---- 3.4 orientation --------------------------------------------------------------------------------

bool isFrontal(Pose pose) {
  final torso = pose.torso, span = pose.shoulderWidth;
  if (torso == null || span == null || span < 0.6 * torso) return false;
  final yaw = pose.faceYaw;
  if (yaw != null) return yaw.abs() < 25;
  return pose.has(const [Kp.lEye, Kp.rEye, Kp.lEar, Kp.rEar]);
}

bool isProfile(Pose pose) {
  final yaw = pose.faceYaw;
  if (yaw != null && yaw.abs() > 60) return true;
  final torso = pose.torso, span = pose.shoulderWidth;
  if (torso == null || span == null) return false;
  final ears =
      (pose[Kp.lEar].visible ? 1 : 0) + (pose[Kp.rEar].visible ? 1 : 0);
  return ears == 1 && span < 0.35 * torso;
}

/// Nose and both eyes unseen (score under 0.2), both shoulders visible, no linked face.
bool isBack(Pose pose) {
  if (pose.faceYaw != null || !pose.hasShoulders) return false;
  return [Kp.nose, Kp.lEye, Kp.rEye].every((i) => pose[i].score < 0.2);
}
