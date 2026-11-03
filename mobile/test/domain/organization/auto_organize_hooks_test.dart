import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/platform/media_organizer.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/corrections/body_link_guard.dart';
import 'package:antigravity_mobile/domain/corrections/correction_service.dart';
import 'package:antigravity_mobile/domain/corrections/correction_target.dart';
import 'package:antigravity_mobile/domain/corrections/correction_verb.dart';
import 'package:antigravity_mobile/domain/organization/dynamic_auto_organizer.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOrganizerBridge implements MediaOrganizerBridge {
  @override
  Future<List<OriginalMediaInfo>> inspect(List<OrganizeAsset> assets) async => [];

  @override
  Future<List<OriginalMoveResult>> preflight(List<OriginalMediaMove> moves) async => [];

  @override
  Future<List<OriginalMoveResult>> move(List<OriginalMediaMove> moves) async => [];
}

class SpyAutoOrganizer extends DynamicAutoOrganizer {
  SpyAutoOrganizer({required super.db, required super.organizer});

  final List<int> syncedMediaIds = [];
  final List<int> syncedPersonGroupIds = [];

  @override
  Future<OriginalMoveResult?> syncMedia(
    int mediaId, {
    String? rootDirectory,
    int? explicitMasterId,
  }) async {
    syncedMediaIds.add(mediaId);
    return null;
  }

  @override
  Future<List<OriginalMoveResult>> syncPersonGroup(
    int personId, {
    String? rootDirectory,
  }) async {
    syncedPersonGroupIds.add(personId);
    return [];
  }
}

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late EmbeddingIndex index;
  late FakeOrganizerBridge bridge;
  late PersonMediaOrganizer organizer;
  late SpyAutoOrganizer spyAutoOrganizer;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('auto_hooks_test_');
    files = FileStore(Directory('${tmp.path}/crops'));
    index = InMemoryEmbeddingIndex();
    bridge = FakeOrganizerBridge();
    organizer = PersonMediaOrganizer(db: db, bridge: bridge);
    spyAutoOrganizer = SpyAutoOrganizer(db: db, organizer: organizer);
  });

  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('CorrectionService.apply triggers DynamicAutoOrganizer on reassignment', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final peopleRepo = PeopleRepository(db, files);
    final bodyLinkGuard = BodyLinkGuard(db);
    final service = CorrectionService(
      db: db,
      peopleRepo: peopleRepo,
      bodyLinkGuard: bodyLinkGuard,
      autoOrganizer: spyAutoOrganizer,
    );

    final pA = await db.into(db.persons).insert(
      PersonsCompanion.insert(name: const Value('Person A'), createdAt: now),
    );
    final pB = await db.into(db.persons).insert(
      PersonsCompanion.insert(name: const Value('Person B'), createdAt: now),
    );

    final mediaId = await db.into(db.media).insert(
      MediaCompanion.insert(
        assetId: 'asset_hook_1',
        kind: 'photo',
        scanStatus: const Value('done'),
        scanVersion: const Value(5),
      ),
    );

    final faceId = await db.into(db.faces).insert(
      FacesCompanion.insert(
        mediaId: Value(mediaId),
        personId: Value(pA),
        modelId: 'buffalo_l',
        embedding: Uint8List(512 * 4),
        qualityScore: 0.9,
        qualityVersion: 1,
        detScore: 0.95,
        facePx: 120.0,
        sharpness: 50.0,
        bboxX: 0.1,
        bboxY: 0.1,
        bboxW: 0.3,
        bboxH: 0.3,
        createdAt: now,
      ),
    );

    await service.apply(
      FaceLinkTarget(faceId: faceId, mediaId: mediaId, personId: pA),
      CorrectionVerb.reassign,
      targetPersonId: pB,
    );

    expect(spyAutoOrganizer.syncedMediaIds, contains(mediaId));
  });

  test('PeopleRepository.setPersonGroup and mergePeople trigger DynamicAutoOrganizer', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final peopleRepo = PeopleRepository(
      db,
      files,
      autoOrganizer: spyAutoOrganizer,
    );

    final groupId = await db.into(db.identityGroups).insert(
      IdentityGroupsCompanion.insert(
        name: 'Family',
        nameKey: 'family',
        createdAt: now,
      ),
    );

    final p1 = await db.into(db.persons).insert(
      PersonsCompanion.insert(name: const Value('Luffy'), createdAt: now),
    );
    final p2 = await db.into(db.persons).insert(
      PersonsCompanion.insert(name: const Value('Zoro'), createdAt: now),
    );

    await peopleRepo.setPersonGroup(p1, groupId);
    expect(spyAutoOrganizer.syncedPersonGroupIds, contains(p1));

    await peopleRepo.mergePeople(sourceId: p2, targetId: p1);
    expect(spyAutoOrganizer.syncedPersonGroupIds, contains(p1));
  });

  test('PhotoResultStore.store triggers auto-move if autoOrganizer is provided', () async {
    final store = PhotoResultStore(
      db: db,
      files: files,
      index: index,
      autoOrganizer: spyAutoOrganizer,
    );

    final mediaId = await db.into(db.media).insert(
      MediaCompanion.insert(
        assetId: 'asset_scan_1',
        kind: 'photo',
        scanStatus: const Value('pending'),
      ),
    );
    final media = await (db.select(db.media)..where((m) => m.id.equals(mediaId))).getSingle();

    final analysis = AnalyzeImageResponse(
      imageW: 1000,
      imageH: 1000,
      modelId: 'buffalo_l',
      faces: const [],
      bodies: const [],
      pairs: const [],
    );

    await store.store(media, analysis);
    expect(spyAutoOrganizer.syncedMediaIds, contains(mediaId));
  });
}
