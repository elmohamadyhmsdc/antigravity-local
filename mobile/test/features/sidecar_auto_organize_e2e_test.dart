import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/platform/media_organizer.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/organization/dynamic_auto_organizer.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_ingestion_service.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class TestDiskOrganizerBridge implements MediaOrganizerBridge {
  TestDiskOrganizerBridge({
    required this.rootDir,
    required this.currentPaths,
    Map<String, int>? currentTimestamps,
  }) : currentTimestamps = currentTimestamps ?? {};

  final Directory rootDir;
  final Map<String, (String, String)> currentPaths; // assetId -> (path, name)
  final Map<String, int> currentTimestamps;

  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async {
    return [
      for (final a in assets)
        OriginalMediaInfo(
          assetId: a.assetId,
          name: currentPaths[a.assetId]?.$2 ?? 'photo.jpg',
          path: currentPaths[a.assetId]?.$1 ?? 'DCIM/Camera/',
          modifiedAt: currentTimestamps[a.assetId] ?? 1700000000000,
          size: 1024,
        ),
    ];
  }

  @override
  Future<List<OriginalMoveResult>> preflight(
    List<OriginalMediaMove> moves,
  ) async {
    return [
      for (final m in moves)
        OriginalMoveResult(
          assetId: m.asset.assetId,
          status: 'ready',
          actual: OriginalMediaInfo(
            assetId: m.asset.assetId,
            name: m.targetName,
            path: m.targetPath,
            modifiedAt: currentTimestamps[m.asset.assetId] ?? 1700000000000,
            size: 1024,
          ),
        ),
    ];
  }

  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves) async {
    final results = <OriginalMoveResult>[];
    for (final m in moves) {
      final srcFile = File('${rootDir.path}/${m.source.path}${m.source.name}');
      final destDir = Directory('${rootDir.path}/${m.targetPath}');
      await destDir.create(recursive: true);
      final destFile = File('${destDir.path}${m.targetName}');
      if (await srcFile.exists()) {
        await srcFile.rename(destFile.path);
      } else {
        await destFile.writeAsString('fake image bytes');
      }

      final mod = DateTime.now().millisecondsSinceEpoch;
      currentTimestamps[m.asset.assetId] = mod;
      currentPaths[m.asset.assetId] = (m.targetPath, m.targetName);

      results.add(
        OriginalMoveResult(
          assetId: m.asset.assetId,
          status: 'moved',
          actual: OriginalMediaInfo(
            assetId: m.asset.assetId,
            name: m.targetName,
            path: m.targetPath,
            modifiedAt: mod,
            size: 1024,
          ),
        ),
      );
    }
    return results;
  }
}

