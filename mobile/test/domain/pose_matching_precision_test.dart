import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:antigravity_mobile/domain/pose/pose_rules.dart';
import 'package:antigravity_mobile/domain/pose/pose_descriptor.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';

void main() {
  group('High-Precision Pose Matching Precision & Gating', () {
    // 17 keypoints JSON helper
    String makeKpts({
      required double noseY,
      required double noseScore,
      required double eyeScore,
      required double hipY,
      required double kneeY,
      required double ankleY,
      double shoulderTiltX = 0.0,
      double shoulderY = 300,
    }) {
      // 17 COCO points:
      // 0: nose, 1: lEye, 2: rEye, 3: lEar, 4: rEar
      // 5: lShoulder, 6: rShoulder, 7: lElbow, 8: rElbow, 9: lWrist, 10: rWrist
      // 11: lHip, 12: rHip, 13: lKnee, 14: rKnee, 15: lAnkle, 16: rAnkle
      final pts = List.generate(17, (i) => [0.5, 0.5, 0.9]);
      // Nose and eyes:
      pts[0] = [0.5, noseY / 1000, noseScore];
      pts[1] = [0.45, (noseY - 20) / 1000, eyeScore];
      pts[2] = [0.55, (noseY - 20) / 1000, eyeScore];
      pts[3] = [0.40, (noseY - 20) / 1000, eyeScore];
      pts[4] = [0.60, (noseY - 20) / 1000, eyeScore];

      // Shoulders:
      pts[5] = [(0.40 + shoulderTiltX), shoulderY / 1000, 0.95];
      pts[6] = [(0.60 + shoulderTiltX), shoulderY / 1000, 0.95];

      // Elbows & wrists:
      pts[7] = [0.35, (shoulderY + 150) / 1000, 0.9];
      pts[8] = [0.65, (shoulderY + 150) / 1000, 0.9];
      pts[9] = [0.35, (shoulderY + 300) / 1000, 0.9];
      pts[10] = [0.65, (shoulderY + 300) / 1000, 0.9];

      // Hips:
      pts[11] = [0.45, hipY / 1000, 0.95];
      pts[12] = [0.55, hipY / 1000, 0.95];

      // Knees:
      pts[13] = [0.45, kneeY / 1000, 0.95];
      pts[14] = [0.55, kneeY / 1000, 0.95];

      // Ankles:
      pts[15] = [0.45, ankleY / 1000, 0.95];
      pts[16] = [0.55, ankleY / 1000, 0.95];

      return jsonEncode(pts);
    }

    test('tags identify frontal vs back and upright vs bent', () {
      // 1. Frontal Upright
      final frontalKpts = makeKpts(
        noseY: 200,
        noseScore: 0.9,
        eyeScore: 0.9,
        hipY: 550,
        kneeY: 750,
        ankleY: 950,
      );
      final frontalPose = Pose.fromJson(
        frontalKpts,
        1000,
        1000,
        extent: 'full',
      )!;
      final frontalTags = tierATags(frontalPose);
      expect(frontalTags.contains(PoseTag.frontal), isTrue);
      expect(frontalTags.contains(PoseTag.standing), isTrue);
      expect(frontalTags.contains(PoseTag.back), isFalse);

      // 2. Back Upright (eyes and nose score < 0.2)
      final backKpts = makeKpts(
        noseY: 200,
        noseScore: 0.05,
        eyeScore: 0.05,
        hipY: 550,
        kneeY: 750,
        ankleY: 950,
      );
      final backPose = Pose.fromJson(backKpts, 1000, 1000, extent: 'full')!;
      final backTags = tierATags(backPose);
      expect(backTags.contains(PoseTag.back), isTrue);
      expect(backTags.contains(PoseTag.standing), isTrue);
      expect(backTags.contains(PoseTag.frontal), isFalse);

      // 3. Back Bent Over (shoulders shifted / tilt ~32 degrees)
      final backBentKpts = makeKpts(
        noseY: 380,
        noseScore: 0.05,
        eyeScore: 0.05,
        hipY: 550,
        kneeY: 750,
        ankleY: 950,
        shoulderTiltX: 0.095, // causes spine tilt ~32.3 degrees
        shoulderY: 400,
      );
      final backBentPose = Pose.fromJson(
        backBentKpts,
        1000,
        1000,
        extent: 'full',
      )!;
      final backBentTags = tierATags(backBentPose);
      expect(backBentTags.contains(PoseTag.back), isTrue);
      expect(backBentTags.contains(PoseTag.bent), isTrue);
      expect(backBentTags.contains(PoseTag.standing), isFalse);
    });

    test('ranking rejects back vs frontal and bent vs upright', () {
      final qTags = encodeTags([PoseTag.back, PoseTag.standing]);
      final candidateBackStandingTags = encodeTags([
        PoseTag.back,
        PoseTag.standing,
      ]);
      final candidateFrontalStandingTags = encodeTags([
        PoseTag.frontal,
        PoseTag.standing,
      ]);
      final candidateBackBentTags = encodeTags([PoseTag.back, PoseTag.bent]);

      final dummyKpts = makeKpts(
        noseY: 200,
        noseScore: 0.05,
        eyeScore: 0.05,
        hipY: 550,
        kneeY: 750,
        ankleY: 950,
      );
      final pose = Pose.fromJson(dummyKpts, 1000, 1000, extent: 'full')!;
      final feat = buildPoseFeature(pose)!;

      final query = (
        feature: feat.toBlob(),
        mask: feat.mask,
        scaleSource: feat.scaleSource,
        tags: qTags,
      );

      final candidates = [
        (
          id: 1,
          feature: feat.toBlob(),
          mask: feat.mask,
          scaleSource: feat.scaleSource,
          tags: candidateBackStandingTags,
        ),
        (
          id: 2,
          feature: feat.toBlob(),
          mask: feat.mask,
          scaleSource: feat.scaleSource,
          tags: candidateFrontalStandingTags,
        ),
        (
          id: 3,
          feature: feat.toBlob(),
          mask: feat.mask,
          scaleSource: feat.scaleSource,
          tags: candidateBackBentTags,
        ),
      ];

      final results = rankCandidates(query, candidates, limit: 10);
      final resultIds = [for (final r in results) r.id];

      expect(
        resultIds,
        contains(1),
        reason: 'Exact match (back + standing) must pass',
      );
      expect(
        resultIds,
        isNot(contains(2)),
        reason: 'Frontal pose must NEVER match Back pose',
      );
      expect(
        resultIds,
        isNot(contains(3)),
        reason: 'Bent pose must NEVER match Upright Standing pose',
      );
    });
  });
}
