import 'dart:io';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_questions.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/seed.dart';

void main() {
  PersonSummary person(int id) => PersonSummary(
    id: id,
    name: 'Person $id',
    faceCount: 100,
    avatarCropPath: null,
    createdAt: DateTime(2026),
  );
  ReviewMatchFace face(
    int id, {
    double score = 0.45,
    double margin = 0.1,
    double quality = 0.8,
  }) => ReviewMatchFace(
    faceId: id,
    cropPath: null,
    score: score,
    decision: 'suggest',
    margin: margin,
    quality: quality,
  );

  test(
    '18000 hypotheses become bounded visible batches; weak evidence is retained',
    () {
      final m = ReviewMatchGroup(
        person: person(1),
        faces: [
          for (var i = 0; i < 18000; i++)
            face(i, score: i < 12000 ? 0.28 : 0.45),
        ],
      );
      final watch = Stopwatch()..start();
      final ready = buildQuestions(
        matches: [m],
        groups: [],
        duplicates: [],
        outfits: [],
      );
      expect(
        ready,
        hasLength(250),
      ); // 6000 useful suggestions / 24 visible members
      expect(
        ready.every((q) => q.matchFaces.length <= reviewBatchSize),
        isTrue,
      );
      expect(
        ready.expand((q) => q.matchFaces).map((f) => f.faceId).toSet(),
        hasLength(6000),
      );
      final all = buildQuestions(
        matches: [m],
        groups: [],
        duplicates: [],
        outfits: [],
        includeDeferred: true,
      );
      expect(all.expand((q) => q.matchFaces), hasLength(18000));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    },
  );

  test('repair questions precede even very large duplicate merges', () {
    final repair = ReviewDoubtfulItem(
      person: person(1),
      faces: [const ReviewDoubtfulFace(faceId: 10, cropPath: null, score: 0.1)],
      remaining: 1,
    );
    final q = buildQuestions(
      matches: [],
      groups: [],
      duplicates: [ReviewDuplicateItem(a: person(1), b: person(2), score: 0.6)],
      outfits: [],
      doubtful: [repair],
    );
    expect(q.first.kind, ReviewQuestionKind.doubtful);
  });

  test(
    'uncertain rival or poor quality does not become work just because similarity is high',
    () {
      final q = buildQuestions(
        matches: [
          ReviewMatchGroup(
            person: person(1),
            faces: [face(1, margin: 0.01), face(2, quality: 0.2), face(3)],
          ),
        ],
        groups: [],
        duplicates: [],
        outfits: [],
      );
      expect(q.single.matchFaces.single.faceId, 3);
    },
  );

  group('stored review and corrections', () {
    late AppDatabase db;
    late Directory temp;
    late PeopleRepository people;
    late ReviewRepository review;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      temp = Directory.systemTemp.createTempSync('ag_review_backlog_');
      people = PeopleRepository(
        db,
        FileStore(temp),
        index: InMemoryEmbeddingIndex(),
      );
      review = ReviewRepository(db, people);
    });
    tearDown(() async {
      await db.close();
      temp.deleteSync(recursive: true);
    });
    Future<void> match(int id, int pid, double score) => db
        .into(db.reviewMatches)
        .insertOnConflictUpdate(
          ReviewMatchesCompanion.insert(
            faceId: Value(id),
            personId: pid,
            score: score,
            margin: 0.1,
            decision: 'suggest',
          ),
        );

    test(
      'batch answers accept visible members, reject exceptions, preserve concurrent edits',
      () async {
        final p = await seedPerson(db), other = await seedPerson(db);
        final ids = [for (var i = 0; i < 4; i++) await seedFace(db, seed: i)];
        await people.assignFaces([ids[2]], other);
        await (db.update(db.faces)..where((f) => f.id.equals(ids[3]))).write(
          const FacesCompanion(hidden: Value(true)),
        );
        await review.answerMatchBatch(ids, p, excluded: {ids[1]});
        final rows = await db.select(db.faces).get();
        expect(rows.map((r) => r.personId).toList(), [p, null, other, null]);
        expect(
          (await db.select(db.faceRejections).get()).single.faceId,
          ids[1],
        );
      },
    );

    test(
      'video decisions resolve the rest of each appearance without undoing exceptions',
      () async {
        final p = await seedPerson(db);
        final ids = [for (var i = 0; i < 5; i++) await seedFace(db, seed: i)];
        for (var i = 0; i < ids.length; i++) {
          await (db.update(db.faces)..where((f) => f.id.equals(ids[i]))).write(
            FacesCompanion(trackId: Value(i < 2 ? 100 : 200)),
          );
        }
        await review.answerMatchBatch(
          [ids[0], ids[2], ids[3]],
          p,
          excluded: {ids[2]},
        );
        final owners = {
          for (final f in await db.select(db.faces).get()) f.id: f.personId,
        };
        expect(ids.map((id) => owners[id]), [p, p, null, p, null]);
        expect(
          (await db.select(db.faceRejections).get())
              .map((r) => r.faceId)
              .toSet(),
          {ids[2], ids[4]},
        );
      },
    );

    test(
      'creating a selected group remembers the unchecked faces and keeps a cover',
      () async {
        final ids = [for (var i = 0; i < 3; i++) await seedFace(db, seed: i)];
        final group = await db
            .into(db.reviewGroups)
            .insert(
              ReviewGroupsCompanion.insert(
                faceIds: '[${ids.join(',')}]',
                cohesion: .6,
                quality: .8,
              ),
            );
        final person = await review.answerGroup(
          groupId: group,
          faceIds: ids,
          excluded: {ids.last},
          name: 'Sara',
        );
        final row = await (db.select(
          db.persons,
        )..where((p) => p.id.equals(person))).getSingle();
        expect(row.avatarFaceId, isNotNull);
        expect(
          (await db.select(db.faceRejections).get()).map(
            (r) => (r.faceId, r.personId),
          ),
          [(ids.last, person)],
        );
        await match(ids.last, person, .9);
        expect(await review.matchesFor(person), isEmpty);
        expect(await db.select(db.reviewGroups).get(), isEmpty);
      },
    );

    test('an album failure rolls back both acceptance and rejection', () async {
      final person = await seedPerson(db);
      final yes = await seedFace(db, seed: 1), no = await seedFace(db, seed: 2);
      await match(yes, person, .8);
      await match(no, person, .7);
      await db.customStatement(
        "CREATE TRIGGER fail_review BEFORE UPDATE OF person_id ON faces WHEN NEW.person_id IS NOT NULL BEGIN SELECT RAISE(ABORT, 'save failed'); END",
      );
      await expectLater(
        review.answerAlbum(
          personId: person,
          faceIds: [yes, no],
          excludedFaces: {no},
          bodyIds: [],
          excludedBodies: {},
        ),
        throwsA(anything),
      );
      expect(
        (await db.select(db.faces).get()).every((f) => f.personId == null),
        isTrue,
      );
      expect(await db.select(db.faceRejections).get(), isEmpty);
    });

    test(
      'snoozing a batch parks its members across changing batch boundaries',
      () async {
        final p = await seedPerson(db);
        final ids = [for (var i = 0; i < 27; i++) await seedFace(db, seed: i)];
        for (final id in ids) {
          await match(id, p, 0.45);
        }
        expect((await review.counts()).matches, 27);
        expect((await review.counts()).total, 2);
        final batch = (await review.questions()).first;
        await review.snooze(batch);
        expect((await review.counts()).total, 1);
        expect((await review.questions()).single.matchFaces, hasLength(3));
        await match(ids.first, p, 0.46); // jitter is not new evidence
        expect((await review.questions()).single.matchFaces, hasLength(3));
        await match(ids.first, p, 0.50);
        expect((await review.questions()).single.matchFaces, hasLength(4));
      },
    );

    test(
      'removing a wrong face clears derived body ownership and retains manual links',
      () async {
        final p = await seedPerson(db);
        final wrong = await seedFace(db, personId: p);
        final media = await seedMedia(db);
        Future<int> body(String method) => db
            .into(db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(media),
                faceId: Value(wrong),
                personId: Value(p),
                bboxX: 0,
                bboxY: 0,
                bboxW: 1,
                bboxH: 1,
                score: 0.9,
                createdAt: 1,
                linkMethod: Value(method),
              ),
            );
        final automatic = await body('weak_face'),
            manual = await body('manual');
        await review.removeDoubtful([wrong], p);
        final rows = {
          for (final b in await db.select(db.bodies).get()) b.id: b,
        };
        expect(rows[automatic]!.personId, isNull);
        expect(rows[manual]!.personId, p);
        expect(
          (await people.body(manual))!.personId,
          p,
        ); // only the explicit manual link remains
      },
    );

    test(
      'a suggested move respects a newer rejection of its destination',
      () async {
        final source = await seedPerson(db);
        final target = await seedPerson(db);
        final face = await seedFace(db, personId: source);
        await db
            .into(db.reviewDoubtful)
            .insert(
              ReviewDoubtfulCompanion.insert(
                faceId: Value(face),
                personId: source,
                score: 0.1,
                suggestedPersonId: Value(target),
              ),
            );
        expect(
          (await review.doubtful()).single.faces.single.suggested?.id,
          target,
        );
        await db
            .into(db.faceRejections)
            .insert(
              FaceRejectionsCompanion.insert(faceId: face, personId: target),
            );

        expect((await review.doubtful()).single.faces.single.suggested, isNull);
        expect(
          await review.moveSuggestedFaces(
            faceIds: [face],
            fromPersonId: source,
            toPersonId: target,
          ),
          0,
        );
        expect((await db.select(db.faces).get()).single.personId, source);
        expect(
          (await db.select(db.faceRejections).get()).single.personId,
          target,
        );
      },
    );

    test(
      'a stale repair card does not remove a newer identity confirmation',
      () async {
        final a = await seedPerson(db), b = await seedPerson(db);
        final f = await seedFace(db, personId: a);
        await people.assignFaces([f], b);
        await review.removeDoubtful([f], a, moveTo: {f: a});
        expect((await db.select(db.faces).get()).single.personId, b);
        expect(
          (await db.select(db.faceConfirmations).get()).single.personId,
          b,
        );
      },
    );
  });
}
