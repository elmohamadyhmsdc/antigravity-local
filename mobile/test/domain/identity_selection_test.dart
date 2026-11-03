// Which faces really are a person, and which are worth building a model / LoRA anchor / swap source from.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/domain/identity/identity_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List unit(math.Random r) {
  final v = Float32List.fromList([
    for (var i = 0; i < 512; i++) r.nextDouble() * 2 - 1,
  ]);
  return _normalize(v);
}

Float32List _normalize(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x * x;
  }
  final n = math.sqrt(s);
  return Float32List.fromList([for (final x in v) x / n]);
}

/// A face of the person whose look is [centre]: the centre plus some noise.
Float32List near(Float32List centre, math.Random r, [double noise = 0.5]) {
  final n = unit(r);
  return _normalize(
    Float32List.fromList([
      for (var i = 0; i < centre.length; i++) centre[i] + noise * n[i],
    ]),
  );
}

IdentityFace face(
  int id,
  Float32List e, {
  double q = 0.7,
  double? yaw,
  double? pitch,
}) => IdentityFace(id: id, embedding: e, quality: q, yaw: yaw, pitch: pitch);

void main() {
  final r = math.Random(5);
  final her = unit(r), stranger = unit(r);

  test('a stranger grouped in by mistake is an outlier; the rest stay', () {
    final faces = [
      for (var i = 0; i < 8; i++) face(i, near(her, r), q: 0.8 - i * 0.01),
      face(100, near(stranger, r), q: 0.9), // the best quality face of all - and not her
      face(101, near(stranger, r), q: 0.5),
    ];

    final s = selectIdentity(faces, dedupe: false);

    expect(s.outliers.toSet(), {100, 101});
    expect(s.kept.map((f) => f.id).toSet(), {for (var i = 0; i < 8; i++) i});
    expect(s.consistency, greaterThan(0.6));
  });

  test('a small set is never trimmed, and neither is one that is mostly "foreign"', () {
    final few = [
      face(1, near(her, r)),
      face(2, near(her, r)),
      face(3, near(stranger, r)),
      face(4, near(her, r)),
    ];
    expect(selectIdentity(few).outliers, isEmpty);

    // half and half: nobody can say which half is the person, so nothing is thrown away
    final split = [
      for (var i = 0; i < 4; i++) face(i, near(her, r)),
      for (var i = 0; i < 4; i++) face(10 + i, near(stranger, r)),
    ];
    expect(selectIdentity(split, dedupe: false).outliers, isEmpty);
  });

  test('near-identical pictures count once, the best one is kept', () {
    final e = near(her, r);
    final faces = [
      face(1, e, q: 0.6),
      face(2, e, q: 0.9),
      face(3, near(her, r), q: 0.7),
    ];

    final s = selectIdentity(faces, minToTrim: 99);

    expect(s.duplicates, [1]);
    expect(s.kept.map((f) => f.id), containsAll([2, 3]));
  });

  test('the top picks cover head poses, not eight frontal shots', () {
    final faces = [
      for (var i = 0; i < 8; i++)
        face(i, near(her, r), q: 0.9, yaw: 1.0 + i, pitch: 0),
      face(50, near(her, r), q: 0.6, yaw: 55, pitch: 0),
      face(51, near(her, r), q: 0.6, yaw: -55, pitch: 5),
    ];

    final s = selectIdentity(faces, top: 4, dedupe: false);

    expect(s.kept, hasLength(4));
    expect(s.kept.map((f) => f.id), containsAll([50, 51]));
    expect(s.poseCoverage.keys, containsAll(['3,0', '-3,0']));
  });

  test('damaged vectors are outliers, not a crash', () {
    final s = selectIdentity([
      face(1, near(her, r)),
      face(2, Float32List(512)), // all zero
      face(3, Float32List.fromList(List.filled(512, double.nan))),
    ]);

    expect(s.outliers.toSet(), {2, 3});
    expect(s.kept.single.id, 1);
  });
}
