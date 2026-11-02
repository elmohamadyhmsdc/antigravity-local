import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/index/embedding_index.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/app_settings.dart';
import '../../data/repositories/kind_corrections.dart';
import '../../data/repositories/library_repository.dart';
import 'photo_result_store.dart';
import 'scan_math.dart';

typedef _Box = ({double x, double y, double w, double h});

/// What a re-detect looks for again.
enum RedetectPart { faces, bodies, both }

/// A re-detect looks harder than the library scan: the PC's full resolution and lower gates.
const redetectMaxSide = 4096;
const redetectBodyScore = 0.30;
const redetectMinQuality = 0.30;

class RedetectOutcome {
  const RedetectOutcome({
    required this.faces,
    required this.bodies,
    this.skippedVideos = 0,
  });

  /// Faces / bodies in the re-detected photos afterwards.
  final int faces;
  final int bodies;

  /// Videos are not re-detected here.
  final int skippedVideos;
}

class _Old {
  _Old(this.id, this.kind, this.box, this.personId);
  final int id;
  final String kind;
  final _Box box;
  final int? personId;
  bool hidden = false, dismissed = false;
  String? ownership;
  String? linkMethod;
  double? linkConfidence;
  List<int> rejected = const [];
}

/// Detects the faces and/or bodies of a photo again on the PC, more sensitively than the scan,
/// and replaces the old boxes. Whoever an old box belonged to (person or character), its hidden
/// flag and "not this person" decisions move to the new box found at the same place. The file's
/// person/character corrections are sent as in a scan.
class Redetector {
  Redetector({
    required this.db,
    required this.files,
    required this.index,
    required this.store,
    required this.media,
    required this.settings,
    required this._api,
  });

  final AppDatabase db;
  final FileStore files;
  final EmbeddingIndex index;
  final PhotoResultStore store;
  final MediaLibrary media;
  final AppSettings settings;
  final MobileApi? Function() _api;

  /// Re-detects one photo. Null when it is not a photo (videos are skipped) or gone.
  Future<RedetectOutcome?> photo(int mediaId, RedetectPart part) async {
    final api = _api();
    if (api == null) throw StateError('Pair with the PC first.');
    final row = await _media(mediaId);
    if (row == null || row.kind != 'photo') return null;
    final bytes = await media.downscaledJpeg(
      row.assetId,
      width: row.width ?? 0,
      height: row.height ?? 0,
      maxSide: redetectMaxSide,
    );
    if (bytes == null) throw StateError('The photo could not be read.');
    final prefs = await settings.load();
    final caps = await api.capabilities();
    final corrections = await LibraryRepository(
      db,
    ).kindCorrections(row.assetId);
    final response = await api.analyzeImage(
      bytes,
      options: AnalyzeOptions(
        detectBodies: true,
        detectCharacters: row.illustrated || caps.engines.characterDetection,
        minQuality: redetectMinQuality,
        bodyScore: redetectBodyScore,
        modelId: prefs.modelId,
        facelessCharacters: row.illustrated,
        forceKind: corrections.forceKind,
        kindOverrides: corrections.dtos(),
      ),
    );
    if (response.faces.isNotEmpty &&
        prefs.modelId != null &&
        response.modelId != prefs.modelId) {
      throw StateError('The PC uses a different face model than this library.');
    }

    // The answer is here, so only local writes follow.
    final redoFaces = part != RedetectPart.bodies;
    final redoBodies = part != RedetectPart.faces;
    final oldFaces = await _oldFaces(mediaId);
    final oldBodies = await _oldBodies(mediaId);
    final removed = await _removeHere(
      mediaId,
      faceIds: redoFaces ? [for (final f in oldFaces) f.id] : const [],
      bodyIds: redoBodies ? [for (final b in oldBodies) b.id] : const [],
    );
    final fresh = await _media(mediaId);
    if (fresh == null) return null;
    await store.store(
      fresh,
      _keep(
        response,
        keepFaces: redoFaces ? null : oldFaces,
        keepBodies: redoBodies ? null : oldBodies,
      ),
    );
    await _carryOver(
      mediaId,
      faces: redoFaces ? oldFaces : const [],
      bodies: redoBodies ? oldBodies : const [],
      removed: removed,
    );
    return RedetectOutcome(
      faces: (await _oldFaces(mediaId)).length,
      bodies: (await _oldBodies(mediaId)).length,
    );
  }

