import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/corrections/targeted_detection_service.dart';

import '../../support/seed.dart';

void main() {
  late AppDatabase db;
  late TargetedDetectionService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = TargetedDetectionService(db: db);
  });

  tearDown(() async => db.close());

  group('TargetedDetectionService', () {
    test(
      'applies targeted body and persists in db and body_overrides',
      () async {
        final mediaId = await seedMedia(db, asset: 'asset_test_1');
        final personId = await seedPerson(db, name: 'Alice');

        final entry = TargetedEntry(
          mediaId: mediaId,
          kind: 'body',
          bbox: const BBox(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
          label: 'Alice Body',
          personId: personId,
          keypoints: [
            [0.15, 0.25, 0.9],
          ],
        );

        final result = await service.apply(entry);
        expect(result.insertedId, isNonZero);
        expect(result.undoToken, isNotEmpty);

        // Verify body was inserted
        final bodies = await (db.select(
          db.bodies,
        )..where((b) => b.id.equals(result.insertedId))).get();
        expect(bodies.length, 1);
        expect(bodies.first.personId, personId);
        expect(bodies.first.bboxX, 0.1);
        expect(bodies.first.kpts, contains('0.15'));

        // Verify override was inserted
        final overrides = await db.select(db.bodyOverrides).get();
        expect(overrides.length, 1);
        expect(overrides.first.assetId, 'asset_test_1');

        // Undo
        await service.undo(result.undoToken);
        final bodiesAfterUndo = await (db.select(
          db.bodies,
        )..where((b) => b.id.equals(result.insertedId))).get();
        expect(bodiesAfterUndo, isEmpty);
        final overridesAfterUndo = await db.select(db.bodyOverrides).get();
        expect(overridesAfterUndo, isEmpty);
      },
    );

    test('applies targeted object and persists in equipment_objects', () async {
      final mediaId = await seedMedia(db, asset: 'asset_obj_1');

      final entry = TargetedEntry(
        mediaId: mediaId,
        kind: 'object',
        bbox: const BBox(x: 0.4, y: 0.5, w: 0.2, h: 0.3),
        label: 'Tennis Racket',
      );

      final result = await service.apply(entry);
      expect(result.insertedId, isNonZero);

      final objects = await (db.select(
        db.equipmentObjects,
      )..where((o) => o.id.equals(result.insertedId))).get();
      expect(objects.length, 1);
      expect(objects.first.label, 'Tennis Racket');

      // Undo
      await service.undo(result.undoToken);
      final objectsAfterUndo = await (db.select(
        db.equipmentObjects,
      )..where((o) => o.id.equals(result.insertedId))).get();
      expect(objectsAfterUndo, isEmpty);
    });
  });
}
