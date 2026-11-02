import 'dart:ui';
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
  });

  final BBox bbox;
  final double score;
  final String label;
  final List<Offset>? outline;
  final List<List<double>>? keypoints;

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

    return TargetedDetectionItem(
      bbox: BBox.fromJson(map(json['bbox'], 'bbox')),
      score: number(json, 'score', 'score'),
      label: field<String>(json, 'label'),
      outline: parsedOutline,
      keypoints: parsedKpts,
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
