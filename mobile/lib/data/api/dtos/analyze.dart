import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import '../../../domain/scan/character_descriptor.dart';

import 'embedding.dart';
import 'json_util.dart';

/// Box in pixels of the uploaded image: top-left origin (openapi.yaml `BBox`).
class BBox {
  const BBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  factory BBox.fromJson(Map<String, dynamic> json, [String path = 'bbox']) =>
      BBox(
        x: number(json, 'x', path),
        y: number(json, 'y', path),
        w: number(json, 'w', path),
        h: number(json, 'h', path),
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// The phone stores boxes normalised to 0..1 of the analysed image.
  BBox normalized(int imageW, int imageH) =>
      BBox(x: x / imageW, y: y / imageH, w: w / imageW, h: h / imageH);

  @override
  bool operator ==(Object other) =>
      other is BBox &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

class Pose {
  const Pose({required this.yaw, required this.pitch, this.roll});

  final double yaw;
  final double pitch;
  final double? roll;

  factory Pose.fromJson(Map<String, dynamic> json) => Pose(
    yaw: number(json, 'yaw', 'pose'),
    pitch: number(json, 'pitch', 'pose'),
    roll: optionalNumber(json, 'roll'),
  );
}

/// face_quality v2 output - how far the identity embedding can be trusted.
class FaceQuality {
  const FaceQuality({
    required this.score,
    required this.version,
    required this.parts,
    required this.detScore,
    required this.facePx,
    required this.sharpness,
    required this.embeddingNorm,
    required this.pose,
  });

  final double score;
  final int version;
  final Map<String, double> parts; // norm, size, sharp, pose
  final double detScore;
  final double facePx;
  final double sharpness;
  final double? embeddingNorm;
  final Pose? pose;

  factory FaceQuality.fromJson(Map<String, dynamic> json) {
    final parts = map(json['quality_parts'], 'quality.quality_parts');
    return FaceQuality(
      score: number(json, 'quality_score', 'quality'),
      version: integer(json, 'quality_version', 'quality'),
      parts: {
        for (final e in parts.entries) e.key: (e.value as num).toDouble(),
      },
      detScore: number(json, 'det_score', 'quality'),
      facePx: number(json, 'face_px', 'quality'),
      sharpness: number(json, 'sharpness', 'quality'),
      embeddingNorm: optionalNumber(json, 'embedding_norm'),
      pose: json['pose'] == null
          ? null
          : Pose.fromJson(map(json['pose'], 'quality.pose')),
    );
  }
}

List<Offset>? _parseOutline(dynamic raw) {
  if (raw is! List || raw.length < 3 || raw.length > 64) {
    return null;
  }
  final points = <Offset>[];
  for (final item in raw) {
    if (item is! List || item.length != 2) {
      return null;
    }
    final x = item[0];
    final y = item[1];
    if (x is! num || y is! num) {
      return null;
    }
    final dx = x.toDouble();
    final dy = y.toDouble();
    if (!dx.isFinite || !dy.isFinite) {
      return null;
    }
    points.add(Offset(dx, dy));
  }
  return points;
}

class DetectedFace {
  const DetectedFace({
    required this.bbox,
    required this.kps,
    required this.detScore,
    required this.embedding,
    required this.quality,
    required this.passesGate,
    this.cropJpeg,
    this.outline,
    this.forced = false,
  });

  final BBox bbox;
  final List<List<double>> kps; // 5 x [x, y]
  final double detScore;
  final Float32List embedding; // 512, unit length
  final FaceQuality quality;
  final bool passesGate; // the phone stores only faces that pass
  final Uint8List? cropJpeg;
  final List<Offset>? outline;

  /// The user said this is a person: never dropped as a drawing.
  final bool forced;

  factory DetectedFace.fromJson(
    Map<String, dynamic> json, [
    String path = 'faces[]',
  ]) {
    final kps = list(
      json['kps'],
      '$path.kps',
    ).map((p) => numbers(p, '$path.kps[]')).toList();
    if (kps.length != 5 || kps.any((p) => p.length != 2)) {
      throw FormatException('$path.kps: expected 5 [x, y] landmarks');
    }
    final crop = json['crop_jpeg'];
    return DetectedFace(
      bbox: BBox.fromJson(map(json['bbox'], '$path.bbox'), '$path.bbox'),
      kps: kps,
      detScore: number(json, 'det_score', path),
      embedding: decodeEmbedding(field<String>(json, 'embedding', path)),
      quality: FaceQuality.fromJson(map(json['quality'], '$path.quality')),
      passesGate: field<bool>(json, 'passes_gate', path),
      cropJpeg: crop is String ? base64Decode(crop) : null,
      outline: _parseOutline(json['outline']),
      forced: json['forced'] == true,
    );
  }
}

class DetectedBody {
  const DetectedBody({
    required this.bbox,
    required this.score,
    this.kpts,
    this.appearance,
    this.extent,
    this.cropJpeg,
    this.outline,
    this.chestEmbedding,
    this.buttocksEmbedding,
    this.morphology,
  });

  /// Roadmap 7.5 (only with `AnalyzeOptions.returnBodyEmbeddings`): DINOv2 384-d unit vectors of the exposed
  /// chest / lower-body patch and the measurable descriptors; null when the body has none.
  final Float32List? chestEmbedding;
  final Float32List? buttocksEmbedding;
  final Map<String, dynamic>? morphology;

  final BBox bbox;
  final double score;
  final List<List<double>>? kpts; // 17 x [x, y, score]
  final List<double>? appearance; // 80-float outfit descriptor
  final String? extent; // full | knee | upper | head
  final Uint8List? cropJpeg;
  final List<Offset>? outline;

  factory DetectedBody.fromJson(
    Map<String, dynamic> json, [
    String path = 'bodies[]',
  ]) {
    final kpts = json['kpts'];
    final appearance = json['appearance'];
    final crop = json['crop_jpeg'];
    return DetectedBody(
      bbox: BBox.fromJson(map(json['bbox'], '$path.bbox'), '$path.bbox'),
      score: number(json, 'score', path),
      kpts: kpts == null
          ? null
          : list(
              kpts,
              '$path.kpts',
            ).map((p) => numbers(p, '$path.kpts[]')).toList(),
      appearance: appearance == null
          ? null
          : numbers(appearance, '$path.appearance'),
      extent: json['extent'] as String?,
      cropJpeg: crop is String ? base64Decode(crop) : null,
      outline: _parseOutline(json['outline']),
      chestEmbedding: _patchEmbedding(json['chest_embedding']),
      buttocksEmbedding: _patchEmbedding(json['buttocks_embedding']),
      morphology: json['morphology'] is Map<String, dynamic>
          ? json['morphology'] as Map<String, dynamic>
          : null,
    );
  }
}

const patchEmbeddingDim = 384;

Float32List? _patchEmbedding(Object? value) =>
    value is String ? decodeVector(value, patchEmbeddingDim) : null;

/// The drawn face of a character. `embedding` is null when the server has no CCIP model.
class CharacterFace {
  const CharacterFace({
    required this.bbox,
    required this.score,
    this.embedding,
    this.cropJpeg,
  });

  final BBox bbox;
  final double score;
  final Float32List? embedding; // characterEmbeddingDim, unit length
  final Uint8List? cropJpeg;

  factory CharacterFace.fromJson(Map<String, dynamic> json) {
    final embedding = json['embedding'];
    if (embedding != null) {
      final model = field<String>(
        json,
        'embedding_model_id',
        'characters[].face',
      );
      if (model != characterEmbeddingModelId) {
        throw FormatException('Unsupported character face model: $model');
      }
    }
    final crop = json['crop_jpeg'];
    return CharacterFace(
      bbox: BBox.fromJson(map(json['bbox'], 'characters[].face.bbox')),
      score: number(json, 'score', 'characters[].face'),
      embedding: embedding is String
          ? decodeVector(embedding, characterEmbeddingDim)
          : null,
      cropJpeg: crop is String ? base64Decode(crop) : null,
    );
  }
}

class DetectedCharacter {
  const DetectedCharacter({
    required this.bbox,
    required this.score,
    required this.descriptor,
    this.modelId = characterModelId,
    this.cropJpeg,
    this.face,
    this.body,
  });

  final BBox bbox;
  final double score;
  final String modelId;
  final List<double> descriptor;
  final Uint8List? cropJpeg;

  /// Like a person, a character may have a face, a body, or both.
  final CharacterFace? face;
  final DetectedBody? body;

  factory DetectedCharacter.fromJson(Map<String, dynamic> json) {
    final descriptor = numbers(json['descriptor'], 'characters[].descriptor');
    if (descriptor.length != characterDescriptorDim ||
        descriptor.any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid character appearance descriptor');
    }
    final model = field<String>(json, 'model_id', 'characters[]');
    if (model != characterModelId) {
      throw FormatException('Unsupported character model: $model');
    }
    return DetectedCharacter(
      bbox: BBox.fromJson(map(json['bbox'], 'characters[].bbox')),
      score: number(json, 'score', 'characters[]'),
      descriptor: descriptor,
      modelId: model,
      cropJpeg: json['crop_jpeg'] is String
          ? base64Decode(json['crop_jpeg'] as String)
          : null,
      face: json['face'] == null
          ? null
          : CharacterFace.fromJson(map(json['face'], 'characters[].face')),
      body: json['body'] == null
          ? null
          : DetectedBody.fromJson(
              map(json['body'], 'characters[].body'),
              'characters[].body',
            ),
    );
  }
}

class FaceBodyPair {
  const FaceBodyPair({
    required this.faceIndex,
    required this.bodyIndex,
    required this.score,
  });

  final int faceIndex;
  final int bodyIndex;
  final double score;

  factory FaceBodyPair.fromJson(Map<String, dynamic> json) => FaceBodyPair(
    faceIndex: integer(json, 'face_index', 'pairs[]'),
    bodyIndex: integer(json, 'body_index', 'pairs[]'),
    score: number(json, 'score', 'pairs[]'),
  );
}

class AnalyzeImageResponse {
  const AnalyzeImageResponse({
    required this.modelId,
    required this.imageW,
    required this.imageH,
    required this.faces,
    required this.bodies,
    required this.pairs,
    this.timingsMs = const {},
    this.characters = const [],
    this.sensitiveRegions,
  });

  /// Null = not asked for (`AnalyzeOptions.returnSensitive` false, or an older server).
  final List<SensitiveRegionDto>? sensitiveRegions;

  final String modelId;
  final int imageW;
  final int imageH;
  final List<DetectedFace> faces;
  final List<DetectedBody> bodies;
  final List<FaceBodyPair> pairs;
  final Map<String, double> timingsMs;
  final List<DetectedCharacter> characters;

  factory AnalyzeImageResponse.fromJson(Map<String, dynamic> json) {
    final faces = list(json['faces'], 'faces');
    final bodies = list(json['bodies'], 'bodies');
    final timings = json['timings_ms'];
    return AnalyzeImageResponse(
      modelId: field<String>(json, 'model_id'),
      imageW: integer(json, 'image_w'),
      imageH: integer(json, 'image_h'),
      characters: [
        for (final c in list(json['characters'] ?? [], 'characters'))
          DetectedCharacter.fromJson(map(c, 'characters[]')),
      ],
      faces: [
        for (var i = 0; i < faces.length; i++)
          DetectedFace.fromJson(map(faces[i], 'faces[$i]'), 'faces[$i]'),
      ],
      bodies: [
        for (var i = 0; i < bodies.length; i++)
          DetectedBody.fromJson(map(bodies[i], 'bodies[$i]'), 'bodies[$i]'),
      ],
      pairs: list(
        json['pairs'],
        'pairs',
      ).map((p) => FaceBodyPair.fromJson(map(p, 'pairs[]'))).toList(),
      sensitiveRegions: json['sensitive_regions'] == null
          ? null
          : [
              for (final r in list(
                json['sensitive_regions'],
                'sensitive_regions',
              ))
                SensitiveRegionDto.fromJson(map(r, 'sensitive_regions[]')),
            ],
      timingsMs: timings == null
          ? const {}
          : {
              for (final e in map(timings, 'timings_ms').entries)
                e.key: (e.value as num).toDouble(),
            },
    );
  }

  /// Faces the phone would store as gallery faces.
  List<DetectedFace> get storableFaces =>
      faces.where((f) => f.passesGate).toList();
}

/// openapi.yaml `AnalyzeImageOptions`.
class AnalyzeOptions {
  const AnalyzeOptions({
    this.detectBodies = true,
    this.minQuality = 0.40,
    this.returnCrops = true,
    this.bodyScore = 0.5,
    this.modelId,
    this.detectCharacters = false,
    this.returnOutlines = true,
    this.facelessCharacters = true,
    this.forceKind,
    this.kindOverrides = const [],
    this.returnSensitive = false,
    this.returnBodyEmbeddings = false,
  });

  /// Also ask for exposed / covered body-part regions (roadmap section 8). Only set when the
  /// server's capabilities say `sensitive_detection`; otherwise it answers 409 `model_missing`.
  final bool returnSensitive;

  /// Roadmap 7.5 (Phase 8): also ask for chest / lower-body embeddings and morphology of exposed regions.
  /// Only when the server advertises `body_embeddings`.
  final bool returnBodyEmbeddings;

  final bool detectBodies;
  final double minQuality;
  final bool returnCrops;
  final double bodyScore;
  final String? modelId;
  final bool detectCharacters;
  final bool returnOutlines;

  /// A faceless body in a frame without real faces is a character. False for files the user
  /// did not mark illustrated: then only next to drawn faces.
  final bool facelessCharacters;

  /// The user's corrections: the whole file ('person' | 'character'), and single detections.
  final String? forceKind;
  final List<KindOverrideDto> kindOverrides;

  Map<String, dynamic> toJson() => {
    'detect_bodies': detectBodies,
    'detect_characters': detectCharacters,
    'min_quality': minQuality,
    'return_crops': returnCrops,
    'body_score': bodyScore,
    if (modelId != null) 'model_id': modelId,
    if (returnOutlines) 'return_outlines': true,
    if (returnSensitive) 'return_sensitive': true,
    if (returnBodyEmbeddings) 'return_body_embeddings': true,
    if (!facelessCharacters) 'faceless_characters': false,
    if (forceKind != null) 'force_kind': forceKind,
    if (kindOverrides.isNotEmpty)
      'kind_overrides': [for (final o in kindOverrides) o.toJson()],
  };
}

/// openapi.yaml `KindOverride`: "this face / body is a person (or a character)".
class KindOverrideDto {
  const KindOverrideDto({
    required this.kind,
    required this.part,
    required this.box,
    this.timestampMs,
  });

  final String kind; // 'person' | 'character'
  final String part; // 'face' | 'body'
  final ({double x, double y, double w, double h}) box; // normalised
  final int? timestampMs;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'part': part,
    'box': [box.x, box.y, box.w, box.h],
    if (timestampMs != null) 'timestamp_ms': timestampMs,
  };
}

/// Target for POST /v1/analyze/outlines.
class OutlineTargetDto {
  const OutlineTargetDto({
    required this.kind,
    required this.bbox,
    this.kps,
    this.kpts,
  });

