import 'dart:convert';
import 'dart:typed_data';

/// Encodes a [Float32List] to a portable base64 string.
String encodeVectorBase64(Float32List vector) {
  final bytes = vector.buffer.asUint8List(
    vector.offsetInBytes,
    vector.lengthInBytes,
  );
  return base64Encode(bytes);
}

/// Decodes a base64 string back into a [Float32List].
Float32List decodeVectorBase64(String base64String) {
  final bytes = base64Decode(base64String);
  final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
  final count = byteData.lengthInBytes ~/ 4;
  final floats = Float32List(count);
  for (var i = 0; i < count; i++) {
    floats[i] = byteData.getFloat32(i * 4, Endian.host);
  }
  return floats;
}

class SidecarMediaInfo {
  const SidecarMediaInfo({
    required this.kind,
    required this.width,
    required this.height,
    this.durationMs = 0,
    this.takenAt,
    this.modifiedAt,
    this.isSensitive = false,
  });

  final String kind;
  final int width;
  final int height;
  final int durationMs;
  final int? takenAt;
  final int? modifiedAt;
  final bool isSensitive;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'width': width,
    'height': height,
    'duration_ms': durationMs,
    if (takenAt != null) 'taken_at': takenAt,
    if (modifiedAt != null) 'modified_at': modifiedAt,
    'is_sensitive': isSensitive,
  };

  factory SidecarMediaInfo.fromJson(Map<String, dynamic> json) =>
      SidecarMediaInfo(
        kind: json['kind'] as String? ?? 'photo',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
        takenAt: (json['taken_at'] as num?)?.toInt(),
        modifiedAt: (json['modified_at'] as num?)?.toInt(),
        isSensitive: json['is_sensitive'] as bool? ?? false,
      );
}

class SidecarOwnership {
  const SidecarOwnership({
    this.groupId,
    this.groupName,
    this.masterPersonId,
    this.masterPersonName,
    this.masterPersonKind = 'person',
  });

  final int? groupId;
  final String? groupName;
  final int? masterPersonId;
  final String? masterPersonName;
  final String masterPersonKind;

  Map<String, dynamic> toJson() => {
    if (groupId != null) 'group_id': groupId,
    if (groupName != null) 'group_name': groupName,
    if (masterPersonId != null) 'master_person_id': masterPersonId,
    if (masterPersonName != null) 'master_person_name': masterPersonName,
    'master_person_kind': masterPersonKind,
  };

  factory SidecarOwnership.fromJson(Map<String, dynamic> json) =>
      SidecarOwnership(
        groupId: (json['group_id'] as num?)?.toInt(),
        groupName: json['group_name'] as String?,
        masterPersonId: (json['master_person_id'] as num?)?.toInt(),
        masterPersonName: json['master_person_name'] as String?,
        masterPersonKind: json['master_person_kind'] as String? ?? 'person',
      );
}

class SidecarFace {
  const SidecarFace({
    this.faceId,
    this.personId,
    this.personName,
    required this.bbox,
    this.quality = 1.0,
    this.yaw = 0.0,
    this.pitch = 0.0,
    this.roll = 0.0,
    this.embeddingModel = 'buffalo_l',
    required this.embedding,
    this.trackId,
  });

  final int? faceId;
  final int? personId;
  final String? personName;
  final List<double> bbox; // [x, y, w, h] normalized
  final double quality;
  final double yaw;
  final double pitch;
  final double roll;
  final String embeddingModel;
  final Float32List embedding;
  final int? trackId;

  Map<String, dynamic> toJson() => {
    if (faceId != null) 'face_id': faceId,
    if (personId != null) 'person_id': personId,
    if (personName != null) 'person_name': personName,
    'bbox': bbox,
    'quality': quality,
    'yaw': yaw,
    'pitch': pitch,
    'roll': roll,
    'embedding_model': embeddingModel,
    'embedding': encodeVectorBase64(embedding),
    if (trackId != null) 'track_id': trackId,
  };

  factory SidecarFace.fromJson(Map<String, dynamic> json) => SidecarFace(
    faceId: (json['face_id'] as num?)?.toInt(),
    personId: (json['person_id'] as num?)?.toInt(),
    personName: json['person_name'] as String?,
    bbox: [for (final n in (json['bbox'] as List? ?? [])) (n as num).toDouble()],
    quality: (json['quality'] as num?)?.toDouble() ?? 1.0,
    yaw: (json['yaw'] as num?)?.toDouble() ?? 0.0,
    pitch: (json['pitch'] as num?)?.toDouble() ?? 0.0,
    roll: (json['roll'] as num?)?.toDouble() ?? 0.0,
    embeddingModel: json['embedding_model'] as String? ?? 'buffalo_l',
    embedding: decodeVectorBase64(json['embedding'] as String? ?? ''),
    trackId: (json['track_id'] as num?)?.toInt(),
  );
}

class SidecarBody {
  const SidecarBody({
    this.bodyId,
    this.personId,
    this.personName,
    required this.bbox,
    this.keypoints = const [],
    this.appearance,
    this.extent = 'full',
    this.outline = const [],
  });

