import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_ingestion_service.dart';

void main() {
  late AppDatabase db;
  late InMemoryEmbeddingIndex index;
  late SidecarIngestionService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    index = InMemoryEmbeddingIndex();
    service = SidecarIngestionService(db: db, index: index);
  });

  tearDown(() async {
    await db.close();
  });

  test('ingestSidecar creates person, group, faces, bodies, and marks media done', () async {
    final meta = SidecarMetadata(
      version: 1,
      assetId: 'asset_99',
      mediaInfo: const SidecarMediaInfo(
        kind: 'photo',
        width: 1920,
        height: 1080,
        takenAt: 1700000000000,
        modifiedAt: 1700000005000,
      ),
      ownership: const SidecarOwnership(
        groupId: 1,
        groupName: 'Pirates',
        masterPersonId: 10,
        masterPersonName: 'Zoro',
        masterPersonKind: 'person',
      ),
      faces: [
        SidecarFace(
          faceId: 1,
          personId: 10,
          personName: 'Zoro',
          bbox: const [0.2, 0.2, 0.3, 0.3],
          quality: 0.95,
          yaw: 0.0,
          pitch: 0.0,
          roll: 0.0,
          embeddingModel: 'buffalo_l',
          embedding: Float32List.fromList(List.filled(512, 0.05)),
          trackId: null,
        ),
      ],
      bodies: [
        SidecarBody(
          bodyId: 1,
          personId: 10,
          bbox: const [0.1, 0.1, 0.5, 0.8],
          keypoints: const [
            [10.0, 20.0, 0.9],
          ],
          appearance: Float32List.fromList(List.filled(80, 0.1)),
          extent: 'full',
          outline: const [
            [0.1, 0.1],
            [0.6, 0.1],
          ],
        ),
      ],
      sensitiveRegions: const [],
      equipmentObjects: const [],
    );

    final mediaId = await service.ingest(meta);
    expect(mediaId, isNotNull);

    // Verify DB media row
    final media = await (db.select(db.media)..where((m) => m.id.equals(mediaId!))).getSingle();
    expect(media.assetId, 'asset_99');
    expect(media.scanStatus, 'done');

    // Verify Person and Group
    final persons = await db.select(db.persons).get();
    expect(persons.length, 1);
    expect(persons.first.name, 'Zoro');

    final groups = await db.select(db.identityGroups).get();
    expect(groups.length, 1);
    expect(groups.first.name, 'Pirates');
    expect(persons.first.groupId, groups.first.id);

    // Verify Faces and Bodies
    final faces = await db.select(db.faces).get();
    expect(faces.length, 1);
    expect(faces.first.personId, persons.first.id);
    expect(faces.first.mediaId, mediaId);

    final bodies = await db.select(db.bodies).get();
    expect(bodies.length, 1);
    expect(bodies.first.personId, persons.first.id);
    expect(bodies.first.mediaId, mediaId);

    // Verify index contains vector
    expect(await index.size(), 1);
  });
}
