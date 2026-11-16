import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> occurrence(int face, int media, {int? frame}) => db
      .into(db.mediaDetections)
      .insert(
        MediaDetectionsCompanion.insert(
          mediaId: media,
          kind: 'f',
          refId: face,
          x: 0.1,
          y: 0.1,
          w: 0.2,
          h: 0.2,
          frameNumber: Value(frame),
        ),
      );

  GroupingPlanResponse match(int face, int person) => GroupingPlanResponse(
    mode: 'apply',
    assignments: [
      FaceAssignment(
        faceId: face,
        personId: person,
        score: 0.9,
        margin: 0.4,
        decision: 'auto',
      ),
    ],
  );

  Future<int?> owner(int face) async => (await (db.select(
    db.faces,
  )..where((f) => f.id.equals(face))).getSingle()).personId;

  test(
    'alias co-occurrence blocks a stale match in either direction',
    () async {
      final person = await seedPerson(db);
      final original = await seedMedia(db, asset: 'original');
      final copy = await seedMedia(db, asset: 'copy');
      final elsewhere = await seedMedia(db, asset: 'elsewhere');
      final anchor = await seedFace(db, mediaId: original, personId: person);
      await occurrence(anchor, copy);
      final candidate = await seedFace(db, mediaId: elsewhere);
      await occurrence(candidate, copy);
      expect(
        (await PlanApplier(
          db,
        ).applyFacePlan(match(candidate, person))).assigned,
        0,
      );
      expect(await owner(candidate), isNull);
    },
  );

  test('a track cannot propagate into an occupied alias frame', () async {
    final person = await seedPerson(db);
    final video = await seedMedia(db, kind: 'video');
    final anchor = await seedFace(
      db,
      mediaId: video,
      frameNumber: 10,
      personId: person,
    );
    final candidate = await seedFace(db, mediaId: video, frameNumber: 20);
    final other = await seedFace(
      db,
      mediaId: video,
      frameNumber: 30,
      personId: person,
    );
    await occurrence(candidate, video, frame: 90);
    await occurrence(other, video, frame: 90);
    await (db.update(db.faces)..where((f) => f.id.isIn([anchor, candidate])))
        .write(FacesCompanion(trackId: Value(anchor)));
    await PlanApplier(
      db,
    ).applyFacePlan(const GroupingPlanResponse(mode: 'apply'));
    expect(await owner(candidate), isNull);
  });

  test('new automatic groups reject shared occurrences across files', () async {
    final photo = await seedMedia(db, asset: 'one');
    final second = await seedMedia(db, asset: 'two');
    final a = await seedFace(db, mediaId: photo);
    final b = await seedFace(db, mediaId: second);
    await occurrence(b, photo);
    final result = await PlanApplier(db).applyFacePlan(
      GroupingPlanResponse(
        mode: 'apply',
        groups: [
          FaceGroup(
            faceIds: [a, b],
            cohesion: 0.95,
            quality: 0.9,
            autoCreate: true,
          ),
        ],
      ),
    );
    expect(result.newPeople, 0);
    expect(await db.select(db.persons).get(), isEmpty);
  });

  test('track propagation does not cross an embedding model or kind', () async {
    final person = await seedPerson(db);
    final anchor = await seedFace(db, personId: person);
    final candidate = await seedFace(db);
    await (db.update(db.faces)..where((f) => f.id.isIn([anchor, candidate])))
        .write(FacesCompanion(trackId: Value(anchor)));
    await (db.update(db.faces)..where((f) => f.id.equals(candidate))).write(
      const FacesCompanion(modelId: Value('different@1')),
    );
    await PlanApplier(
      db,
    ).applyFacePlan(const GroupingPlanResponse(mode: 'apply'));
    expect(await owner(candidate), isNull);
  });

  test(
    'body constraints see face owners and prevent cross-kind assignments',
    () async {
      final person = await seedPerson(db);
      final face = await seedFace(db, personId: person);
      final anchor = await seedBody(db, faceId: face);
      final distinct = await seedBody(db);
      final character = await seedBody(db);
      final free = await seedBody(db);
      await db
          .into(db.bodyDistinct)
          .insert(BodyDistinctCompanion.insert(bodyA: anchor, bodyB: distinct));
      await (db.update(db.bodies)..where((b) => b.id.equals(character))).write(
        const BodiesCompanion(kind: Value('character')),
      );
      final result = await PlanApplier(db).applyBodyPlan(
        GroupingPlanResponse(
          mode: 'apply',
          bodyLinks: [
            for (final id in [distinct, character, free])
              BodyLinkPlan(
                bodyId: id,
                personId: person,
                method: 'weak_face',
                confidence: 0.9,
                decision: 'auto',
              ),
          ],
        ),
      );
      expect(result, 1);
      final rows = {
        for (final b in await db.select(db.bodies).get()) b.id: b.personId,
      };
      expect(rows[distinct], isNull);
      expect(rows[character], isNull);
      expect(rows[free], person);
    },
  );
}
