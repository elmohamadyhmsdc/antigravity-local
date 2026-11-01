import 'dart:convert';

/// Local provenance, deliberately kept out of the PC request contract.
class ArtifactContext {
  const ArtifactContext({
    this.mediaId,
    this.assetId,
    this.detectionId,
    this.personId,
    this.targetPersonId,
    this.modelId,
    this.datasetId,
    this.referenceMediaId,
  });

  final int? mediaId;
  final String? assetId;
  final int? detectionId;
  final int? personId;
  final int? targetPersonId;
  final String? modelId;
  final String? datasetId;
  final int? referenceMediaId;

  Map<String, dynamic> toJson() => {
    if (mediaId != null) 'mediaId': mediaId,
    if (assetId != null) 'assetId': assetId,
    if (detectionId != null) 'detectionId': detectionId,
    if (personId != null) 'personId': personId,
    if (targetPersonId != null) 'targetPersonId': targetPersonId,
    if (modelId != null) 'modelId': modelId,
    if (datasetId != null) 'datasetId': datasetId,
    if (referenceMediaId != null) 'referenceMediaId': referenceMediaId,
  };

  static ArtifactContext? decode(String? value) {
    if (value == null) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      return ArtifactContext(
        mediaId: json['mediaId'] is int ? json['mediaId'] as int : null,
        assetId: json['assetId'] is String ? json['assetId'] as String : null,
        detectionId: json['detectionId'] is int
            ? json['detectionId'] as int
            : null,
        personId: json['personId'] is int ? json['personId'] as int : null,
        targetPersonId: json['targetPersonId'] is int
            ? json['targetPersonId'] as int
            : null,
        modelId: json['modelId'] is String ? json['modelId'] as String : null,
        datasetId: json['datasetId'] is String
            ? json['datasetId'] as String
            : null,
        referenceMediaId: json['referenceMediaId'] is int
            ? json['referenceMediaId'] as int
            : null,
      );
    } on FormatException {
      return null;
    }
  }

  ArtifactContext mergePerson(int sourceId, int targetId) => ArtifactContext(
    mediaId: mediaId,
    assetId: assetId,
    detectionId: detectionId,
    personId: personId == sourceId ? targetId : personId,
    targetPersonId: targetPersonId == sourceId ? targetId : targetPersonId,
    modelId: modelId,
    datasetId: datasetId,
    referenceMediaId: referenceMediaId,
  );
}

const artifactContextPrefix = 'artifact.context.';