void main() {
  late Directory tempDir;
  final sidecarStorage = const SidecarStorage();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sidecar_e2e_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'Full End-to-End: Organize -> Write Sidecar -> Wipe DB -> Zero-Rescan Restore -> Dynamic Reassign',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // =========================================================================
      // STEP 1: INITIAL STATE (DB1)
      // =========================================================================
      final db1 = AppDatabase(NativeDatabase.memory());
      final currentPaths = <String, (String, String)>{
        'asset_e2e_1': ('DCIM/Camera/', 'ahmed_portrait.jpg'),
      };
      final currentTimestamps = <String, int>{'asset_e2e_1': 1700000000000};
      final bridge1 = TestDiskOrganizerBridge(
        rootDir: tempDir,
        currentPaths: currentPaths,
        currentTimestamps: currentTimestamps,
      );
      final organizer1 = PersonMediaOrganizer(db: db1, bridge: bridge1);
      final autoOrganizer1 = DynamicAutoOrganizer(
        db: db1,
        organizer: organizer1,
        sidecarStorage: sidecarStorage,
      );

      // Initial camera file on disk
      final initialRelativePath = 'DCIM/Camera/ahmed_portrait.jpg';
      final cameraFile = File('${tempDir.path}/$initialRelativePath');
      await cameraFile.parent.create(recursive: true);
      await cameraFile.writeAsString('initial media contents');

      // Groups & Person
      final familyGroupId = await db1
          .into(db1.identityGroups)
          .insert(
            IdentityGroupsCompanion.insert(
              name: 'Family',
              nameKey: 'family',
              createdAt: now,
            ),
          );
      final ahmedPersonId = await db1
          .into(db1.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Ahmed'),
              groupId: Value(familyGroupId),
              createdAt: now,
            ),
          );

      // Media row
      final mediaId1 = await db1
          .into(db1.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'asset_e2e_1',
              kind: 'photo',
              scanStatus: const Value('done'),
              scanVersion: const Value(5),
              modifiedAt: const Value(1700000000000),
              width: const Value(1920),
              height: const Value(1080),
            ),
          );

      // Face detection with 512-float ArcFace embedding
      final faceVector = Float32List.fromList(
        List.generate(512, (i) => i * 0.001),
      );
      final faceId1 = await db1
          .into(db1.faces)
          .insert(
            FacesCompanion.insert(
              mediaId: Value(mediaId1),
              personId: Value(ahmedPersonId),
              modelId: 'buffalo_l',
              embedding: Uint8List.view(faceVector.buffer),
              qualityScore: 0.95,
              qualityVersion: 1,
              detScore: 0.99,
              facePx: 250.0,
              sharpness: 60.0,
              bboxX: 0.2,
              bboxY: 0.2,
              bboxW: 0.4,
              bboxH: 0.4,
              createdAt: now,
            ),
          );

      // Detection linkage
      await db1
          .into(db1.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: mediaId1,
              kind: 'f',
              refId: faceId1,
              x: 0.2,
              y: 0.2,
              w: 0.4,
              h: 0.4,
            ),
          );

      // =========================================================================
      // STEP 2: ORGANIZE MEDIA & VERIFY COMPANION SIDECAR ON DISK
      // =========================================================================
      final organizeResult = await autoOrganizer1.syncMedia(
        mediaId1,
        rootDirectory: tempDir.path,
      );

      expect(organizeResult, isNotNull);
      expect(organizeResult!.moved, isTrue);

      final expectedMediaRelPath =
          '${organizeResult.actual!.path}${organizeResult.actual!.name}';
      final expectedMediaFullPath = '${tempDir.path}/$expectedMediaRelPath';
      final expectedSidecarFullPath = '$expectedMediaFullPath.json';

      // Verify both files physically exist on disk
      expect(File(expectedMediaFullPath).existsSync(), isTrue);
      expect(File(expectedSidecarFullPath).existsSync(), isTrue);

      // Read and verify sidecar contents
      final sidecarMeta = await sidecarStorage.readSidecar(
        expectedMediaFullPath,
      );
      expect(sidecarMeta, isNotNull);
      expect(sidecarMeta!.assetId, 'asset_e2e_1');
      expect(sidecarMeta.ownership.groupName, 'Family');
      expect(sidecarMeta.ownership.masterPersonName, 'Ahmed');
      expect(sidecarMeta.faces.length, 1);
      expect(sidecarMeta.faces.first.embedding.length, 512);

      await db1.close();

      // =========================================================================
      // STEP 3: SIMULATE DB WIPE / ZERO-RESCAN RESTORATION (DB2)
      // =========================================================================
      final db2 = AppDatabase(NativeDatabase.memory());
      final index2 = InMemoryEmbeddingIndex();
      final ingestionService2 = SidecarIngestionService(db: db2, index: index2);
      final repo2 = LibraryRepository(
        db2,
        ingestionService: ingestionService2,
        sidecarStorage: sidecarStorage,
      );

      const scannedAsset = AssetInfo(
        id: 'asset_e2e_1',
        kind: 'photo',
        modifiedAt: 1700000000000,
        takenAt: 1700000000000,
        width: 1920,
        height: 1080,
      );

      final syncResult = await repo2.syncAssets(
        [scannedAsset],
        assetPaths: {'asset_e2e_1': expectedMediaFullPath},
      );

      // Zero-rescan ingestion: marked as completed/restored directly
      expect(syncResult.restored, 1);

      // Verify DB2 media row is fully done without PC scan
      final restoredMedia = await repo2.mediaByAssetId('asset_e2e_1');
      expect(restoredMedia, isNotNull);
      expect(restoredMedia!.scanStatus, 'done');
      expect(restoredMedia.scanVersion, 5);

      // Verify Group and Person restored
      final restoredPersons = await db2.select(db2.persons).get();
      expect(restoredPersons.length, 1);
      expect(restoredPersons.first.name, 'Ahmed');

      final restoredGroups = await db2.select(db2.identityGroups).get();
      expect(restoredGroups.length, 1);
      expect(restoredGroups.first.name, 'Family');

      // Verify Face & EmbeddingIndex restored
      final restoredFaces = await db2.select(db2.faces).get();
      expect(restoredFaces.length, 1);
      expect(restoredFaces.first.personId, restoredPersons.first.id);
      expect(await index2.size(), 1);

      // =========================================================================
      // STEP 4: DYNAMIC REASSIGNMENT & FOLDER AUTO-MOVE
      // =========================================================================
      final bridge2 = TestDiskOrganizerBridge(
        rootDir: tempDir,
        currentPaths: currentPaths,
        currentTimestamps: currentTimestamps,
      );
      final organizer2 = PersonMediaOrganizer(db: db2, bridge: bridge2);
      final autoOrganizer2 = DynamicAutoOrganizer(
        db: db2,
        organizer: organizer2,
        sidecarStorage: sidecarStorage,
      );

      // Create Sara in Friends group
      final friendsGroupId = await db2
          .into(db2.identityGroups)
          .insert(
            IdentityGroupsCompanion.insert(
              name: 'Friends',
              nameKey: 'friends',
              createdAt: now,
            ),
          );
      final saraPersonId = await db2
          .into(db2.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Sara'),
              groupId: Value(friendsGroupId),
              createdAt: now,
            ),
          );

      // Reassign face to Sara in DB2
      await (db2.update(db2.faces)
            ..where((f) => f.id.equals(restoredFaces.first.id)))
          .write(FacesCompanion(personId: Value(saraPersonId)));

      // Trigger dynamic auto-organizer sync
      final reassignResult = await autoOrganizer2.syncMedia(
        restoredMedia.id,
        rootDirectory: tempDir.path,
      );

      expect(reassignResult, isNotNull);
      expect(reassignResult!.moved, isTrue);

      final saraMediaRelPath =
          '${reassignResult.actual!.path}${reassignResult.actual!.name}';
      final saraMediaFullPath = '${tempDir.path}/$saraMediaRelPath';
      final saraSidecarFullPath = '$saraMediaFullPath.json';

      // Verify media & sidecar moved into Friends/Sara/ folder
      expect(saraMediaFullPath, contains('Friends/Sara/'));
      expect(File(saraMediaFullPath).existsSync(), isTrue);
      expect(File(saraSidecarFullPath).existsSync(), isTrue);

      // Verify old sidecar at Family/Ahmed/ was deleted
      expect(File(expectedSidecarFullPath).existsSync(), isFalse);

      // =========================================================================
      // STEP 5: MASTER PERSON SWITCHING ON SHARED PHOTO
      // =========================================================================
      // Add Luffy to the media
      final strawHatsGroupId = await db2
          .into(db2.identityGroups)
          .insert(
            IdentityGroupsCompanion.insert(
              name: 'StrawHats',
              nameKey: 'strawhats',
              createdAt: now,
            ),
          );
      final luffyPersonId = await db2
          .into(db2.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Luffy'),
              groupId: Value(strawHatsGroupId),
              createdAt: now,
            ),
          );

      final luffyFaceVector = Float32List.fromList(
        List.generate(512, (i) => 0.05),
      );
      final luffyFaceId = await db2
          .into(db2.faces)
          .insert(
            FacesCompanion.insert(
              mediaId: Value(restoredMedia.id),
              personId: Value(luffyPersonId),
              modelId: 'buffalo_l',
              embedding: Uint8List.view(luffyFaceVector.buffer),
              qualityScore: 0.90,
              qualityVersion: 1,
              detScore: 0.95,
              facePx: 180.0,
              sharpness: 55.0,
              bboxX: 0.6,
              bboxY: 0.2,
              bboxW: 0.3,
              bboxH: 0.3,
              createdAt: now,
            ),
          );

      await db2
          .into(db2.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: restoredMedia.id,
              kind: 'f',
              refId: luffyFaceId,
              x: 0.6,
              y: 0.2,
              w: 0.3,
              h: 0.3,
            ),
          );

      // Switch Master Person explicitly to Luffy
      final masterResult = await autoOrganizer2.setMasterPerson(
        restoredMedia.id,
        luffyPersonId,
        rootDirectory: tempDir.path,
      );

      expect(masterResult, isNotNull);
      expect(masterResult!.moved, isTrue);

      final luffyMediaRelPath =
          '${masterResult.actual!.path}${masterResult.actual!.name}';
      final luffyMediaFullPath = '${tempDir.path}/$luffyMediaRelPath';
      final luffySidecarFullPath = '$luffyMediaFullPath.json';

      // Verify media and sidecar physically moved to StrawHats/Luffy/
      expect(luffyMediaFullPath, contains('StrawHats/Luffy/'));
      expect(File(luffyMediaFullPath).existsSync(), isTrue);
      expect(File(luffySidecarFullPath).existsSync(), isTrue);

      // Verify sidecar preserves metadata for both people (Luffy as master, Sara present)
      final sharedSidecar = await sidecarStorage.readSidecar(
        luffyMediaFullPath,
      );
      expect(sharedSidecar, isNotNull);
      expect(sharedSidecar!.ownership.masterPersonName, 'Luffy');
      expect(sharedSidecar.faces.length, 2);
      final faceNames = sharedSidecar.faces.map((f) => f.personName).toSet();
      expect(faceNames, containsAll(['Luffy', 'Sara']));

      await db2.close();
    },
  );
}