  final String kind; // 'f' or 'b'
  final BBox bbox;
  final List<List<double>>? kps;
  final List<List<double>>? kpts;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'bbox': bbox.toJson(),
    if (kps != null) 'kps': kps,
    if (kpts != null) 'kpts': kpts,
  };

  factory OutlineTargetDto.fromJson(Map<String, dynamic> json) =>
      OutlineTargetDto(
        kind: field<String>(json, 'kind'),
        bbox: BBox.fromJson(map(json['bbox'], 'bbox')),
        kps: json['kps'] == null
            ? null
            : (json['kps'] as List<dynamic>)
                  .map(
                    (pt) => (pt as List<dynamic>)
                        .map((v) => (v as num).toDouble())
                        .toList(),
                  )
                  .toList(),
        kpts: json['kpts'] == null
            ? null
            : (json['kpts'] as List<dynamic>)
                  .map(
                    (pt) => (pt as List<dynamic>)
                        .map((v) => (v as num).toDouble())
                        .toList(),
                  )
                  .toList(),
      );
}

/// Response from POST /v1/analyze/outlines.
class AnalyzeOutlinesResponse {
  const AnalyzeOutlinesResponse({required this.outlines});

  final List<List<Offset>?> outlines;

  factory AnalyzeOutlinesResponse.fromJson(Map<String, dynamic> json) {
    final rawList = list(json['outlines'], 'outlines');
    return AnalyzeOutlinesResponse(
      outlines: [
        for (var i = 0; i < rawList.length; i++)
          rawList[i] == null
              ? null
              : (rawList[i] as List<dynamic>).map((pt) {
                  final p = pt as List<dynamic>;
                  return Offset(
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  );
                }).toList(),
      ],
    );
  }
}

