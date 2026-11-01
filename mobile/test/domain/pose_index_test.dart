// Roadmap Phase 2: the pose-descriptor cache, the Tier-A chips, ranked "find similar" and colour chips.

import 'dart:convert';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/outfit_palette.dart';
import 'package:antigravity_mobile/domain/pose/pose_descriptor.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

/// Frontal standing person on a 1000 x 1500 picture, in pixels.
const standing = <List<double>>[
  [500, 300],
  [530, 280],
  [470, 280],
  [560, 290],
  [440, 290],
  [650, 400],
  [350, 400],
  [670, 550],
  [330, 550],
  [680, 700],
  [320, 700],
  [560, 800],
  [440, 800],
  [560, 1050],
  [440, 1050],
  [560, 1300],
  [440, 1300],
];

String kpts(List<List<double>> pts, {int w = 1000, int h = 1500}) =>
    jsonEncode([
      for (final p in pts) [p[0] / w, p[1] / h, 0.9],
    ]);

List<List<double>> withWrist(double y) => [
  for (var i = 0; i < 17; i++) i == 9 ? [680, y] : standing[i],
];

const _mirror = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15];

List<List<double>> mirrorOf(List<List<double>> pts) => [
  for (var i = 0; i < 17; i++) [1000 - pts[_mirror[i]][0], pts[_mirror[i]][1]],
];

List<List<double>> rotated(List<List<double>> pts) => [
  for (final p in pts) [1500 - p[1], p[0]],
];

void main() {
  late AppDatabase db;
  late PoseIndex index;
  late int media;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    index = PoseIndex(db);
    media = await seedMedia(db, asset: 'p', width: 1000, height: 1500);
  });
  tearDown(() => db.close());

  Future<int> body(
    List<List<double>> pts, {
    String extent = 'full',
    int? personId,
    List<double>? appearance,
  }) async {
    final id = await seedBody(
      db,
      mediaId: media,
      personId: personId,
      linkMethod: personId == null ? null : 'manual',
      appearance: appearance,
    );
    await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
      BodiesCompanion(kpts: Value(kpts(pts)), extent: Value(extent)),
    );
    return id;
  }

  test('tags are stored as whole comma-delimited words', () {
    expect(encodeTags({'standing', 'frontal'}), ',frontal,standing,');
    expect(encodeTags({}), '');
    expect(decodeTags(',frontal,standing,'), ['frontal', 'standing']);
  });

  test(
    'rebuild writes one row per body once, with tags and a descriptor',
    () async {
      final a = await body(standing);
      final lying = await body(rotated(standing));
      await seedBody(db, mediaId: media); // no keypoints: not a candidate
      expect(await index.pending(), 2);
      expect(await index.rebuild(batch: 1), 2, reason: 'works in batches');
      expect(await index.pending(), 0);
      expect(await index.rebuild(), 0, reason: 'idempotent');

      final rows = {
        for (final r in await db.select(db.bodyPoseFeatures).get()) r.bodyId: r,
      };
      expect(rows[a]!.tags, ',frontal,standing,');
      expect(rows[a]!.scaleSource, 'torso');
      expect(rows[a]!.feature.length, 34 * 4);
      expect(rows[lying]!.tags, ',lying,');
    },
  );

  test('an outdated version, or a rewritten body, is rebuilt', () async {
    final a = await body(standing);
    await index.rebuild();
    await db.customStatement('UPDATE body_pose_features SET version = 0');
    expect(await index.pending(), 1);
    expect(await index.rebuild(), 1);
    await index.invalidate(a);
    expect(await index.pending(), 1);
  });

  test(
    'a body with no usable keypoints still gets a row so it is not retried forever',
    () async {
      final id = await seedBody(db, mediaId: media);
      await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
        const BodiesCompanion(kpts: Value('[[0.1,0.1,0.9]]')),
      );
      await index.rebuild();
      final row = await db.select(db.bodyPoseFeatures).getSingle();
      expect((row.visibleMask, row.tags, row.feature.length), (0, '', 0));
      expect(await index.pending(), 0);
    },
  );

  test('chips: bodies with a tag, counts, scoped to a person', () async {
    final lina = await seedPerson(db, name: 'Lina');
    final a = await body(standing, personId: lina);
    final b = await body(withWrist(250));
    await index.rebuild();
    expect(await index.bodiesWithTag('standing'), unorderedEquals([a, b]));
    expect(await index.bodiesWithTag('one_arm_up'), [b]);
    expect(await index.bodiesWithTag('standing', personId: lina), [a]);
    expect(
      await index.bodiesWithTag('stand'),
      isEmpty,
      reason: 'whole tags only',
    );
    final counts = await index.tagCounts();
    expect(
      (counts['standing'], counts['one_arm_up'], counts['frontal']),
      (2, 1, 2),
    );
    expect((await index.tagCounts(personId: lina))['one_arm_up'], isNull);
  });

  test(
    'find similar: the same pose first (a mirror counts), a lying body last, never itself',
    () async {
      final query = await body(withWrist(250));
      final mirror = await body(mirrorOf(withWrist(250)));
      final plain = await body(standing);
      final lying = await body(rotated(standing));
      await index.rebuild();

      final result = await index.findSimilar(query);
      expect(result.map((r) => r.bodyId), isNot(contains(query)));
      expect(result.first.bodyId, mirror);
      expect(result.first.similarity, closeTo(1, 1e-3));
      final order = result.map((r) => r.bodyId).toList();
      expect(order.indexOf(plain), lessThan(order.indexOf(lying)));
      expect(
        result.firstWhere((r) => r.bodyId == lying).similarity,
        lessThan(0.1),
      );
      expect(await index.findSimilar(query, limit: 2), hasLength(2));
    },
  );

  test(
    'find similar to a stored exemplar copy works after the exemplar body is gone',
    () async {
      final a = await body(standing);
      final b = await body(standing);
      await index.rebuild();
      final row = await (db.select(
        db.bodyPoseFeatures,
      )..where((x) => x.bodyId.equals(a))).getSingle();
      final feature = PoseFeature.fromBlob(
        row.feature,
        row.visibleMask,
        row.scaleSource,
      );
      await (db.delete(db.bodies)..where((x) => x.id.equals(a))).go();
      final result = await index.findSimilarToFeature(feature);
      expect(result.map((r) => r.bodyId), [b]);
    },
  );

  test('colour chips read the stored outfit descriptors', () async {
    List<double> region(int? hue, int? value) {
      final r = List<double>.filled(40, 0);
      if (hue != null) r[hue * 3 + 1] = 1;
      if (value != null) r[36 + value] = 1;
      return r;
    }

    final blueWhite = await body(
      standing,
      appearance: [...region(7, null), ...region(null, 3)],
    );
    final redBlack = await body(
      standing,
      appearance: [...region(0, null), ...region(null, 0)],
    );
    expect(await index.bodiesWithColor(OutfitColor.blue), [blueWhite]);
    expect(
      await index.bodiesWithColor(OutfitColor.blue, region: OutfitRegion.legs),
      isEmpty,
    );
    expect(
      await index.bodiesWithColor(OutfitColor.black, region: OutfitRegion.legs),
      [redBlack],
    );
    expect(await index.bodiesWithColor(OutfitColor.red), [redBlack]);
  });
}
