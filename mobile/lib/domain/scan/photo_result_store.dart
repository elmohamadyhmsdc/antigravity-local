import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/index/embedding_index.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/face_suppression_store.dart';
import 'drawn_faces.dart';
import 'scan_math.dart';
import 'video_tracks.dart';
import '../geometry/outline.dart';

class StoreOutcome {
  const StoreOutcome({
    this.facesSeen = 0,
    this.newFaceIds = const [],
    this.linkedFaces = 0,
    this.newBodies = 0,
    this.newCharacters = 0,
  });

  final int facesSeen; // faces that passed the quality gate
  final List<int> newFaceIds;
  final int linkedFaces; // seen again: linked to a face the library already had
  final int newBodies;
  final int newCharacters;

  int get newFaces => newFaceIds.length;
}

typedef _Box = ({double x, double y, double w, double h});

class _Existing {
  _Existing(
    this.id,
    this.box,
    this.vector,
    this.quality,
    this.version,
    this.track,
  );
  final int id;
  final _Box box;
  final Float32List vector;
  final double quality;
  final int version;
  final int? track;
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
    AnalyzeImageResponse analysis, {
    int? frameNumber,
    int? timestampMs,
    bool complete = true,
  }) async {
    final w = analysis.imageW, h = analysis.imageH;
    final now = _clock().millisecondsSinceEpoch;
    // Drawn (anime/cartoon) faces score like good faces but are never people; older PC
    // servers still send them.
    final drawn = {
      for (var i = 0; i < analysis.faces.length; i++)
        if (isDrawnFace(analysis.faces[i].embedding)) i,
    };
    final gated = [
      for (var i = 0; i < analysis.faces.length; i++)
        if (analysis.faces[i].passesGate && !drawn.contains(i)) i,
    ];

    final hits = await _index.nearest([
      for (final i in gated) analysis.faces[i].embedding,
    ]);

    final video = media.kind == 'video' && frameNumber != null;
    final newIds = <int>[];
    final newVectors = <(int, Float32List)>[];
    final replaced = <(int, Float32List)>[];
    var linked = 0, newBodies = 0, newCharacters = 0;

    await _db.transaction(() async {
      final inFile = await _facesOfMedia(media.id, frameNumber);
      final faceDbId = <int, int>{}; // analysis face index -> faces.id
      final suppressed = await FaceSuppressionStore(
        _db,
      ).forAsset(media.assetId);
      final ignored = <int>{};
      final used = <int>{};
      final targets =
          <int, int>{}; // gated position -> existing face of this frame

      // A rescan of the same frame finds its own faces again first.
      for (var k = 0; k < gated.length; k++) {
        final i = gated[k];
        final face = analysis.faces[i];
        if (FaceSuppressionStore.matches(
          suppressed,
          asset: media.assetId,
          model: analysis.modelId,
          embedding: face.embedding,
          box: _box(face.bbox, w, h),
          video: media.kind == 'video',
          frame: frameNumber,
        )) {
          ignored.add(i);
          continue;
        }
        // Ignore deleted detections before they can consume an existing match
        // belonging to another face in this same frame.
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
        if (target != null) {
          used.add(target);
          targets[k] = target;
        }
      }

      // In a video, the others continue a track of an earlier frame.
      final tracks = video
          ? await _faceTracks(media.id, frameNumber, timestampMs)
          : const <int, Track<Float32List>>{};
      final trackOf = <int, Track<Float32List>?>{};
      if (tracks.isNotEmpty) {
        final taken = {
          for (final c in inFile)
            if (used.contains(c.id)) c.track,
        };
        final open = [
          for (var k = 0; k < gated.length; k++)
            if (!ignored.contains(gated[k]) && !targets.containsKey(k)) k,
        ];
        final assigned = assignTracks<Float32List>(
          values: [for (final k in open) analysis.faces[gated[k]].embedding],
          boxes: [
            for (final k in open) _box(analysis.faces[gated[k]].bbox, w, h),
          ],
          timestampMs: timestampMs,
          tracks: tracks.values.where((t) => !taken.contains(t.id)),
          similarity: faceSimilarity,
          identity: trackIdentityCosine,
          motion: trackMotionCosine,
        );
        for (var n = 0; n < open.length; n++) {
          trackOf[open[n]] = assigned[n];
        }
      }

      for (var k = 0; k < gated.length; k++) {
        final i = gated[k];
        if (ignored.contains(i)) continue;
        final face = analysis.faces[i];
        final box = _box(face.bbox, w, h);
        var target = targets[k];
        final rescanned = target != null;
        if (target != null) {
          if (await _refreshLinkedFace(target, face)) {
            faceDbId[i] = target;
            linked++;
            continue;
          }
          target = null;
        }
        final track = trackOf[k];
        if (track != null) {
          switch (placeInTrack<Float32List>(
            track,
            face.embedding,
            face.quality.score,
            similarity: faceSimilarity,
            maxViews: maxFacesPerTrack,
            diverse: trackDiverseCosine,
          )) {
            case LinkView(:final view):
              faceDbId[i] = view.id;
              linked++;
              continue;
            case ReplaceView(:final view):
              await _replaceView(
                view.id,
                face,
                box,
                w,
                h,
                frameNumber,
                timestampMs,
              );
              replaced.add((view.id, face.embedding));
              view
                ..value = face.embedding
                ..quality = face.quality.score;
              faceDbId[i] = view.id;
              linked++;
              continue;
            case InsertView():
              break;
          }
        }
        final hit = hits[k];
        if (!rescanned &&
            track == null &&
            hit != null &&
            hit.cosine >= duplicateCosine &&
            !used.contains(hit.id)) {
          target = hit.id;
          used.add(target);
          if (await _refreshLinkedFace(target, face)) {
            faceDbId[i] = target;
            linked++;
            continue;
          }
        }
        // A stale index hit cannot recreate a deletion: suppression was checked
        // inside this write transaction, after any manual correction committed.
        final id = await _db
            .into(_db.faces)
            .insert(
              FacesCompanion.insert(
                mediaId: Value(media.id),
                frameNumber: Value(frameNumber),
                timestampMs: Value(timestampMs),
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
                kps: Value(_kpsJson(face, w, h)),
                createdAt: now,
              ),
            );
        if (video) {
          await (_db.update(_db.faces)..where((f) => f.id.equals(id))).write(
            FacesCompanion(trackId: Value(track?.id ?? id)),
          );
          if (track != null) {
            track.views.add(
              TrackView(
                id: id,
                value: face.embedding,
                quality: face.quality.score,
              ),
            );
          }
        }
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
        if (!faceDbId.containsKey(i)) continue;
        final face = analysis.faces[i];
        final box = _box(face.bbox, w, h);
        await _putDetection(
          media.id,
          'f',
          faceDbId[i]!,
          box,
          frameNumber,
          timestampMs,
          encodeOutline(face.outline, face.bbox),
        );
      }

      // ---- bodies --------------------------------------------------------------------
      final faceOfBody = {
        for (final p in analysis.pairs) p.bodyIndex: p.faceIndex,
      };
      final existingBodies = await _bodiesOfMedia(media.id, frameNumber);
      final usedBodies = <int>{};
      final keptOutfits = <List<double>>[
        for (final b in existingBodies)
          if (b.faceId == null && b.appearance != null) b.appearance!,
      ];
      var keptFaceless = existingBodies.where((b) => b.faceId == null).length;
      final bodyTracks = video
          ? await _bodyTracks(media.id, frameNumber, timestampMs)
          : const <int, Track<List<double>?>>{};
      final faceTrackOf = video
          ? await _trackIds(faceDbId.values)
          : const <int, int>{};
      final usedTracks = {
        for (final e in existingBodies)
          if (e.track != null) e.track!,
      };

      for (var bi = 0; bi < analysis.bodies.length; bi++) {
        final body = analysis.bodies[bi];
        final fi = faceOfBody[bi];
        if (drawn.contains(fi)) continue; // a drawn figure, not a person's body
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
          await _putDetection(
            media.id,
            'b',
            same.id,
            box,
            frameNumber,
            timestampMs,
            encodeOutline(body.outline, body.bbox),
          );
          continue;
        }

        Track<List<double>?>? bodyTrack;
        final faceTrack = faceId == null ? null : faceTrackOf[faceId];
        if (video) {
          if (faceTrack != null) {
            bodyTrack = bodyTracks.values
                .where(
                  (t) => t.faceTrack == faceTrack && !usedTracks.contains(t.id),
                )
                .firstOrNull;
          } else if (faceId == null) {
            bodyTrack = assignTracks<List<double>?>(
              values: [body.appearance],
              boxes: [box],
              timestampMs: timestampMs,
              tracks: bodyTracks.values.where(
                (t) => t.faceTrack == null && !usedTracks.contains(t.id),
              ),
              similarity: outfitSimilarity,
              identity: sameOutfitSimilarity,
              motion: trackMotionOutfit,
            ).single;
          }
          if (bodyTrack != null) {
            usedTracks.add(bodyTrack.id);
            final placement = placeInTrack<List<double>?>(
              bodyTrack,
              body.appearance,
              body.score,
              similarity: outfitSimilarity,
              maxViews: maxBodiesPerTrack,
              diverse: trackDiverseOutfit,
            );
            if (placement
                case LinkView(:final view) || ReplaceView(:final view)) {
              await _putDetection(
                media.id,
                'b',
                view.id,
                box,
                frameNumber,
                timestampMs,
                encodeOutline(body.outline, body.bbox),
              );
              continue;
            }
          } else if (faceId == null &&
              bodyTracks.values.where((t) => t.faceTrack == null).length >=
                  maxFacelessBodiesPerMedia) {
            continue;
          }
        } else if (faceId == null) {
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
        if (fi != null && faceId == null && !ignored.contains(fi)) {
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
                frameNumber: Value(frameNumber),
                timestampMs: Value(timestampMs),
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
        if (video) {
          await (_db.update(_db.bodies)..where((b) => b.id.equals(id))).write(
            BodiesCompanion(trackId: Value(bodyTrack?.id ?? id)),
          );
          final track =
              bodyTrack ?? (bodyTracks[id] = Track(id, faceTrack: faceTrack));
          track.views.add(
            TrackView(id: id, value: body.appearance, quality: body.score),
          );
          usedTracks.add(track.id);
        }
        if (body.cropJpeg != null) {
          final path = await _files.writeBodyCrop(id, body.cropJpeg!);
          await (_db.update(_db.bodies)..where((b) => b.id.equals(id))).write(
            BodiesCompanion(cropPath: Value(path)),
          );
        }
        await _putDetection(
          media.id,
          'b',
          id,
          box,
          frameNumber,
          timestampMs,
          encodeOutline(body.outline, body.bbox),
        );
        newBodies++;
        if (faceId == null) {
          keptFaceless++;
          if (body.appearance != null) keptOutfits.add(body.appearance!);
        }
      }

      newCharacters = await CharacterRepository(_db, _files).store(
        media,
        analysis,
        frameNumber: frameNumber,
        timestampMs: timestampMs,
      );
      await (_db.update(_db.media)..where((m) => m.id.equals(media.id))).write(
        MediaCompanion(
          scanStatus: Value(complete ? 'done' : 'scanning'),
          lastScannedFrame: frameNumber == null
              ? const Value.absent()
              : Value(frameNumber + 1),
          scanVersion: const Value(scanVersion),
          scannedAt: Value(now),
          scanError: const Value(null),
        ),
      );
    });

    if (replaced.isNotEmpty) {
      await _index.remove([for (final (id, _) in replaced) id]);
    }
    await _index.addAll([...newVectors, ...replaced]);
    return StoreOutcome(
      facesSeen: gated.length,
      newFaceIds: newIds,
      linkedFaces: linked,
      newBodies: newBodies,
      newCharacters: newCharacters,
    );
  }

  // ---- helpers ---------------------------------------------------------------------

  _Box _box(BBox pixels, int w, int h) {
    final n = pixels.normalized(w, h);
    return clampBox(n.x, n.y, n.w, n.h);
  }

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  static String _kpsJson(DetectedFace face, int w, int h) => jsonEncode([
    for (final p in face.kps) [_r(p[0] / w), _r(p[1] / h)],
  ]);

  // ---- video tracks ---------------------------------------------------------------

  /// Embeddings change in place only through [_replaceView], so each is read once per video.
  final _vectors = <int, Float32List>{};
  int? _vectorsMedia;

  /// The face tracks of this video, with where each was seen shortly before [frameNumber].
  Future<Map<int, Track<Float32List>>> _faceTracks(
    int mediaId,
    int frameNumber,
    int? timestampMs,
  ) async {
    if (_vectorsMedia != mediaId) {
      _vectors.clear();
      _vectorsMedia = mediaId;
    }
    final rows = await _db
        .customSelect(
          '''
          SELECT f.id, f.track_id, f.quality_score,
            (f.person_id IS NULL AND f.review_dismissed = 0 AND f.hidden = 0
              AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = f.id)
              AND NOT EXISTS (SELECT 1 FROM identity_set_faces s WHERE s.face_id = f.id)
              AND NOT EXISTS (SELECT 1 FROM persons p WHERE p.avatar_face_id = f.id)) AS free
          FROM faces f WHERE f.media_id = ? AND f.track_id IS NOT NULL ORDER BY f.id
          ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.faces},
        )
        .get();
    final missing = [
      for (final r in rows)
        if (!_vectors.containsKey(r.read<int>('id'))) r.read<int>('id'),
    ];
    for (var i = 0; i < missing.length; i += 500) {
      final chunk = missing.sublist(i, math.min(i + 500, missing.length));
      for (final r
          in await _db
              .customSelect(
                'SELECT id, embedding FROM faces WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
                variables: [for (final id in chunk) Variable.withInt(id)],
                readsFrom: {_db.faces},
              )
              .get()) {
        _vectors[r.read<int>('id')] = embeddingFromBlob(
          r.read<Uint8List>('embedding'),
        );
      }
    }
    final tracks = <int, Track<Float32List>>{};
    for (final r in rows) {
      final id = r.read<int>('id');
      final trackId = r.read<int>('track_id');
      tracks
          .putIfAbsent(trackId, () => Track(trackId))
          .views
          .add(
            TrackView(
              id: id,
              value: _vectors[id]!,
              quality: r.read<double>('quality_score'),
              replaceable: r.read<bool>('free'),
            ),
          );
    }
    await _lastSeen('f', 'faces', mediaId, frameNumber, timestampMs, tracks);
    return tracks;
  }

  Future<Map<int, Track<List<double>?>>> _bodyTracks(
    int mediaId,
    int frameNumber,
    int? timestampMs,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT b.id, b.track_id, b.appearance, b.score, f.track_id AS face_track
          FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
          WHERE b.media_id = ? AND b.track_id IS NOT NULL ORDER BY b.id
          ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();
    final tracks = <int, Track<List<double>?>>{};
    for (final r in rows) {
      final appearance = r.readNullable<Uint8List>('appearance');
      final trackId = r.read<int>('track_id');
      final track = tracks.putIfAbsent(trackId, () => Track(trackId));
      track.faceTrack ??= r.readNullable<int>('face_track');
      track.views.add(
        TrackView(
          id: r.read<int>('id'),
          value: appearance == null ? null : appearanceFromBlob(appearance),
          quality: r.read<double>('score'),
        ),
      );
    }
    await _lastSeen('b', 'bodies', mediaId, frameNumber, timestampMs, tracks);
    return tracks;
  }

  /// Fills each track's most recent box before [frameNumber], within the motion gap.
  Future<void> _lastSeen(
    String kind,
    String table,
    int mediaId,
    int frameNumber,
    int? timestampMs,
    Map<int, Track<Object?>> tracks,
  ) async {
    if (tracks.isEmpty) return;
    final rows = await _db
        .customSelect(
          '''
          SELECT t.track_id, d.x, d.y, d.w, d.h, d.timestamp_ms
          FROM media_detections d JOIN $table t ON t.id = d.ref_id
          WHERE d.media_id = ? AND d.kind = ? AND d.frame_number < ?
            AND (?4 IS NULL OR d.timestamp_ms IS NULL OR d.timestamp_ms >= ?4 - $trackMotionGapMs)
            AND t.track_id IS NOT NULL
          ORDER BY d.frame_number DESC
          ''',
          variables: [
            Variable.withInt(mediaId),
            Variable.withString(kind),
            Variable.withInt(frameNumber),
            Variable<int>(timestampMs),
          ],
          readsFrom: {_db.mediaDetections},
        )
        .get();
    for (final r in rows) {
      final track = tracks[r.read<int>('track_id')];
      if (track == null || track.lastBox != null) continue;
      track
        ..lastBox = (
          x: r.read<double>('x'),
          y: r.read<double>('y'),
          w: r.read<double>('w'),
          h: r.read<double>('h'),
        )
        ..lastTimestampMs = r.readNullable<int>('timestamp_ms');
    }
  }

  Future<Map<int, int>> _trackIds(Iterable<int> faceIds) async {
    final ids = faceIds.toSet().toList();
    if (ids.isEmpty) return const {};
    return {
      for (final r
          in await _db
              .customSelect(
                'SELECT id, track_id FROM faces WHERE track_id IS NOT NULL AND id IN (${List.filled(ids.length, '?').join(',')})',
                variables: [for (final id in ids) Variable.withInt(id)],
                readsFrom: {_db.faces},
              )
              .get())
        r.read<int>('id'): r.read<int>('track_id'),
    };
  }

  /// A clearly better view takes the place of the track's weakest untouched one. Detections
  /// that pointed at it still show the same person.
  Future<void> _replaceView(
    int faceId,
    DetectedFace face,
    _Box box,
    int w,
    int h,
    int? frameNumber,
    int? timestampMs,
  ) async {
    await (_db.update(_db.faces)..where((f) => f.id.equals(faceId))).write(
      FacesCompanion(
        embedding: Value(embeddingToBlob(face.embedding)),
        qualityScore: Value(face.quality.score),
        qualityVersion: Value(face.quality.version),
        detScore: Value(face.detScore),
        facePx: Value(face.quality.facePx),
        sharpness: Value(face.quality.sharpness),
        embeddingNorm: Value(face.quality.embeddingNorm),
        yaw: Value(face.quality.pose?.yaw),
        pitch: Value(face.quality.pose?.pitch),
        roll: Value(face.quality.pose?.roll),
        bboxX: Value(box.x),
        bboxY: Value(box.y),
        bboxW: Value(box.w),
        bboxH: Value(box.h),
        kps: Value(_kpsJson(face, w, h)),
        frameNumber: Value(frameNumber),
        timestampMs: Value(timestampMs),
      ),
    );
    _vectors[faceId] = face.embedding;
    if (face.cropJpeg != null) {
      final path = await _files.writeFaceCrop(faceId, face.cropJpeg!);
      await (_db.update(_db.faces)..where((f) => f.id.equals(faceId))).write(
        FacesCompanion(cropPath: Value(path)),
      );
    }
  }

  String _kpts(DetectedBody body, int w, int h) => jsonEncode([
    for (final k in body.kpts ?? const <List<double>>[])
      [_r(k[0] / w), _r(k[1] / h), k[2]],
  ]);

  Future<List<_Existing>> _facesOfMedia(int mediaId, int? frameNumber) async {
    final rows = await _db
        .customSelect(
          'SELECT id, bbox_x, bbox_y, bbox_w, bbox_h, embedding, quality_score, quality_version, track_id FROM faces WHERE media_id = ? AND frame_number IS ?',
          variables: [Variable.withInt(mediaId), Variable<int>(frameNumber)],
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
          r.readNullable<int>('track_id'),
        ),
    ];
  }

  Future<List<_ExistingBody>> _bodiesOfMedia(
    int mediaId,
    int? frameNumber,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT id, face_id, bbox_x, bbox_y, bbox_w, bbox_h, appearance, track_id FROM bodies WHERE media_id = ? AND frame_number IS ?',
          variables: [Variable.withInt(mediaId), Variable<int>(frameNumber)],
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
          r.readNullable<int>('track_id'),
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
    int? frameNumber,
    int? timestampMs, [
    String? outline,
  ]) async {
    await _db.customUpdate(
      'DELETE FROM media_detections WHERE media_id = ? AND kind = ? AND ref_id = ? AND frame_number IS ?',
      variables: [
        Variable.withInt(mediaId),
        Variable.withString(kind),
        Variable.withInt(refId),
        Variable<int>(frameNumber),
      ],
      updates: {_db.mediaDetections},
    );
    await _db
        .into(_db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            frameNumber: Value(frameNumber),
            timestampMs: Value(timestampMs),
            kind: kind,
            refId: refId,
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            outline: Value(outline),
          ),
        );
  }
}

class _ExistingBody {
  _ExistingBody(this.id, this.faceId, this.box, this.appearance, this.track);
  final int id;
  final int? faceId;
  final _Box box;
  final List<double>? appearance;
  final int? track;
}
