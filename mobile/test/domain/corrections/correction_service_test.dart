import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:antigravity_mobile/domain/corrections/correction_scope.dart';
import 'package:antigravity_mobile/domain/corrections/correction_target.dart';
import 'package:antigravity_mobile/domain/corrections/correction_verb.dart';
import 'package:antigravity_mobile/domain/corrections/correction_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PeopleRepository peopleRepo;
  late BodyLinkGuard bodyLinkGuard;
  late CorrectionService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    peopleRepo = PeopleRepository(db, FileStore(Directory.systemTemp));
    bodyLinkGuard = BodyLinkGuard(db);
    service = CorrectionService(
      db: db,
      peopleRepo: peopleRepo,
      bodyLinkGuard: bodyLinkGuard,
    );
  });

  tearDown(() async => db.close());

  test('allowedVerbs matches specification for every target', () {
    expect(
      service.allowedVerbs(
        const FaceLinkTarget(faceId: 1, mediaId: 1, personId: 1),
      ),
      containsAll([
        CorrectionVerb.reassign,
        CorrectionVerb.notThisPerson,
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ]),
    );

    expect(
      service.allowedVerbs(
        const BodyLinkTarget(bodyId: 1, mediaId: 1, personId: 1),
      ),
      containsAll([
        CorrectionVerb.reassign,
        CorrectionVerb.notThisPerson,
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notARealThing,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ]),
    );

    expect(
      service.allowedVerbs(
        const BodyPairTarget(bodyAId: 1, bodyBId: 2, mediaId: 1),
      ),
      containsAll([
        CorrectionVerb.belongsToNoOne,
        CorrectionVerb.notSamePerson,
        CorrectionVerb.unlink,
        CorrectionVerb.confirm,
      ]),
    );
  });

  test('Face belongsToNoOne sets ownership none and undo restores', () async {
    final mediaId = await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            assetId: 'asset_face_1',
            kind: 'photo',
            scanStatus: const Value('done'),
          ),
        );
    final personId = await db
        .into(db.persons)
        .insert(PersonsCompanion.insert(createdAt: 1));

    final faceId = await db
        .into(db.faces)
        .insert(
          FacesCompanion.insert(
            mediaId: Value(mediaId),
            personId: Value(personId),
            modelId: 'm',
            embedding: Uint8List(2048),
            qualityScore: 0.9,
            qualityVersion: 1,
            detScore: 0.9,
            facePx: 100,
            sharpness: 50,
            bboxX: 0.1,
            bboxY: 0.1,
            bboxW: 0.2,
            bboxH: 0.2,
            createdAt: 1,
          ),
        );

    final target = FaceLinkTarget(
      faceId: faceId,
      mediaId: mediaId,
      personId: personId,
    );

    // Preview
    final prev = await service.preview(target, CorrectionVerb.belongsToNoOne);
    expect(prev.itemsCount, 1);
    expect(prev.consequences, isNotEmpty);

    // Apply
    final result = await service.apply(target, CorrectionVerb.belongsToNoOne);
    expect(result.affectedCount, 1);

    final faceAfter = await (db.select(
      db.faces,
    )..where((f) => f.id.equals(faceId))).getSingle();
    expect(faceAfter.personId, isNull);
    expect(faceAfter.ownership, 'none');
    expect(faceAfter.reviewDismissed, isTrue);

    final overrides = await db.select(db.faceOverrides).get();
    expect(overrides.length, 1);
    expect(overrides.first.ownership, 'none');

    // Undo
    final undone = await service.undo(result.undoToken);
    expect(undone, isTrue);

    final faceRestored = await (db.select(
      db.faces,
    )..where((f) => f.id.equals(faceId))).getSingle();
    expect(faceRestored.personId, personId);
    expect(faceRestored.ownership, isNull);
    expect(faceRestored.reviewDismissed, isFalse);

    final remainingOverrides = await db.select(db.faceOverrides).get();
    expect(remainingOverrides, isEmpty);
  });

  test(
    'Body belongsToNoOne and notARealThing set ownership and hidden with undo',
    () async {
      final mediaId = await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'asset_body_1',
              kind: 'photo',
              scanStatus: const Value('done'),
            ),
          );
      final personId = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));

      final bodyId = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              personId: Value(personId),
              bboxX: 0.1,
              bboxY: 0.1,
              bboxW: 0.4,
              bboxH: 0.7,
              score: 0.9,
              createdAt: 1,
            ),
          );

      final target = BodyLinkTarget(
        bodyId: bodyId,
        mediaId: mediaId,
        personId: personId,
      );

      // Apply belongsToNoOne
      final res1 = await service.apply(target, CorrectionVerb.belongsToNoOne);
      var body = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyId))).getSingle();
      expect(body.personId, isNull);
      expect(body.ownership, 'none');
      expect(body.hidden, isFalse);

      await service.undo(res1.undoToken);
      body = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyId))).getSingle();
      expect(body.personId, personId);
      expect(body.ownership, isNull);

      // Apply notARealThing
      final res2 = await service.apply(target, CorrectionVerb.notARealThing);
      body = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyId))).getSingle();
      expect(body.hidden, isTrue);
      expect(body.personId, isNull);

      await service.undo(res2.undoToken);
      body = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyId))).getSingle();
      expect(body.hidden, isFalse);
      expect(body.personId, personId);
    },
  );

  test(
    'BodyPair notSamePerson creates distinct entry, unlinks duplicate and separates track',
    () async {
      final mediaId = await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'asset_pair_1',
              kind: 'video',
              scanStatus: const Value('done'),
            ),
          );
      final personId = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));

      final bodyA = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              personId: Value(personId),
              trackId: const Value(10),
              bboxX: 0.1,
              bboxY: 0.1,
              bboxW: 0.3,
              bboxH: 0.6,
              score: 0.9,
              createdAt: 1,
            ),
          );

      final bodyB = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              personId: Value(personId),
              trackId: const Value(10),
              bboxX: 0.5,
              bboxY: 0.1,
              bboxW: 0.3,
              bboxH: 0.6,
              score: 0.88,
              createdAt: 2,
            ),
          );

      final target = BodyPairTarget(
        bodyAId: bodyA,
        bodyBId: bodyB,
        mediaId: mediaId,
      );

      final result = await service.apply(target, CorrectionVerb.notSamePerson);
      expect(result.affectedCount, 2);

      // Distinct inserted
      final distinct = await db.select(db.bodyDistinct).get();
      expect(distinct.length, 1);
      expect(distinct.first.bodyA, bodyA);
      expect(distinct.first.bodyB, bodyB);

      // bodyB unlinked and track cleared
      final bAfter = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyB))).getSingle();
      expect(bAfter.personId, isNull);
      expect(bAfter.trackId, isNull);

      // Undo
      final undone = await service.undo(result.undoToken);
      expect(undone, isTrue);

      final distinctAfterUndo = await db.select(db.bodyDistinct).get();
      expect(distinctAfterUndo, isEmpty);

      final bRestored = await (db.select(
        db.bodies,
      )..where((b) => b.id.equals(bodyB))).getSingle();
      expect(bRestored.personId, personId);
      expect(bRestored.trackId, 10);
    },
  );

  test('Track scope affects all elements in the same track', () async {
    final mediaId = await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            assetId: 'asset_track_video',
            kind: 'video',
            scanStatus: const Value('done'),
          ),
        );
    final personId = await db
        .into(db.persons)
        .insert(PersonsCompanion.insert(createdAt: 1));

    final b1 = await db
        .into(db.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(mediaId),
            personId: Value(personId),
            trackId: const Value(42),
            bboxX: 0.1,
            bboxY: 0.1,
            bboxW: 0.3,
            bboxH: 0.6,
            score: 0.9,
            createdAt: 1,
          ),
        );

    final b2 = await db
        .into(db.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(mediaId),
            personId: Value(personId),
            trackId: const Value(42),
            bboxX: 0.12,
            bboxY: 0.11,
            bboxW: 0.3,
            bboxH: 0.6,
            score: 0.89,
            createdAt: 2,
          ),
        );

    final target = BodyLinkTarget(
      bodyId: b1,
      mediaId: mediaId,
      personId: personId,
      trackId: 42,
    );

    final prev = await service.preview(
      target,
      CorrectionVerb.belongsToNoOne,
      scope: CorrectionScope.track,
    );
    expect(prev.itemsCount, 2);

    final res = await service.apply(
      target,
      CorrectionVerb.belongsToNoOne,
      scope: CorrectionScope.track,
    );
    expect(res.affectedCount, 2);

    final b1Row = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(b1))).getSingle();
    final b2Row = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(b2))).getSingle();

    expect(b1Row.ownership, 'none');
    expect(b2Row.ownership, 'none');
    expect(b1Row.personId, isNull);
    expect(b2Row.personId, isNull);
  });
}
