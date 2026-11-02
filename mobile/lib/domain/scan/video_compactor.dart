import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/index/embedding_index.dart';
import 'scan_math.dart';
import 'video_tracks.dart';

class CompactResult {
  const CompactResult({
    this.videos = 0,
    this.facesRemoved = 0,
    this.bodiesRemoved = 0,
  });

  final int videos;
  final int facesRemoved;
  final int bodiesRemoved;

  CompactResult operator +(CompactResult o) => CompactResult(
    videos: videos + o.videos,
    facesRemoved: facesRemoved + o.facesRemoved,
    bodiesRemoved: bodiesRemoved + o.bodiesRemoved,
  );
}

class _Row {
  _Row({
    required this.id,
    required this.box,
    required this.timestampMs,
    required this.frame,
    required this.quality,
    required this.personId,
    required this.flags,
    required this.pinned,
    required this.rejected,
  });

  final int id;
  final NormBox box;
  final int? timestampMs;
  final int frame;
  final double quality;
  final int? personId;

  /// Everything else that must match before two rows can become one (dismissed/hidden, link).
  final String flags;

  /// Referenced by something the user made (cover, identity set): never removed.
  final bool pinned;
  final Set<int> rejected;
}

/// Turns videos scanned before tracking (a face and a body row for every sampled frame) into
/// tracks, the way the scan now stores them. A removed row's detections, bodies, corrections and
/// review suggestions move to the view of its track that stays; rows the user made a decision
/// about are only merged into rows that agree with it. One video per transaction.
class VideoCompactor {
  VideoCompactor({required this._db, required this._files, this._index});

  final AppDatabase _db;
  final FileStore _files;
  final EmbeddingIndex? _index;

  /// Scanned videos that still have rows outside any track.
  Future<List<int>> pendingVideos() async => [
    for (final r
        in await _db
            .customSelect(
              '''
              SELECT m.id FROM media m WHERE m.kind = 'video' AND m.scan_status = 'done' AND (
                EXISTS (SELECT 1 FROM faces f WHERE f.media_id = m.id AND f.kind = 'person' AND f.frame_number IS NOT NULL AND f.track_id IS NULL)
                OR EXISTS (SELECT 1 FROM bodies b WHERE b.media_id = m.id AND b.kind = 'person' AND b.frame_number IS NOT NULL AND b.track_id IS NULL))
              ORDER BY m.id
              ''',
              readsFrom: {_db.media, _db.faces, _db.bodies},
            )
            .get())
      r.read<int>('id'),
  ];

  Stream<int> watchPendingCount() => _db
      .customSelect(
        '''
        SELECT COUNT(*) AS n FROM media m WHERE m.kind = 'video' AND m.scan_status = 'done' AND (
          EXISTS (SELECT 1 FROM faces f WHERE f.media_id = m.id AND f.kind = 'person' AND f.frame_number IS NOT NULL AND f.track_id IS NULL)
          OR EXISTS (SELECT 1 FROM bodies b WHERE b.media_id = m.id AND b.kind = 'person' AND b.frame_number IS NOT NULL AND b.track_id IS NULL))
        ''',
        readsFrom: {_db.media, _db.faces, _db.bodies},
      )
      .watchSingle()
      .map((r) => r.read<int>('n'));

