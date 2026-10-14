import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/index/embedding_index.dart';
import '../../data/repositories/library_repository.dart';
import 'scan_math.dart';

class StoreOutcome {
  const StoreOutcome({
    this.facesSeen = 0,
    this.newFaceIds = const [],
    this.linkedFaces = 0,
    this.newBodies = 0,
  });

  final int facesSeen; // faces that passed the quality gate
  final List<int> newFaceIds;
  final int linkedFaces; // seen again: linked to a face the library already had
  final int newBodies;

  int get newFaces => newFaceIds.length;
}

typedef _Box = ({double x, double y, double w, double h});

class _Existing {
  _Existing(this.id, this.box, this.vector, this.quality, this.version);
  final int id;
  final _Box box;
  final Float32List vector;
  final double quality;
  final int version;
}

/// Writes what the PC found in one photo: faces, bodies, crops and the detections that tie them to
/// the photo - all in ONE transaction, so a photo is either fully scanned or not at all (the scan
/// is resumable and re-running it for the same photo changes nothing).
///
/// Mirrors LibraryScanner._scan_frame / _FileState.store_face / store_body on the PC.
class PhotoResultStore {
  PhotoResultStore({
    required this._db,
    required this._files,
    required this._index,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final EmbeddingIndex _index;
  final DateTime Function() _clock;

  Future<StoreOutcome> store(
    MediaRow media,
    AnalyzeImageResponse analysis,
  ) async {
    final w = analysis.imageW, h = analysis.imageH;
    final now = _clock().millisecondsSinceEpoch;
    final gated = [
      for (var i = 0; i < analysis.faces.length; i++)
        if (analysis.faces[i].passesGate) i,
    ];

    final inFile = await _facesOfMedia(media.id);
    final hits = await _index.nearest([
      for (final i in gated) analysis.faces[i].embedding,
    ]);

    // ---- decide, per face: the same face again, or a new one --------------------------
    final used = <int>{};
    final faceTarget =
        <
          int,
          int?
        >{}; // analysis face index -> existing face id (null = new face)
    for (var k = 0; k < gated.length; k++) {
      final i = gated[k];
      final face = analysis.faces[i];
      final box = _box(face.bbox, w, h);
      int? target;
      for (final c in inFile) {
        if (!used.contains(c.id) && iou(box, c.box) >= sameBoxIou) {
          target = c.id;
          break;
        }
      }
      if (target == null) {
        _Existing? closest;
        var best = -1.0;
        for (final c in inFile) {
          if (used.contains(c.id)) continue;
          final sim = cosine(c.vector, face.embedding);
          if (sim > best) {
            best = sim;
            closest = c;
          }
        }
        if (closest != null && best >= sameFileCosine) target = closest.id;
      }
      final hit = hits[k];
      if (target == null &&
          hit != null &&
          hit.cosine >= duplicateCosine &&
          !used.contains(hit.id)) {
        target = hit.id;
      }
      if (target != null) used.add(target);
      faceTarget[i] = target;
    }

    final newIds = <int>[];
    final newVectors = <(int, Float32List)>[];
    var linked = 0, newBodies = 0;

    await _db.transaction(() async {
      final faceDbId = <int, int>{}; // analysis face index -> faces.id

      for (final i in gated) {
        final face = analysis.faces[i];
        final target = faceTarget[i];
        if (target != null && await _refreshLinkedFace(target, face)) {
          faceDbId[i] = target;
          linked++;
          continue;
        }
        // (a face the index still remembered but the user deleted meanwhile counts as a new face)
        final box = _box(face.bbox, w, h);
        final id = await _db
            .into(_db.faces)
            .insert(
              FacesCompanion.insert(
                mediaId: Value(media.id),
                modelId: analysis.modelId,
                embedding: embeddingToBlob(face.embedding),
                qualityScore: face.quality.score,
                qualityVersion: face.quality.version,
                detScore: face.detScore,
                facePx: face.quality.facePx,
                sharpness: face.quality.sharpness,
                embeddingNorm: Value(face.quality.embeddingNorm),
                yaw: Value(face.quality.pose?.yaw),
                pitch: Value(face.quality.pose?.pitch),
                roll: Value(face.quality.pose?.roll),
                bboxX: box.x,
                bboxY: box.y,
                bboxW: box.w,
                bboxH: box.h,
                kps: Value(
                  jsonEncode([
                    for (final p in face.kps) [_r(p[0] / w), _r(p[1] / h)],
                  ]),
                ),
                createdAt: now,
              ),
            );
        if (face.cropJpeg != null) {
          final path = await _files.writeFaceCrop(id, face.cropJpeg!);
          await (_db.update(_db.faces)..where((f) => f.id.equals(id))).write(
            FacesCompanion(cropPath: Value(path)),
          );
        }
        faceDbId[i] = id;
        newIds.add(id);
        newVectors.add((id, face.embedding));
      }

      // detections of the faces, replacing earlier rows for the same (photo, face)
      for (final i in gated) {
        final box = _box(analysis.faces[i].bbox, w, h);
        await _putDetection(media.id, 'f', faceDbId[i]!, box);
      }

      // ---- bodies --------------------------------------------------------------------
      final faceOfBody = {
        for (final p in analysis.pairs) p.bodyIndex: p.faceIndex,
      };
      final existingBodies = await _bodiesOfMedia(media.id);
      final usedBodies = <int>{};
      final keptOutfits = <List<double>>[
        for (final b in existingBodies)
          if (b.faceId == null && b.appearance != null) b.appearance!,
      ];
      var keptFaceless = existingBodies.where((b) => b.faceId == null).length;

      for (var bi = 0; bi < analysis.bodies.length; bi++) {
        final body = analysis.bodies[bi];
        final fi = faceOfBody[bi];
        final faceId = fi == null ? null : faceDbId[fi];
        final box = _box(body.bbox, w, h);

        _ExistingBody? same;
        for (final e in existingBodies) {
          if (!usedBodies.contains(e.id) && iou(box, e.box) >= sameBoxIou) {
            same = e;
            break;
          }
        }
        if (same != null) {
          usedBodies.add(same.id);
          await _db.customUpdate(
            'UPDATE bodies SET score = ?, extent = ?, kpts = ?, appearance = ?, face_id = COALESCE(face_id, ?) WHERE id = ?',
            variables: [
              Variable.withReal(body.score),
              Variable<String>(body.extent),
              Variable<String>(_kpts(body, w, h)),
              Variable<Uint8List>(
                body.appearance == null
                    ? null
                    : appearanceToBlob(body.appearance!),
              ),
              Variable<int>(faceId),
              Variable.withInt(same.id),
            ],
            updates: {_db.bodies},
          );
          await _putDetection(media.id, 'b', same.id, box);
          continue;
        }

        if (faceId == null) {
          // faceless bodies: only keep ones that look different from what this photo already has
          if (keptFaceless >= maxFacelessBodiesPerMedia) continue;
          if (body.appearance != null &&
              keptOutfits.any(
                (k) =>
                    appearanceSimilarity(body.appearance, k) >=
                    sameOutfitSimilarity,
              )) {
            continue;
          }
        }

        Float32List? weak;
        double? weakQuality;
        if (fi != null && faceId == null) {
          weak = analysis
              .faces[fi]
              .embedding; // a face the quality gate refused: weak evidence
          weakQuality = analysis.faces[fi].quality.score;
        }
        final id = await _db
            .into(_db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(media.id),
                faceId: Value(faceId),
                bboxX: box.x,
                bboxY: box.y,
                bboxW: box.w,
                bboxH: box.h,
                score: body.score,
                kpts: Value(_kpts(body, w, h)),
                extent: Value(body.extent),
                appearance: Value(
                  body.appearance == null
                      ? null
                      : appearanceToBlob(body.appearance!),
                ),
                weakFaceEmbedding: Value(
                  weak == null ? null : embeddingToBlob(weak),
                ),
                weakFaceQuality: Value(weakQuality),
                createdAt: now,
              ),
            );
        if (body.cropJpeg != null) {
          final path = await _files.writeBodyCrop(id, body.cropJpeg!);
          await (_db.update(_db.bodies)..where((b) => b.id.equals(id))).write(
            BodiesCompanion(cropPath: Value(path)),
          );
        }
        await _putDetection(media.id, 'b', id, box);
        newBodies++;
        if (faceId == null) {
          keptFaceless++;
          if (body.appearance != null) keptOutfits.add(body.appearance!);
        }
      }

      await (_db.update(_db.media)..where((m) => m.id.equals(media.id))).write(
        MediaCompanion(
          scanStatus: const Value('done'),
          scanVersion: const Value(scanVersion),
          scannedAt: Value(now),
          scanError: const Value(null),
        ),
      );
    });

    await _index.addAll(newVectors);
    return StoreOutcome(
      facesSeen: gated.length,
      newFaceIds: newIds,
      linkedFaces: linked,
      newBodies: newBodies,
    );
  }

  // ---- helpers ---------------------------------------------------------------------

  _Box _box(BBox pixels, int w, int h) {
    final n = pixels.normalized(w, h);
    return clampBox(n.x, n.y, n.w, n.h);
  }

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  String _kpts(DetectedBody body, int w, int h) => jsonEncode([
    for (final k in body.kpts ?? const <List<double>>[])
      [_r(k[0] / w), _r(k[1] / h), k[2]],
  ]);

  Future<List<_Existing>> _facesOfMedia(int mediaId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, bbox_x, bbox_y, bbox_w, bbox_h, embedding, quality_score, quality_version FROM faces WHERE media_id = ?',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.faces},
        )
        .get();
    return [
      for (final r in rows)
        _Existing(
          r.read<int>('id'),
          (
            x: r.read<double>('bbox_x'),
            y: r.read<double>('bbox_y'),
            w: r.read<double>('bbox_w'),
            h: r.read<double>('bbox_h'),
          ),
          embeddingFromBlob(r.read<Uint8List>('embedding')),
          r.read<double>('quality_score'),
          r.read<int>('quality_version'),
        ),
    ];
  }

