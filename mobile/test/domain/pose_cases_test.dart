// The shared golden pose cases (the app/mobile_api/contract/fixtures/pose/cases.json, written by
// the app/test_pose_filters.py): the Dart rules and descriptor must give exactly what the Python
// implementation gives, so the Phase 0 evaluation measures the rules the phone runs.

import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/domain/pose/pose_descriptor.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:antigravity_mobile/domain/pose/pose_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final file = File('../the app/mobile_api/contract/fixtures/pose/cases.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = json['cases'] as Map<String, dynamic>;

  Pose poseOf(Map<String, dynamic> c) => Pose(
    [
      for (final p in c['points'] as List<dynamic>)
        Pt(
          (p[0] as num).toDouble(),
          (p[1] as num).toDouble(),
          (p[2] as num).toDouble(),
        ),
    ],
    extent: c['extent'] as String?,
    faceYaw: (c['face_yaw'] as num?)?.toDouble(),
  );

  test('there are cases to compare', () {
    expect(cases.length, greaterThanOrEqualTo(10));
  });

  for (final entry in cases.entries) {
    test('${entry.key}: same tags and same descriptor as Python', () {
      final c = entry.value as Map<String, dynamic>;
      final pose = poseOf(c);
      expect(
        tierATags(pose).toList()..sort(),
        (c['tags'] as List<dynamic>).cast<String>(),
      );
      final feature = buildPoseFeature(pose);
      final expected = c['feature'] as Map<String, dynamic>?;
      if (expected == null) {
        expect(feature, isNull);
        return;
      }
      expect(feature, isNotNull);
      expect(feature!.scaleSource, expected['scale_source']);
      expect(feature.mask, expected['mask']);
      final data = (expected['data'] as List<dynamic>).cast<num>();
      for (var i = 0; i < 34; i++) {
        expect(
          feature.data[i],
          closeTo(data[i].toDouble(), 1e-4),
          reason: 'float $i',
        );
      }
    });
  }

  test('pairwise similarity, coverage and comparability match Python', () {
    final features = <String, PoseFeature?>{
      for (final e in cases.entries)
        e.key: buildPoseFeature(poseOf(e.value as Map<String, dynamic>)),
    };
    final pairs = json['similarities'] as List<dynamic>;
    expect(pairs, isNotEmpty);
    for (final p in pairs) {
      final a = features[p['a']]!, b = features[p['b']]!;
      final result = comparePoses(a, b);
      final expected = p['result'] as Map<String, dynamic>?;
      if (expected == null) {
        expect(result, isNull, reason: '${p['a']} vs ${p['b']}');
      } else {
        expect(result, isNotNull, reason: '${p['a']} vs ${p['b']}');
        expect(
          result!.similarity,
          closeTo((expected['similarity'] as num).toDouble(), 1e-3),
        );
        expect(
          result.coverage,
          closeTo((expected['coverage'] as num).toDouble(), 1e-3),
        );
        expect(result.shared, expected['shared']);
      }
    }
  });
}
