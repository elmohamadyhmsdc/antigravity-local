// Roadmap Phase 3: categories from an example - preview, remove-before-save, "rejected is never re-added",
// scoring of new scans, the exemplar copy that survives its body, and outfit categories.

import 'dart:convert';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/body_categories.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

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

List<List<double>> withWrist(double y) => [
  for (var i = 0; i < 17; i++) i == 9 ? [680, y] : standing[i],
];

List<List<double>> rotated(List<List<double>> pts) => [
  for (final p in pts) [1500 - p[1], p[0]],
];

String kpts(List<List<double>> pts) => jsonEncode([
  for (final p in pts) [p[0] / 1000, p[1] / 1500, 0.9],
]);

void main() {
  late AppDatabase db;
  late PoseIndex poses;
  late BodyCategories categories;
  late int media;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    poses = PoseIndex(db);
    categories = BodyCategories(db, poses: poses);
    media = await seedMedia(db, asset: 'c', width: 1000, height: 1500);
  });
  tearDown(() => db.close());

  Future<int> body(List<List<double>> pts, {List<double>? appearance}) async {
    final id = await seedBody(db, mediaId: media, appearance: appearance);
    await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
      BodiesCompanion(kpts: Value(kpts(pts)), extent: const Value('full')),
    );
    return id;
  }

  group('poses', () {
    test(
      'preview lists what looks alike; saving keeps them, rejects the removed, and the exemplar is manual',
      () async {
        final exemplar = await body(withWrist(250));
        final alike1 = await body(withWrist(255));
        final alike2 = await body(withWrist(245));
        final lying = await body(rotated(standing));
        await poses.rebuild();

        final draft = (await categories.draftPose(exemplar))!;
        expect(
          draft.matches.map((m) => m.bodyId),
          containsAll([exemplar, alike1, alike2]),
        );
        expect(draft.matches.map((m) => m.bodyId), isNot(contains(lying)));
        expect(
          draft.matches.first.similarity,
          greaterThanOrEqualTo(draft.matches.last.similarity),
        );

        final id = await categories.savePose(
          draft,
          '  Hand up ',
          removed: {alike2},
        );
        final category = await db.select(db.poseCategories).getSingle();
        expect(
          (category.name, category.exemplarBodyId, category.threshold),
          ('Hand up', exemplar, defaultPoseThreshold),
        );
        final states = {
          for (final m in await db.select(db.bodyPoseMatches).get())
            m.bodyId: m.state,
        };
        expect(states[alike1], 'auto');
        expect(states[alike2], 'rejected');
        expect(states[exemplar], 'manual');
        expect(states.containsKey(lying), isFalse);
        expect(
          await categories.bodiesInPose(id),
          unorderedEquals([exemplar, alike1]),
        );
      },
    );

    test('a body without a descriptor cannot be named', () async {
      final id = await seedBody(db, mediaId: media);
      await poses.rebuild();
      expect(await categories.draftPose(id), isNull);
    });

    test(
      'new scans are scored; a rejected body is never added again',
      () async {
        final exemplar = await body(withWrist(250));
        final removedOne = await body(withWrist(252));
        await poses.rebuild();
        final id = await categories.savePose(
          (await categories.draftPose(exemplar))!,
          'Hand up',
          removed: {removedOne},
        );

        final newcomer = await body(withWrist(248));
        final stranger = await body(rotated(standing));
        await poses.rebuild();
        expect(await categories.rescorePose(id), 1);
        expect(
          await categories.bodiesInPose(id),
          unorderedEquals([exemplar, newcomer]),
        );
        expect(
          await categories.rescorePose(id),
          0,
          reason: 'nothing new, nothing added',
        );
        final states = {
          for (final m in await db.select(db.bodyPoseMatches).get())
            m.bodyId: m.state,
        };
        expect(
          states[removedOne],
          'rejected',
          reason: 'still rejected after the rescoring',
        );
        expect(states.containsKey(stranger), isFalse);

        await categories.setPoseState(id, stranger, 'manual');
        expect(await categories.bodiesInPose(id), contains(stranger));
        await categories.setPoseState(id, newcomer, 'rejected');
        expect(await categories.bodiesInPose(id), isNot(contains(newcomer)));
        expect(await categories.rescoreAllPoses(), 0);
      },
    );

    test(
      'deleting the exemplar body keeps the category and its stored exemplar',
      () async {
        final exemplar = await body(withWrist(250));
        final other = await body(withWrist(251));
        await poses.rebuild();
        final id = await categories.savePose(
          (await categories.draftPose(exemplar))!,
          'Hand up',
        );
        await (db.delete(db.bodies)..where((b) => b.id.equals(exemplar))).go();
        final category = await db.select(db.poseCategories).getSingle();
        expect(category.exemplarBodyId, isNull);
        expect(category.exemplarFeature.length, 34 * 4);
        expect(await categories.bodiesInPose(id), [other]);
        final later = await body(withWrist(249));
        await poses.rebuild();
        expect(await categories.rescorePose(id), 1);
        expect(
          await categories.bodiesInPose(id),
          unorderedEquals([other, later]),
        );
      },
    );

    test('rename and delete cascade to the matches', () async {
      final exemplar = await body(withWrist(250));
      await poses.rebuild();
      final id = await categories.savePose(
        (await categories.draftPose(exemplar))!,
        'A',
      );
      await categories.renamePose(id, 'B ');
      expect((await db.select(db.poseCategories).getSingle()).name, 'B');
      await categories.deletePose(id);
      expect(await db.select(db.poseCategories).get(), isEmpty);
      expect(await db.select(db.bodyPoseMatches).get(), isEmpty);
    });
  });

  group('outfits', () {
    List<double> shade(int seed, {double legs = 1}) {
      final a = outfit(seed);
      return [...a.take(40), ...a.skip(40).map((v) => v * legs)];
    }

    test(
      'preview by outfit, scoped to a person, lower-only ignores the torso',
      () async {
        final lina = await seedPerson(db, name: 'Lina');
        final a = outfit(1);
        final same = await seedBody(
          db,
          mediaId: media,
          personId: lina,
          linkMethod: 'manual',
          appearance: a,
        );
        final alike = await seedBody(db, mediaId: media, appearance: a);
        final other = await seedBody(db, mediaId: media, appearance: outfit(9));
        final sameLegsOnly = await seedBody(
          db,
          mediaId: media,
          appearance: [...outfit(4).take(40), ...a.skip(40)],
        );

        var draft = (await categories.draftOutfit(same))!;
        expect(
          draft.matches.map((m) => m.bodyId),
          unorderedEquals([same, alike]),
        );
        expect(draft.matches.map((m) => m.bodyId), isNot(contains(other)));

        draft = (await categories.draftOutfit(same, lowerOnly: true))!;
        expect(
          draft.matches.map((m) => m.bodyId),
          containsAll([same, alike, sameLegsOnly]),
        );

        draft = (await categories.draftOutfit(same, personId: lina))!;
        expect(draft.matches.map((m) => m.bodyId), [
          same,
        ], reason: 'person-scoped');
        expect(shade(1).length, 80);
      },
    );

    test(
      'save, rejection memory, rescoring, deletion of the exemplar',
      () async {
        final a = outfit(2);
        final ex = await seedBody(db, mediaId: media, appearance: a);
        final dup = await seedBody(db, mediaId: media, appearance: a);
        final id = await categories.saveOutfit(
          (await categories.draftOutfit(ex))!,
          'Red jacket',
          removed: {dup},
        );
        expect(await categories.bodiesInOutfit(id), [ex]);
        final fresh = await seedBody(db, mediaId: media, appearance: a);
        expect(
          await categories.rescoreOutfit(id),
          1,
          reason: 'only the new body: dup stays rejected',
        );
        expect(
          await categories.bodiesInOutfit(id),
          unorderedEquals([ex, fresh]),
        );
        await (db.delete(db.bodies)..where((b) => b.id.equals(ex))).go();
        final category = await db.select(db.outfitCategories).getSingle();
        expect(
          (category.exemplarBodyId, category.exemplarAppearance.length),
          (null, 320),
        );
        expect(await categories.rescoreAllOutfits(), 0);
        await categories.deleteOutfit(id);
        expect(await db.select(db.bodyOutfitMatches).get(), isEmpty);
      },
    );

    test('a body without an outfit cannot be named', () async {
      final id = await seedBody(db, mediaId: media);
      expect(await categories.draftOutfit(id), isNull);
    });
  });
}