  /// Re-detects every photo a person (or character) is seen in. `progress(done, total)`;
  /// `cancelled` is checked between photos.
  Future<RedetectOutcome> person(
    int personId,
    RedetectPart part, {
    void Function(int done, int total)? progress,
    bool Function()? cancelled,
  }) async {
    final rows = await db
        .customSelect(
          '''SELECT DISTINCT m.id, m.kind FROM media m WHERE m.id IN (
               SELECT media_id FROM faces WHERE person_id = ?1
               UNION SELECT media_id FROM bodies WHERE person_id = ?1
               UNION SELECT b.media_id FROM bodies b JOIN faces f ON f.id = b.face_id
                 WHERE f.person_id = ?1) ORDER BY m.id''',
          variables: [Variable.withInt(personId)],
          readsFrom: {db.media, db.faces, db.bodies},
        )
        .get();
    final photos = [
      for (final r in rows)
        if (r.read<String>('kind') == 'photo') r.read<int>('id'),
    ];
    var faces = 0, bodies = 0;
    for (var i = 0; i < photos.length; i++) {
      if (cancelled?.call() ?? false) break;
      progress?.call(i, photos.length);
      final out = await photo(photos[i], part);
      faces += out?.faces ?? 0;
      bodies += out?.bodies ?? 0;
    }
    progress?.call(photos.length, photos.length);
    return RedetectOutcome(
      faces: faces,
      bodies: bodies,
      skippedVideos: rows.length - photos.length,
    );
  }

  // ---- helpers ---------------------------------------------------------------------

  /// This photo's boxes go. A row that other files also show (the same face linked from a
  /// duplicate photo) stays for them; only its box here goes, and the store finds it again.
  /// Returns the rows that were deleted.
  Future<({Set<int> faces, Set<int> bodies})> _removeHere(
    int mediaId, {
    required List<int> faceIds,
    required List<int> bodyIds,
  }) async {
    final drop = <String, List<int>>{};
    for (final (part, ids) in [('f', faceIds), ('b', bodyIds)]) {
      if (ids.isEmpty) continue;
      final marks = List.filled(ids.length, '?').join(',');
      final vars = [for (final i in ids) Variable.withInt(i)];
      final shared = {
        for (final r
            in await db
                .customSelect(
                  'SELECT DISTINCT ref_id FROM media_detections WHERE kind = ? AND media_id != ? '
                  'AND ref_id IN ($marks)',
                  variables: [
                    Variable.withString(part),
                    Variable.withInt(mediaId),
                    ...vars,
                  ],
                  readsFrom: {db.mediaDetections},
                )
                .get())
          r.read<int>('ref_id'),
      };
      await db.customUpdate(
        'DELETE FROM media_detections WHERE kind = ? AND media_id = ? AND ref_id IN ($marks)',
        variables: [
          Variable.withString(part),
          Variable.withInt(mediaId),
          ...vars,
        ],
        updates: {db.mediaDetections},
      );
      drop[part] = [
        for (final i in ids)
          if (!shared.contains(i)) i,
      ];
    }
    await KindCorrections(db, files, index: index).removeDetections(
      faceIds: drop['f'] ?? const [],
      bodyIds: drop['b'] ?? const [],
    );
    return (faces: {...?drop['f']}, bodies: {...?drop['b']});
  }

  /// The answer without the part that is not re-detected: of that part only what matches a
  /// kept row stays (so the store refreshes and links it instead of adding a new one).
  AnalyzeImageResponse _keep(
    AnalyzeImageResponse r, {
    List<_Old>? keepFaces,
    List<_Old>? keepBodies,
  }) {
    if (keepFaces == null && keepBodies == null) return r;
    final w = r.imageW, h = r.imageH;
    bool kept(List<_Old>? old, BBox box, String kind, String part) =>
        old == null ||
        old.any(
          (o) =>
              o.kind == kind && sameDetectionBox(o.box, _norm(box, w, h), part),
        );
    final faceAt = <int, int>{};
    final faces = <DetectedFace>[];
    for (var i = 0; i < r.faces.length; i++) {
      final f = r.faces[i];
      // A face below the gate is no row, only evidence for its body: it can stay.
      if (f.passesGate && !kept(keepFaces, f.bbox, 'person', 'face')) continue;
      faceAt[i] = faces.length;
      faces.add(f);
    }
    final bodyAt = <int, int>{};
    final bodies = <DetectedBody>[];
    for (var i = 0; i < r.bodies.length; i++) {
      if (!kept(keepBodies, r.bodies[i].bbox, 'person', 'body')) continue;
      bodyAt[i] = bodies.length;
      bodies.add(r.bodies[i]);
    }
    final characters = <DetectedCharacter>[];
    for (final c in r.characters) {
      final face =
          c.face != null && kept(keepFaces, c.face!.bbox, 'character', 'face')
          ? c.face
          : null;
      final body =
          c.body != null && kept(keepBodies, c.body!.bbox, 'character', 'body')
          ? c.body
          : null;
      // The old PC's whole-figure character (no face, no body) is stored as a body.
      final figure = c.face == null && c.body == null;
      if (face == null &&
          body == null &&
          !(figure && kept(keepBodies, c.bbox, 'character', 'body'))) {
        continue;
      }
      characters.add(
        DetectedCharacter(
          bbox: c.bbox,
          score: c.score,
          descriptor: c.descriptor,
          modelId: c.modelId,
          cropJpeg: c.cropJpeg,
          face: face,
          body: body,
        ),
      );
    }
    return AnalyzeImageResponse(
      modelId: r.modelId,
      imageW: w,
      imageH: h,
      faces: faces,
      bodies: bodies,
      pairs: [
        for (final p in r.pairs)
          if (faceAt.containsKey(p.faceIndex) &&
              bodyAt.containsKey(p.bodyIndex))
            FaceBodyPair(
              faceIndex: faceAt[p.faceIndex]!,
              bodyIndex: bodyAt[p.bodyIndex]!,
              score: p.score,
            ),
      ],
      timingsMs: r.timingsMs,
      characters: characters,
    );
  }

