import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/platform/media_organizer.dart';
import 'package:antigravity_mobile/domain/organization/dynamic_auto_organizer.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';

class FakeOrganizerBridge implements MediaOrganizerBridge {
  final moved = <OriginalMediaMove>[];

  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async => [
    for (final a in assets)
      OriginalMediaInfo(
        assetId: a.assetId,
        name: 'test_photo.jpg',
        path: 'DCIM/Camera/test_photo.jpg',
        modifiedAt: 1700000000000,
        size: 2048,
        mimeType: 'image/jpeg',
      ),
  ];

  @override
  Future<List<OriginalMoveResult>> preflight(List<OriginalMediaMove> moves) async => [
    for (final m in moves)
      OriginalMoveResult(
        assetId: m.asset.assetId,
        status: 'ready',
        actual: OriginalMediaInfo(
          assetId: m.asset.assetId,
          name: m.targetName,
          path: m.targetPath,
          modifiedAt: 1700000000000,
          size: 2048,
        ),
      ),
  ];

  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves) async {
    moved.addAll(moves);
    return [
      for (final m in moves)
        OriginalMoveResult(
          assetId: m.asset.assetId,
          status: 'moved',
          actual: OriginalMediaInfo(
            assetId: m.asset.assetId,
            name: m.targetName,
            path: m.targetPath,
            modifiedAt: 1700000001000,
            size: 2048,
          ),
        ),
    ];
  }
}

void main() {
  late Directory tempDir;
  late AppDatabase db;
  late FakeOrganizerBridge bridge;
  late PersonMediaOrganizer organizer;
  late SidecarStorage sidecarStorage;
  late DynamicAutoOrganizer autoOrganizer;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('auto_organizer_test');
    db = AppDatabase(NativeDatabase.memory());
    bridge = FakeOrganizerBridge();
    organizer = PersonMediaOrganizer(db: db, bridge: bridge);
    sidecarStorage = const SidecarStorage();
    autoOrganizer = DynamicAutoOrganizer(
      db: db,
      organizer: organizer,
      sidecarStorage: sidecarStorage,
    );
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('DynamicAutoOrganizer moves media and generates sidecar when reassigning person', () async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Create Group and Person
    final groupId = await db.into(db.identityGroups).insert(
      IdentityGroupsCompanion.insert(name: 'StrawHats', nameKey: 'strawhats', createdAt: now),
    );
    final luffyId = await db.into(db.persons).insert(
      PersonsCompanion.insert(name: const Value('Luffy'), groupId: Value(groupId), createdAt: now),
    );

    // Create Media
    final mediaId = await db.into(db.media).insert(
      MediaCompanion.insert(
        assetId: 'asset_auto_1',
        kind: 'photo',
        scanStatus: const Value('done'),
        modifiedAt: const Value(1700000000000),
      ),
    );

    // Create Face assigned to Luffy
    await db.into(db.faces).insert(
      FacesCompanion.insert(
        mediaId: Value(mediaId),
        personId: Value(luffyId),
        modelId: 'buffalo_l',
        embedding: Uint8List(2048),
        qualityScore: 0.95,
        qualityVersion: 1,
        detScore: 0.95,
        facePx: 120.0,
        sharpness: 90.0,
        bboxX: 0.2,
        bboxY: 0.2,
        bboxW: 0.3,
        bboxH: 0.3,
        createdAt: now,
      ),
    );

    // Trigger auto-sync for media
    final result = await autoOrganizer.syncMedia(mediaId, rootDirectory: tempDir.path);
    expect(result, isNotNull);
    expect(result!.moved, isTrue);
    expect(bridge.moved.length, 1);
    expect(bridge.moved.first.targetPath, contains('StrawHats/Luffy/'));

    // Verify sidecar was created on disk in target folder
    final sidecarFile = File('${tempDir.path}/${bridge.moved.first.targetPath}${bridge.moved.first.targetName}.json');
    expect(await sidecarFile.exists(), isTrue);

    final readMeta = await sidecarStorage.readSidecar('${tempDir.path}/${bridge.moved.first.targetPath}${bridge.moved.first.targetName}');
    expect(readMeta, isNotNull);
    expect(readMeta!.ownership.masterPersonName, 'Luffy');
    expect(readMeta.faces.length, 1);
  });
}