/// openapi.yaml `SensitiveRegion`: an exposed / covered body-part box (NudeNet), pixel coordinates.
class SensitiveRegionDto {
  const SensitiveRegionDto({
    required this.label,
    required this.exposed,
    required this.score,
    required this.bbox,
    this.bodyIndex,
    this.characterIndex,
  });

  final String label; // NudeNet v3 label, e.g. FEMALE_BREAST_EXPOSED
  final bool exposed;
  final double score;
  final BBox bbox;

  /// Index into `AnalyzeImageResponse.bodies`; null when no body fits.
  final int? bodyIndex;

  /// Index into `AnalyzeImageResponse.characters` when the region is on a drawn character's body
  /// (then [bodyIndex] is null): characters get the same regions as people.
  final int? characterIndex;

  factory SensitiveRegionDto.fromJson(Map<String, dynamic> json) =>
      SensitiveRegionDto(
        label: field<String>(json, 'label', 'sensitive_regions[]'),
        exposed: field<bool>(json, 'exposed', 'sensitive_regions[]'),
        score: number(json, 'score', 'sensitive_regions[]'),
        bbox: BBox.fromJson(map(json['bbox'], 'sensitive_regions[].bbox')),
        bodyIndex: json['body_index'] == null
            ? null
            : integer(json, 'body_index', 'sensitive_regions[]'),
        characterIndex: json['character_index'] == null
            ? null
            : integer(json, 'character_index', 'sensitive_regions[]'),
      );

