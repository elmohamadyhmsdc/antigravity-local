import 'package:flutter/foundation.dart';

/// Target reference representing an entity or media/detection selection
/// used across Studio, Reface, Viewer and other flows.
@immutable
class TargetRef {
  const TargetRef({
    this.mediaId,
    this.detectionId,
    this.personId,
    this.identitySetId,
    this.faceId,
  });

  final int? mediaId;
  final int? detectionId;
  final int? personId;
  final int? identitySetId;
  final int? faceId;

  bool get isEmpty =>
      mediaId == null &&
      detectionId == null &&
      personId == null &&
      identitySetId == null &&
      faceId == null;

  bool get isNotEmpty => !isEmpty;

  /// Parses a target string in the format `media:123,det:456`, `media:123`, or `det:456`.
  static (int? mediaId, int? detId) parseTargetString(String? targetStr) {
    if (targetStr == null || targetStr.trim().isEmpty) {
      return (null, null);
    }
    int? mId;
    int? dId;

    // Check if it's purely numeric (legacy target parameter = detectionId)
    final numeric = int.tryParse(targetStr);
    if (numeric != null) {
      return (null, numeric);
    }

    final parts = targetStr.split(',');
    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length == 2) {
        final key = kv[0].trim().toLowerCase();
        final val = int.tryParse(kv[1].trim());
        if (key == 'media') {
          mId = val;
        } else if (key == 'det' || key == 'detection') {
          dId = val;
        }
      }
    }
    return (mId, dId);
  }

  /// Parses [TargetRef] from query parameters with full backward compatibility
  /// for both legacy parameters (`media`, `target`, `face`, `person`, `identity`)
  /// and the unified `target=media:ID,det:ID` format.
  factory TargetRef.fromQueryParams(Map<String, String> params) {
    int? mediaId;
    int? detectionId;

    final targetRaw = params['target'];
    final (parsedMedia, parsedDet) = parseTargetString(targetRaw);
    mediaId = parsedMedia;
    detectionId = parsedDet;

    // Legacy fallbacks if not resolved via target string:
    if (mediaId == null && params.containsKey('media')) {
      mediaId = int.tryParse(params['media'] ?? '');
    }
    final personId = int.tryParse(params['person'] ?? params['personId'] ?? '');
    final identitySetId = int.tryParse(
      params['identity'] ?? params['identitySetId'] ?? '',
    );
    final faceId = int.tryParse(params['face'] ?? params['faceId'] ?? '');

    return TargetRef(
      mediaId: mediaId,
      detectionId: detectionId,
      personId: personId,
      identitySetId: identitySetId,
      faceId: faceId,
    );
  }

  factory TargetRef.fromUri(Uri uri) =>
      TargetRef.fromQueryParams(uri.queryParameters);

  /// Serializes media and detection target to `media:ID[,det:ID]`.
  String? toTargetParam() {
    if (mediaId == null && detectionId == null) return null;
    final parts = <String>[];
    if (mediaId != null) parts.add('media:$mediaId');
    if (detectionId != null) parts.add('det:$detectionId');
    return parts.join(',');
  }

  /// Exports to a query parameter map using the v2 specification format.
  Map<String, String> toQueryParams() {
    final map = <String, String>{};
    final targetStr = toTargetParam();
    if (targetStr != null) {
      map['target'] = targetStr;
    }
    if (personId != null) {
      map['person'] = personId.toString();
    }
    if (identitySetId != null) {
      map['identity'] = identitySetId.toString();
    }
    if (faceId != null) {
      map['face'] = faceId.toString();
    }
    return map;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TargetRef &&
          runtimeType == other.runtimeType &&
          mediaId == other.mediaId &&
          detectionId == other.detectionId &&
          personId == other.personId &&
          identitySetId == other.identitySetId &&
          faceId == other.faceId;

  @override
  int get hashCode =>
      Object.hash(mediaId, detectionId, personId, identitySetId, faceId);

  @override
  String toString() =>
      'TargetRef(mediaId: $mediaId, detectionId: $detectionId, personId: $personId, identitySetId: $identitySetId, faceId: $faceId)';
}
