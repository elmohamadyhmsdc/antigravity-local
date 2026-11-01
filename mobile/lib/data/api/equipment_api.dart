import 'dart:typed_data';

import 'dtos/analyze.dart';
import 'dtos/json_util.dart';

abstract interface class EquipmentApi {
  Future<EquipmentResponse> analyzeEquipment(
    Uint8List image,
    List<SensitiveBodyTargetDto> bodies,
  );
}

class EquipmentObject {
  const EquipmentObject({
    required this.key,
    required this.label,
    required this.box,
    this.bodyIndex,
  });
  final String key, label;
  final BBox box;
  final int? bodyIndex;
  factory EquipmentObject.fromJson(Map<String, dynamic> json) =>
      EquipmentObject(
        key: field<String>(json, 'object_key'),
        label: field<String>(json, 'label'),
        box: BBox.fromJson(map(json['bbox'], 'bbox')),
        bodyIndex: json['body_index'] as int?,
      );
}

class EquipmentResponse {
  const EquipmentResponse({required this.version, required this.objects});
  final int version;
  final List<EquipmentObject> objects;
  factory EquipmentResponse.fromJson(Map<String, dynamic> json) =>
      EquipmentResponse(
        version: integer(json, 'model_version'),
        objects: [
          for (final o in list(json['objects'], 'objects'))
            EquipmentObject.fromJson(map(o, 'objects[]')),
        ],
      );
}
