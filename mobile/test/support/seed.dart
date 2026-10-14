import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;

/// Deterministic 512-d unit vector: the same seed always gives the same "face".
Float32List unitVec(int seed) {
  final r = Random(seed);
  final v = Float32List(embeddingDim);
  var sum = 0.0;
  for (var i = 0; i < embeddingDim; i++) {
    final x =
        (r.nextDouble() * 2 - 1) +
        (r.nextDouble() * 2 - 1) +
        (r.nextDouble() * 2 - 1);
    v[i] = x;
    sum += x * x;
  }
  final inv = 1 / sqrt(sum);
  for (var i = 0; i < embeddingDim; i++) {
    v[i] = v[i] * inv;
  }
  return v;
}

/// `base` nudged by `noise` (0 = identical, ~0.6 = the same person on another day, big = a stranger).
Float32List near(Float32List base, int noiseSeed, double noise) {
  final n = unitVec(noiseSeed);
  final out = Float32List(embeddingDim);
  var sum = 0.0;
  for (var i = 0; i < embeddingDim; i++) {
    out[i] = base[i] + noise * n[i];
    sum += out[i] * out[i];
  }
  final inv = 1 / sqrt(sum);
  for (var i = 0; i < embeddingDim; i++) {
    out[i] = out[i] * inv;
  }
  return out;
}

double dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

Future<int> seedPerson(
  AppDatabase db, {
  String? name,
  int createdAt = 1,
  int? avatarFaceId,
}) => db
    .into(db.persons)
    .insert(
      PersonsCompanion.insert(
        name: Value(name),
        createdAt: createdAt,
        avatarFaceId: Value(avatarFaceId),
      ),
    );

Future<int> seedMedia(
  AppDatabase db, {
  String asset = 'asset-1',
  String kind = 'photo',
  String status = 'done',
  int modifiedAt = 1000,
  int width = 1200,
  int height = 800,
  int? takenAt,
}) => db
    .into(db.media)
    .insert(
      MediaCompanion.insert(
        assetId: asset,
        kind: kind,
        modifiedAt: Value(modifiedAt),
        width: Value(width),
        height: Value(height),
        takenAt: Value(takenAt ?? modifiedAt),
        scanStatus: Value(status),
      ),
    );

Future<int> seedFace(
  AppDatabase db, {
  int? mediaId,
  int? personId,
  double quality = 0.7,
  Float32List? embedding,
  int seed = 1,
  String? cropPath,
  bool dismissed = false,
  int? frameNumber,
  double x = 0.1,
  double y = 0.1,
  double w = 0.2,
  double h = 0.2,
}) async {
  final id = await db
      .into(db.faces)
      .insert(
        FacesCompanion.insert(
          mediaId: Value(mediaId),
          personId: Value(personId),
          modelId: 'buffalo_l@1',
          embedding: embeddingToBlob(embedding ?? unitVec(seed)),
          qualityScore: quality,
          qualityVersion: 2,
          detScore: 0.9,
          facePx: 100,
          sharpness: 200,
          bboxX: x,
          bboxY: y,
          bboxW: w,
          bboxH: h,
          cropPath: Value(cropPath),
          reviewDismissed: Value(dismissed),
          frameNumber: Value(frameNumber),
          createdAt: 1,
        ),
      );
  if (mediaId != null) {
    await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            kind: 'f',
            refId: id,
            x: x,
            y: y,
            w: w,
            h: h,
          ),
        );
  }
  return id;
}

/// A fake outfit descriptor (80 floats: torso + legs, two unit-norm regions of 40).
List<double> outfit(int seed) {
  final r = Random(seed);
  final out = <double>[];
  for (var region = 0; region < 2; region++) {
    final v = [for (var i = 0; i < 40; i++) r.nextDouble()];
    final n = sqrt(v.fold<double>(0, (a, b) => a + b * b));
    out.addAll(v.map((x) => x / n));
  }
  return out;
}