  final int? bodyId;
  final int? personId;
  final String? personName;
  final List<double> bbox; // [x, y, w, h] normalized
  final List<List<double>> keypoints;
  final Float32List? appearance;
  final String extent;
  final List<List<double>> outline;

  Map<String, dynamic> toJson() => {
    if (bodyId != null) 'body_id': bodyId,
    if (personId != null) 'person_id': personId,
    if (personName != null) 'person_name': personName,
    'bbox': bbox,
    'keypoints': keypoints,
    if (appearance != null) 'appearance': encodeVectorBase64(appearance!),
    'extent': extent,
    'outline': outline,
  };

  factory SidecarBody.fromJson(Map<String, dynamic> json) => SidecarBody(
    bodyId: (json['body_id'] as num?)?.toInt(),
    personId: (json['person_id'] as num?)?.toInt(),
    personName: json['person_name'] as String?,
    bbox: [for (final n in (json['bbox'] as List? ?? [])) (n as num).toDouble()],
    keypoints: [
      for (final pt in (json['keypoints'] as List? ?? []))
        [for (final v in (pt as List)) (v as num).toDouble()],
    ],
    appearance: json['appearance'] != null
        ? decodeVectorBase64(json['appearance'] as String)
        : null,
    extent: json['extent'] as String? ?? 'full',
    outline: [
      for (final pt in (json['outline'] as List? ?? []))
        [for (final v in (pt as List)) (v as num).toDouble()],
    ],
  );
}

class SidecarSensitiveRegion {
  const SidecarSensitiveRegion({
    required this.label,
    required this.bbox,
    this.outline = const [],
    this.exposed = false,
  });

  final String label;
  final List<double> bbox;
  final List<List<double>> outline;
  final bool exposed;

  Map<String, dynamic> toJson() => {
    'label': label,
    'bbox': bbox,
    'outline': outline,
    'exposed': exposed,
  };

  factory SidecarSensitiveRegion.fromJson(Map<String, dynamic> json) =>
      SidecarSensitiveRegion(
        label: json['label'] as String? ?? '',
        bbox: [
          for (final n in (json['bbox'] as List? ?? [])) (n as num).toDouble(),
        ],
        outline: [
          for (final pt in (json['outline'] as List? ?? []))
            [for (final v in (pt as List)) (v as num).toDouble()],
        ],
        exposed: json['exposed'] as bool? ?? false,
      );
}

class SidecarEquipmentObject {
  const SidecarEquipmentObject({
    required this.label,
    required this.bbox,
  });

  final String label;
  final List<double> bbox;

  Map<String, dynamic> toJson() => {
    'label': label,
    'bbox': bbox,
  };

  factory SidecarEquipmentObject.fromJson(Map<String, dynamic> json) =>
      SidecarEquipmentObject(
        label: json['label'] as String? ?? '',
        bbox: [
          for (final n in (json['bbox'] as List? ?? [])) (n as num).toDouble(),
        ],
      );
}

class SidecarMetadata {
  const SidecarMetadata({
    this.version = 1,
    required this.assetId,
    required this.mediaInfo,
    required this.ownership,
    this.faces = const [],
    this.bodies = const [],
    this.sensitiveRegions = const [],
    this.equipmentObjects = const [],
  });

  final int version;
  final String assetId;
  final SidecarMediaInfo mediaInfo;
  final SidecarOwnership ownership;
  final List<SidecarFace> faces;
  final List<SidecarBody> bodies;
  final List<SidecarSensitiveRegion> sensitiveRegions;
  final List<SidecarEquipmentObject> equipmentObjects;

  Map<String, dynamic> toJson() => {
    'version': version,
    'asset_id': assetId,
    'media_info': mediaInfo.toJson(),
    'ownership': ownership.toJson(),
    'faces': [for (final f in faces) f.toJson()],
    'bodies': [for (final b in bodies) b.toJson()],
    'sensitive_regions': [for (final s in sensitiveRegions) s.toJson()],
    'equipment_objects': [for (final e in equipmentObjects) e.toJson()],
  };

  factory SidecarMetadata.fromJson(Map<String, dynamic> json) =>
      SidecarMetadata(
        version: (json['version'] as num?)?.toInt() ?? 1,
        assetId: json['asset_id'] as String? ?? '',
        mediaInfo: SidecarMediaInfo.fromJson(
          (json['media_info'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        ownership: SidecarOwnership.fromJson(
          (json['ownership'] as Map?)?.cast<String, dynamic>() ?? {},
        ),
        faces: [
          for (final f in (json['faces'] as List? ?? []))
            SidecarFace.fromJson((f as Map).cast<String, dynamic>()),
        ],
        bodies: [
          for (final b in (json['bodies'] as List? ?? []))
            SidecarBody.fromJson((b as Map).cast<String, dynamic>()),
        ],
        sensitiveRegions: [
          for (final s in (json['sensitive_regions'] as List? ?? []))
            SidecarSensitiveRegion.fromJson((s as Map).cast<String, dynamic>()),
        ],
        equipmentObjects: [
          for (final e in (json['equipment_objects'] as List? ?? []))
            SidecarEquipmentObject.fromJson((e as Map).cast<String, dynamic>()),
        ],
      );
}