  Map<String, dynamic> toJson() => {
    'label': label,
    'exposed': exposed,
    'score': score,
    'bbox': bbox.toJson(),
    'body_index': bodyIndex,
    if (characterIndex != null) 'character_index': characterIndex,
  };
}

/// A stored body sent to POST /v1/analyze/sensitive: its pixel box and (when known) keypoints, which
/// decide which body a region belongs to.
class SensitiveBodyTargetDto {
  const SensitiveBodyTargetDto({required this.bbox, this.kpts});

  final BBox bbox;
  final List<List<double>>? kpts; // 17 x [x, y, score], image pixels

  Map<String, dynamic> toJson() => {
    'bbox': bbox.toJson(),
    if (kpts != null) 'kpts': kpts,
  };

  factory SensitiveBodyTargetDto.fromJson(Map<String, dynamic> json) =>
      SensitiveBodyTargetDto(
        bbox: BBox.fromJson(map(json['bbox'], 'bbox')),
        kpts: json['kpts'] == null
            ? null
            : [
                for (final pt in json['kpts'] as List<dynamic>)
                  [for (final v in pt as List<dynamic>) (v as num).toDouble()],
              ],
      );
}

/// Response from POST /v1/analyze/sensitive.
class BodyEmbeddingsDto {
  const BodyEmbeddingsDto({
    this.chestEmbedding,
    this.buttocksEmbedding,
    this.morphology,
  });

