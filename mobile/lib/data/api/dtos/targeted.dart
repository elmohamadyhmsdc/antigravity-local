import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'embedding.dart';
import 'analyze.dart';
import 'json_util.dart';

/// One detection returned from POST /v1/analyze/targeted.
class TargetedDetectionItem {
  const TargetedDetectionItem({
    required this.bbox,
    required this.score,
    required this.label,
    this.outline,
    this.keypoints,
    this.embedding,
    this.embeddingModelId,
    this.cropJpeg,
    this.facePx,
    this.manual = false,
  });

  final BBox bbox;
  final double score;
  final String label;
  final List<Offset>? outline;
  final List<List<double>>? keypoints;
  final Float32List? embedding;
  final String? embeddingModelId;
  final Uint8List? cropJpeg;
  final double? facePx;
  final bool manual;

  factory TargetedDetectionItem.fromJson(Map<String, dynamic> json) {
    List<Offset>? parsedOutline;
    if (json['outline'] is List) {
      parsedOutline = [
        for (final pt in json['outline'] as List)
          if (pt is List && pt.length >= 2)
            Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble()),
      ];
    }

    List<List<double>>? parsedKpts;
    if (json['keypoints'] is List) {
      parsedKpts = [
        for (final pt in json['keypoints'] as List)
          if (pt is List) [for (final v in pt) (v as num).toDouble()],
      ];
    }

    final modelId = json['embedding_model_id'] as String?;
    final encoded = json['embedding'];
    if (encoded != null && modelId != characterEmbeddingModelId) {
      throw const FormatException('Unsupported targeted character model');
    }
    return TargetedDetectionItem(
      bbox: BBox.fromJson(map(json['bbox'], 'bbox')),
      score: number(json, 'score', 'score'),
      label: field<String>(json, 'label'),
      outline: parsedOutline,
      keypoints: parsedKpts,
      embeddingModelId: modelId,
      embedding: encoded is String
          ? decodeVector(encoded, characterEmbeddingDim)
          : null,
      cropJpeg: json['crop_jpeg'] is String
          ? base64Decode(json['crop_jpeg'] as String)
          : null,
      facePx: (json['face_px'] as num?)?.toDouble(),
      manual: json['manual'] == true,
    );
  }
}

/// Response from POST /v1/analyze/targeted.
class TargetedAnalysisResponse {
  const TargetedAnalysisResponse({
    required this.targetKind,
    required this.detections,
  });

  final String targetKind;
  final List<TargetedDetectionItem> detections;

  factory TargetedAnalysisResponse.fromJson(Map<String, dynamic> json) =>
      TargetedAnalysisResponse(
        targetKind: field<String>(json, 'target_kind'),
        detections: [
          for (final d in list(json['detections'] ?? [], 'detections'))
            TargetedDetectionItem.fromJson(map(d, 'detections[]')),
        ],
      );
}
