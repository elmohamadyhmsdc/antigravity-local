// Roadmap Phase 1: pose geometry (denormalised keypoints), the Tier-A rules, the mirror-invariant
// descriptor, and the coarse outfit colours. Pure functions on synthetic skeletons.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/domain/pose/outfit_palette.dart';
import 'package:antigravity_mobile/domain/pose/pose_descriptor.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:antigravity_mobile/domain/pose/pose_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// A standing, frontal person in image pixels (1000 x 1500 picture). Shoulders 300 wide, torso 400.
Map<int, List<double>> standing() => {
  Kp.nose: [500, 300],
  Kp.lEye: [530, 280],
  Kp.rEye: [470, 280],
  Kp.lEar: [560, 290],
  Kp.rEar: [440, 290],
  Kp.lShoulder: [650, 400],
  Kp.rShoulder: [350, 400],
  Kp.lElbow: [670, 550],
  Kp.rElbow: [330, 550],
  Kp.lWrist: [680, 700],
  Kp.rWrist: [320, 700],
  Kp.lHip: [560, 800],
  Kp.rHip: [440, 800],
  Kp.lKnee: [560, 1050],
  Kp.rKnee: [440, 1050],
  Kp.lAnkle: [560, 1300],
  Kp.rAnkle: [440, 1300],
};

Pose pose(
  Map<int, List<double>> pts, {
  String? extent = 'full',
  double? yaw,
  Set<int> hidden = const {},
  Set<int> faint = const {},
}) => Pose(
  [
    for (var i = 0; i < 17; i++)
      pts.containsKey(i)
          ? Pt(
              pts[i]![0],
              pts[i]![1],
              hidden.contains(i) ? 0.0 : (faint.contains(i) ? 0.1 : 0.9),
            )
          : const Pt(0, 0, 0),
  ],
  extent: extent,
  faceYaw: yaw,
);

Map<int, List<double>> moved(
  Map<int, List<double>> base,
  Map<int, List<double>> changes,
) => {...base, ...changes};

Map<int, List<double>> mirrored(Map<int, List<double>> pts) => {
  for (final e in pts.entries)
    Kp.mirror[e.key]: [1000 - e.value[0], e.value[1]],
};

Map<int, List<double>> rotated(Map<int, List<double>> pts) => {
  for (final e in pts.entries) e.key: [1500 - e.value[1], e.value[0]],
};