  final Float32List? chestEmbedding;
  final Float32List? buttocksEmbedding;
  final Map<String, dynamic>? morphology;

  factory BodyEmbeddingsDto.fromJson(Map<String, dynamic> json) =>
      BodyEmbeddingsDto(
        chestEmbedding: _patchEmbedding(json['chest_embedding']),
        buttocksEmbedding: _patchEmbedding(json['buttocks_embedding']),
        morphology: json['morphology'] is Map<String, dynamic>
            ? json['morphology'] as Map<String, dynamic>
            : null,
      );
}

class AnalyzeSensitiveResponse {
  const AnalyzeSensitiveResponse({
    required this.modelVersion,
    required this.regions,
    this.bodies,
  });

  final int modelVersion;
  final List<SensitiveRegionDto> regions;

  /// Only when asked with `embeddings`: one entry per requested body, in order.
  final List<BodyEmbeddingsDto>? bodies;

  factory AnalyzeSensitiveResponse.fromJson(Map<String, dynamic> json) =>
      AnalyzeSensitiveResponse(
        modelVersion: integer(json, 'model_version'),
        regions: [
          for (final r in list(json['regions'], 'regions'))
            SensitiveRegionDto.fromJson(map(r, 'regions[]')),
        ],
        bodies: json['bodies'] == null
            ? null
            : [
                for (final b in list(json['bodies'], 'bodies'))
                  BodyEmbeddingsDto.fromJson(map(b, 'bodies[]')),
              ],
      );
}

