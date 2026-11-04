import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_ingestion_service.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late InMemoryEmbeddingIndex index;
  late SidecarIngestionService ingestion;
  late SidecarStorage sidecarStorage;
  late LibraryRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zero_rescan_test');
    db = AppDatabase(NativeDatabase.memory());
    index = InMemoryEmbeddingIndex();
    ingestion = SidecarIngestionService(db: db, index: index);
    sidecarStorage = const SidecarStorage();
    repo = LibraryRepository(
      db,
      ingestionService: ingestion,
      sidecarStorage: sidecarStorage,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'syncAssets automatically ingests sidecars and marks media done without pending scan',
    () async {
      final mediaFile = File('${tempDir.path}/Luffy_0001.jpg');
      await mediaFile.writeAsBytes([1, 2, 3]);

      final metadata = SidecarMetadata(
        version: 1,
        assetId: 'asset_sidecar_1',
        mediaInfo: const SidecarMediaInfo(
          kind: 'photo',
          width: 1200,
          height: 1600,
          modifiedAt: 1700000000000,
          takenAt: 1700000000000,
        ),
        ownership: const SidecarOwnership(
          groupName: 'StrawHats',
          masterPersonName: 'Luffy',
        ),
        faces: [
          SidecarFace(
            personName: 'Luffy',
            bbox: const [0.2, 0.2, 0.4, 0.4],
            quality: 0.98,
            embeddingModel: 'buffalo_l',
            embedding: Float32List.fromList(List.filled(512, 0.1)),
          ),
        ],
        bodies: const [],
      );

      // Write sidecar JSON on disk
      await sidecarStorage.writeSidecar(mediaFile.path, metadata);

      const asset = AssetInfo(
        id: 'asset_sidecar_1',
        kind: 'photo',
        modifiedAt: 1700000000000,
        takenAt: 1700000000000,
        width: 1200,
        height: 1600,
      );

      // Call syncAssets passing the known media file path
      final result = await repo.syncAssets(
        [asset],
        assetPaths: {'asset_sidecar_1': mediaFile.path},
      );

      expect(result.restored, 1);

      // Verify DB media row
      final row = await repo.mediaByAssetId('asset_sidecar_1');
      expect(row, isNotNull);
      expect(row!.scanStatus, 'done');
      expect(row.width, 1200);

      // Verify Person created and Index fed
      final person = await (db.select(
        db.persons,
      )..where((p) => p.name.equals('Luffy'))).getSingle();
      expect(person.name, 'Luffy');
      expect(await index.size(), 1);
    },
  );
}
