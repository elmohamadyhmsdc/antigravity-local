import 'dart:io';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late FileStore files;
  late InMemoryEmbeddingIndex index;
  late PeopleRepository people;
  late PhotoResultStore store;
  void bind() {
    index = InMemoryEmbeddingIndex();
    people = PeopleRepository(db, files, index: index);
    store = PhotoResultStore(db: db, files: files, index: index);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('face_corrections_');
    db = AppDatabase(NativeDatabase(File('${dir.path}/library.db')));
    files = FileStore(Directory('${dir.path}/crops'));
    bind();
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });
  Future<MediaRow> media(String asset, {String kind = 'photo'}) async {
    final id = await seedMedia(db, asset: asset, kind: kind);
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  FaceAssignment assignment(int face, int person) => FaceAssignment(
    faceId: face,
    personId: person,
    score: .99,
    margin: .5,
    decision: 'auto',
  );
  FaceGroup group(List<int> faces) =>
      FaceGroup(faceIds: faces, cohesion: .99, quality: .9, autoCreate: true);

  test(
    'deleted photo face stays deleted after reopen and media reimport; another person survives',
    () async {
      final photo = await media('original');
      final response = analysis(
        faces: [
          faceJson(unitVec(1), box: [100, 100, 200, 240]),
          faceJson(unitVec(2), box: [600, 100, 200, 240]),
        ],
      );
      final initial = await store.store(photo, response);
      final removed = initial.newFaceIds.first;
      final crop = (await (db.select(
        db.faces,
      )..where((f) => f.id.equals(removed))).getSingle()).cropPath;
      await people.deleteFaces([removed]);
      expect(files.resolve(crop!).existsSync(), isFalse);
      await db.close();
      db = AppDatabase(NativeDatabase(File('${dir.path}/library.db')));
      bind();
      for (final face in await db.select(db.faces).get()) {
        await index.addAll([(face.id, embeddingFromBlob(face.embedding))]);
      }
      final repeated = await store.store(photo, response);
      expect(repeated.newFaces, 0);
      expect(
        (await db.select(db.faces).get()).single.id,
        initial.newFaceIds.last,
      );
      expect(await db.select(db.faceSuppressions).get(), hasLength(1));
      await (db.delete(db.media)..where((m) => m.id.equals(photo.id))).go();
      final imported = await media('original');
      expect((await store.store(imported, response)).newFaces, 1);
      expect(await db.select(db.faces).get(), hasLength(1));
    },
  );

  test(
    'known linked copies stay deleted, but the person is allowed in a new photo',
    () async {
      final a = await media('a'), b = await media('b');
      final response = analysis(faces: [faceJson(unitVec(1))]);
      final first = await store.store(a, response);
      expect((await store.store(b, response)).linkedFaces, 1);
      await people.deleteFaces(first.newFaceIds);
      expect((await store.store(a, response)).newFaces, 0);
      expect((await store.store(b, response)).newFaces, 0);
      final c = await media('new-photo');
      expect((await store.store(c, response)).newFaces, 1);
    },
  );

  test(
    'two copies of the same person in one photo do not both disappear',
    () async {
      final photo = await media('two-copies');
      final response = analysis(
        faces: [
          faceJson(unitVec(1), box: [100, 100, 200, 240]),
          faceJson(unitVec(1), box: [600, 100, 200, 240]),
        ],
      );
      final first = await store.store(photo, response);
      await people.deleteFaces([first.newFaceIds.first]);
      expect((await store.store(photo, response)).newFaces, 0);
      expect(
        (await db.select(db.faces).get()).single.id,
        first.newFaceIds.last,
      );
    },
  );

  test(
    'a deleted video face cannot return in a later moving frame or become weak body evidence',
    () async {
      final video = await media('video', kind: 'video');
      final first = await store.store(
        video,
        analysis(faces: [faceJson(unitVec(1))]),
        frameNumber: 0,
      );
      await people.deleteFaces(first.newFaceIds);
      final moved = await store.store(
        video,
        analysis(
          faces: [
            faceJson(unitVec(1), box: [600, 100, 200, 240]),
          ],
          bodies: [bodyJson()],
          pairs: [(0, 0)],
        ),
        frameNumber: 15,
      );
      expect(moved.newFaces, 0);
      expect(
        (await db.select(db.bodies).get()).single.weakFaceEmbedding,
        isNull,
      );
      expect(
        (await store.store(
          video,
          analysis(faces: [faceJson(unitVec(2))]),
          frameNumber: 30,
        )).newFaces,
        1,
      );
    },
  );

  test(
    'hide and rejection win over stale automatic and review plans',
    () async {
      final person = await seedPerson(db);
      final rejected = await seedFace(db, seed: 1);
      final hidden = [await seedFace(db, seed: 2), await seedFace(db, seed: 3)];
      final plan = GroupingPlanResponse(
        mode: 'apply',
        assignments: [assignment(rejected, person)],
        groups: [group(hidden)],
      );
      await people.rejectFaces([rejected], fromPersonId: person);
      await people.dismissFaces(hidden);
      final result = await PlanApplier(db).applyFacePlan(plan);
      expect((result.assigned, result.newPeople), (0, 0));
      final request = await GroupingInputs(db).request(
        mode: 'apply',
        stages: ['match', 'cluster'],
        strictness: 'balanced',
      );
      expect(request.dismissedFaceIds.toSet(), hidden.toSet());
      final review = ReviewRepository(db, people);
      await review.replaceAll(plan);
      expect(await review.matches(), isEmpty);
      expect(await review.groupItems(), isEmpty);
      await people.assignFaces([hidden.first], person);
      expect(
        (await (db.select(
              db.faces,
            )..where((f) => f.id.equals(hidden.first))).getSingle())
            .reviewDismissed,
        isFalse,
      );
    },
  );

  test(
    'merge preserves corrections and stale suggestions cannot undo the merge',
    () async {
      final source = await seedPerson(db, name: 'Drop');
      final target = await seedPerson(db, name: 'Keep');
      final third = await seedPerson(db, name: 'Different');
      final owned = await seedFace(db, personId: source, seed: 1);
      final stray = await seedFace(db, seed: 2);
      await people.rejectFaces([stray], fromPersonId: source);
      await people.markDistinct(source, third);
      final review = ReviewRepository(db, people);
      await review.replaceAll(
        GroupingPlanResponse(
          mode: 'review',
          duplicates: [
            DuplicatePeople(personA: target, personB: third, score: .99),
          ],
        ),
      );
      await people.mergePeople(sourceId: source, targetId: target);
      expect(await people.areDistinct(target, third), isTrue);
      expect(await review.duplicates(), isEmpty);
      final stale = GroupingPlanResponse(
        mode: 'apply',
        assignments: [assignment(stray, target)],
        groups: [
          group([owned]),
        ],
        duplicates: [
          DuplicatePeople(personA: target, personB: third, score: .99),
        ],
      );
      expect((await PlanApplier(db).applyFacePlan(stale)).assigned, 0);
      await review.replaceAll(stale);
      expect(await review.matches(), isEmpty);
      expect(await review.duplicates(), isEmpty);
      expect(await review.duplicateScore(target, third), isNull);
      expect(
        (await (db.select(
          db.faces,
        )..where((f) => f.id.equals(owned))).getSingle()).personId,
        target,
      );
      expect(
        await (db.select(
          db.persons,
        )..where((p) => p.id.equals(source))).getSingleOrNull(),
        isNull,
      );
    },
  );

  test(
    'deleting a person keeps their faces available manually without recreating a profile',
    () async {
      final person = await seedPerson(db);
      final face = await seedFace(db, personId: person);
      await people.deletePerson(person);
      expect(
        (await PlanApplier(db).applyFacePlan(
          GroupingPlanResponse(
            mode: 'apply',
            groups: [
              group([face]),
            ],
          ),
        )).newPeople,
        0,
      );
      expect(await db.select(db.persons).get(), isEmpty);
      expect((await db.select(db.faces).get()).single.reviewDismissed, isTrue);
    },
  );
}