/// One garment tag with its raw WD14 score (roadmap Phase 7). Evidence only: no tag is a filter yet.
class GarmentTagDto {
  const GarmentTagDto({
    required this.tag,
    required this.category,
    required this.score,
  });

  final String tag;
  final String
  category; // upper | outerwear | lower | full_body | pattern | accessory | footwear
  final double score;

  factory GarmentTagDto.fromJson(Map<String, dynamic> json) => GarmentTagDto(
    tag: field<String>(json, 'tag', 'tags[]'),
    category: field<String>(json, 'category', 'tags[]'),
    score: number(json, 'score', 'tags[]'),
  );
}

/// Response from POST /v1/analyze/garments: one tag list per requested body, in order.
class AnalyzeGarmentsResponse {
  const AnalyzeGarmentsResponse({
    required this.modelVersion,
    required this.bodies,
  });

  final int modelVersion;
  final List<List<GarmentTagDto>> bodies;

  factory AnalyzeGarmentsResponse.fromJson(Map<String, dynamic> json) =>
      AnalyzeGarmentsResponse(
        modelVersion: integer(json, 'model_version'),
        bodies: [
          for (final b in list(json['bodies'], 'bodies'))
            [
              for (final t in list(map(b, 'bodies[]')['tags'], 'tags'))
                GarmentTagDto.fromJson(map(t, 'tags[]')),
            ],
        ],
      );
}

/// One candidate's answer from POST /v1/analyze/marks.
class MarkMatchDto {
  const MarkMatchDto({
    required this.index,
    required this.inliers,
    required this.matches,
    required this.inlierRatio,
    required this.mirrored,
  });

  final int index;
  final int inliers;
  final int matches;
  final double inlierRatio;
  final bool mirrored;

  factory MarkMatchDto.fromJson(Map<String, dynamic> json) => MarkMatchDto(
    index: integer(json, 'index', 'results[]'),
    inliers: integer(json, 'inliers', 'results[]'),
    matches: integer(json, 'matches', 'results[]'),
    inlierRatio: number(json, 'inlier_ratio', 'results[]'),
    mirrored: field<bool>(json, 'mirrored', 'results[]'),
  );
}

class AnalyzeMarksResponse {
  const AnalyzeMarksResponse({required this.results});

  final List<MarkMatchDto> results;

  factory AnalyzeMarksResponse.fromJson(Map<String, dynamic> json) =>
      AnalyzeMarksResponse(
        results: [
          for (final r in list(json['results'], 'results'))
            MarkMatchDto.fromJson(map(r, 'results[]')),
        ],
      );
}
