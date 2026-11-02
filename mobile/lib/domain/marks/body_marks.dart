/// Roadmap Phase 6 (section 7.4): tattoos the user marked on a body of a known person, and the search for the
/// same tattoo on faceless bodies of other photos.
///
/// * The patch is cut from the ORIGINAL photo (not the 512 px crop), kept as `marks/<id>.png` in the private
///   file store (so it travels in the backup), with its position stored relative to the segment's anchor
///   keypoints ([anchorFor]).
/// * A search cuts the same place (and the opposite segment, for mirror selfies) from every faceless body
///   whose anchors are visible and asks the PC to match them (`/v1/analyze/marks`, OpenCV, nothing stored).
/// * A match is only a SUGGESTION ([MarkEvidence]); nothing is linked automatically until Phase 0 shows
///   precision. Patches are biometric data and stay on the phone like face embeddings.
library;

import 'dart:io' show FileSystemException;

import 'package:drift/drift.dart';

import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../pose/pose_geometry.dart';
import 'mark_geometry.dart';
import '../corrections/body_link_guard.dart';

/// Cuts [rect] (a rotated rectangle in the photo's pixels) out of [media]'s original; null when the file is
/// gone or unreadable. The real one decodes the original on the phone; tests pass a fake.
typedef PatchCutter =
    Future<Uint8List?> Function(MediaRow media, MarkRect rect);

class MarkHit {
  const MarkHit({
    required this.bodyId,
    required this.mediaId,
    required this.inliers,
    required this.inlierRatio,
    required this.mirrored,
    required this.evidence,
    required this.viaOppositeSegment,
  });

  final int bodyId;
  final int? mediaId;
  final int inliers;
  final double inlierRatio;
  final bool mirrored;
  final MarkEvidence evidence;
  final bool viaOppositeSegment;
}

class BodyMarkStore {
  BodyMarkStore(this._db, this._files, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final DateTime Function() _clock;

  /// [anchor] comes from [anchorFor]; [patch] is the JPEG cut from the original photo.
  Future<int> create({
    required int personId,
    required String segment,
    required Map<String, dynamic> anchor,
    required Uint8List patch,
    int? sourceBodyId,
    String? label,
  }) async {
    assert(markSegments.contains(segment));
    final id = await _db
        .into(_db.bodyMarks)
        .insert(
          BodyMarksCompanion.insert(
            personId: personId,
            sourceBodyId: Value(sourceBodyId),
            segment: segment,
            anchor: _encode(anchor),
            patchPath: 'pending',
            label: Value(label),
            createdAt: _clock().millisecondsSinceEpoch,
          ),
        );
    // small files (a few tens of KB): written synchronously, so the row and its file never disagree
    final path = 'marks/$id.png';
    final file = _files.resolve(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(patch, flush: true);
    await (_db.update(_db.bodyMarks)..where((m) => m.id.equals(id))).write(
      BodyMarksCompanion(patchPath: Value(path)),
    );
    return id;
  }

  Future<List<BodyMarkRow>> ofPerson(int personId) =>
      (_db.select(_db.bodyMarks)
            ..where((m) => m.personId.equals(personId))
            ..orderBy([(m) => OrderingTerm.desc(m.createdAt)]))
          .get();

  Future<Uint8List?> patchOf(BodyMarkRow mark) async {
    final file = _files.resolve(mark.patchPath);
    return file.existsSync() ? file.readAsBytesSync() : null;
  }

  Future<void> delete(int markId) async {
    final mark = await (_db.select(
      _db.bodyMarks,
    )..where((m) => m.id.equals(markId))).getSingleOrNull();
    if (mark == null) return;
    final file = _files.resolve(mark.patchPath);
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // still shown or locked (Windows): a leftover patch is only wasted space, like an uncollected crop
    }
    await (_db.delete(_db.bodyMarks)..where((m) => m.id.equals(markId))).go();
  }

  static String _encode(Map<String, dynamic> anchor) =>
      '{"c":[${(anchor['c'] as List).join(',')}],"size":[${(anchor['size'] as List).join(',')}]}';
}

class MarkMatcher {
  MarkMatcher(this._db, this._store, this._api);

  final AppDatabase _db;
  final BodyMarkStore _store;
  final MobileApi? Function() _api;

  /// One request carries at most this many bodies (two patches each, the PC's limit is 64 candidates).
  static const bodiesPerRequest = 32;

  Map<String, dynamic> _anchor(BodyMarkRow mark) {
    final c = RegExp(
      r'"c":\[([^\]]*)\]',
    ).firstMatch(mark.anchor)!.group(1)!.split(',');
    final s = RegExp(
      r'"size":\[([^\]]*)\]',
    ).firstMatch(mark.anchor)!.group(1)!.split(',');
    return {
      'c': [for (final v in c) double.parse(v)],
      'size': [for (final v in s) double.parse(v)],
    };
  }

