// Guards around the grouping data: one person is never twice in a frame, a lone video appearance
// is not a person, a damaged embedding cannot stop grouping, and merges cannot contradict the data.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart'
    show characterEmbeddingModelId;
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_config.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late PeopleRepository repo;
  late PlanApplier applier;
  late GroupingInputs inputs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_guards_');
    repo = PeopleRepository(
      db,
      FileStore(Directory('${tmp.path}/crops')),
      index: InMemoryEmbeddingIndex(),
    );
    applier = PlanApplier(db);
    inputs = GroupingInputs(db);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int?> personOf(int faceId) async => (await (db.select(
    db.faces,
  )..where((f) => f.id.equals(faceId))).getSingle()).personId;

  GroupingPlanResponse assign(int faceId, int personId) => GroupingPlanResponse(
    mode: 'apply',
    assignments: [
      FaceAssignment(
        faceId: faceId,
        personId: personId,
        score: 0.9,
        margin: 0.5,
        decision: 'auto',
      ),
    ],
  );

  group('one person is never twice in a frame', () {
    test('a doubtful track cannot propagate its owner to more faces', () async {
      final person = await seedPerson(db);
      final anchor = await seedFace(db, personId: person);
      final pending = await seedFace(db, seed: 2);
      await (db.update(db.faces)..where((f) => f.id.isIn([anchor, pending])))
          .write(FacesCompanion(trackId: Value(anchor)));
      await db
          .into(db.reviewDoubtful)
          .insert(
            ReviewDoubtfulCompanion.insert(
              faceId: Value(anchor),
              personId: person,
              score: 0.1,
            ),
          );
      await applier.applyFacePlan(const GroupingPlanResponse(mode: 'apply'));
      expect(await personOf(pending), isNull);
    });

    test(
      'doubtful assignments are excluded from subsequent identity models',
      () async {
        final person = await seedPerson(db);
        await seedFace(db, personId: person);
        final wrong = await seedFace(db, personId: person, seed: 2);
        expect((await inputs.models()).single.count, 2);
        await db
            .into(db.reviewDoubtful)
            .insert(
              ReviewDoubtfulCompanion.insert(
                faceId: Value(wrong),
                personId: person,
                score: 0.1,
              ),
            );
        expect((await inputs.models()).single.count, 1);
        await repo.confirmFaces([wrong], person);
        expect((await inputs.models()).single.count, 2);
      },
    );

    test(
      'a stale automatic face match respects hidden and no-owner corrections',
      () async {
        final person = await seedPerson(db);
        final hidden = await seedFace(db),
            noOwner = await seedFace(db, seed: 2);
        await (db.update(db.faces)..where((f) => f.id.equals(hidden))).write(
          const FacesCompanion(hidden: Value(true)),
        );
        await (db.update(db.faces)..where((f) => f.id.equals(noOwner))).write(
          const FacesCompanion(ownership: Value('none')),
        );
        await applier.applyFacePlan(assign(hidden, person));
        await applier.applyFacePlan(assign(noOwner, person));
        expect(await personOf(hidden), isNull);
        expect(await personOf(noOwner), isNull);
      },
    );
    test('the applier will not add a second face of the same photo', () async {
      final sara = await seedPerson(db);
      final photo = await seedMedia(db);
      final other = await seedMedia(db, asset: 'asset-2');
      await seedFace(db, mediaId: photo, personId: sara, seed: 1);
      final sameFrame = await seedFace(db, mediaId: photo, seed: 2);
      final elsewhere = await seedFace(db, mediaId: other, seed: 3);

      await applier.applyFacePlan(assign(sameFrame, sara));
      await applier.applyFacePlan(assign(elsewhere, sara));

      expect(await personOf(sameFrame), isNull);
      expect(await personOf(elsewhere), sara);
    });

    test('different frames of one video are fine', () async {
      final sara = await seedPerson(db);
      final video = await seedMedia(db, kind: 'video');
      await seedFace(
        db,
        mediaId: video,
        frameNumber: 10,
        personId: sara,
        seed: 1,
      );
      final later = await seedFace(
        db,
        mediaId: video,
        frameNumber: 40,
        seed: 2,
      );

      await applier.applyFacePlan(assign(later, sara));

      expect(await personOf(later), sara);
    });

    test('people sharing a frame are sent as distinct pairs', () async {
      final a = await seedPerson(db), b = await seedPerson(db);
      final c = await seedPerson(db);
      final photo = await seedMedia(db);
      await seedFace(db, mediaId: photo, personId: a, seed: 1);
      await seedFace(db, mediaId: photo, personId: b, seed: 2);
      await seedFace(db, personId: c, seed: 3);
      await db
          .into(db.personDistinct)
          .insert(PersonDistinctCompanion.insert(personA: a, personB: c));

      expect(await inputs.distinctPairs(), [(a, b), (a, c)]);
      final request = await inputs.request(
        mode: 'apply',
        stages: ['match', 'cluster'],
        strictness: 'balanced',
      );
      expect(request.linkAlikePeople, isTrue);
      expect(request.distinctPairs, [(a, b), (a, c)]);
    });

    test('merging two people who appear together is refused', () async {
      final a = await seedPerson(db), b = await seedPerson(db);
      final photo = await seedMedia(db);
      await seedFace(db, mediaId: photo, personId: a, seed: 1);
      final bFace = await seedFace(db, mediaId: photo, personId: b, seed: 2);

      expect(await repo.sharedFrames(a, b), 1);
      await expectLater(
        repo.mergePeople(sourceId: b, targetId: a),
        throwsA(isA<MergeBlockedException>()),
      );
      expect(await personOf(bFace), b);
      expect(
        await (db.select(db.persons)..where((p) => p.id.equals(b))).get(),
        hasLength(1),
      );
    });

    test('a merge that is consistent still works', () async {
      final a = await seedPerson(db), b = await seedPerson(db);
      final photo = await seedMedia(db);
      final other = await seedMedia(db, asset: 'asset-2');
      await seedFace(db, mediaId: photo, personId: a, seed: 1);
      final bFace = await seedFace(db, mediaId: other, personId: b, seed: 2);

      await repo.mergePeople(sourceId: b, targetId: a);

      expect(await personOf(bFace), a);
    });

    test('a person and a character are never merged', () async {
      final a = await seedPerson(db);
      final c = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              kind: const Value('character'),
              createdAt: 1,
            ),
          );

      await expectLater(
        repo.mergePeople(sourceId: c, targetId: a),
        throwsA(isA<MergeBlockedException>()),
      );
    });
  });

  group('new people from groups', () {
    GroupingPlanResponse group(List<int> ids) => GroupingPlanResponse(
      mode: 'apply',
      groups: [
        FaceGroup(faceIds: ids, cohesion: 0.9, quality: 0.8, autoCreate: true),
      ],
    );

    Future<int> people() async => (await db.select(db.persons).get()).length;

    test('a group from one video alone does not become a person', () async {
      final video = await seedMedia(db, kind: 'video');
      final ids = [
        for (var i = 0; i < 3; i++)
          await seedFace(db, mediaId: video, frameNumber: i * 30, seed: i + 1),
      ];

      final result = await applier.applyFacePlan(group(ids));

      expect(result.newPeople, 0);
      expect(await people(), 0);
      for (final id in ids) {
        expect(await personOf(id), isNull);
      }
    });

    test('a group seen in two files does', () async {
      final one = await seedMedia(db);
      final two = await seedMedia(db, asset: 'asset-2');
      final three = await seedMedia(db, asset: 'asset-3');
      final ids = [
        await seedFace(db, mediaId: one, seed: 1),
        await seedFace(db, mediaId: two, seed: 2),
        await seedFace(db, mediaId: three, seed: 3),
      ];

      final result = await applier.applyFacePlan(group(ids));

      expect(result.newPeople, 1);
      expect(await people(), 1);
    });

    test('faces with no file are not judged by it', () async {
      final ids = [for (var i = 0; i < 3; i++) await seedFace(db, seed: i + 1)];

      expect((await applier.applyFacePlan(group(ids))).newPeople, 1);
    });

    test(
      'a duplicate of a face also seen elsewhere counts as another file',
      () async {
        final video = await seedMedia(db, kind: 'video');
        final photo = await seedMedia(db, asset: 'asset-2');
        final ids = [
          for (var i = 0; i < 3; i++)
            await seedFace(
              db,
              mediaId: video,
              frameNumber: i * 30,
              seed: i + 1,
            ),
        ];
        await db
            .into(db.mediaDetections)
            .insert(
              MediaDetectionsCompanion.insert(
                mediaId: photo,
                kind: 'f',
                refId: ids.first,
                x: 0.1,
                y: 0.1,
                w: 0.2,
                h: 0.2,
              ),
            );

        expect((await applier.applyFacePlan(group(ids))).newPeople, 1);
      },
    );
  });

  group('tiny faces', () {
    Future<void> shrink(int faceId, double px) =>
        (db.update(db.faces)..where((f) => f.id.equals(faceId))).write(
          FacesCompanion(facePx: Value(px)),
        );

    test(
      'are not grouped, matched against or used to build a person',
      () async {
        final sara = await seedPerson(db);
        final good = await seedFace(db, personId: sara, seed: 1);
        final speck = await seedFace(db, personId: sara, seed: 2);
        final lonely = await seedFace(db, seed: 3);
        final stranger = await seedFace(db, seed: 4);
        await shrink(speck, 30);
        await shrink(stranger, 30);

        expect((await inputs.pending()).map((f) => f.id), [lonely]);
        final models = await inputs.models();
        expect(models, hasLength(1));
        expect(
          models.single.count,
          1,
          reason: 'only the face big enough counts',
        );
        expect(good, isNonZero);
      },
    );

    test(
      'a drawn character face is judged by the lower character bar',
      () async {
        final c = await db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(
                kind: const Value('character'),
                createdAt: 1,
              ),
            );
        final vector = Float32List(768)..[0] = 1; // CCIP size
        final small = await seedFace(db, personId: c, embedding: vector);
        final tiny = await seedFace(db, personId: c, embedding: vector);
        await shrink(small, 35);
        await shrink(tiny, 20);
        await (db.update(
          db.faces,
        )..where((f) => f.id.isIn([small, tiny]))).write(
          const FacesCompanion(
            kind: Value('character'),
            modelId: Value(characterEmbeddingModelId),
          ),
        );

        final models = await GroupingInputs(db, kind: 'character').models();

        expect(models.single.count, 1);
      },
    );
  });

  group('person models', () {
    test('a stranger grouped in by mistake does not shape the model', () async {
      Float32List dir(int axis, [int axis2 = -1, double w = 0.0]) {
        final v = Float32List(512)..[axis] = 1;
        if (axis2 >= 0) v[axis2] = w;
        return v;
      }

      final sara = await seedPerson(db);
      for (var i = 0; i < 8; i++) {
        await seedFace(
          db,
          personId: sara,
          embedding: dir(0, 10 + i, 0.2),
          quality: 0.7,
        );
      }
      await seedFace(
        db,
        personId: sara,
        embedding: dir(300),
        quality: 0.95,
      ); // not her

      final model = (await inputs.models()).single;

      expect(model.count, 8, reason: 'the odd face is left out');
      // the prototype points at her, not between her and the stranger
      var dot = 0.0;
      for (var i = 0; i < 512; i++) {
        dot += model.proto[i] * dir(0)[i];
      }
      expect(dot, greaterThan(0.95));
      expect(model.members.every((m) => m[300].abs() < 0.01), isTrue);
    });

    test(
      'a person with many faces keeps profiles among the members, not only the sharpest',
      () async {
        final sara = await seedPerson(db);
        Float32List mix(int main, int other, double w) {
          final v = Float32List(512)
            ..[main] = 1
            ..[other] = w;
          var s = 0.0;
          for (final x in v) {
            s += x * x;
          }
          final n = math.sqrt(s);
          return Float32List.fromList([for (final x in v) x / n]);
        }

        for (var i = 0; i < 40; i++) {
          await seedFace(
            db,
            personId: sara,
            embedding: mix(0, 1 + (i % 3), 0.9),
            quality: 0.9,
          );
        }
        for (var i = 0; i < 12; i++) {
          await seedFace(
            db,
            personId: sara,
            embedding: mix(0, 100 + i, 0.9),
            quality: 0.3,
          ); // other looks, each its own
        }

        final model = (await inputs.models(cap: 20)).single;

        expect(model.members, hasLength(20));
        final unusual = model.members.where(
          (m) => m.sublist(100, 112).any((x) => x.abs() > 0.1),
        );
        expect(
          unusual,
          isNotEmpty,
          reason:
              'the unusual looks are represented, not only the sharpest faces',
        );
      },
    );
  });

  group('reface sources', () {
    late StudioRepository studio;
    setUp(() {
      studio = StudioRepository(db, FileStore(Directory('${tmp.path}/studio')));
    });

    test('skip hidden, tiny and nobody-owned faces', () async {
      final sara = await seedPerson(db);
      final fine = await seedFace(db, personId: sara, seed: 1);
      final hidden = await seedFace(db, personId: sara, seed: 2);
      final tiny = await seedFace(db, personId: sara, seed: 3);
      final nobody = await seedFace(db, personId: sara, seed: 4);
      await (db.update(db.faces)..where((f) => f.id.equals(hidden))).write(
        const FacesCompanion(hidden: Value(true)),
      );
      await (db.update(db.faces)..where((f) => f.id.equals(tiny))).write(
        const FacesCompanion(facePx: Value(50)),
      );
      await (db.update(db.faces)..where((f) => f.id.equals(nobody))).write(
        const FacesCompanion(ownership: Value('none')),
      );

      expect((await studio.sourceFaces(sara)).map((f) => f.id), [fine]);
    });

    test('the default selection spreads over head poses', () async {
      final sara = await seedPerson(db);
      // eight frontal shots of the best quality, then three different poses of lower quality
      for (var i = 0; i < 8; i++) {
        final f = await seedFace(db, personId: sara, seed: i + 1, quality: 0.9);
        await (db.update(db.faces)..where((x) => x.id.equals(f))).write(
          FacesCompanion(yaw: Value(1.0 + i), pitch: const Value(0)),
        );
      }
      final profiles = <int>[];
      for (final (i, yaw) in [50.0, -50.0, 30.0].indexed) {
        final f = await seedFace(
          db,
          personId: sara,
          seed: 20 + i,
          quality: 0.6,
        );
        await (db.update(db.faces)..where((x) => x.id.equals(f))).write(
          FacesCompanion(yaw: Value(yaw), pitch: const Value(0)),
        );
        profiles.add(f);
      }

      final picked = StudioRepository.diverseSources(
        await studio.sourceFaces(sara),
        5,
      );

      // the two extreme profiles are in, ahead of the sixth frontal shot of the same sitting
      expect(
        picked.map((f) => f.id).toSet().intersection(profiles.take(2).toSet()),
        hasLength(2),
      );
      expect(
        picked.where((f) => (f.yaw ?? 0).abs() < 10),
        hasLength(lessThan(4)),
      );
    });
  });

  group('request size', () {
    test(
      'the per-person member cap shrinks in a big library so the request stays under the PC limit',
      () {
        expect(effectiveMemberCap(50), 100);
        expect(effectiveMemberCap(360), 100);
        expect(effectiveMemberCap(800), 45); // 36000 / 800
        expect(effectiveMemberCap(5000), groupingMinMemberCap);
        expect(effectiveMemberCap(0), 100);
        for (final people in [10, 400, 1000, 3000]) {
          final members = people * effectiveMemberCap(people);
          // 2.7 KB of base64 per vector, uncompressed JSON: under 128 MB on the wire even before gzip
          expect(
            members * 2732 / 1048576,
            lessThan(128 * 1.0 + (people > 1000 ? 200 : 0)),
          );
        }
      },
    );
  });

  group('mixed embedding models', () {
    test(
      'faces from another model are left out of grouping once the library has a model',
      () async {
        final sara = await seedPerson(db);
        final mine = await seedFace(db, personId: sara, seed: 1);
        final foreign = await seedFace(db, personId: sara, seed: 2);
        final loose = await seedFace(db, seed: 3);
        final looseForeign = await seedFace(db, seed: 4);
        for (final id in [foreign, looseForeign]) {
          await (db.update(db.faces)..where((f) => f.id.equals(id))).write(
            const FacesCompanion(modelId: Value('antelopev2@1')),
          );
        }

        // no model recorded yet: nothing is filtered
        expect(
          (await inputs.pending()).map((f) => f.id),
          containsAll([loose, looseForeign]),
        );
        expect((await inputs.models()).single.count, 2);

        await db.putSetting('library.model_id', 'buffalo_l@1');

        expect((await inputs.pending()).map((f) => f.id), [loose]);
        expect((await inputs.models()).single.count, 1);
        expect(mine, isNonZero);
      },
    );
  });

  group('damaged data cannot stop grouping', () {
    test(
      'a face with a wrong-sized or non-finite vector is left out',
      () async {
        final sara = await seedPerson(db);
        await seedFace(db, personId: sara, seed: 1);
        final broken = await seedFace(db, seed: 2);
        final nan = await seedFace(db, seed: 3);
        final fine = await seedFace(db, seed: 4);
        await (db.update(db.faces)..where((f) => f.id.equals(broken))).write(
          FacesCompanion(embedding: Value(Uint8List(12))),
        );
        final bad = Float32List(512)..[0] = double.nan;
        await (db.update(db.faces)..where((f) => f.id.equals(nan))).write(
          FacesCompanion(embedding: Value(bad.buffer.asUint8List())),
        );

        expect((await inputs.pending()).map((f) => f.id), [fine]);
        expect(await inputs.models(), hasLength(1));
      },
    );
  });
}
