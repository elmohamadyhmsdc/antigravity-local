import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../domain/geometry/outline.dart';
import '../../domain/scan/scan_math.dart';
import '../../domain/scan/video_tracks.dart';
import '../api/dtos/analyze.dart';
import '../api/dtos/embedding.dart';
import '../db/app_database.dart';
import '../files/file_store.dart';

typedef _Box = ({double x, double y, double w, double h});

/// A drawn face seen again inside one file (the same drawing in neighbouring frames).
const characterSameFileCosine = 0.90;

/// Characters are stored like people: a face (CCIP identity), a body (outfit), both, or - when
/// the PC only sends the old whole-figure box - a body. They live in `faces`/`bodies` with
/// kind = 'character', so grouping, review, merge and the People screens work on them the same
/// way; every people-only query filters kind = 'person'.
class CharacterRepository {
  CharacterRepository(this.db, this.files);
  final AppDatabase db;
  final FileStore files;

  /// Called inside PhotoResultStore's transaction, before its scan checkpoint. Returns how many
  /// faces and faceless bodies were new.
  Future<int> store(
    MediaRow media,
    AnalyzeImageResponse analysis, {
    int? frameNumber,
    int? timestampMs,
    Map<int, DetectedBody>? bodyEvidence,
  }) async {
    if (analysis.characters.isEmpty) return 0;
    final w = analysis.imageW, h = analysis.imageH;
    final now = DateTime.now().millisecondsSinceEpoch;
    final facesHere = await _faces(media.id);
    final bodiesHere = await _bodies(media.id, frameNumber);
    final usedFaces = <int>{}, usedBodies = <int>{};
    var inserted = 0;
    final video = media.kind == 'video' && frameNumber != null;
    final tracks = video
        ? await _bodyTracks(media.id)
        : <int, Track<List<double>?>>{};
    final usedTracks = {
      for (final b in bodiesHere)
        if (b.track != null) b.track!,
    };

    for (final c in analysis.characters) {
      int? faceId;
      final face = c.face;
      final vector = face?.embedding;
      if (face != null && vector != null) {
        final box = _box(face.bbox, w, h);
        _Face? same;
        for (final f in facesHere) {
          if (!usedFaces.contains(f.id) &&
              f.frame == frameNumber &&
              iou(box, f.box) >= .65) {
            same = f;
            break;
          }
        }
        if (same == null) {
          var best = -1.0;
          for (final f in facesHere) {
            if (usedFaces.contains(f.id)) continue;
            final sim = cosine(f.vector, vector);
            if (sim > best) {
              best = sim;
              same = f;
            }
          }
          if (best < characterSameFileCosine) same = null;
        }
        if (same != null) {
          faceId = same.id;
        } else {
          faceId = await db
              .into(db.faces)
              .insert(
                FacesCompanion.insert(
                  mediaId: Value(media.id),
                  frameNumber: Value(frameNumber),
                  timestampMs: Value(timestampMs),
                  modelId: characterEmbeddingModelId,
                  embedding: embeddingToBlob(vector),
                  qualityScore: face.score,
                  qualityVersion: 100,
                  detScore: face.score,
                  facePx: face.bbox.w > face.bbox.h ? face.bbox.w : face.bbox.h,
                  sharpness: 0,
                  bboxX: box.x,
                  bboxY: box.y,
                  bboxW: box.w,
                  bboxH: box.h,
                  kind: const Value('character'),
                  createdAt: now,
                ),
              );
          if (face.cropJpeg != null) {
            final path = await files.writeFaceCrop(faceId, face.cropJpeg!);
            await (db.update(db.faces)..where((f) => f.id.equals(faceId!)))
                .write(FacesCompanion(cropPath: Value(path)));
          }
          facesHere.add(_Face(faceId, box, vector, frameNumber));
          inserted++;
        }
        if (video) {
          await (db.update(db.faces)..where((f) => f.id.equals(faceId!))).write(
            FacesCompanion(trackId: Value(faceId)),
          );
        }
        usedFaces.add(faceId);
        await _putDetection(
          media.id,
          'f',
          faceId,
          box,
          frameNumber,
          timestampMs,
        );
      }

      // The old PC sent one whole-figure box and no face or body: that box is the body.
      final body =
          c.body ??
          (c.face == null
              ? DetectedBody(bbox: c.bbox, score: c.score, cropJpeg: c.cropJpeg)
              : null);
      if (body == null) continue;
      final box = _box(body.bbox, w, h);
      _Body? same;
      for (final b in bodiesHere) {
        if (!usedBodies.contains(b.id) && iou(box, b.box) >= .65) {
          same = b;
          break;
        }
      }
      if (same != null) {
        if(video) {
          var restored = same.track == null ? null : tracks[same.track];
          restored ??= faceId == null
            ? assignTracks<List<double>?>(values:[body.appearance],boxes:[box],timestampMs:timestampMs,
                tracks:tracks.values.where((t)=>t.faceTrack==null&&!usedTracks.contains(t.id)),
                similarity:outfitSimilarity,identity:sameOutfitSimilarity,motion:trackMotionOutfit).single
            : tracks.values.where((t)=>t.faceTrack==faceId&&!usedTracks.contains(t.id)).firstOrNull;
          final trackId=restored?.id??same.id;
          await (db.update(db.bodies)..where((b)=>b.id.equals(same!.id))).write(BodiesCompanion(trackId:Value(trackId)));
          restored??=tracks[trackId]=Track(trackId,faceTrack:faceId);
          if(!restored.views.any((v)=>v.id==same!.id)) {
            restored.views.add(TrackView(id:same.id,value:body.appearance,quality:body.score));
          }
          usedTracks.add(trackId);
        }
        usedBodies.add(same.id);
        if (bodyEvidence != null) bodyEvidence[same.id] = body;
        await db.customUpdate(
          'UPDATE bodies SET face_id = COALESCE(face_id, ?), kpts = ?, extent = ?, appearance = COALESCE(?, appearance) WHERE id = ?',
          variables: [
            Variable<int>(faceId),
            Variable<String>(_kpts(body, w, h)),
            Variable<String>(body.extent),
            Variable<Uint8List>(
              body.appearance == null
                  ? null
                  : appearanceToBlob(body.appearance!),
            ),
            Variable.withInt(same.id),
          ],
          updates: {db.bodies},
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
      Track<List<double>?>? track;
      if (video) {
        if (faceId != null) {
          track = tracks.values
              .where((t) => t.faceTrack == faceId && !usedTracks.contains(t.id))
              .firstOrNull;
        } else {
          track = assignTracks<List<double>?>(
            values: [body.appearance],
            boxes: [box],
            timestampMs: timestampMs,
            tracks: tracks.values.where(
              (t) => t.faceTrack == null && !usedTracks.contains(t.id),
            ),
            similarity: outfitSimilarity,
            identity: sameOutfitSimilarity,
            motion: trackMotionOutfit,
          ).single;
        }
        if (track != null) {
          usedTracks.add(track.id);
          final placement = placeInTrack<List<double>?>(
            track,
            body.appearance,
            body.score,
            similarity: outfitSimilarity,
            maxViews: maxBodiesPerTrack,
            diverse: trackDiverseOutfit,
          );
          if (placement case LinkView(:final view)) {
            if (bodyEvidence != null) bodyEvidence[view.id] = body;
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
        }
      }
      final id = await db
          .into(db.bodies)
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
              kind: const Value('character'),
              createdAt: now,
            ),
          );
      if (video) {
        await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
          BodiesCompanion(trackId: Value(track?.id ?? id)),
        );
        track ??= tracks[id] = Track(id, faceTrack: faceId);
        track.views.add(
          TrackView(id: id, value: body.appearance, quality: body.score),
        );
        usedTracks.add(track.id);
      }
      if (bodyEvidence != null) bodyEvidence[id] = body;
      if (body.cropJpeg != null) {
        final path = await files.writeBodyCrop(id, body.cropJpeg!);
        await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
          BodiesCompanion(cropPath: Value(path)),
        );
      }
      bodiesHere.add(_Body(id, box, video ? track?.id ?? id : null));
      usedBodies.add(id);
      await _putDetection(
        media.id,
        'b',
        id,
        box,
        frameNumber,
        timestampMs,
        encodeOutline(body.outline, body.bbox),
      );
      if (faceId == null) inserted++;
    }
    return inserted;
  }

  Future<Map<int, Track<List<double>?>>> _bodyTracks(int mediaId) async {
    final rows =
        await (db.select(db.bodies)
              ..where(
                (b) =>
                    b.mediaId.equals(mediaId) &
                    b.kind.equals('character') &
                    b.trackId.isNotNull(),
              )
              ..orderBy([(b) => OrderingTerm.desc(b.timestampMs)]))
            .get();
    final tracks = <int, Track<List<double>?>>{};
    for (final b in rows) {
      final track = tracks.putIfAbsent(
        b.trackId!,
        () => Track(b.trackId!, faceTrack: b.faceId),
      );
      track.views.add(
        TrackView(
          id: b.id,
          value: b.appearance == null
              ? null
              : appearanceFromBlob(b.appearance!),
          quality: b.score,
        ),
      );
    }
    final seen = await db
        .customSelect(
          '''SELECT b.track_id,d.x,d.y,d.w,d.h,d.timestamp_ms
      FROM media_detections d JOIN bodies b ON d.ref_id=b.id AND d.kind='b'
      WHERE d.media_id=? AND b.kind='character' AND b.track_id IS NOT NULL
      ORDER BY d.timestamp_ms DESC''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.bodies, db.mediaDetections},
        )
        .get();
    for (final r in seen) {
      final track = tracks[r.read<int>('track_id')];
      if (track == null || track.lastBox != null) continue;
      track.lastBox = (
        x: r.read<double>('x'),
        y: r.read<double>('y'),
        w: r.read<double>('w'),
        h: r.read<double>('h'),
      );
      track.lastTimestampMs = r.readNullable<int>('timestamp_ms');
    }
    return tracks;
  }

  _Box _box(BBox pixels, int w, int h) {
    final n = pixels.normalized(w, h);
    return clampBox(n.x, n.y, n.w, n.h);
  }

  static double _r(double v) => (v * 10000).roundToDouble() / 10000;

  String _kpts(DetectedBody body, int w, int h) => jsonEncode([
    for (final k in body.kpts ?? const <List<double>>[])
      [_r(k[0] / w), _r(k[1] / h), k[2]],
  ]);

  Future<List<_Face>> _faces(int mediaId) async {
    final rows = await db
        .customSelect(
          "SELECT id, bbox_x, bbox_y, bbox_w, bbox_h, embedding, frame_number FROM faces WHERE media_id = ? AND kind = 'character'",
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.faces},
        )
        .get();
    return [
      for (final r in rows)
        _Face(
          r.read<int>('id'),
          (
            x: r.read<double>('bbox_x'),
            y: r.read<double>('bbox_y'),
            w: r.read<double>('bbox_w'),
            h: r.read<double>('bbox_h'),
          ),
          vectorFromBlob(r.read<Uint8List>('embedding')),
          r.readNullable<int>('frame_number'),
        ),
    ];
  }

  Future<List<_Body>> _bodies(int mediaId, int? frameNumber) async {
    final rows = await db
        .customSelect(
          "SELECT id, bbox_x, bbox_y, bbox_w, bbox_h, track_id FROM bodies WHERE media_id = ? AND frame_number IS ? AND kind = 'character'",
          variables: [Variable.withInt(mediaId), Variable<int>(frameNumber)],
          readsFrom: {db.bodies},
        )
        .get();
    return [
      for (final r in rows)
        _Body(r.read<int>('id'), (
          x: r.read<double>('bbox_x'),
          y: r.read<double>('bbox_y'),
          w: r.read<double>('bbox_w'),
          h: r.read<double>('bbox_h'),
        ), r.readNullable<int>('track_id')),
    ];
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
    await db.customUpdate(
      'DELETE FROM media_detections WHERE media_id = ? AND kind = ? AND ref_id = ? AND frame_number IS ?',
      variables: [
        Variable.withInt(mediaId),
        Variable.withString(kind),
        Variable.withInt(refId),
        Variable<int>(frameNumber),
      ],
      updates: {db.mediaDetections},
    );
    await db
        .into(db.mediaDetections)
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

class _Face {
  _Face(this.id, this.box, this.vector, this.frame);
  final int id;
  final _Box box;
  final Float32List vector;
  final int? frame;
}

class _Body {
  _Body(this.id, this.box, [this.track]);
  final int? track;
  final int id;
  final _Box box;
}