Future<int> seedBody(
  AppDatabase db, {
  int? mediaId,
  int? faceId,
  int? personId,
  String? linkMethod,
  double? linkConfidence,
  List<double>? appearance,
  Float32List? weakFace,
  int? frameNumber,
  String? cropPath,
  double score = 0.9,
}) async {
  final id = await db
      .into(db.bodies)
      .insert(
        BodiesCompanion.insert(
          mediaId: Value(mediaId),
          faceId: Value(faceId),
          personId: Value(personId),
          linkMethod: Value(linkMethod),
          linkConfidence: Value(linkConfidence),
          bboxX: 0.2,
          bboxY: 0.1,
          bboxW: 0.4,
          bboxH: 0.8,
          score: score,
          appearance: Value(
            appearance == null ? null : packFloat32(appearance),
          ),
          weakFaceEmbedding: Value(
            weakFace == null ? null : embeddingToBlob(weakFace),
          ),
          frameNumber: Value(frameNumber),
          cropPath: Value(cropPath),
          createdAt: 1,
        ),
      );
  if (mediaId != null) {
    await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            kind: 'b',
            refId: id,
            x: 0.2,
            y: 0.1,
            w: 0.4,
            h: 0.8,
          ),
        );
  }
  return id;
}

// ---- analyze responses ---------------------------------------------------------------

Map<String, dynamic> _quality(double score, {double facePx = 120}) => {
  'quality_score': score,
  'quality_version': 2,
  'quality_parts': {'norm': 0.8, 'size': 0.7, 'sharp': 0.7, 'pose': 0.9},
  'det_score': 0.93,
  'face_px': facePx,
  'sharpness': 220.0,
  'embedding_norm': 21.0,
  'pose': {'yaw': 3.0, 'pitch': -2.0, 'roll': 0.5},
};

/// One face as the PC would answer it. `box` is [x, y, w, h] in pixels of a 1000 x 800 image.
Map<String, dynamic> faceJson(
  Float32List embedding, {
  List<double> box = const [100, 100, 200, 240],
  double quality = 0.8,
  bool passes = true,
  bool crop = true,
}) => {
  'bbox': {'x': box[0], 'y': box[1], 'w': box[2], 'h': box[3]},
  'kps': [
    [box[0] + 0.3 * box[2], box[1] + 0.35 * box[3]],
    [box[0] + 0.7 * box[2], box[1] + 0.35 * box[3]],
    [box[0] + 0.5 * box[2], box[1] + 0.55 * box[3]],
    [box[0] + 0.35 * box[2], box[1] + 0.75 * box[3]],
    [box[0] + 0.65 * box[2], box[1] + 0.75 * box[3]],
  ],
  'det_score': 0.93,
  'embedding': encodeEmbedding(embedding),
  'quality': _quality(quality),
  'passes_gate': passes,
  'crop_jpeg': crop && passes ? base64Encode([0xFF, 0xD8, 0xFF, 0xD9]) : null,
};

Map<String, dynamic> bodyJson({
  List<double> box = const [50, 60, 400, 700],
  List<double>? appearance,
  bool crop = true,
}) => {
  'bbox': {'x': box[0], 'y': box[1], 'w': box[2], 'h': box[3]},
  'score': 0.9,
  'kpts': [
    for (var i = 0; i < 17; i++) [box[0] + 10.0 * i, box[1] + 20.0 * i, 0.9],
  ],
  'appearance': appearance ?? outfit(1),
  'extent': 'upper',
  'crop_jpeg': crop ? base64Encode([0xFF, 0xD8, 0xFF, 0xD9]) : null,
};

/// An AnalyzeImageResponse for a 1000 x 800 picture.
AnalyzeImageResponse analysis({
  List<Map<String, dynamic>> faces = const [],
  List<Map<String, dynamic>> bodies = const [],
  List<(int, int)> pairs = const [],
  String modelId = 'buffalo_l@1',
}) => AnalyzeImageResponse.fromJson({
  'model_id': modelId,
  'image_w': 1000,
  'image_h': 800,
  'faces': faces,
  'bodies': bodies,
  'pairs': [
    for (final (f, b) in pairs)
      {'face_index': f, 'body_index': b, 'score': 0.8},
  ],
});
