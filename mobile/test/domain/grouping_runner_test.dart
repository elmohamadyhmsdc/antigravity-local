// The three grouping rounds and how the phone applies the PC's plan: confident decisions only,
// real ids, one transaction per round, and anything the user did meanwhile wins.

import 'dart:io';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_runner.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:drift/drift.dart' show Variable;
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
      settings: AppSettings(db),
      review: review,
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int?> personOf(int face) async => (await (db.select(
    db.faces,
  )..where((f) => f.id.equals(face))).getSingle()).personId;

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
        'apply:match,cluster',
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
    expect(api.groupingCalls[2].strictness, 'balanced');
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

  test('the strictness setting is what the PC is asked to use', () async {
    await AppSettings(db).setStrictness('strict');
    final sara = await seedPerson(db);
    await seedFace(db, personId: sara, seed: 1);
    await runner.run();
    expect(api.groupingCalls.single.strictness, 'strict');
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
      expect(
        (l.personId, l.linkMethod, l.linkConfidence),
        (sara, 'appearance', 0.95),
      );
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
      expect(run.bodiesLinked, 1);

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
                  method: 'appearance',
                  confidence: 0.8,
                  decision: 'suggest',
                ),
                BodyLinkPlan(
                  bodyId: body,
                  personId: sara,
                  method: 'appearance',
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
