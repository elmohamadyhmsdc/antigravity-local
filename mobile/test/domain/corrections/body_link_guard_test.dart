import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late BodyLinkGuard guard;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    guard = BodyLinkGuard(db);
  });

  tearDown(() async => db.close());

  test(
    'canAutoLink returns false for ownership none or hidden bodies',
    () async {
      final mediaId = await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'asset_guard_1',
              kind: 'photo',
              scanStatus: const Value('done'),
            ),
          );
      final personId = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));

      final normalBody = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              bboxX: 0.1,
              bboxY: 0.1,
              bboxW: 0.4,
              bboxH: 0.7,
              score: 0.9,
              createdAt: 1,
            ),
          );

      final noneBody = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              bboxX: 0.1,
              bboxY: 0.1,
              bboxW: 0.4,
              bboxH: 0.7,
              score: 0.9,
              ownership: const Value('none'),
              createdAt: 1,
            ),
          );

      final hiddenBody = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              bboxX: 0.1,
              bboxY: 0.1,
              bboxW: 0.4,
              bboxH: 0.7,
              score: 0.9,
              hidden: const Value(true),
              createdAt: 1,
            ),
          );

      expect(await guard.canAutoLink(normalBody, personId), isTrue);
      expect(await guard.canAutoLink(noneBody, personId), isFalse);
      expect(await guard.canAutoLink(hiddenBody, personId), isFalse);
    },
  );

  test('canAutoLink returns false when distinct from person body', () async {
    final mediaId = await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            assetId: 'asset_guard_2',
            kind: 'photo',
            scanStatus: const Value('done'),
          ),
        );
    final personId = await db
        .into(db.persons)
        .insert(PersonsCompanion.insert(createdAt: 1));

    final personBody = await db
        .into(db.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(mediaId),
            personId: Value(personId),
            bboxX: 0.1,
            bboxY: 0.1,
            bboxW: 0.3,
            bboxH: 0.6,
            score: 0.9,
            createdAt: 1,
          ),
        );

    final candidateBody = await db
        .into(db.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(mediaId),
            bboxX: 0.5,
            bboxY: 0.1,
            bboxW: 0.3,
            bboxH: 0.6,
            score: 0.85,
            createdAt: 1,
          ),
        );

    expect(await guard.canAutoLink(candidateBody, personId), isTrue);

    // Mark distinct
    await db
        .into(db.bodyDistinct)
        .insert(
          BodyDistinctCompanion.insert(bodyA: personBody, bodyB: candidateBody),
        );

    // Auto link must now be rejected
    expect(await guard.canAutoLink(candidateBody, personId), isFalse);

    // Manual link clears the conflict
    await guard.onManualLink(candidateBody, personId);
    expect(await guard.canAutoLink(candidateBody, personId), isTrue);
  });

  test(
    'findMergeConflicts identifies distinct bodies between people',
    () async {
      final mediaId = await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'asset_guard_3',
              kind: 'photo',
              scanStatus: const Value('done'),
            ),
          );
      final pA = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));
      final pB = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 2));

      final bodyA = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(mediaId),
              personId: Value(pA),
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
              personId: Value(pB),
              bboxX: 0.5,
              bboxY: 0.1,
              bboxW: 0.3,
              bboxH: 0.6,
              score: 0.85,
              createdAt: 1,
            ),
          );

      expect(await guard.findMergeConflicts(pB, pA), isEmpty);

      // Mark distinct
      await db
          .into(db.bodyDistinct)
          .insert(BodyDistinctCompanion.insert(bodyA: bodyA, bodyB: bodyB));

      final conflicts = await guard.findMergeConflicts(pB, pA);
      expect(conflicts, contains(bodyB));
    },
  );
}
