import 'dart:convert';
import 'dart:typed_data';

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

class DetectedFace {
  const DetectedFace({
    required this.bbox,
    required this.kps,
    required this.detScore,
    required this.embedding,
    required this.quality,
    required this.passesGate,
    this.cropJpeg,
  });

  final BBox bbox;
  final List<List<double>> kps; // 5 x [x, y]
  final double detScore;
  final Float32List embedding; // 512, unit length
  final FaceQuality quality;
  final bool passesGate; // the phone stores only faces that pass
  final Uint8List? cropJpeg;

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
  });

  final BBox bbox;
  final double score;
  final List<List<double>>? kpts; // 17 x [x, y, score]
  final List<double>? appearance; // 80-float outfit descriptor
  final String? extent; // full | knee | upper | head
  final Uint8List? cropJpeg;

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
  });

  final String modelId;
  final int imageW;
  final int imageH;
  final List<DetectedFace> faces;
  final List<DetectedBody> bodies;
  final List<FaceBodyPair> pairs;
  final Map<String, double> timingsMs;

  factory AnalyzeImageResponse.fromJson(Map<String, dynamic> json) {
    final faces = list(json['faces'], 'faces');
    final bodies = list(json['bodies'], 'bodies');
    final timings = json['timings_ms'];
    return AnalyzeImageResponse(
      modelId: field<String>(json, 'model_id'),
      imageW: integer(json, 'image_w'),
      imageH: integer(json, 'image_h'),
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
  });

  final bool detectBodies;
  final double minQuality;
  final bool returnCrops;
  final double bodyScore;
  final String? modelId;

  Map<String, dynamic> toJson() => {
    'detect_bodies': detectBodies,
    'min_quality': minQuality,
    'return_crops': returnCrops,
    'body_score': bodyScore,
    if (modelId != null) 'model_id': modelId,
  };
}
