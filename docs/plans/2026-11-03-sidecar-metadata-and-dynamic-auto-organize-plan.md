# Sidecar Metadata Persistence & Dynamic Auto-Organization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 1:1 sidecar metadata (`.json`) persistence for organized media, zero-rescan local database restoration upon re-import, and immediate dynamic auto-organization of media files and sidecars when people, groups, or media assignments change.

**Architecture:** 
- A domain `SidecarMetadata` service handles serialization of all AI detections, embeddings (ArcFace 512-d / CCIP 768-d), keypoints, outlines, and person/group ownership into a companion `<filename>.<ext>.json`.
- A `SidecarIngestionService` integrated into `LibraryRepository.syncAssets` performs zero-network, zero-GPU local ingestion in ~3ms/item, populating SQLite tables and in-memory `EmbeddingIndex`.
- A `DynamicAutoOrganizer` monitors identity and grouping changes (`CorrectionService`, `setPersonGroup`, `mergePeople`, `PhotoResultStore`), scheduling atomic two-file moves (media + sidecar) via MediaStore with crash-resilient journaling and Master Person resolution.

**Tech Stack:** Flutter / Dart, Drift / SQLite (Schema 19), SQLCipher, Android MediaStore Bridge, Riverpod.

---

## Plan Structure Overview

1. **Task 1: Sidecar Metadata Model & Base64 Vector Codecs** (`mobile/lib/domain/organization/sidecar_metadata.dart`)
2. **Task 2: Sidecar File Writer & Native File Bridge** (`mobile/lib/domain/organization/sidecar_storage.dart`)
3. **Task 3: Zero-Rescan Ingestion Pipeline** (`mobile/lib/domain/organization/sidecar_ingestion_service.dart`)
4. **Task 4: Library Sync Integration for Zero-Rescan** (`mobile/lib/data/repositories/library_repository.dart`)
5. **Task 5: Master Person Resolution & Switching** (`mobile/lib/domain/organization/master_person_resolver.dart`)
6. **Task 6: Dynamic Auto-Organization Engine** (`mobile/lib/domain/organization/dynamic_auto_organizer.dart`)
7. **Task 7: Mutations Hooking (Corrections, Group Change, Merge & New Media)**
8. **Task 8: Media Inspector UI & Library Settings Integration**
9. **Task 9: Full End-to-End Acceptance & Verification**

---

### Task 1: Sidecar Metadata Model & Base64 Vector Codecs

**Files:**
- Create: `mobile/lib/domain/organization/sidecar_metadata.dart`
- Test: `mobile/test/domain/organization/sidecar_metadata_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/sidecar_metadata_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';

void main() {
  test('SidecarMetadata round-trip encodes and decodes full metadata tree', () {
    final original = SidecarMetadata(
      version: 1,
      assetId: '10042',
      mediaInfo: const SidecarMediaInfo(
        kind: 'photo',
        width: 3024,
        height: 4032,
        durationMs: 0,
        takenAt: 1698765432000,
        modifiedAt: 1698765440000,
        isSensitive: false,
      ),
      ownership: const SidecarOwnership(
        groupId: 3,
        groupName: 'Family',
        masterPersonId: 12,
        masterPersonName: 'Ahmed',
        masterPersonKind: 'person',
      ),
      faces: [
        SidecarFace(
          faceId: 412,
          personId: 12,
          personName: 'Ahmed',
          bbox: [0.35, 0.20, 0.25, 0.25],
          quality: 0.89,
          yaw: 4.2,
          pitch: -2.1,
          roll: 0.8,
          embeddingModel: 'buffalo_l',
          embedding: Float32List.fromList([0.123, -0.456, 0.789]),
          trackId: null,
        ),
      ],
      bodies: [
        SidecarBody(
          bodyId: 801,
          personId: 12,
          bbox: [0.28, 0.18, 0.40, 0.75],
          keypoints: const [
            [100.0, 150.0, 0.95],
            [110.0, 140.0, 0.92],
          ],
          appearance: Float32List.fromList([0.1, 0.2, 0.3]),
          extent: 'full',
          outline: const [
            [0.28, 0.18],
            [0.68, 0.18],
            [0.68, 0.93],
            [0.28, 0.93],
          ],
        ),
      ],
      sensitiveRegions: const [],
      equipmentObjects: const [],
    );

    final jsonString = jsonEncode(original.toJson());
    final decoded = SidecarMetadata.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );

    expect(decoded.version, 1);
    expect(decoded.assetId, '10042');
    expect(decoded.mediaInfo.width, 3024);
    expect(decoded.ownership.masterPersonName, 'Ahmed');
    expect(decoded.faces.length, 1);
    expect(decoded.faces.first.embedding.length, 3);
    expect(decoded.faces.first.embedding[0], closeTo(0.123, 1e-5));
    expect(decoded.bodies.length, 1);
    expect(decoded.bodies.first.outline.length, 4);
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/sidecar_metadata_test.dart
```
Expected: FAIL with compilation error (Target file does not exist).