void main() {
  group('geometry', () {
    test(
      'keypoints are denormalised by width AND height, so the same body measures the same on any frame',
      () {
        final truth = standing();
        for (final (w, h) in [(1500, 1500), (900, 1600), (4000, 3000)]) {
          final json = jsonEncode([
            for (var i = 0; i < 17; i++)
              [truth[i]![0] / w, truth[i]![1] / h, 0.9],
          ]);
          final p = Pose.fromJson(json, w, h, extent: 'full')!;
          expect(p[Kp.lShoulder].x, closeTo(650, 1e-6));
          expect(p[Kp.lAnkle].y, closeTo(1300, 1e-6));
          expect(
            angle(p[Kp.lHip], p[Kp.lKnee], p[Kp.lAnkle]),
            closeTo(180, 1e-6),
          );
          expect(p.torso, closeTo(400, 1e-6));
          expect(p.spineTilt, closeTo(0, 1e-6));
        }
      },
    );

    test('bodies with no image size or broken keypoints are skipped', () {
      expect(Pose.fromJson('[[0.1,0.1,0.9]]', 100, 100), isNull);
      expect(Pose.fromJson(null, 100, 100), isNull);
      expect(Pose.fromJson('not json', 100, 100), isNull);
      expect(
        Pose.fromJson(jsonEncode(List.filled(17, [0.1, 0.1, 0.9])), null, 100),
        isNull,
      );
      expect(
        Pose.fromJson(jsonEncode(List.filled(17, [0.1, 0.1, 0.9])), 0, 100),
        isNull,
      );
    });

    test('angle, mid and the visibility threshold', () {
      expect(
        angle(const Pt(0, 1, 1), const Pt(0, 0, 1), const Pt(1, 0, 1)),
        closeTo(90, 1e-9),
      );
      expect(mid(const Pt(0, 0, 0.9), const Pt(2, 4, 0.5)).y, 2);
      expect(const Pt(0, 0, 0.3).visible, isTrue);
      expect(const Pt(0, 0, 0.29).visible, isFalse);
    });
  });

  group('tier A rules', () {
    test('a frontal standing person', () {
      final tags = tierATags(pose(standing()));
      expect(tags, containsAll([PoseTag.standing, PoseTag.frontal]));
      expect(tags, isNot(contains(PoseTag.lying)));
      expect(tags, isNot(contains(PoseTag.sitting)));
    });

    test('leg rules need the leg: extent upper never stands or sits', () {
      final upper = pose(standing(), extent: 'upper');
      expect(tierATags(upper), isNot(contains(PoseTag.standing)));
      expect(tierATags(upper), isNot(contains(PoseTag.sitting)));
      expect(
        tierATags(pose(standing(), hidden: {Kp.lAnkle, Kp.rAnkle})),
        isNot(contains(PoseTag.standing)),
      );
    });

    test(
      'lying is a horizontal spine; the optional guard recognises a sideways standing photo',
      () {
        final lying = pose(rotated(standing()));
        expect(tierATags(lying), contains(PoseTag.lying));
        expect(tierATags(lying), isNot(contains(PoseTag.standing)));
        expect(
          tierATags(lying, guardRotatedStanding: true),
          isNot(contains(PoseTag.lying)),
        );
        // a really lying person (knees bent, relaxed) stays lying with the guard on
        final relaxed = rotated(
          moved(standing(), {
            Kp.lKnee: [
              600,
              1000,
            ], // knees bent: not straight enough to be Standing
            Kp.rKnee: [400, 1000],
            Kp.lAnkle: [900, 1100],
            Kp.rAnkle: [100, 1100],
          }),
        );
        expect(
          tierATags(pose(relaxed), guardRotatedStanding: true),
          contains(PoseTag.lying),
        );
      },
    );

    test('sitting, side view and frontal with the thigh foreshortened', () {
      final side = moved(standing(), {
        Kp.lKnee: [800, 820],
        Kp.rKnee: [700, 820],
        Kp.lAnkle: [800, 1080],
        Kp.rAnkle: [700, 1080],
      });
      expect(tierATags(pose(side)), contains(PoseTag.sitting));
      expect(tierATags(pose(side)), isNot(contains(PoseTag.standing)));
      final frontal = moved(standing(), {
        Kp.lKnee: [560, 890],
        Kp.rKnee: [440, 890],
        Kp.lAnkle: [560, 1250],
        Kp.rAnkle: [440, 1250],
      });
      expect(tierATags(pose(frontal)), contains(PoseTag.sitting));
      expect(tierATags(pose(frontal)), isNot(contains(PoseTag.standing)));
      expect(
        tierATags(pose(frontal, extent: 'knee')),
        contains(PoseTag.sitting),
        reason: 'knee extent is enough',
      );
    });

    test('arms up, one arm up, spread, hands on hips', () {
      final both = moved(standing(), {
        Kp.lWrist: [680, 250],
        Kp.rWrist: [320, 250],
      });
      expect(tierATags(pose(both)), contains(PoseTag.armsUp));
      final one = moved(standing(), {
        Kp.lWrist: [680, 250],
      });
      expect(tierATags(pose(one)), contains(PoseTag.oneArmUp));
      expect(tierATags(pose(one)), isNot(contains(PoseTag.armsUp)));
      final spread = moved(standing(), {
        Kp.lElbow: [800, 400],
        Kp.rElbow: [200, 400],
        Kp.lWrist: [950, 400],
        Kp.rWrist: [50, 400],
      });
      expect(tierATags(pose(spread)), contains(PoseTag.armsSpread));
      expect(tierATags(pose(spread)), isNot(contains(PoseTag.armsUp)));
      final hips = moved(standing(), {
        Kp.lElbow: [780, 600],
        Kp.rElbow: [220, 600],
        Kp.lWrist: [565, 800],
        Kp.rWrist: [435, 800],
      });
      expect(tierATags(pose(hips)), contains(PoseTag.handsOnHips));
      expect(tierATags(pose(standing())), isNot(contains(PoseTag.handsOnHips)));
      // an unseen wrist is "unknown", not "lowered": one arm up needs the other arm seen
      final hiddenWrist = moved(standing(), {
        Kp.lWrist: [680, 250],
      });
      expect(
        tierATags(pose(hiddenWrist, hidden: {Kp.rWrist})),
        isNot(contains(PoseTag.oneArmUp)),
      );
    });

    test(
      'orientation: frontal, profile, back; a missing face never makes a back view by itself',
      () {
        expect(tierATags(pose(standing(), yaw: 10)), contains(PoseTag.frontal));
        expect(
          tierATags(pose(standing(), yaw: 80)),
          containsAll([PoseTag.profile]),
        );
        expect(
          tierATags(pose(standing(), yaw: 80)),
          isNot(contains(PoseTag.frontal)),
        );
        final backView = pose(standing(), faint: {Kp.nose, Kp.lEye, Kp.rEye});
        expect(tierATags(backView), contains(PoseTag.back));
        expect(
          tierATags(
            pose(standing(), faint: {Kp.nose, Kp.lEye, Kp.rEye}, yaw: 0),
          ),
          isNot(contains(PoseTag.back)),
        );
        final narrow = moved(standing(), {
          Kp.lShoulder: [540, 400],
          Kp.rShoulder: [460, 400],
          Kp.rEar: [0, 0],
        });
        expect(
          tierATags(pose(narrow, hidden: {Kp.rEar})),
          contains(PoseTag.profile),
        );
      },
    );

    test('nothing visible gives no tag', () {
      expect(tierATags(pose({}, extent: null)), isEmpty);
      expect(
        tierATags(pose(standing(), hidden: standing().keys.toSet())),
        isEmpty,
      );
    });
  });

  group('descriptor', () {
    test(
      'identical poses match fully; the left-right mirror is the same pose',
      () {
        final a = buildPoseFeature(pose(standing()))!;
        final same = comparePoses(a, a)!;
        expect(same.similarity, closeTo(1, 1e-9));
        expect(same.coverage, 1);
        final flipped = buildPoseFeature(pose(mirrored(standing())))!;
        expect(comparePoses(a, flipped)!.similarity, closeTo(1, 1e-6));
        final raised = buildPoseFeature(
          pose(
            moved(standing(), {
              Kp.lWrist: [680, 250],
            }),
          ),
        )!;
        final raisedMirror = buildPoseFeature(
          pose(
            mirrored(
              moved(standing(), {
                Kp.lWrist: [680, 250],
              }),
            ),
          ),
        )!;
        expect(
          comparePoses(raised, raisedMirror)!.similarity,
          closeTo(1, 1e-6),
        );
        expect(
          comparePoses(a, raised)!.similarity,
          lessThan(comparePoses(a, flipped)!.similarity),
        );
      },
    );

    test(
      'scale and position do not matter; rotation does (standing is not lying)',
      () {
        final a = buildPoseFeature(pose(standing()))!;
        final moved2 = {
          for (final e in standing().entries)
            e.key: [e.value[0] * 0.5 + 40, e.value[1] * 0.5 + 90],
        };
        expect(
          comparePoses(a, buildPoseFeature(pose(moved2))!)!.similarity,
          closeTo(1, 1e-6),
        );
        final lying = buildPoseFeature(pose(rotated(standing())))!;
        expect(comparePoses(a, lying)!.similarity, lessThan(0.05));
      },
    );

    test('the descriptor is the same on a 1:1 and a 9:16 frame', () {
      final truth = standing();
      PoseFeature feature(int w, int h) => buildPoseFeature(
        Pose.fromJson(
          jsonEncode([
            for (var i = 0; i < 17; i++)
              [truth[i]![0] / w, truth[i]![1] / h, 0.9],
          ]),
          w,
          h,
          extent: 'full',
        )!,
      )!;
      final x = feature(1500, 1500), y = feature(900, 1600);
      for (var i = 0; i < 34; i++) {
        expect(x.data[i], closeTo(y.data[i], 1e-5));
      }
    });

    test(
      'hips missing: only a frontal body is normalised by its shoulders, and only like with like compares',
      () {
        final noHips = {
          for (final e in standing().entries)
            if (e.key < Kp.lHip) e.key: e.value,
        };
        final shoulder = buildPoseFeature(pose(noHips, extent: 'upper'))!;
        expect(shoulder.scaleSource, 'shoulder');
        final withHips = buildPoseFeature(pose(standing()))!;
        expect(withHips.scaleSource, 'torso');
        expect(
          comparePoses(shoulder, withHips),
          isNull,
          reason: 'different scale sources are not comparable',
        );
        final noEars = {...noHips}
          ..remove(Kp.lEar)
          ..remove(Kp.rEar);
        expect(
          buildPoseFeature(pose(noEars, extent: 'upper')),
          isNull,
          reason: 'not frontal: shoulders foreshortened',
        );
        expect(
          buildPoseFeature(pose(noHips, extent: 'upper', yaw: 70)),
          isNull,
        );
      },
    );

    test(
      'fewer than 8 shared points is not comparable; coverage penalises an upper-body match to a full body',
      () {
        final full = buildPoseFeature(pose(standing()))!;
        final fewPts = {
          Kp.lShoulder: standing()[Kp.lShoulder]!,
          Kp.rShoulder: standing()[Kp.rShoulder]!,
          Kp.lHip: standing()[Kp.lHip]!,
          Kp.rHip: standing()[Kp.rHip]!,
        };
        expect(
          buildPoseFeature(pose(fewPts)),
          isNull,
          reason: 'a descriptor needs 8 visible points',
        );
        final upperOnly = buildPoseFeature(
          pose({
            for (final e in standing().entries)
              if (e.key <= Kp.rHip) e.key: e.value,
          }, extent: 'upper'),
        )!;
        final m = comparePoses(full, upperOnly)!;
        expect(
          m.similarity,
          closeTo(1, 1e-6),
          reason: 'the shared points agree exactly',
        );
        expect(m.coverage, closeTo(13 / 17, 1e-9));
        expect(m.score, lessThan(comparePoses(full, full)!.score));
      },
    );

    test('blob round trip', () {
      final f = buildPoseFeature(pose(standing()))!;
      final back = PoseFeature.fromBlob(
        Uint8List.fromList(f.toBlob()),
        f.mask,
        f.scaleSource,
      );
      expect(back.data, f.data);
      expect(back.visibleCount, 17);
    });
  });

  group('outfit colours', () {
    /// A descriptor with all of the torso mass in one hue bin and all of the legs mass in one value bin.
    List<double> descriptor({
      int? torsoHue,
      int? torsoValue,
      int? legsHue,
      int? legsValue,
    }) {
      List<double> region(int? hue, int? value) {
        final r = List<double>.filled(40, 0);
        if (hue != null) r[hue * 3 + 1] = 1;
        if (value != null) r[36 + value] = 1;
        return r;
      }

      return [...region(torsoHue, torsoValue), ...region(legsHue, legsValue)];
    }

    test(
      'hue families and greys, honest about what the descriptor cannot say',
      () {
        expect(
          dominantColor(descriptor(torsoHue: 7), OutfitRegion.torso),
          OutfitColor.blue,
        );
        expect(
          dominantColor(descriptor(torsoHue: 8), OutfitRegion.torso),
          OutfitColor.blue,
          reason: 'navy / royal: one family',
        );
        expect(
          dominantColor(descriptor(torsoHue: 11), OutfitRegion.torso),
          OutfitColor.red,
        );
        expect(
          dominantColor(descriptor(torsoHue: 0), OutfitRegion.torso),
          OutfitColor.red,
        );
        expect(
          dominantColor(descriptor(torsoHue: 4), OutfitRegion.torso),
          OutfitColor.green,
        );
        expect(
          dominantColor(descriptor(torsoValue: 3), OutfitRegion.torso),
          OutfitColor.white,
        );
        expect(
          dominantColor(descriptor(torsoValue: 0), OutfitRegion.torso),
          OutfitColor.black,
        );
        expect(
          dominantColor(descriptor(legsValue: 1), OutfitRegion.legs),
          OutfitColor.darkGrey,
        );
      },
    );

    test(
      'a region that is not visible says nothing; a mixed one has no dominant colour',
      () {
        final d = descriptor(torsoHue: 7);
        expect(colorShares(d, OutfitRegion.legs), isNull);
        expect(dominantColor(d, OutfitRegion.legs), isNull);
        final mixed = List<double>.filled(80, 0);
        mixed[7 * 3 + 1] = math.sqrt(0.25);
        mixed[1 * 3 + 1] = math.sqrt(0.25);
        mixed[36 + 3] = math.sqrt(0.25);
        mixed[36 + 0] = math.sqrt(0.25);
        expect(dominantColor(mixed, OutfitRegion.torso), isNull);
        expect(colorShares([0.0], OutfitRegion.torso), isNull);
      },
    );

    test('colourful / monochrome / contrasting / filter', () {
      final bluePlusWhite = descriptor(torsoHue: 7, legsValue: 3);
      expect(isColourful(bluePlusWhite), isTrue);
      expect(isContrasting(bluePlusWhite), isTrue);
      expect(isMonochrome(bluePlusWhite), isFalse);
      expect(
        hasColor(bluePlusWhite, OutfitColor.blue, region: OutfitRegion.torso),
        isTrue,
      );
      expect(
        hasColor(bluePlusWhite, OutfitColor.blue, region: OutfitRegion.legs),
        isFalse,
      );
      expect(
        hasColor(bluePlusWhite, OutfitColor.white),
        isTrue,
        reason: 'either region',
      );
      final allBlack = descriptor(torsoValue: 0, legsValue: 0);
      expect(isMonochrome(allBlack), isTrue);
      expect(isColourful(allBlack), isFalse);
      expect(isContrasting(allBlack), isFalse);
    });
  });
}