  /// Each old box hands what was decided about it to the closest new box of its kind.
  Future<void> _carryOver(
    int mediaId, {
    required List<_Old> faces,
    required List<_Old> bodies,
    required ({Set<int> faces, Set<int> bodies}) removed,
  }) => db.transaction(() async {
    final gone = removed.faces;
    final newFaces = [
      for (final f in await _oldFaces(mediaId))
        if (!gone.contains(f.id)) f,
    ];
    final taken = <int>{};
    for (final old in faces) {
      final next = _closest(old, newFaces, 'face', taken);
      if (next == null) continue;
      taken.add(next.id);
      if (old.personId != null && next.personId == null) {
        final p = Variable.withInt(old.personId!);
        // Only to someone who still exists: the box may have been the last of a deleted group.
        await db.customUpdate(
          'UPDATE faces SET person_id = ? WHERE id = ? AND EXISTS (SELECT 1 FROM persons WHERE id = ?)',
          variables: [p, Variable.withInt(next.id), p],
          updates: {db.faces},
        );
      }
      await db.customUpdate(
        'UPDATE faces SET hidden = ?, review_dismissed = ?, ownership = ? WHERE id = ?',
        variables: [
          Variable.withBool(old.hidden),
          Variable.withBool(old.dismissed),
          Variable<String>(old.ownership),
          Variable.withInt(next.id),
        ],
        updates: {db.faces},
      );
      for (final pid in old.rejected) {
        await db
            .into(db.faceRejections)
            .insert(
              FaceRejectionsCompanion.insert(faceId: next.id, personId: pid),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
    final goneBodies = removed.bodies;
    final newBodies = [
      for (final b in await _oldBodies(mediaId))
        if (!goneBodies.contains(b.id)) b,
    ];
    taken.clear();
    for (final old in bodies) {
      final next = _closest(old, newBodies, 'body', taken);
      if (next == null) continue;
      taken.add(next.id);
      if (old.personId != null && next.personId == null) {
        final p = Variable.withInt(old.personId!);
        await db.customUpdate(
          'UPDATE bodies SET person_id = ?, link_method = ?, link_confidence = ? '
          'WHERE id = ? AND EXISTS (SELECT 1 FROM persons WHERE id = ?)',
          variables: [
            p,
            Variable<String>(old.linkMethod),
            Variable<double>(old.linkConfidence),
            Variable.withInt(next.id),
            p,
          ],
          updates: {db.bodies},
        );
      }
      await db.customUpdate(
        'UPDATE bodies SET hidden = ?, ownership = ? WHERE id = ?',
        variables: [
          Variable.withBool(old.hidden),
          Variable<String>(old.ownership),
          Variable.withInt(next.id),
        ],
        updates: {db.bodies},
      );
      for (final pid in old.rejected) {
        await db
            .into(db.bodyRejections)
            .insert(
              BodyRejectionsCompanion.insert(bodyId: next.id, personId: pid),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await db.customUpdate(
        'UPDATE OR REPLACE body_distinct SET body_a = ? WHERE body_a = ?',
        variables: [Variable.withInt(next.id), Variable.withInt(old.id)],
        updates: {db.bodyDistinct},
      );
      await db.customUpdate(
        'UPDATE OR REPLACE body_distinct SET body_b = ? WHERE body_b = ?',
        variables: [Variable.withInt(next.id), Variable.withInt(old.id)],
        updates: {db.bodyDistinct},
      );
    }
    final mediaRow = await _media(mediaId);
    if (mediaRow != null) {
      final overrides = await (db.select(
        db.bodyOverrides,
      )..where((o) => o.assetId.equals(mediaRow.assetId))).get();
      for (final o in overrides) {
        for (final next in newBodies) {
          if (sameDetectionBox(
            (x: o.x, y: o.y, w: o.w, h: o.h),
            next.box,
            'body',
          )) {
            await (db.update(
              db.bodies,
            )..where((b) => b.id.equals(next.id))).write(
              BodiesCompanion(
                ownership: Value(o.ownership),
                hidden: Value(o.hidden),
              ),
            );
          }
        }
      }
    }
  });

  _Old? _closest(_Old old, List<_Old> candidates, String part, Set<int> taken) {
    _Old? best;
    var bestScore = -1.0;
    for (final c in candidates) {
      if (taken.contains(c.id) || c.kind != old.kind) continue;
      if (!sameDetectionBox(old.box, c.box, part)) continue;
      final score = _overlap(old.box, c.box);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  static double _overlap(_Box a, _Box b) {
    final ix =
        (a.x + a.w < b.x + b.w ? a.x + a.w : b.x + b.w) -
        (a.x > b.x ? a.x : b.x);
    final iy =
        (a.y + a.h < b.y + b.h ? a.y + a.h : b.y + b.h) -
        (a.y > b.y ? a.y : b.y);
    return ix > 0 && iy > 0 ? ix * iy : 0;
  }

  static _Box _norm(BBox box, int w, int h) {
    final n = box.normalized(w, h);
    return clampBox(n.x, n.y, n.w, n.h); // as PhotoResultStore stores it
  }

  Future<List<_Old>> _oldFaces(int mediaId) async {
    final rows = await db
        .customSelect(
          // The boxes this photo shows, whichever file the face row came from.
          '''SELECT f.id, f.kind, f.person_id, f.hidden, f.review_dismissed, f.ownership,
               d.x AS bbox_x, d.y AS bbox_y, d.w AS bbox_w, d.h AS bbox_h,
               (SELECT group_concat(person_id) FROM face_rejections r WHERE r.face_id = f.id) AS rejected
             FROM media_detections d JOIN faces f ON f.id = d.ref_id
             WHERE d.media_id = ? AND d.kind = 'f' AND d.frame_number IS NULL''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.faces, db.faceRejections, db.mediaDetections},
        )
        .get();
    return [
      for (final r in rows)
        _Old(r.read<int>('id'), r.read<String>('kind'), (
            x: r.read<double>('bbox_x'),
            y: r.read<double>('bbox_y'),
            w: r.read<double>('bbox_w'),
            h: r.read<double>('bbox_h'),
          ), r.readNullable<int>('person_id'))
          ..hidden = r.read<bool>('hidden')
          ..dismissed = r.read<bool>('review_dismissed')
          ..ownership = r.readNullable<String>('ownership')
          ..rejected = [
            for (final s in (r.readNullable<String>('rejected') ?? '').split(
              ',',
            ))
              if (s.isNotEmpty) int.parse(s),
          ],
    ];
  }

  Future<List<_Old>> _oldBodies(int mediaId) async {
    final rows = await db
        .customSelect(
          '''SELECT b.id, b.kind, b.person_id, b.link_method, b.link_confidence, b.hidden, b.ownership,
               d.x AS bbox_x, d.y AS bbox_y, d.w AS bbox_w, d.h AS bbox_h,
               (SELECT group_concat(person_id) FROM body_rejections r WHERE r.body_id = b.id) AS rejected
             FROM media_detections d JOIN bodies b ON b.id = d.ref_id
             WHERE d.media_id = ? AND d.kind = 'b' AND d.frame_number IS NULL''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {db.bodies, db.bodyRejections, db.mediaDetections},
        )
        .get();
    return [
      for (final r in rows)
        _Old(r.read<int>('id'), r.read<String>('kind'), (
            x: r.read<double>('bbox_x'),
            y: r.read<double>('bbox_y'),
            w: r.read<double>('bbox_w'),
            h: r.read<double>('bbox_h'),
          ), r.readNullable<int>('person_id'))
          ..linkMethod = r.readNullable<String>('link_method')
          ..linkConfidence = r.readNullable<double>('link_confidence')
          ..hidden = r.read<bool>('hidden')
          ..ownership = r.readNullable<String>('ownership')
          ..rejected = [
            for (final s in (r.readNullable<String>('rejected') ?? '').split(
              ',',
            ))
              if (s.isNotEmpty) int.parse(s),
          ],
    ];
  }

  Future<MediaRow?> _media(int id) =>
      (db.select(db.media)..where((m) => m.id.equals(id))).getSingleOrNull();
}