  Future<List<_ExistingBody>> _bodiesOfMedia(int mediaId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, face_id, bbox_x, bbox_y, bbox_w, bbox_h, appearance FROM bodies WHERE media_id = ?',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.bodies},
        )
        .get();
    return [
      for (final r in rows)
        _ExistingBody(
          r.read<int>('id'),
          r.readNullable<int>('face_id'),
          (
            x: r.read<double>('bbox_x'),
            y: r.read<double>('bbox_y'),
            w: r.read<double>('bbox_w'),
            h: r.read<double>('bbox_h'),
          ),
          r.readNullable<Uint8List>('appearance') == null
              ? null
              : appearanceFromBlob(r.read<Uint8List>('appearance')),
        ),
    ];
  }

  /// A face seen again keeps its home photo; only a better view of it (higher quality, or scored by a
  /// newer quality version) refreshes its quality fields.
  /// False when that face no longer exists.
  Future<bool> _refreshLinkedFace(int faceId, DetectedFace face) async {
    final row = await (_db.select(
      _db.faces,
    )..where((f) => f.id.equals(faceId))).getSingleOrNull();
    if (row == null) return false;
    if (row.qualityVersion < face.quality.version ||
        face.quality.score > row.qualityScore) {
      await (_db.update(_db.faces)..where((f) => f.id.equals(faceId))).write(
        FacesCompanion(
          qualityScore: Value(face.quality.score),
          qualityVersion: Value(face.quality.version),
          detScore: Value(face.detScore),
          facePx: Value(face.quality.facePx),
          sharpness: Value(face.quality.sharpness),
          embeddingNorm: Value(face.quality.embeddingNorm),
          yaw: Value(face.quality.pose?.yaw),
          pitch: Value(face.quality.pose?.pitch),
          roll: Value(face.quality.pose?.roll),
        ),
      );
    }
    return true;
  }

  Future<void> _putDetection(
    int mediaId,
    String kind,
    int refId,
    _Box box,
  ) async {
    await _db.customUpdate(
      'DELETE FROM media_detections WHERE media_id = ? AND kind = ? AND ref_id = ?',
      variables: [
        Variable.withInt(mediaId),
        Variable.withString(kind),
        Variable.withInt(refId),
      ],
      updates: {_db.mediaDetections},
    );
    await _db
        .into(_db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            kind: kind,
            refId: refId,
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
          ),
        );
  }
}

class _ExistingBody {
  _ExistingBody(this.id, this.faceId, this.box, this.appearance);
  final int id;
  final int? faceId;
  final _Box box;
  final List<double>? appearance;
}
