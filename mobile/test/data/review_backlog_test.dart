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