  Future<CompactResult> compactAll({
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final videos = await pendingVideos();
    var total = const CompactResult();
    for (var i = 0; i < videos.length; i++) {
      if (cancelled?.call() ?? false) break;
      onProgress?.call(i, videos.length);
      total += await compactVideo(videos[i]);
    }
    onProgress?.call(videos.length, videos.length);
    return total;
  }

  Future<CompactResult> compactVideo(int mediaId) async {
    final crops = <String?>[];
    final droppedFaces = <int>[];
    var bodiesRemoved = 0;
    await _db.transaction(() async {
      final faceMerge = await _trackFaces(mediaId);
      droppedFaces.addAll(faceMerge.keys);
      crops.addAll(await _apply('faces', 'f', faceMerge));
      final bodyMerge = await _trackBodies(mediaId);
      bodiesRemoved = bodyMerge.length;
      crops.addAll(await _apply('bodies', 'b', bodyMerge));
    });
    _db.markTablesUpdated([
      _db.faces,
      _db.bodies,
      _db.mediaDetections,
      _db.faceRejections,
      _db.bodyRejections,
      _db.reviewMatches,
      _db.reviewBodyLinks,
    ]);
    await _files.deleteAll(crops);
    if (droppedFaces.isNotEmpty) await _index?.remove(droppedFaces);
    return CompactResult(
      videos: 1,
      facesRemoved: droppedFaces.length,
      bodiesRemoved: bodiesRemoved,
    );
  }

  // ---- faces --------------------------------------------------------------------------

  /// Re-tracks every face of the video; returns removed row -> the row that stays.
  Future<Map<int, int>> _trackFaces(int mediaId) async {
    final rejections = await _rejections(
      'face_rejections',
      'face_id',
      'faces',
      mediaId,
    );
    final rows = await _db
        .customSelect(
          '''
          SELECT f.id, f.embedding, f.quality_score, f.person_id, f.review_dismissed, f.hidden, f.ownership,
            f.bbox_x, f.bbox_y, f.bbox_w, f.bbox_h, f.timestamp_ms, f.frame_number,
            (EXISTS (SELECT 1 FROM identity_set_faces s WHERE s.face_id = f.id)
              OR EXISTS (SELECT 1 FROM persons p WHERE p.avatar_face_id = f.id)) AS pinned
          FROM faces f WHERE f.media_id = ? AND f.kind = 'person' AND f.frame_number IS NOT NULL
          ORDER BY f.frame_number, f.id
          ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.faces},
        )
        .get();
    final byId = <int, _Row>{};
    final frames = <int, List<(_Row, Float32List)>>{};
    for (final r in rows) {
      final row = _Row(
        id: r.read<int>('id'),
        box: (
          x: r.read<double>('bbox_x'),
          y: r.read<double>('bbox_y'),
          w: r.read<double>('bbox_w'),
          h: r.read<double>('bbox_h'),
        ),
        timestampMs: r.readNullable<int>('timestamp_ms'),
        frame: r.read<int>('frame_number'),
        quality: r.read<double>('quality_score'),
        personId: r.readNullable<int>('person_id'),
        flags:
            '${r.read<bool>('review_dismissed')}:${r.read<bool>('hidden')}:${r.readNullable<String>('ownership') ?? ''}',
        pinned: r.read<bool>('pinned'),
        rejected: rejections[r.read<int>('id')] ?? const {},
      );
      byId[row.id] = row;
      frames.putIfAbsent(row.frame, () => []).add((
        row,
        embeddingFromBlob(r.read<Uint8List>('embedding')),
      ));
    }
    return _track<Float32List>(
      frames: frames,
      byId: byId,
      similarity: faceSimilarity,
      identity: trackIdentityCosine,
      motion: trackMotionCosine,
      maxViews: maxFacesPerTrack,
      diverse: trackDiverseCosine,
      table: 'faces',
    );
  }

  // ---- bodies -------------------------------------------------------------------------

  Future<Map<int, int>> _trackBodies(int mediaId) async {
    final rejections = await _rejections(
      'body_rejections',
      'body_id',
      'bodies',
      mediaId,
    );
    final rows = await _db
        .customSelect(
          '''
          SELECT b.id, b.appearance, b.score, b.person_id, b.link_method, b.face_id, b.ownership, b.hidden,
            f.track_id AS face_track, b.bbox_x, b.bbox_y, b.bbox_w, b.bbox_h,
            b.timestamp_ms, b.frame_number
          FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
          WHERE b.media_id = ? AND b.kind = 'person' AND b.frame_number IS NOT NULL
          ORDER BY b.frame_number, b.id
          ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();
    final byId = <int, _Row>{};
    final faceTrackOf = <int, int?>{};
    final frames = <int, List<(_Row, List<double>?)>>{};
    for (final r in rows) {
      final row = _Row(
        id: r.read<int>('id'),
        box: (
          x: r.read<double>('bbox_x'),
          y: r.read<double>('bbox_y'),
          w: r.read<double>('bbox_w'),
          h: r.read<double>('bbox_h'),
        ),
        timestampMs: r.readNullable<int>('timestamp_ms'),
        frame: r.read<int>('frame_number'),
        quality: r.read<double>('score'),
        personId: r.readNullable<int>('person_id'),
        // a body with a face only merges into one of the same face track (or a faceless view)
        flags:
            '${r.readNullable<String>('link_method') ?? ''}:${r.readNullable<String>('ownership') ?? ''}:${r.read<bool>('hidden') ? 1 : 0}',
        pinned: false,
        rejected: rejections[r.read<int>('id')] ?? const {},
      );
      byId[row.id] = row;
      faceTrackOf[row.id] = r.readNullable<int>('face_id') == null
          ? null
          : r.readNullable<int>('face_track') ?? -r.read<int>('face_id');
      final appearance = r.readNullable<Uint8List>('appearance');
      frames.putIfAbsent(row.frame, () => []).add((
        row,
        appearance == null ? null : appearanceFromBlob(appearance),
      ));
    }
    return _track<List<double>?>(
      frames: frames,
      byId: byId,
      similarity: outfitSimilarity,
      identity: sameOutfitSimilarity,
      motion: trackMotionOutfit,
      maxViews: maxBodiesPerTrack,
      diverse: trackDiverseOutfit,
      table: 'bodies',
      faceTrackOf: faceTrackOf,
    );
  }

  // ---- shared -------------------------------------------------------------------------

  /// Walks the frames in order exactly like the scan does. Sets every kept row's track id and
  /// returns removed row -> kept row.
  Future<Map<int, int>> _track<V>({
    required Map<int, List<(_Row, V)>> frames,
    required Map<int, _Row> byId,
    required double Function(V, V) similarity,
    required double identity,
    required double motion,
    required int maxViews,
    required double diverse,
    required String table,
    Map<int, int?>? faceTrackOf,
  }) async {
    final tracks = <Track<V>>[];
    final byFaceTrack = <int, Track<V>>{};
    final merge = <int, int>{};
    final trackOf = <int, int>{};

    bool canMerge(_Row d, _Row r) =>
        !d.pinned &&
        d.personId == r.personId &&
        d.flags == r.flags &&
        (r.personId == null || !d.rejected.contains(r.personId));

    TrackView<V> view(_Row row, V value) => TrackView(
      id: row.id,
      value: value,
      quality: row.quality,
      replaceable: !row.pinned,
    );

    for (final frame in frames.keys.toList()..sort()) {
      final items = frames[frame]!;
      final timestamp = items.first.$1.timestampMs;
      final found = List<Track<V>?>.filled(items.length, null);
      final used = <Track<V>>{};
      final loose = <int>[];
      for (var i = 0; i < items.length; i++) {
        final faceTrack = faceTrackOf?[items[i].$1.id];
        if (faceTrack == null) {
          loose.add(i);
          continue;
        }
        final t = byFaceTrack[faceTrack];
        if (t != null && used.add(t)) found[i] = t;
      }
      final assigned = assignTracks<V>(
        values: [for (final i in loose) items[i].$2],
        boxes: [for (final i in loose) items[i].$1.box],
        timestampMs: timestamp,
        tracks: tracks.where((t) => !used.contains(t) && t.faceTrack == null),
        similarity: similarity,
        identity: identity,
        motion: motion,
      );
      for (var n = 0; n < loose.length; n++) {
        found[loose[n]] = assigned[n];
      }

      for (var i = 0; i < items.length; i++) {
        final (row, value) = items[i];
        var t = found[i];
        if (t == null) {
          final faceTrack = faceTrackOf?[row.id];
          t = Track<V>(row.id, faceTrack: faceTrack);
          tracks.add(t);
          if (faceTrack != null) byFaceTrack[faceTrack] = t;
          t.views.add(view(row, value));
        } else {
          switch (placeInTrack<V>(
            t,
            value,
            row.quality,
            similarity: similarity,
            maxViews: maxViews,
            diverse: diverse,
          )) {
            case InsertView():
              t.views.add(view(row, value));
            case LinkView():
              // the closest view may carry another decision: take the closest that agrees
              TrackView<V>? into;
              var best = -2.0;
              for (final v in t.views) {
                final s = similarity(v.value, value);
                if (s > best && canMerge(row, byId[v.id]!)) {
                  best = s;
                  into = v;
                }
              }
              if (into != null) {
                merge[row.id] = into.id;
              } else {
                t.views.add(view(row, value));
              }
            case ReplaceView(view: final weak):
              final old = byId[weak.id]!;
              if (canMerge(old, row)) {
                merge[old.id] = row.id;
                t.views
                  ..remove(weak)
                  ..add(view(row, value));
              } else {
                t.views.add(view(row, value));
              }
          }
        }
        trackOf[row.id] = t.id;
        t
          ..lastBox = row.box
          ..lastTimestampMs = row.timestampMs;
      }
    }

    int root(int id) {
      var r = id;
      while (merge[r] != null) {
        r = merge[r]!;
      }
      return r;
    }

    final resolved = {for (final d in merge.keys) d: root(d)};
    // The id of a track is its first row; it stays the id even if that row was merged away.
    final kept = <int, List<int>>{};
    for (final e in trackOf.entries) {
      if (!resolved.containsKey(e.key)) {
        kept.putIfAbsent(e.value, () => []).add(e.key);
      }
    }
    for (final e in kept.entries) {
      for (var i = 0; i < e.value.length; i += 500) {
        final chunk = e.value.sublist(i, math.min(i + 500, e.value.length));
        await _db.customStatement(
          'UPDATE $table SET track_id = ? WHERE id IN (${List.filled(chunk.length, '?').join(',')})',
          [e.key, ...chunk],
        );
      }
    }
    return resolved;
  }

  Future<Map<int, Set<int>>> _rejections(
    String table,
    String column,
    String owner,
    int mediaId,
  ) async {
    final out = <int, Set<int>>{};
    for (final r
        in await _db
            .customSelect(
              'SELECT r.$column AS id, r.person_id FROM $table r JOIN $owner o ON o.id = r.$column WHERE o.media_id = ?',
              variables: [Variable.withInt(mediaId)],
            )
            .get()) {
      out
          .putIfAbsent(r.read<int>('id'), () => {})
          .add(r.read<int>('person_id'));
    }
    return out;
  }

  /// Moves everything that pointed at a removed row to the row that stays, then removes it.
  /// Returns the crops to delete once the transaction is committed.
  Future<List<String?>> _apply(
    String table,
    String kind,
    Map<int, int> merge,
  ) async {
    if (merge.isEmpty) return const [];
    await _db.customStatement(
      'CREATE TEMP TABLE IF NOT EXISTS compact_map (d INTEGER PRIMARY KEY, r INTEGER NOT NULL)',
    );
    await _db.customStatement('DELETE FROM compact_map');
    final pairs = merge.entries.toList();
    for (var i = 0; i < pairs.length; i += 400) {
      final chunk = pairs.sublist(i, math.min(i + 400, pairs.length));
      await _db.customStatement(
        'INSERT INTO compact_map (d, r) VALUES ${List.filled(chunk.length, '(?, ?)').join(', ')}',
        [
          for (final e in chunk) ...[e.key, e.value],
        ],
      );
    }
    const moved = 'SELECT r FROM compact_map WHERE d =';
    await _db.customStatement(
      "UPDATE media_detections SET ref_id = ($moved media_detections.ref_id) WHERE kind = '$kind' AND ref_id IN (SELECT d FROM compact_map)",
    );
    if (table == 'faces') {
      await _db.customStatement(
        'UPDATE bodies SET face_id = ($moved bodies.face_id) WHERE face_id IN (SELECT d FROM compact_map)',
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO face_rejections (face_id, person_id) SELECT m.r, x.person_id FROM face_rejections x JOIN compact_map m ON m.d = x.face_id',
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO review_matches (face_id, person_id, score, margin, decision) SELECT m.r, x.person_id, x.score, x.margin, x.decision FROM review_matches x JOIN compact_map m ON m.d = x.face_id',
      );
    } else {
      await _db.customStatement(
        'INSERT OR IGNORE INTO body_rejections (body_id, person_id) SELECT m.r, x.person_id FROM body_rejections x JOIN compact_map m ON m.d = x.body_id',
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO review_body_links (body_id, person_id, method, confidence) SELECT m.r, x.person_id, x.method, x.confidence FROM review_body_links x JOIN compact_map m ON m.d = x.body_id',
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO body_distinct (body_a, body_b) SELECT CASE WHEN m.r < x.body_b THEN m.r ELSE x.body_b END, CASE WHEN m.r < x.body_b THEN x.body_b ELSE m.r END FROM body_distinct x JOIN compact_map m ON m.d = x.body_a WHERE m.r != x.body_b',
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO body_distinct (body_a, body_b) SELECT CASE WHEN x.body_a < m.r THEN x.body_a ELSE m.r END, CASE WHEN x.body_a < m.r THEN m.r ELSE x.body_a END FROM body_distinct x JOIN compact_map m ON m.d = x.body_b WHERE m.r != x.body_a',
      );
    }
    final crops = [
      for (final r
          in await _db
              .customSelect(
                'SELECT crop_path FROM $table WHERE id IN (SELECT d FROM compact_map)',
              )
              .get())
        r.readNullable<String>('crop_path'),
    ];
    await _db.customStatement(
      'DELETE FROM $table WHERE id IN (SELECT d FROM compact_map)',
    );
    await _db.customStatement('DELETE FROM compact_map');
    return crops;
  }
}