  /// Faceless bodies (nobody's, no face) of photos with a size, whose [segment] anchors are visible; the
  /// ones in the person's own events (within 6 h of one of their bodies) come first.
  Future<List<({BodyRow body, MediaRow media, Pose pose, bool sameEvent})>>
  candidates(BodyMarkRow mark) async {
    final times = [
      for (final r
          in await _db
              .customSelect(
                '''SELECT m.taken_at AS t FROM bodies b JOIN media m ON m.id = b.media_id
               LEFT JOIN faces f ON f.id = b.face_id
               WHERE COALESCE(f.person_id, b.person_id) = ? AND m.taken_at IS NOT NULL''',
                variables: [Variable.withInt(mark.personId)],
                readsFrom: {_db.bodies, _db.media, _db.faces},
              )
              .get())
        r.read<int>('t'),
    ]..sort();
    bool inEvent(int? t) =>
        t != null && times.any((x) => (x - t).abs() <= 6 * 3600 * 1000);
    final rows =
        await (_db.select(_db.bodies)..where(
              (b) =>
                  b.kind.equals('person') &
                  b.personId.isNull() &
                  b.faceId.isNull() &
                  b.kpts.isNotNull(),
            ))
            .get();
    final out = <({BodyRow body, MediaRow media, Pose pose, bool sameEvent})>[];
    final mediaCache = <int, MediaRow?>{};
    for (final b in rows) {
      final mid = b.mediaId;
      if (mid == null || b.id == mark.sourceBodyId) continue;
      final media = mediaCache[mid] ??= await (_db.select(
        _db.media,
      )..where((m) => m.id.equals(mid))).getSingleOrNull();
      if (media == null) continue;
      final pose = Pose.fromJson(
        b.kpts,
        media.width,
        media.height,
        extent: b.extent,
      );
      if (pose == null || !segmentVisible(pose, mark.segment)) continue;
      out.add((
        body: b,
        media: media,
        pose: pose,
        sameEvent: inEvent(media.takenAt),
      ));
    }
    out.sort((a, b) => (b.sameEvent ? 1 : 0) - (a.sameEvent ? 1 : 0));
    return out;
  }

  /// Hits with evidence (best first). Null when the PC is not connected or the mark's patch is gone.
  Future<List<MarkHit>?> search(
    BodyMarkRow mark,
    PatchCutter cutter, {
    int maxBodies = 256,
  }) async {
    final api = _api();
    final reference = await _store.patchOf(mark);
    if (api == null || reference == null) return null;
    final anchor = _anchor(mark);
    final opposite = oppositeSegment(mark.segment);
    final candidates = (await this.candidates(mark)).take(maxBodies).toList();
    final hits = <MarkHit>[];
    for (var start = 0; start < candidates.length; start += bodiesPerRequest) {
      final batch = candidates.skip(start).take(bodiesPerRequest).toList();
      final patches = <Uint8List>[];
      final owners =
          <(int, bool)>[]; // (index in batch, via the opposite segment)
      for (var i = 0; i < batch.length; i++) {
        final c = batch[i];
        for (final (segment, via) in [
          (mark.segment, false),
          if (opposite != mark.segment) (opposite, true),
        ]) {
          final rect = rectFor(c.pose, segment, anchor);
          if (rect == null) continue;
          final bytes = await cutter(c.media, rect);
          if (bytes == null) continue;
          patches.add(bytes);
          owners.add((i, via));
        }
        if (opposite == mark.segment) {
          // torso / pelvis: the flipped patch is tried by the PC itself
        }
      }
      if (patches.isEmpty) continue;
      final response = await api.analyzeMarks(reference, patches);
      final best = <int, MarkHit>{};
      for (final r in response.results) {
        if (r.index >= owners.length) continue;
        final (bodyIndex, via) = owners[r.index];
        final evidence = markEvidence(
          inliers: r.inliers,
          inlierRatio: r.inlierRatio,
        );
        if (evidence == MarkEvidence.none) continue;
        final c = batch[bodyIndex];
        final hit = MarkHit(
          bodyId: c.body.id,
          mediaId: c.media.id,
          inliers: r.inliers,
          inlierRatio: r.inlierRatio,
          mirrored: r.mirrored,
          evidence: evidence,
          viaOppositeSegment: via,
        );
        final old = best[bodyIndex];
        if (old == null || hit.inliers > old.inliers) best[bodyIndex] = hit;
      }
      hits.addAll(best.values);
    }
    hits.sort((a, b) => b.inliers.compareTo(a.inliers));
    return hits;
  }

  /// Puts the hits in the Quick Review queue as `tattoo` suggestions (never as a link): confidence 0.95 for a strong
  /// match, 0.80 for a possible one. The review tables are replaced by every grouping run, so a search can be
  /// repeated; a body that already belongs to someone is left alone.
  Future<int> publishSuggestions(BodyMarkRow mark, List<MarkHit> hits) async {
    var published = 0;
    await _db.transaction(() async {
      for (final h in hits) {
        final owner = await (_db.select(
          _db.bodies,
        )..where((b) => b.id.equals(h.bodyId))).getSingleOrNull();
        if (owner == null ||
            owner.personId != null ||
            owner.faceId != null ||
            owner.ownership == 'none' ||
            owner.hidden) {
          continue;
        }
        if (!await BodyLinkGuard(_db).canAutoLink(h.bodyId, mark.personId)) {
          continue;
        }
        await _db
            .into(_db.reviewBodyLinks)
            .insert(
              ReviewBodyLinksCompanion.insert(
                bodyId: Value(h.bodyId),
                personId: mark.personId,
                method: 'tattoo',
                confidence: h.evidence == MarkEvidence.strong ? 0.95 : 0.80,
              ),
              mode: InsertMode.insertOrReplace,
            );
        published++;
      }
    });
    return published;
  }
}
