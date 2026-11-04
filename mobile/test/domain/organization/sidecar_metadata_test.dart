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
          bbox: const [0.35, 0.20, 0.25, 0.25],
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
          bbox: const [0.28, 0.18, 0.40, 0.75],
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
      sensitiveRegions: const [
        SidecarSensitiveRegion(
          label: 'exposed_breast',
          bbox: [0.3, 0.4, 0.2, 0.2],
          exposed: true,
        ),
      ],
      equipmentObjects: const [
        SidecarEquipmentObject(label: 'backpack', bbox: [0.1, 0.2, 0.3, 0.4]),
      ],
    );

    final jsonMap = original.toJson();
    final jsonString = jsonEncode(jsonMap);
    final decoded = SidecarMetadata.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );

    expect(decoded.version, 1);
    expect(decoded.assetId, '10042');
    expect(decoded.mediaInfo.width, 3024);
    expect(decoded.mediaInfo.height, 4032);
    expect(decoded.mediaInfo.isSensitive, isFalse);
    expect(decoded.ownership.masterPersonName, 'Ahmed');
    expect(decoded.ownership.groupName, 'Family');
    expect(decoded.faces.length, 1);
    expect(decoded.faces.first.embedding.length, 3);
    expect(decoded.faces.first.embedding[0], closeTo(0.123, 1e-5));
    expect(decoded.faces.first.embedding[1], closeTo(-0.456, 1e-5));
    expect(decoded.faces.first.embedding[2], closeTo(0.789, 1e-5));
    expect(decoded.bodies.length, 1);
    expect(decoded.bodies.first.outline.length, 4);
    expect(decoded.bodies.first.appearance?.length, 3);
    expect(decoded.sensitiveRegions.length, 1);
    expect(decoded.sensitiveRegions.first.label, 'exposed_breast');
    expect(decoded.equipmentObjects.length, 1);
    expect(decoded.equipmentObjects.first.label, 'backpack');
  });
}
