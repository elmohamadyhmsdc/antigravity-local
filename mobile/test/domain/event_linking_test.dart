// Roadmap Phase 5 on the phone: the grouping request carries each photo's time, sends the identified
// bodies a faceless body could be explained by (within the window, in another photo) and no others, and
// the plan applier treats `event_outfit` as a derived link.

import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/seed.dart';

const hour = 3600 * 1000;
const t0 = 1762000000000;

void main() {
  late AppDatabase db;
  late GroupingInputs inputs;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    inputs = GroupingInputs(db);
  });
  tearDown(() => db.close());

  Future<int> photo(String asset, int takenAt) =>
      seedMedia(db, asset: asset, takenAt: takenAt);

  test('GroupingBody sends taken_at only when it knows it', () {
    expect(const GroupingBody(id: 1).toJson().containsKey('taken_at'), isFalse);
    expect(const GroupingBody(id: 1, takenAt: t0).toJson()['taken_at'], t0);
    final back = GroupingBody.fromJson(
      const GroupingBody(id: 1, takenAt: t0, rejectedPersonIds: []).toJson(),
    );
    expect(back.takenAt, t0);
  });

  test(
    'identified bodies in other photos of the same event are sent; far ones are not',
    () async {
      final person = await seedPerson(db, name: 'Lina');
      final face = await seedFace(
        db,
        mediaId: await photo('f0', t0),
        personId: person,
      );
      final near = await photo('near', t0);
      final far = await photo('far', t0 + 3 * 24 * hour);
      final faceless = await photo('beach', t0 + 2 * hour);
      final outfitA = outfit(1);

      final anchorNear = await seedBody(
        db,
        mediaId: near,
        faceId: face,
        personId: person,
        appearance: outfitA,
      );
      final anchorFar = await seedBody(
        db,
        mediaId: far,
        personId: person,
        linkMethod: 'manual',
        appearance: outfitA,
      );
      final loose = await seedBody(db, mediaId: faceless, appearance: outfitA);

      final bodies = await inputs.bodies(dropDerived: false);
      final byId = {for (final b in bodies) b.id: b};
      expect(byId.keys, containsAll([loose, anchorNear]));
      expect(
        byId.containsKey(anchorFar),
        isFalse,
        reason: 'three days away: cannot explain the faceless body',
      );
      expect(byId[loose]!.takenAt, t0 + 2 * hour);
      expect(byId[anchorNear]!.takenAt, t0);
      expect(byId[anchorNear]!.anchorPersonId, person);
    },
  );

  test(
    'without any faceless body with a time, unrelated photos stay out of the request',
    () async {
      final person = await seedPerson(db);
      final lonely = await photo('lonely', t0);
      await seedBody(
        db,
        mediaId: lonely,
        personId: person,
        linkMethod: 'manual',
        appearance: outfit(2),
      );
      expect(await inputs.bodies(dropDerived: false), isEmpty);
    },
  );

  test(
    'event_outfit links are derived: round 2 does not treat them as anchors',
    () async {
      final person = await seedPerson(db);
      final media = await photo('x', t0);
      final id = await seedBody(
        db,
        mediaId: media,
        personId: person,
        linkMethod: 'event_outfit',
        linkConfidence: 0.93,
        appearance: outfit(3),
      );
      final other = await photo('y', t0 + hour);
      await seedBody(db, mediaId: other, appearance: outfit(3));
      final kept = await inputs.bodies(dropDerived: false);
      expect(kept.firstWhere((b) => b.id == id).anchorPersonId, person);
      final rederived = await inputs.bodies(dropDerived: true);
      expect(rederived.firstWhere((b) => b.id == id).anchorPersonId, isNull);
    },
  );

  test(
    'the applier stores event_outfit and clears it before re-deriving, keeping manual links',
    () async {
      final person = await seedPerson(db);
      final a = await photo('a', t0);
      final b = await photo('b', t0 + hour);
      final manual = await photo('c', t0);
      final loose = await seedBody(db, mediaId: b, appearance: outfit(4));
      final handMade = await seedBody(
        db,
        mediaId: manual,
        personId: person,
        linkMethod: 'manual',
      );
      final stale = await seedBody(
        db,
        mediaId: a,
        personId: person,
        linkMethod: 'event_outfit',
        linkConfidence: 0.9,
      );

      final applier = PlanApplier(db);
      final linked = await applier.applyBodyPlan(
        GroupingPlanResponse(
          mode: 'apply',
          bodyLinks: [
            BodyLinkPlan(
              bodyId: loose,
              personId: person,
              method: 'event_outfit',
              confidence: 0.94,
              decision: 'auto',
            ),
            BodyLinkPlan(
              bodyId: stale,
              personId: person,
              method: 'event_outfit',
              confidence: 0.6,
              decision: 'suggest',
            ),
          ],
        ),
      );
      expect(linked, 1);
      final rows = {for (final r in await db.select(db.bodies).get()) r.id: r};
      expect(
        (rows[loose]!.personId, rows[loose]!.linkMethod),
        (person, 'event_outfit'),
      );
      expect(
        rows[stale]!.personId,
        isNull,
        reason: 'a stale derived link is re-derived, here to nothing',
      );
      expect(rows[handMade]!.linkMethod, 'manual');
    },
  );

  test('the event_outfit golden fixtures round-trip and carry the link', () {
    final request = fixture('GroupingPlanRequest.event_outfit');
    final parsed = GroupingPlanRequest.fromJson(request);
    expect(parsed.bodies.map((b) => b.takenAt), everyElement(isNotNull));
    expect(parsed.toJson()['bodies'], request['bodies']);
    final response = GroupingPlanResponse.fromJson(
      fixture('GroupingPlanResponse.event_outfit'),
    );
    expect(response.bodyLinks.single.method, 'event_outfit');
    expect(response.bodyLinks.single.isAuto, isTrue);
    expect(response.bodyLinks.single.bodyId, 12);
  });

  test('the event_outfit golden fixtures round-trip and carry the link', () {
    final request = fixture('GroupingPlanRequest.event_outfit');
    final parsed = GroupingPlanRequest.fromJson(request);
    expect(parsed.bodies.map((b) => b.takenAt), everyElement(isNotNull));
    expect(parsed.toJson()['bodies'], request['bodies']);
    final response = GroupingPlanResponse.fromJson(
      fixture('GroupingPlanResponse.event_outfit'),
    );
    expect(response.bodyLinks.single.method, 'event_outfit');
    expect(response.bodyLinks.single.isAuto, isTrue);
    expect(response.bodyLinks.single.bodyId, 12);
  });
}
