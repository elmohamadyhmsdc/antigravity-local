// The three grouping rounds and how the phone applies the PC's plan: confident decisions only,
// real ids, one transaction per round, and anything the user did meanwhile wins.

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/identity_rescan.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_runner.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

GroupingPlanResponse _plan(
  String mode, {
  List<FaceAssignment> assignments = const [],
  List<FaceGroup> groups = const [],
  List<DuplicatePeople> duplicates = const [],
  List<BodyLinkPlan> bodyLinks = const [],
  List<int> unsorted = const [],
}) => GroupingPlanResponse(
  mode: mode,
  assignments: assignments,
  groups: groups,
  duplicates: duplicates,
  bodyLinks: bodyLinks,
  unsortedFaceIds: unsorted,
);

FaceAssignment _assign(
  int face,
  int person, {
  String decision = 'auto',
  double score = 0.6,
}) => FaceAssignment(
  faceId: face,
  personId: person,
  score: score,
  margin: 0.2,
  decision: decision,
);

FaceGroup _group(List<int> ids, {bool auto = true}) =>
    FaceGroup(faceIds: ids, cohesion: 0.6, quality: 0.7, autoCreate: auto);

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FakeMobileApi api;
  late ReviewRepository review;
  late GroupingRunner runner;
  MobileApiHolder? holder;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_group_');
    api = FakeMobileApi();
    holder = MobileApiHolder(api);
    final people = PeopleRepository(
      db,
      FileStore(Directory('${tmp.path}/crops')),
    );
    review = ReviewRepository(db, people);
    runner = GroupingRunner(
      db: db,
      api: () => holder!.api,
      review: review,
      people: people,
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int?> personOf(int face) async => (await (db.select(
    db.faces,
  )..where((f) => f.id.equals(face))).getSingle()).personId;

  test('rebuild repairs an isolated saved body while keeping manual and crowded links', () async {
    final actual = await seedPerson(db, name: 'Actual subject');
    final other = await seedPerson(db, name: 'Unrelated person');
    final stale = await seedFace(db, personId: other);
    final media = await seedMedia(db);
    final correct = await seedFace(
      db, mediaId: media, personId: actual, x: .31, y: .12, w: .17, h: .16,
    );
    final body = await seedBody(db, mediaId: media, faceId: stale);
    final crowded = await seedMedia(db, asset: 'crowded');
    await seedFace(
      db, mediaId: crowded, personId: actual, x: .31, y: .12, w: .17, h: .16,
    );
    await seedFace(
      db, mediaId: crowded, personId: other, x: .71, y: .15, w: .17, h: .16,
    );
    final crowdedBody = await seedBody(db, mediaId: crowded, faceId: stale);
    final manual = await seedMedia(db, asset: 'manual');
    await seedFace(
      db, mediaId: manual, personId: actual, x: .31, y: .12, w: .17, h: .16,
    );
    final manualBody = await seedBody(
      db, mediaId: manual, faceId: stale, personId: other, linkMethod: 'manual',
    );
    api.groupingHandler = (request) => _plan(request.mode);

    expect((await runner.rebuild()).bodiesLinked, 1);
    final rows = {for (final body in await db.select(db.bodies).get()) body.id: body};
    expect(rows[body]?.faceId, correct);
    expect(rows[crowdedBody]?.faceId, stale);
    expect(rows[manualBody]?.faceId, stale);
    expect(rows[manualBody]?.personId, other);
    final displayed = await MediaQueries(db).watchDetections(media).first;
    expect(displayed.singleWhere((d) => d.kind == 'b').personId, actual);
    expect((await runner.rebuild()).bodiesLinked, 0);
  });

  test('a pending physical face prevents a weak-face link to someone else', () async {
    final other = await seedPerson(db, name: 'Unrelated person');
    final actual = await seedPerson(db, name: 'Actual subject');
    final media = await seedMedia(db);
    final face = await seedFace(db, mediaId: media);
    final body = await seedBody(
      db, mediaId: media, faceId: face, personId: other, linkMethod: 'weak_face',
    );
    final queries = MediaQueries(db);
    Future<int?> bodyOwnerInViewer() async =>
        (await queries.watchDetections(media).first)
            .singleWhere((d) => d.kind == 'b').personId;
    expect(await bodyOwnerInViewer(), isNull);

    expect(await PlanApplier(db).applyBodyPlan(_plan('apply', bodyLinks: [
      BodyLinkPlan(bodyId: body, personId: other, method: 'weak_face',
          confidence: .95, decision: 'auto'),
    ])), 0);
    await (db.update(db.faces)..where((f) => f.id.equals(face)))
        .write(FacesCompanion(personId: Value(actual)));
    expect(await bodyOwnerInViewer(), actual);
    await PeopleRepository(db, FileStore(tmp)).linkBody(body, other);
    expect(await bodyOwnerInViewer(), other);
  });

  test('saved video repair requires agreement across reused body frames', () async {
    final actual = await seedPerson(db, name: 'Subject');
    final other = await seedPerson(db, name: 'Other subject');
    final face = await seedFace(db, personId: actual);
    final stale = await seedFace(db, personId: other);
    final media = await seedMedia(db, kind: 'video');
    final body = await seedBody(db, faceId: stale);
    await (db.update(db.bodies)..where((b) => b.id.equals(body))).write(
      BodiesCompanion(mediaId: Value(media), frameNumber: const Value(0)),
    );
    Future<int> observation(String kind, int id, int frame) =>
        db.into(db.mediaDetections).insert(MediaDetectionsCompanion.insert(
          mediaId: media,
          frameNumber: Value(frame),
          kind: kind,
          refId: id,
          x: kind == 'f' ? .31 : .20,
          y: kind == 'f' ? .12 : .10,
          w: kind == 'f' ? .17 : .40,
          h: kind == 'f' ? .16 : .80,
        ));
    await observation('b', body, 0);
    await observation('f', face, 0);
    await observation('b', body, 30);
    final conflict = await observation('f', stale, 30);
    api.groupingHandler = (request) => _plan(request.mode);

    expect((await runner.rebuild()).bodiesLinked, 0);
    expect((await db.select(db.bodies).getSingle()).faceId, stale);
    await (db.update(db.mediaDetections)..where((d) => d.id.equals(conflict)))
        .write(MediaDetectionsCompanion(refId: Value(face)));
    expect((await runner.rebuild()).bodiesLinked, 1);
    expect((await db.select(db.bodies).getSingle()).faceId, face);
  });

  test('library repair audits two-face profiles in both collections', () async {
    final person = await seedPerson(db, name: 'Sara');
    final cover = await seedFace(db, personId: person);
    final wrongPerson = await seedFace(db, personId: person, seed: 2);
    await (db.update(db.persons)..where((p) => p.id.equals(person))).write(
      PersonsCompanion(avatarFaceId: Value(cover)),
    );
    final lookalike = await seedPerson(db, name: 'Nadia');
    final nadia = await seedFace(db, personId: lookalike, seed: 2);
    await seedFace(db, personId: lookalike, embedding: near(unitVec(2), 15, .2));
    await PeopleRepository(db, FileStore(tmp)).confirmFaces([nadia], lookalike);
    final character = await db
        .into(db.persons)
        .insert(
          PersonsCompanion.insert(
            name: const Value('Nova'),
            kind: const Value('character'),
            createdAt: 1,
          ),
        );
    final confirmed = await seedFace(db, personId: character);
    final wrongCharacter = await seedFace(db, personId: character);
    for (final (id, axis) in [(confirmed, 0), (wrongCharacter, 1)]) {
      await (db.update(db.faces)..where((f) => f.id.equals(id))).write(
        FacesCompanion(
          kind: const Value('character'),
          modelId: const Value(characterEmbeddingModelId),
          embedding: Value(
            embeddingToBlob(Float32List(characterEmbeddingDim)..[axis] = 1),
          ),
        ),
      );
    }
    final characters = PeopleRepository(db, FileStore(tmp), kind: 'character');
    await characters.confirmFaces([confirmed], character);
    final both = GroupingRunner(
      db: db,
      api: () => api,
      review: review,
      people: PeopleRepository(db, FileStore(tmp)),
      then: GroupingRunner(
        db: db,
        api: () => api,
        review: ReviewRepository(db, characters),
        people: characters,
        kind: 'character',
      ),
    );
    api.groupingHandler = (request) {
      if (request.mode == 'apply' && request.stages.contains('cluster')) {
        expect(request.stages, isNot(contains('people')));
        expect(
          request.pending.single.id,
          request.strictness == 'character' ? wrongCharacter : wrongPerson,
        );
        expect(request.pending.single.rejectedPersonIds, [
          request.strictness == 'character' ? character : person,
        ]);
      }
      return _plan(request.mode);
    };
    await both.repairLibrary();
    expect(await personOf(cover), person);
    expect(await personOf(confirmed), character);
    expect(await personOf(wrongPerson), isNull);
    expect(await personOf(wrongCharacter), isNull);
  });

  test(
    'rebuild rolls back both collections if the character plan fails',
    () async {
      final people = PeopleRepository(db, FileStore(tmp));
      final characters = PeopleRepository(
        db,
        FileStore(tmp),
        kind: 'character',
      );
      final both = GroupingRunner(
        db: db,
        api: () => holder!.api,
        review: review,
        people: people,
        then: GroupingRunner(
          db: db,
          api: () => holder!.api,
          review: ReviewRepository(db, characters),
          people: characters,
          kind: 'character',
        ),
      );
      final named = await seedPerson(db, name: 'Sara');
      final anchor = await seedFace(db, personId: named);
      final automatic = await seedPerson(db);
      final released = await seedFace(db, personId: automatic);
      final dismissed = await seedFace(
        db,
        personId: automatic,
        dismissed: true,
      );
      final body = await seedBody(
        db,
        personId: automatic,
        linkMethod: 'weak_face',
      );
      final manual = await seedPerson(db);
      final manualBody = await seedBody(
        db,
        personId: manual,
        linkMethod: 'manual',
      );
      final queued = await seedPerson(db);
      await IdentityRescan(db).queue(queued);
      final character = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Nova'),
              kind: const Value('character'),
              createdAt: 1,
            ),
          );
      Future<int> characterFace(int axis) async {
        final face = await seedFace(db, personId: character);
        final vector = Float32List(characterEmbeddingDim)..[axis] = 1;
        await (db.update(db.faces)..where((f) => f.id.equals(face))).write(
          FacesCompanion(
            kind: const Value('character'),
            modelId: const Value(characterEmbeddingModelId),
            embedding: Value(embeddingToBlob(vector)),
          ),
        );
        return face;
      }

      final nova = await characterFace(0);
      await characters.confirmFaces([nova], character);
      final wrongCharacter = await characterFace(1);
      var failCharacter = true;
      api.groupingHandler = (request) {
        if (request.strictness == 'character') {
          if (failCharacter) throw StateError('PC disconnected');
          if (request.stages.contains('cluster')) {
            expect(request.pending.map((f) => f.id), [wrongCharacter]);
            expect(request.pending.single.rejectedPersonIds, [character]);
          }
          return _plan(request.mode);
        }
        if (request.mode == 'apply' && request.stages.contains('cluster')) {
          expect(request.pending.map((f) => f.id), contains(released));
          expect(request.dismissedFaceIds, contains(dismissed));
          expect(request.models.map((m) => m.pid), [named]);
          return _plan('apply', assignments: [_assign(released, named)]);
        }
        return _plan(request.mode);
      };
      await expectLater(both.rebuild(), throwsStateError);
      expect(await personOf(released), automatic);
      expect(await personOf(dismissed), automatic);
      expect(await personOf(wrongCharacter), character);
      expect((await people.body(body))?.personId, automatic);
      failCharacter = false;
      final result = await both.rebuild();
      expect(result.assigned, 1);
      expect(result.facesRepaired, 1);
      expect(await personOf(anchor), named);
      expect(await personOf(released), named);
      expect(await personOf(dismissed), isNull);
      expect(await personOf(nova), character);
      expect(await personOf(wrongCharacter), isNull);
      expect((await people.body(body))?.personId, isNull);
      expect((await people.body(manualBody))?.personId, manual);
      expect((await db.select(db.persons).get()).map((p) => p.id), [
        named,
        manual,
        queued,
        character,
      ]);
    },
  );

  test(
    'identity repair separates a mixed person into a new identity through the PC plan',
    () async {
      final p = await seedPerson(db, name: 'Sara');
      final cover = await seedFace(db, personId: p, seed: 1);
      final wrong = [
        await seedFace(db, personId: p, seed: 2),
        await seedFace(db, personId: p, embedding: near(unitVec(2), 99, .2)),
      ];
      await (db.update(db.persons)..where((row) => row.id.equals(p))).write(
        PersonsCompanion(avatarFaceId: Value(cover)),
      );
      api.groupingHandler = (request) {
        if (request.mode == 'apply' && request.stages.contains('cluster')) {
          expect(request.pending.map((f) => f.id).toSet(), wrong.toSet());
          expect(
            request.pending.every((f) => f.rejectedPersonIds.contains(p)),
            isTrue,
          );
          return _plan('apply', groups: [_group(wrong)]);
        }
        return _plan(request.mode);
      };
      await runner.run(repairExisting: true, repairPersonId: p);
      expect(await personOf(cover), p);
      final split = await personOf(wrong.first);
      expect(split, isNotNull);
      expect(split, isNot(p));
      expect(await personOf(wrong.last), split);
      expect(
        (await (db.select(
          db.persons,
        )..where((row) => row.id.equals(p))).getSingle()).name,
        'Sara',
      );
    },
  );

  test('manual sort repairs clear mistakes inside named people', () async {
    final sara = await seedPerson(db, name: 'Sara');
    final omar = await seedPerson(db, name: 'Omar');
    for (var i = 0; i < 8; i++) {
      await seedFace(db, personId: sara, embedding: near(unitVec(1), i, 0.3));
      await seedFace(db, personId: omar, embedding: near(unitVec(2), i, 0.3));
    }
    final clear = await seedFace(db, personId: sara, seed: 2);
    final linkedBody = await seedBody(
      db,
      faceId: clear,
      personId: sara,
      linkMethod: 'weak_face',
    );
    final manual = await seedFace(db, personId: sara, seed: 1);
    await PeopleRepository(db, FileStore(tmp)).confirmFaces([manual], sara);
    final ambiguous = await seedFace(db, personId: sara, seed: 2);
    final blocked = await seedFace(db, personId: sara, seed: 2);
    final sharedPhoto = await seedMedia(db);
    await seedFace(db, personId: omar, mediaId: sharedPhoto, seed: 2);
    await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: sharedPhoto,
            kind: 'f',
            refId: blocked,
            x: 0.1,
            y: 0.1,
            w: 0.2,
            h: 0.2,
          ),
        );
    api.groupingHandler = (request) {
      if (request.stages.join(',') != 'match') return _plan(request.mode);
      expect(request.pending.map((f) => f.id), [clear, ambiguous, blocked]);
      expect(request.models.map((m) => m.pid), [sara, omar]);
      return _plan(
        'apply',
        assignments: [
          _assign(clear, omar),
          _assign(ambiguous, omar, decision: 'suggest'),
          _assign(blocked, omar),
        ],
      );
    };

    expect((await runner.run()).facesRepaired, 0);
    expect(await personOf(clear), sara);
    final result = await runner.run(repairExisting: true);

    expect(result.facesRepaired, 1);
    expect(await personOf(clear), omar);
    expect(await personOf(manual), sara);
    expect(await personOf(ambiguous), sara);
    expect(await personOf(blocked), sara);
    expect((await db.select(db.persons).get()).map((p) => p.name), [
      'Sara',
      'Omar',
    ]);
    expect(
      (await review.doubtful()).single.faces.map((f) => f.faceId),
      unorderedEquals([ambiguous, blocked]),
    );
    expect((await db.select(db.faceConfirmations).get()).single.faceId, manual);
    final body = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(linkedBody))).getSingle();
    expect(body.personId, isNull);
    expect(body.linkMethod, isNull);
  });

  test('a lock set during the repair upload wins over the PC plan', () async {
    final sara = await seedPerson(db, name: 'Sara');
    final omar = await seedPerson(db, name: 'Omar');
    for (var i = 0; i < 6; i++) {
      await seedFace(db, personId: sara, seed: 1);
      await seedFace(db, personId: omar, seed: 2);
    }
    final face = await seedFace(db, personId: sara, seed: 2);
    api.groupingHandler = (request) async {
      if (request.stages.join(',') != 'match') return _plan(request.mode);
      await PeopleRepository(
        db,
        FileStore(tmp),
      ).setPersonFlags([omar], groupingLocked: true);
      return _plan('apply', assignments: [_assign(face, omar)]);
    };

    expect((await runner.run(repairExisting: true)).facesRepaired, 0);
    expect(await personOf(face), sara);
    expect(api.groupingCalls.map((r) => r.stages.join(',')), contains('match'));
  });

  test(
    'a lock rejects even an already requested automatic plan until unlocked',
    () async {
      final id = await seedPerson(db, name: 'Sara');
      final face = await seedFace(db, seed: 5);
      final repo = PeopleRepository(db, FileStore(tmp));
      final plan = _plan('apply', assignments: [_assign(face, id)]);
      await repo.setPersonFlags([id], groupingLocked: true);
      expect((await PlanApplier(db).applyFacePlan(plan)).assigned, 0);
      expect(await personOf(face), isNull);
      await repo.setPersonFlags([id], groupingLocked: false);
      expect((await PlanApplier(db).applyFacePlan(plan)).assigned, 1);
      expect(await personOf(face), id);
    },
  );

  test(
    'round 1 gives confident matches to existing people and turns auto-create groups into people',
    () async {
      final sara = await seedPerson(db, name: 'Sara');
      await seedFace(db, personId: sara, seed: 1);
      final f1 = await seedFace(db, seed: 2); // matched to Sara
      final f2 = await seedFace(db, seed: 3); // only a suggestion: not applied
      final g1 = await seedFace(db, seed: 4, quality: 0.6);
      final g2 = await seedFace(
        db,
        seed: 5,
        quality: 0.9,
      ); // the best of its group: becomes the cover
      final g3 = await seedFace(db, seed: 6, quality: 0.8);
      final small = await seedFace(db, seed: 7);
      final small2 = await seedFace(db, seed: 8);

      api.groupingHandler = (r) => r.mode == 'apply'
          ? _plan(
              'apply',
              assignments: [
                _assign(f1, sara),
                _assign(f2, sara, decision: 'suggest'),
              ],
              groups: [
                _group([g1, g2, g3]),
                _group([small, small2], auto: false),
              ],
            )
          : _plan('review', unsorted: [f2, small, small2]);

      final run = await runner.run();

      expect(await personOf(f1), sara);
      expect(
        await personOf(f2),
        isNull,
        reason: 'a suggestion is for the Review screen, not applied',
      );
      final newPerson = await personOf(g1);
      expect(newPerson, isNotNull);
      expect({await personOf(g2), await personOf(g3)}, {newPerson});
      expect(
        await personOf(small),
        isNull,
        reason: 'a group the PC did not mark auto_create stays unsorted',
      );
      final created = await (db.select(
        db.persons,
      )..where((p) => p.id.equals(newPerson!))).getSingle();
      expect(
        created.avatarFaceId,
        g2,
        reason: 'the best-quality face is the cover',
      );
      expect(created.name, isNull);

      expect((run.assigned, run.newPeople, run.facesInNewPeople), (1, 1, 3));
      expect(run.skipped, isFalse);
    },
  );

  test('anything the user did while the PC was thinking wins', () async {
    final sara = await seedPerson(db, name: 'Sara');
    final omar = await seedPerson(db, name: 'Omar');
    final a = await seedFace(db, seed: 1);
    final b = await seedFace(db, seed: 2);
    final c = await seedFace(db, seed: 3);
    const deletedPerson = 4242;

    // the user put face `a` on Omar after the request was sent
    await db.customUpdate(
      'UPDATE faces SET person_id = ? WHERE id = ?',
      variables: [Variable.withInt(omar), Variable.withInt(a)],
      updates: {db.faces},
    );
    final result = await PlanApplier(db).applyFacePlan(
      _plan(
        'apply',
        assignments: [
          _assign(a, sara),
          _assign(b, deletedPerson),
          _assign(c, sara),
        ],
        groups: [
          _group([a, b]),
        ], // a is taken: the group is not created from what is left
      ),
    );

    expect(
      await personOf(a),
      omar,
      reason: 'a face that has a person by now is left alone',
    );
    expect(
      await personOf(b),
      isNull,
      reason: 'a person that was deleted is not resurrected',
    );
    expect(await personOf(c), sara);
    expect(
      result.newPeople,
      0,
      reason: 'a partly sorted group waits for the next round',
    );
    expect((await db.select(db.persons).get()).length, 2);
  });

  test('the rounds, in order, each asking only for what it needs', () async {
    final sara = await seedPerson(db, name: 'Sara');
    final media = await seedMedia(db);
    final face = await seedFace(db, personId: sara, mediaId: media, seed: 1);
    await seedFace(db, seed: 2);
    await seedBody(
      db,
      mediaId: media,
      faceId: face,
      appearance: outfit(1),
      frameNumber: 0,
    );
    await seedBody(db, mediaId: media, appearance: outfit(2), frameNumber: 60);

    await runner.run();

    expect(
      api.groupingCalls.map((c) => '${c.mode}:${c.stages.join(',')}').toList(),
      [
        'apply:match,cluster,people',
        'apply:bodies',
        'review:match,cluster,duplicates,bodies',
      ],
    );
    expect(api.groupingCalls[0].pending, isNotEmpty);
    expect(
      api.groupingCalls[1].pending,
      isEmpty,
      reason: 'the body round needs no faces',
    );
    expect(api.groupingCalls[1].bodies.length, 2);
    expect(api.groupingCalls[2].strictness, 'auto');
    expect(api.groupingCalls[2].models.single.pid, sara);
  });

  test(
    'with nothing unsorted and no bodies, only the review round runs',
    () async {
      final sara = await seedPerson(db);
      await seedFace(db, personId: sara, seed: 1);
      await runner.run();
      expect(api.groupingCalls.map((c) => c.mode).toList(), ['review']);
    },
  );

  test(
    'people are grouped with library-derived thresholds, not a setting',
    () async {
      final sara = await seedPerson(db);
      await seedFace(db, personId: sara, seed: 1);
      await runner.run();
      expect(api.groupingCalls.single.strictness, 'auto');
    },
  );

  group('provisional people the PC says are one person', () {
    GroupingPlanResponse Function(GroupingPlanRequest) mergeOnce(
      List<PersonMergePlan> merges,
    ) {
      var sent = false;
      return (r) {
        if (r.stages.contains('people') && !sent) {
          sent = true;
          return GroupingPlanResponse(mode: r.mode, merges: merges);
        }
        return GroupingPlanResponse(mode: r.mode, merges: const []);
      };
    }

    test(
      'are merged, and only unnamed ones are offered as provisional',
      () async {
        final sara = await seedPerson(db, name: 'Sara');
        final a = await seedPerson(db);
        final b = await seedPerson(db);
        final fa = await seedFace(db, personId: a, seed: 1);
        final fb = await seedFace(db, personId: b, seed: 2);
        await seedFace(db, personId: sara, seed: 3);
        api.groupingHandler = mergeOnce([
          PersonMergePlan(absorb: b, into: a, score: 0.7),
        ]);

        final run = await runner.run();

        final first = api.groupingCalls.first;
        expect(first.stages, contains('people'));
        expect(first.provisionalPersonIds, [a, b]);
        expect(run.peopleMerged, 1);
        expect(await personOf(fa), a);
        expect(await personOf(fb), a);
        expect(
          (await db.select(db.persons).get()).map((p) => p.id),
          isNot(contains(b)),
        );
        expect(
          api.groupingCalls
              .where((c) => c.mode == 'apply' && c.stages.contains('people'))
              .length,
          2,
          reason: 'a merge makes a better model: round 1 runs once more',
        );
      },
    );

    test('a person the user named since the plan was made stays', () async {
      final a = await seedPerson(db);
      final b = await seedPerson(db);
      final fb = await seedFace(db, personId: b, seed: 2);
      await seedFace(db, personId: a, seed: 1);
      api.groupingHandler = (r) {
        if (r.stages.contains('people')) {
          // the user names b while the PC is thinking
          return (db.update(db.persons)..where((p) => p.id.equals(b)))
              .write(const PersonsCompanion(name: Value('Omar')))
              .then(
                (_) => GroupingPlanResponse(
                  mode: r.mode,
                  merges: [PersonMergePlan(absorb: b, into: a, score: 0.7)],
                ),
              );
        }
        return GroupingPlanResponse(mode: r.mode);
      };

      final run = await runner.run();

      expect(run.peopleMerged, 0);
      expect(await personOf(fb), b);
    });

    test('two people seen in one photo are never merged', () async {
      final a = await seedPerson(db);
      final b = await seedPerson(db);
      final media = await seedMedia(db);
      await seedFace(db, personId: a, mediaId: media, seed: 1);
      final fb = await seedFace(db, personId: b, mediaId: media, seed: 2);
      api.groupingHandler = mergeOnce([
        PersonMergePlan(absorb: b, into: a, score: 0.9),
      ]);

      final run = await runner.run();

      expect(run.peopleMerged, 0);
      expect(await personOf(fb), b);
    });
  });

  test(
    'round 2 re-derives outfit links: stale derived ones are cleared, links made by hand stay',
    () async {
      final sara = await seedPerson(db, name: 'Sara');
      final media = await seedMedia(db);
      final face = await seedFace(db, personId: sara, mediaId: media, seed: 1);
      await seedBody(
        db,
        mediaId: media,
        faceId: face,
        appearance: outfit(1),
        frameNumber: 0,
      );
      final loose = await seedBody(
        db,
        mediaId: media,
        appearance: outfit(2),
        frameNumber: 60,
      );
      final stale = await seedBody(
        db,
        mediaId: media,
        personId: sara,
        linkMethod: 'appearance',
        linkConfidence: 0.9,
        appearance: outfit(3),
        frameNumber: 90,
      );
      final manual = await seedBody(
        db,
        mediaId: media,
        personId: sara,
        linkMethod: 'manual',
        appearance: outfit(4),
        frameNumber: 120,
      );

      api.groupingHandler = (r) {
        if (r.mode == 'apply') {
          return _plan(
            'apply',
            bodyLinks: [
              BodyLinkPlan(
                bodyId: loose,
                personId: sara,
                method: 'appearance',
                confidence: 0.95,
                decision: 'auto',
              ),
              BodyLinkPlan(
                bodyId: manual,
                personId: sara,
                method: 'appearance',
                confidence: 0.99,
                decision: 'auto',
              ),
            ],
          );
        }
        return _plan('review');
      };
      final run = await runner.run();

      Future<BodyRow> body(int id) =>
          (db.select(db.bodies)..where((b) => b.id.equals(id))).getSingle();
      final l = await body(loose);
      expect((l.personId, l.linkMethod, l.linkConfidence), (null, null, null));
      final s = await body(stale);
      expect(
        (s.personId, s.linkMethod),
        (null, null),
        reason: 'it was not re-derived, so it is gone',
      );
      final m = await body(manual);
      expect(
        (m.personId, m.linkMethod),
        (sara, 'manual'),
        reason: 'a link made by hand is never overwritten',
      );
      expect(run.bodiesLinked, 0);

      final request = api.groupingCalls.firstWhere(
        (c) => c.stages.contains('bodies') && c.mode == 'apply',
      );
      final byId = {for (final b in request.bodies) b.id: b};
      expect(
        byId[stale]!.anchorPersonId,
        isNull,
        reason: 'derived links are not anchors while they are re-derived',
      );
      expect(byId[manual]!.anchorPersonId, sara);
    },
  );

  test(
    'round 3 stores what still needs a decision and ignores what no longer exists',
    () async {
      final sara = await seedPerson(db, name: 'Sara');
      final anna = await seedPerson(db, name: 'Anna');
      await seedFace(db, personId: sara, seed: 1);
      await seedFace(db, personId: anna, seed: 2);
      final f1 = await seedFace(db, seed: 3);
      final f2 = await seedFace(db, seed: 4);
      final f3 = await seedFace(db, seed: 5);
      final media = await seedMedia(db);
      final body = await seedBody(db, mediaId: media, appearance: outfit(1));

      api.groupingHandler = (r) => r.mode == 'apply'
          ? _plan('apply')
          : _plan(
              'review',
              assignments: [
                _assign(f1, sara, decision: 'suggest', score: 0.4),
                _assign(f2, 4242, decision: 'suggest'),
              ],
              groups: [
                _group([f2, f3], auto: false),
                _group([777], auto: false),
              ],
              duplicates: [
                DuplicatePeople(personA: anna, personB: sara, score: 0.55),
                DuplicatePeople(personA: sara, personB: 4242, score: 0.5),
              ],
              bodyLinks: [
                BodyLinkPlan(
                  bodyId: body,
                  personId: sara,
                  method: 'weak_face',
                  confidence: 0.8,
                  decision: 'suggest',
                ),
                BodyLinkPlan(
                  bodyId: body,
                  personId: sara,
                  method: 'weak_face',
                  confidence: 0.99,
                  decision: 'auto',
                ),
              ],
              unsorted: [f3],
            );
      final run = await runner.run();

      final counts = await review.counts();
      expect(
        (counts.matches, counts.groups, counts.duplicates, counts.bodyLinks),
        (1, 1, 1, 1),
      );
      expect(run.review.total, 4);
      final matches = await review.matches();
      expect(matches.single.person.id, sara);
      expect(matches.single.faces.single.faceId, f1);
      final dup = (await review.duplicates()).single;
      expect({dup.a.id, dup.b.id}, {anna, sara});
      expect(
        await review.duplicateScore(sara, anna),
        0.55,
        reason: 'looked up in either order',
      );
      final groups = await review.groupItems();
      expect(groups.single.faces.map((f) => f.faceId), [f2, f3]);
      final link = (await review.bodyLinks()).single;
      expect(
        (link.bodyId, link.person.id, link.confidence),
        (body, sara, 0.8),
        reason: 'only suggestions are kept',
      );

      // running again replaces the old plan instead of piling up
      await runner.run();
      expect((await review.counts()).total, 4);
    },
  );

  test(
    'a match that becomes automatic in review is applied before asking',
    () async {
      final sara = await seedPerson(db, name: 'Sara');
      final media = await seedMedia(db);
      await seedFace(db, personId: sara, mediaId: media);
      final automatic = await seedFace(db, seed: 2);
      final uncertain = await seedFace(db, seed: 3);
      final conflicted = await seedFace(db, seed: 4, mediaId: media);

      api.groupingHandler = (r) => r.mode == 'apply'
          ? _plan('apply')
          : _plan(
              'review',
              assignments: [
                if (r.pending.any((f) => f.id == automatic))
                  _assign(automatic, sara),
                _assign(uncertain, sara, decision: 'suggest', score: 0.36),
                _assign(conflicted, sara),
              ],
            );

      final result = await runner.run();
      expect(result.assigned, 1);
      expect(await personOf(automatic), sara);
      expect(await personOf(uncertain), isNull);
      expect(await personOf(conflicted), isNull);
      expect(
        (await review.matches()).single.faces.map((f) => f.faceId),
        unorderedEquals([uncertain, conflicted]),
      );
      expect(api.groupingCalls.where((r) => r.mode == 'review'), hasLength(2));
    },
  );

  test(
    'a suggestion disappears from the Review screen when the user sorts the face',
    () async {
      final sara = await seedPerson(db, name: 'Sara');
      await seedFace(db, personId: sara, seed: 1);
      final f1 = await seedFace(db, seed: 2);
      final f2 = await seedFace(db, seed: 3);
      api.groupingHandler = (r) => r.mode == 'apply'
          ? _plan('apply')
          : _plan(
              'review',
              assignments: [
                _assign(f1, sara, decision: 'suggest'),
                _assign(f2, sara, decision: 'suggest'),
              ],
              groups: [
                _group([f1, f2], auto: false),
              ],
            );
      await runner.run();
      expect((await review.counts()).matches, 2);

      await review.acceptMatches([f1], sara);
      final counts = await review.counts();
      expect((counts.matches, counts.groups), (1, 1));
      expect(
        (await review.groupItems()).single.faces.map((f) => f.faceId),
        [f2],
        reason: 'the group shrinks',
      );

      await review.rejectMatches([f2], sara);
      expect((await review.counts()).matches, 0);
      final rejection = await db.select(db.faceRejections).get();
      expect(rejection.map((r) => (r.faceId, r.personId)), [(f2, sara)]);
    },
  );

  test(
    'dismissing a group hides its faces from later group suggestions',
    () async {
      final f1 = await seedFace(db, seed: 1);
      final f2 = await seedFace(db, seed: 2);
      api.groupingHandler = (r) => _plan(
        r.mode,
        groups: r.mode == 'review'
            ? [
                _group([f1, f2], auto: false),
              ]
            : const [],
      );
      await runner.run();
      final group = (await review.groupItems()).single;
      await review.dismissGroup(group.id);
      expect(await review.groupItems(), isEmpty);
      final dismissed = await db.select(db.faces).get();
      expect(dismissed.every((f) => f.reviewDismissed), isTrue);
      await runner.run();
      expect(api.groupingCalls.last.dismissedFaceIds, [f1, f2]);
    },
  );

  test('no PC paired: nothing is sent and the run says so', () async {
    holder!.api = null;
    await seedFace(db, seed: 1);
    final run = await runner.run();
    expect(run.skipped, isTrue);
    expect(api.groupingCalls, isEmpty);
  });

  test('two callers at once share one run', () async {
    await seedFace(db, seed: 1);
    final a = runner.run();
    final b = runner.run();
    await Future.wait([a, b]);
    expect(api.groupingCalls.where((c) => c.mode == 'review').length, 1);
  });

  test(
    'a PC that fails changes nothing and the error reaches the caller',
    () async {
      final sara = await seedPerson(db);
      await seedFace(db, personId: sara, seed: 1);
      final f = await seedFace(db, seed: 2);
      api.groupingError = ApiException.network('refused');
      await expectLater(runner.run(), throwsA(isA<ApiException>()));
      expect(await personOf(f), isNull);
      // and the next try works
      api.groupingError = null;
      await runner.run();
      expect(api.groupingCalls, isNotEmpty);
    },
  );
}

/// Lets a test unpair mid-way.
class MobileApiHolder {
  MobileApiHolder(this.api);
  FakeMobileApi? api;
}
