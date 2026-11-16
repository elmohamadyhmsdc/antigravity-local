import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/corrections/targeted_detection_service.dart';

import '../../support/seed.dart';

void main() {
  late AppDatabase db;
  late TargetedDetectionService service;
  late Directory temporary;
  late FileStore files;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temporary = await Directory.systemTemp.createTemp('anime-targeted-');
    files = FileStore(temporary);
    service = TargetedDetectionService(db: db, files: files);
  });

  tearDown(() async {
    await db.close();
    await temporary.delete(recursive: true);
  });

  TargetedEntry animeEntry(int mediaId, {String name = '', int? personId}) => TargetedEntry(
    mediaId: mediaId, kind: 'anime_face',
    bbox: const BBox(x: .2, y: .3, w: .3, h: .4),
    label: name, personId: personId,
    embeddingModelId: characterEmbeddingModelId,
    embedding: Float32List(characterEmbeddingDim)..[0] = 1,
    cropJpeg: Uint8List.fromList([255, 216, 255, 217]),
    score: 0, manual: true, facePx: 128,
  );

  group('TargetedDetectionService', () {
    test('anime face saves CCIP, crop, named character and correction; undo removes them', () async {
      final media = await seedMedia(db, asset: 'anime-photo');
      final result = await service.apply(animeEntry(media, name: 'Mira'));
      final face = await db.select(db.faces).getSingle();
      expect(face.kind, 'character');
      expect(face.modelId, characterEmbeddingModelId);
      expect(vectorFromBlob(face.embedding).length, characterEmbeddingDim);
      expect(face.detScore, 0);
      expect(face.facePx, 128);
      final owner = await db.select(db.persons).getSingle();
      expect(owner.kind, 'character');
      expect(owner.name, 'Mira');
      expect(owner.avatarFaceId, face.id);
      expect(face.personId, owner.id);
      expect(await files.resolve(face.cropPath!).readAsBytes(), [255, 216, 255, 217]);
      final detection = await db.select(db.mediaDetections).getSingle();
      expect(detection.refId, face.id);
      final correction = await db.select(db.kindOverrides).getSingle();
      expect(correction.kind, 'character');
      expect(correction.part, 'face');
      expect(correction.assetId, 'anime-photo');
      await service.undo(result.undoToken);
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.persons).get(), isEmpty);
      expect(await db.select(db.mediaDetections).get(), isEmpty);
      expect(await db.select(db.kindOverrides).get(), isEmpty);
      expect(await files.allFiles(), isEmpty);
    });

    test('same-box recovery refuses duplicates without changing saved evidence', () async {
      final media = await seedMedia(db, asset: 'same-anime');
      await service.apply(animeEntry(media));
      await expectLater(service.apply(animeEntry(media)), throwsStateError);
      expect(await db.select(db.faces).get(), hasLength(1));
      expect(await db.select(db.mediaDetections).get(), hasLength(1));
      expect(await db.select(db.kindOverrides).get(), hasLength(1));
      expect(await files.allFiles(), hasLength(1));
    });

    test('failed anime save rolls back the identity, face, correction and crop', () async {
      final media = await seedMedia(db, asset: 'rollback-anime');
      await db.customStatement('CREATE TRIGGER reject_detection BEFORE INSERT ON media_detections '
          "BEGIN SELECT RAISE(ABORT, 'fixture failure'); END");
      await expectLater(service.apply(animeEntry(media, name: 'Transient')), throwsA(anything));
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.persons).get(), isEmpty);
      expect(await db.select(db.kindOverrides).get(), isEmpty);
      expect(await files.allFiles(), isEmpty);
    });

    test('anime faces cannot be assigned to human identities', () async {
      final media = await seedMedia(db, asset: 'protected-person');
      final human = await seedPerson(db, name: 'Human');
      await expectLater(service.apply(animeEntry(media, personId: human)), throwsStateError);
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.kindOverrides).get(), isEmpty);
      expect((await db.select(db.persons).getSingle()).kind, 'person');
    });

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

        // Verify media_detections was inserted
        final dets = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId) & d.kind.equals('b'))).get();
        expect(dets.length, 1);
        expect(dets.first.refId, result.insertedId);

        // Undo
        await service.undo(result.undoToken);
        final bodiesAfterUndo = await (db.select(
          db.bodies,
        )..where((b) => b.id.equals(result.insertedId))).get();
        expect(bodiesAfterUndo, isEmpty);
        final overridesAfterUndo = await db.select(db.bodyOverrides).get();
        expect(overridesAfterUndo, isEmpty);
        final detsAfterUndo = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId))).get();
        expect(detsAfterUndo, isEmpty);
      },
    );

    test(
      'applies targeted area and persists in sensitive_regions and media_detections',
      () async {
        final mediaId = await seedMedia(db, asset: 'asset_area_1');

        final entry = TargetedEntry(
          mediaId: mediaId,
          kind: 'area',
          bbox: const BBox(x: 0.2, y: 0.3, w: 0.4, h: 0.5),
          label: 'Custom Tattoo Area',
        );

        final result = await service.apply(entry);
        expect(result.insertedId, isNonZero);

        // Verify sensitive_regions
        final regions = await (db.select(
          db.sensitiveRegions,
        )..where((r) => r.id.equals(result.insertedId))).get();
        expect(regions.length, 1);
        expect(regions.first.label, 'Custom Tattoo Area');
        expect(regions.first.exposed, isTrue);

        // Verify media_detections
        final dets = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId) & d.kind.equals('a'))).get();
        expect(dets.length, 1);
        expect(dets.first.refId, result.insertedId);

        // Verify settings
        final settings = await db.select(db.settings).get();
        expect(settings.any((s) => s.value == 'Custom Tattoo Area'), isTrue);

        // Undo
        await service.undo(result.undoToken);
        final regionsAfterUndo = await (db.select(
          db.sensitiveRegions,
        )..where((r) => r.id.equals(result.insertedId))).get();
        expect(regionsAfterUndo, isEmpty);

        final detsAfterUndo = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId))).get();
        expect(detsAfterUndo, isEmpty);
      },
    );

    test(
      'applies targeted face and persists in faces and media_detections',
      () async {
        final mediaId = await seedMedia(db, asset: 'asset_face_1');
        final personId = await seedPerson(db, name: 'Bob');

        final entry = TargetedEntry(
          mediaId: mediaId,
          kind: 'face',
          bbox: const BBox(x: 0.1, y: 0.1, w: 0.2, h: 0.2),
          label: 'Bob Face',
          personId: personId,
        );

        final result = await service.apply(entry);
        expect(result.insertedId, isNonZero);

        // Verify face in db
        final faces = await (db.select(
          db.faces,
        )..where((f) => f.id.equals(result.insertedId))).get();
        expect(faces.length, 1);
        expect(faces.first.personId, personId);

        // Verify media_detections
        final dets = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId) & d.kind.equals('f'))).get();
        expect(dets.length, 1);
        expect(dets.first.refId, result.insertedId);

        // Undo
        await service.undo(result.undoToken);
        final facesAfterUndo = await (db.select(
          db.faces,
        )..where((f) => f.id.equals(result.insertedId))).get();
        expect(facesAfterUndo, isEmpty);
        final detsAfterUndo = await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId))).get();
        expect(detsAfterUndo, isEmpty);
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
