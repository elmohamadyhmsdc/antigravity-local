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

  test('SidecarStorage writes, reads, moves and deletes companion json file', () async {
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

    // 1. Write sidecar
    final writtenFile = await storage.writeSidecar(mediaFile.path, metadata);
    expect(await writtenFile.exists(), isTrue);
    expect(writtenFile.path, '${tempDir.path}/Luffy_0001.jpg.json');

    // 2. Read sidecar
    final readMeta = await storage.readSidecar(mediaFile.path);
    expect(readMeta, isNotNull);
    expect(readMeta!.ownership.masterPersonName, 'Luffy');
    expect(readMeta.assetId, '1001');

    // 3. Move sidecar
    final newMediaFile = File('${tempDir.path}/Luffy_new.jpg');
    await storage.moveSidecar(mediaFile.path, newMediaFile.path);
    expect(await writtenFile.exists(), isFalse);
    expect(await File('${tempDir.path}/Luffy_new.jpg.json').exists(), isTrue);

    // 4. Delete sidecar
    await storage.deleteSidecar(newMediaFile.path);
    expect(await File('${tempDir.path}/Luffy_new.jpg.json').exists(), isFalse);
  });
}