**Step 3: Write minimal implementation**

Implement `mobile/lib/domain/organization/sidecar_metadata.dart`:
- `SidecarMediaInfo`: width, height, durationMs, takenAt, modifiedAt, isSensitive.
- `SidecarOwnership`: groupId, groupName, masterPersonId, masterPersonName, masterPersonKind.
- `SidecarFace`: bbox, quality, yaw, pitch, roll, embeddingModel, Float32List embedding (encoded/decoded via base64 byte buffer), personId, personName.
- `SidecarBody`: bbox, keypoints, appearance, extent, outline, personId.
- `SidecarMetadata`: top-level root class with `toJson()` and `fromJson()`.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/sidecar_metadata_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/organization/sidecar_metadata.dart mobile/test/domain/organization/sidecar_metadata_test.dart
git commit -m "feat(sidecar): add SidecarMetadata model with base64 vector codec"
```

---

### Task 2: Sidecar File Writer & Storage Bridge

**Files:**
- Create: `mobile/lib/domain/organization/sidecar_storage.dart`
- Test: `mobile/test/domain/organization/sidecar_storage_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/sidecar_storage_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';

void main() {
  late Directory tempDir;
  late SidecarStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sidecar_storage_test');
    storage = SidecarStorage();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('SidecarStorage writes and reads companion json file', () async {
    final mediaFile = File('${tempDir.path}/Luffy_0001.jpg');
    await mediaFile.writeAsBytes([1, 2, 3]);

    final metadata = SidecarMetadata(
      version: 1,
      assetId: '1001',
      mediaInfo: const SidecarMediaInfo(kind: 'photo', width: 100, height: 100),
      ownership: const SidecarOwnership(masterPersonName: 'Luffy'),
      faces: const [],
      bodies: const [],
      sensitiveRegions: const [],
      equipmentObjects: const [],
    );

    final writtenFile = await storage.writeSidecar(mediaFile.path, metadata);
    expect(await writtenFile.exists(), isTrue);
    expect(writtenFile.path, '${tempDir.path}/Luffy_0001.jpg.json');

    final readMeta = await storage.readSidecar(mediaFile.path);
    expect(readMeta, isNotNull);
    expect(readMeta!.ownership.masterPersonName, 'Luffy');
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/sidecar_storage_test.dart
```
Expected: FAIL (unresolved identifier).

**Step 3: Write minimal implementation**

Implement `mobile/lib/domain/organization/sidecar_storage.dart`:
- `writeSidecar(String mediaPath, SidecarMetadata metadata)`: writes JSON string to `${mediaPath}.json`.
- `readSidecar(String mediaPath)`: reads and decodes `${mediaPath}.json` if it exists, returns null if missing or invalid.
- `moveSidecar(String oldMediaPath, String newMediaPath)`: renames/moves `${oldMediaPath}.json` to `${newMediaPath}.json`.
- `deleteSidecar(String mediaPath)`: deletes companion json if present.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/sidecar_storage_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/organization/sidecar_storage.dart mobile/test/domain/organization/sidecar_storage_test.dart
git commit -m "feat(sidecar): add SidecarStorage file read/write/move operations"
```

---

### Task 3: Zero-Rescan Ingestion Pipeline

**Files:**
- Create: `mobile/lib/domain/organization/sidecar_ingestion_service.dart`
- Test: `mobile/test/domain/organization/sidecar_ingestion_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/sidecar_ingestion_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_ingestion_service.dart';

void main() {
  late AppDatabase db;
  late EmbeddingIndex index;
  late SidecarIngestionService service;

  setUp(() {
    db = AppDatabase.inMemory();
    index = EmbeddingIndex();
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
          keypoints: const [],
          appearance: Float32List.fromList(List.filled(80, 0.1)),
          extent: 'full',
          outline: const [],
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

    // Verify Faces and Bodies
    final faces = await db.select(db.faces).get();
    expect(faces.length, 1);
    expect(faces.first.personId, persons.first.id);

    final bodies = await db.select(db.bodies).get();
    expect(bodies.length, 1);
    expect(bodies.first.personId, persons.first.id);

    // Verify index contains vector
    expect(index.length, 1);
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/sidecar_ingestion_test.dart
```
Expected: FAIL (class not defined).

**Step 3: Write minimal implementation**

Implement `mobile/lib/domain/organization/sidecar_ingestion_service.dart`:
- `ingest(SidecarMetadata meta)` method in SQLite transaction:
  - Resolves or creates `identity_groups` by name.
  - Resolves or creates `persons` by name and group.
  - Inserts `media` row with `scan_status = 'done'`, `scan_version = scanVersion`.
  - Inserts `faces` rows, associates with resolved person IDs.
  - Inserts `bodies` rows, associates with resolved person IDs.
  - Inserts `media_detections` (ref_id, bbox, outline).
  - Inserts `sensitive_regions`.
  - Feeds face embeddings into `index.add(faceId, vector)`.
  - Returns `mediaId`.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/sidecar_ingestion_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/organization/sidecar_ingestion_service.dart mobile/test/domain/organization/sidecar_ingestion_test.dart
git commit -m "feat(sidecar): add SidecarIngestionService for zero-rescan local restoration"
```

---

### Task 4: Library Sync Integration for Zero-Rescan

**Files:**
- Modify: `mobile/lib/data/repositories/library_repository.dart`
- Modify: `mobile/lib/domain/scan/scan_engine.dart`
- Test: `mobile/test/domain/scan/zero_rescan_sync_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/scan/zero_rescan_sync_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_metadata.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_ingestion_service.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';

void main() {
  test('syncAssets automatically ingests sidecars and marks files done', () async {
    final db = AppDatabase.inMemory();
    final index = EmbeddingIndex();
    final ingestion = SidecarIngestionService(db: db, index: index);
    final repo = LibraryRepository(db: db, ingestionService: ingestion);

    final asset = AssetInfo(
      id: 'asset_sidecar_1',
      kind: 'photo',
      path: '/storage/DCIM/Your Gallery/Anime/Luffy/Luffy_0001.jpg',
      modifiedAt: 1700000000,
      width: 1000,
      height: 1000,
    );

    // Mock Sidecar existing on disk for asset_sidecar_1
    // repo.syncAssets should detect sidecar, ingest it, and mark row done directly
    final result = await repo.syncAssets([asset]);
    expect(result.added, 1);

    final row = await repo.mediaByAssetId('asset_sidecar_1');
    expect(row, isNotNull);
    expect(row!.scanStatus, 'done');

    await db.close();
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/scan/zero_rescan_sync_test.dart
```
Expected: FAIL.

**Step 3: Write minimal implementation**

Modify `mobile/lib/data/repositories/library_repository.dart`:
- Inject `SidecarIngestionService` and `SidecarStorage` into `LibraryRepository`.
- In `syncAssets`: check if asset has companion sidecar.
- If sidecar exists and passes validation, call `ingestionService.ingest(meta)` directly and count as completed/restored, skipping pending queue.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/scan/zero_rescan_sync_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/data/repositories/library_repository.dart mobile/lib/domain/scan/scan_engine.dart mobile/test/domain/scan/zero_rescan_sync_test.dart
git commit -m "feat(library): integrate sidecar detection into syncAssets for zero-rescan"
```

---

### Task 5: Master Person Resolution & Switching

**Files:**
- Create: `mobile/lib/domain/organization/master_person_resolver.dart`
- Test: `mobile/test/domain/organization/master_person_resolver_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/master_person_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/organization/master_person_resolver.dart';

void main() {
  test('MasterPersonResolver selects organized person first, then largest face', () {
    final resolver = MasterPersonResolver();
    final p1 = PersonRow(id: 1, name: 'Ahmed', kind: 'person', createdAt: 0);
    final p2 = PersonRow(id: 2, name: 'Sara', kind: 'person', createdAt: 0);

    // Case 1: p1 is already organized into a folder, p2 is not
    final chosen1 = resolver.resolveMaster(
      candidates: [p1, p2],
      organizedPersonIds: {1},
    );
    expect(chosen1.id, 1);

    // Case 2: Neither or both organized -> largest bounding box area wins
    final chosen2 = resolver.resolveMasterByBbox(
      candidates: [p1, p2],
      faceBoxes: {
        1: [0.1, 0.1, 0.2, 0.2], // area = 0.04
        2: [0.4, 0.4, 0.4, 0.4], // area = 0.16
      },
    );
    expect(chosen2.id, 2);
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/master_person_resolver_test.dart
```
Expected: FAIL.

**Step 3: Write minimal implementation**

Implement `mobile/lib/domain/organization/master_person_resolver.dart`:
- `resolveMaster({required List<PersonRow> candidates, required Set<int> organizedPersonIds, int? explicitChoice})`
- Returns primary owner person.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/master_person_resolver_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/organization/master_person_resolver.dart mobile/test/domain/organization/master_person_resolver_test.dart
git commit -m "feat(organizer): add MasterPersonResolver for shared media ownership"
```

---

### Task 6: Dynamic Auto-Organization Engine

**Files:**
- Create: `mobile/lib/domain/organization/dynamic_auto_organizer.dart`
- Modify: `mobile/lib/domain/organization/person_media_organizer.dart`
- Test: `mobile/test/domain/organization/dynamic_auto_organizer_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/dynamic_auto_organizer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/organization/dynamic_auto_organizer.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:antigravity_mobile/domain/organization/sidecar_storage.dart';

void main() {
  test('DynamicAutoOrganizer syncs media and sidecar to target folder', () async {
    final db = AppDatabase.inMemory();
    final organizer = PersonMediaOrganizer(db: db, bridge: FakeMediaOrganizerBridge());
    final sidecars = FakeSidecarStorage();
    final autoOrganizer = DynamicAutoOrganizer(
      db: db,
      organizer: organizer,
      sidecarStorage: sidecars,
    );

    // When a photo is reassigned to person 2
    final moveResult = await autoOrganizer.handleMediaReassigned(
      mediaId: 5,
      newPersonId: 2,
    );

    expect(moveResult.success, isTrue);
    expect(sidecars.lastMovedMediaId, 5);

    await db.close();
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/dynamic_auto_organizer_test.dart
```
Expected: FAIL.

**Step 3: Write minimal implementation**

Implement `mobile/lib/domain/organization/dynamic_auto_organizer.dart`:
- `handleMediaReassigned({required int mediaId, required int? newPersonId})`:
  - Recalculates master person.
  - Moves physical media file via `organizer.applySingle()`.
  - Serializes and writes updated `SidecarMetadata` in target folder.
  - Cleans up old sidecar if path changed.
- `handlePersonGroupChanged({required int personId, required int? newGroupId})`:
  - Computes new folder path for person.
  - Schedules batch move of person's files and sidecars to new group path.
- `handleNewMediaAssigned({required int mediaId, required int personId})`:
  - If person is in organized set, automatically triggers move to their folder.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/dynamic_auto_organizer_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/organization/dynamic_auto_organizer.dart mobile/lib/domain/organization/person_media_organizer.dart mobile/test/domain/organization/dynamic_auto_organizer_test.dart
git commit -m "feat(organizer): implement DynamicAutoOrganizer for background sync"
```

---

### Task 7: Mutations Hooking (Corrections, Groups, Merges & Detections)

**Files:**
- Modify: `mobile/lib/domain/corrections/correction_service.dart`
- Modify: `mobile/lib/data/repositories/people_repository.dart`
- Modify: `mobile/lib/domain/scan/photo_result_store.dart`
- Test: `mobile/test/domain/organization/auto_organize_hooks_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/domain/organization/auto_organize_hooks_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CorrectionService.apply triggers DynamicAutoOrganizer on reassignment', () async {
    // Verifies that reassigning a face from person A to person B dispatches auto-organizer
  });

  test('PeopleRepository.setPersonGroup triggers DynamicAutoOrganizer folder move', () async {
    // Verifies moving person to another group moves files
  });

  test('PhotoResultStore.store triggers auto-move if person has organized folder', () async {
    // Verifies new scan for organized person moves media automatically
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/domain/organization/auto_organize_hooks_test.dart
```
Expected: FAIL.

**Step 3: Write minimal implementation**

- Wire `dynamicAutoOrganizerProvider` into `CorrectionService.apply()`.
- Wire into `PeopleRepository.setPersonGroup()` and `mergePeople()`.
- Wire into `PhotoResultStore.store()` for newly scanned media belonging to an organized person.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/domain/organization/auto_organize_hooks_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/domain/corrections/correction_service.dart mobile/lib/data/repositories/people_repository.dart mobile/lib/domain/scan/photo_result_store.dart mobile/test/domain/organization/auto_organize_hooks_test.dart
git commit -m "feat(organizer): wire dynamic auto-organization into corrections, groups, and store"
```

---

### Task 8: Media Inspector UI & Library Settings Integration

**Files:**
- Modify: `mobile/lib/features/inspector/media_inspector.dart`
- Modify: `mobile/lib/features/settings/library_settings_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Test: `mobile/test/features/inspector/media_inspector_master_test.dart`
- Test: `mobile/test/features/settings/auto_organize_settings_test.dart`

**Step 1: Write the failing test**

```dart
// mobile/test/features/inspector/media_inspector_master_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MediaInspector displays Master Star badge on file owner and allows switching', (tester) async {
    // Pump media inspector with 2 detected people
    // Verify master badge on person 1
    // Tap person 2 menu -> 'Set as primary file owner'
    // Verify person 2 is now master
  });
}
```

**Step 2: Run test to verify it fails**

Run:
```powershell
flutter test test/features/inspector/media_inspector_master_test.dart
```
Expected: FAIL.

**Step 3: Write minimal implementation**

- `media_inspector.dart`:
  - Show `"Master ⭐"` pill next to master person.
  - In other detected person cards, add overflow item: `"Set as primary file owner"`.
  - Tapping invokes `dynamicAutoOrganizer.setMasterPerson(mediaId, personId)`.
- `library_settings_screen.dart`:
  - Add switch for `"Auto-sync organized folders"` (`settings.auto_organize_enabled`).
  - Add switch for `"Save sidecar metadata (.json)"` (`settings.save_sidecar_enabled`).
- Regenerate localization via `flutter gen-l10n`.

**Step 4: Run test to verify it passes**

Run:
```powershell
flutter test test/features/inspector/media_inspector_master_test.dart
flutter test test/features/settings/auto_organize_settings_test.dart
```
Expected: PASS.

**Step 5: Commit**

```powershell
git add mobile/lib/features/inspector/media_inspector.dart mobile/lib/features/settings/library_settings_screen.dart mobile/lib/l10n/
git commit -m "feat(ui): add master person switcher in inspector and auto-sync toggles in settings"
```

---

### Task 9: Full End-to-End Acceptance & Verification

**Files:**
- Test: `mobile/test/features/sidecar_auto_organize_e2e_test.dart`

**Step 1: Write and run end-to-end integration test**

Verify complete user journey:
1. Organize a person's photos into `DCIM/Your Gallery/Family/Ahmed/`.
2. Confirm companion `.json` sidecars are written with complete embedding and detection payloads.
3. Simulate app uninstall / database wipe (instantiate empty in-memory DB).
4. Run `syncAssets` on the organized folder: verify all persons, groups, faces, bodies, and embeddings are 100% restored with zero PC/GPU requests.
5. Reassign a face from Ahmed to Sara: verify media and `.json` sidecar move to `DCIM/Your Gallery/Friends/Sara/`.
6. Switch Master Person on a shared photo: verify file moves to new master.

Run:
```powershell
flutter test test/features/sidecar_auto_organize_e2e_test.dart
```
Expected: PASS.

**Step 2: Static Analysis and Regression Suite**

Run:
```powershell
cd mobile
flutter analyze --no-pub
flutter test test/domain/ test/data/ test/features/
```
Expected: 0 issues, all passing.

**Step 3: Update ANTIGRAVITY_HANDOFF.md and Commit**

Record completed implementation, verification results, and APK delivery status.
Commit with:
```powershell
git commit -m "feat(organizer): complete sidecar metadata persistence and dynamic auto-organize"
```
