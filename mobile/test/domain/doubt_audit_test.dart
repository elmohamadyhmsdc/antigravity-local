// "Are you sure these are Sara?": the audit of faces already on a person (named ones included), the
// questions it feeds, and what every answer does.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_questions.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/identity/doubt_audit.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late PeopleRepository people;
  late ReviewRepository review;
  final r = math.Random(11);

  Float32List unit() {
    final v = [for (var i = 0; i < 512; i++) r.nextDouble() * 2 - 1];
    final n = math.sqrt(v.fold<double>(0, (s, x) => s + x * x));
    return Float32List.fromList([for (final x in v) x / n]);
  }

  Float32List around(Float32List c, [double noise = 0.5]) {
    final n = unit();
    final v = [for (var i = 0; i < 512; i++) c[i] + noise * n[i]];
    final len = math.sqrt(v.fold<double>(0, (s, x) => s + x * x));
    return Float32List.fromList([for (final x in v) x / len]);
  }

  final sara = unit(), omar = unit(), stranger = unit();

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_audit_');
    people = PeopleRepository(
      db,
      FileStore(Directory('${tmp.path}/crops')),
      index: InMemoryEmbeddingIndex(),
    );
    review = ReviewRepository(db, people);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<List<int>> faces(int person, Float32List centre, int n) async => [
    for (var i = 0; i < n; i++)
      await seedFace(db, personId: person, embedding: around(centre)),
  ];

  /// Seeds a bare face row for a person: seedFace does not mark it as vouched for, like a scan does not.
  Future<int> named(String name) => seedPerson(db, name: name);

  test(
    'a NAMED person with a few wrong faces: exactly those come back, worst first',
    () async {
      final s = await named('Sara');
      final good = await faces(s, sara, 10);
      final wrong = await faces(s, stranger, 2);

      final result = await DoubtAudit(db).run();

      expect(result.faces, 2);
      final item = (await review.doubtful()).single;
      expect(item.person.id, s);
      expect(item.faces.map((f) => f.faceId).toSet(), wrong.toSet());
      expect(item.faces.every((f) => !good.contains(f.faceId)), isTrue);
      expect(
        item.faces.first.score,
        lessThanOrEqualTo(item.faces.last.score),
        reason: 'worst first',
      );
      expect((await review.counts()).doubtful, 2);
      expect(
        (await review.counts()).total,
        1,
        reason: 'one repair batch, not two per-face decisions',
      );
    },
  );

  test('a clean person asks nothing', () async {
    final s = await named('Sara');
    await faces(s, sara, 10);

    expect((await DoubtAudit(db).run()).faces, 0);
    expect(await review.doubtful(), isEmpty);
  });

  test('the doubted face that fits another person better says who', () async {
    final s = await named('Sara');
    final o = await named('Omar');
    await faces(s, sara, 10);
    await faces(o, omar, 10);
    final strayed = await seedFace(
      db,
      personId: s,
      embedding: around(omar, 0.3),
    );

    await DoubtAudit(db).run();

    final face = (await review.doubtful()).single.faces.single;
    expect(face.faceId, strayed);
    expect(face.suggested?.id, o);
  });

  test(
    'faces the user vouched for are never doubted - and they define "her" when most faces are wrong',
    () async {
      final s = await named('Sara');
      final vouched = await faces(s, sara, 3);
      await faces(s, stranger, 7); // the person is MOSTLY somebody else
      await people.confirmFaces(vouched, s);

      await DoubtAudit(db).run();

      final flagged = (await review.doubtful())
          .expand((i) => i.faces)
          .map((f) => f.faceId)
          .toSet();
      expect(flagged.length, 7);
      expect(flagged.intersection(vouched.toSet()), isEmpty);
    },
  );

  test(
    '"Yes" confirms them for good; the next audit leaves them alone',
    () async {
      final s = await named('Sara');
      await faces(s, sara, 10);
      final odd = await faces(s, stranger, 2);
      await DoubtAudit(db).run();

      await review.confirmDoubtful(odd, s);

      expect((await review.counts()).doubtful, 0);
      await DoubtAudit(db).run();
      expect(await review.doubtful(), isEmpty);
      expect(
        (await db.select(db.faceConfirmations).get())
            .map((c) => c.faceId)
            .toSet(),
        odd.toSet(),
      );
    },
  );

  test(
    '"No" takes them off her and never lets grouping put them back',
    () async {
      final s = await named('Sara');
      await faces(s, sara, 10);
      final odd = await faces(s, stranger, 2);
      await DoubtAudit(db).run();

      await review.removeDoubtful(odd, s);

      final rows = await (db.select(
        db.faces,
      )..where((f) => f.id.isIn(odd))).get();
      expect(rows.every((f) => f.personId == null), isTrue);
      expect(
        (await db.select(db.faceRejections).get())
            .map((x) => (x.faceId, x.personId))
            .toSet(),
        {for (final id in odd) (id, s)},
      );
      expect(await review.doubtful(), isEmpty);
    },
  );

  test(
    'a face moved to the person it looks like joins them, vouched for',
    () async {
      final s = await named('Sara');
      final o = await named('Omar');
      await faces(s, sara, 10);
      await faces(o, omar, 10);
      final strayed = await seedFace(
        db,
        personId: s,
        embedding: around(omar, 0.3),
      );
      await DoubtAudit(db).run();

      await review.removeDoubtful([strayed], s, moveTo: {strayed: o});

      final row = await (db.select(
        db.faces,
      )..where((f) => f.id.equals(strayed))).getSingle();
      expect(row.personId, o);
      expect((await db.select(db.faceConfirmations).get()).single.personId, o);
    },
  );

  test(
    'a face the user assigns by hand is vouched for, and a rejection forgets it',
    () async {
      final s = await named('Sara');
      final f = await seedFace(db, embedding: sara);

      await people.assignFaces([f], s);
      expect((await db.select(db.faceConfirmations).get()).single.faceId, f);

      await people.rejectFaces([f]);
      expect(await db.select(db.faceConfirmations).get(), isEmpty);
    },
  );

  test('merging keeps what was vouched for on the merged person', () async {
    final a = await named('A'), b = await named('B');
    final fa = await seedFace(db, embedding: sara);
    await people.assignFaces([fa], b);

    await people.mergePeople(sourceId: b, targetId: a);

    expect((await db.select(db.faceConfirmations).get()).single.personId, a);
  });

  test('a locked person is not audited', () async {
    final s = await named('Sara');
    await faces(s, sara, 10);
    await faces(s, stranger, 2);
    await people.setPersonFlags([s], groupingLocked: true);

    expect((await DoubtAudit(db).run()).faces, 0);
  });

  test(
    'questions: one per batch of 24, worst person first, "Not sure" parks it',
    () async {
      final s = await named('Sara');
      await faces(s, sara, 30);
      await faces(s, stranger, 10);
      final o = await named('Omar');
      await faces(o, omar, 12);
      await faces(o, stranger, 2);
      await DoubtAudit(db).run();

      final all = await review.questions();
      final doubtful = all
          .where((q) => q.kind == ReviewQuestionKind.doubtful)
          .toList();

      expect(doubtful, hasLength(2));
      expect(doubtful.map((q) => q.doubtful!.person.id).toSet(), {s, o});
      expect(
        doubtful.first.doubtful!.faces.length,
        10,
        reason: 'the bigger batch first',
      );

      await review.snooze(doubtful.first);
      final after = await review.questions();
      expect(
        after.where((q) => q.kind == ReviewQuestionKind.doubtful),
        hasLength(1),
      );
    },
  );

  test(
    'more than 24 doubtful faces make several questions for the same person',
    () async {
      final s = await named('Sara');
      await faces(s, sara, 40);
      await faces(s, stranger, 20);
      await DoubtAudit(db).run();

      final batches = await review.doubtful();

      expect(
        batches.map((b) => b.faces.length).fold<int>(0, (a, b) => a + b),
        20,
      );
      expect(
        batches.every((b) => b.faces.length <= ReviewDoubtfulItem.chunkSize),
        isTrue,
      );
    },
  );

  test('a damaged embedding is skipped, not a crash', () async {
    final s = await named('Sara');
    await faces(s, sara, 8);
    final broken = await seedFace(db, personId: s, embedding: sara);
    await (db.update(db.faces)..where((f) => f.id.equals(broken))).write(
      FacesCompanion(embedding: Value(Uint8List(12))),
    );

    await expectLater(DoubtAudit(db).run(), completes);
  });
  test(
    'a confirmed profile rescues that view from a frontal majority',
    () async {
      final p = await named('Sara');
      final fronts = await faces(p, sara, 8);
      final profile = await seedFace(db, personId: p, embedding: stranger);
      final sameProfile = await seedFace(
        db,
        personId: p,
        embedding: around(stranger, 0.15),
      );
      await people.confirmFaces([fronts[0], fronts[1], profile], p);
      await DoubtAudit(db).run();
      final flagged = (await review.doubtful())
          .expand((q) => q.faces)
          .map((f) => f.faceId);
      expect(flagged, isNot(contains(sameProfile)));
    },
  );

  test(
    'blur and invalid vectors are unknown evidence, not wrong-identity tasks',
    () async {
      final p = await named('Sara');
      await faces(p, sara, 8);
      await seedFace(db, personId: p, quality: 0.2, embedding: stranger);
      await seedFace(db, personId: p, embedding: Float32List(512));
      expect((await DoubtAudit(db).run()).faces, 0);
    },
  );
}
