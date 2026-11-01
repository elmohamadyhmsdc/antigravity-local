import 'package:drift/drift.dart';

import '../../domain/scan/scan_math.dart';
import '../../domain/sensitive/sensitive_policy.dart';
import '../api/dtos/analyze.dart';
import '../db/app_database.dart';

/// Stores the exposed / covered regions the PC found (roadmap section 8.3) and keeps the derived
/// `media.is_sensitive` in step. Local to the phone; no crop of these areas is ever written.
class SensitiveStore {
  SensitiveStore(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Expression<bool> _frame($SensitiveRegionsTable r, int? frameNumber) =>
      frameNumber == null
      ? r.frameNumber.isNull()
      : r.frameNumber.equals(frameNumber);

  /// Replaces the regions of one photo (or one video frame). A region the user already decided about
  /// (`user_state`) is matched to a new one with the same label and IoU >= 0.5 and keeps its state; a
  /// confirmed region the model no longer sees stays (it is the user's word), a dismissed one goes.
  ///
  /// [bodyIds] maps the response's body index to `bodies.id` (a skipped body has no entry).
  /// Joins the caller's transaction when there is one.
  Future<void> replaceRegions(
    int mediaId,
    List<SensitiveRegionDto> regions, {
    required int imageW,
    required int imageH,
    required Map<int, int> bodyIds,
    required int modelVersion,
    int? frameNumber,
    int? timestampMs,
  }) async {
    await _db.transaction(() async {
      final now = _clock().millisecondsSinceEpoch;
      final old =
          await (_db.select(_db.sensitiveRegions)..where(
                (r) => r.mediaId.equals(mediaId) & _frame(r, frameNumber),
              ))
              .get();
      final used = <int>{};
      final inserts = <SensitiveRegionsCompanion>[];
      for (final region in regions) {
        final n = region.bbox.normalized(imageW, imageH);
        final box = clampBox(n.x, n.y, n.w, n.h);
        String? userState;
        for (final o in old) {
          if (used.contains(o.id) ||
              o.userState == null ||
              o.label != region.label) {
            continue;
          }
          if (iou(box, (x: o.x, y: o.y, w: o.w, h: o.h)) >= sameBoxIou) {
            used.add(o.id);
            userState = o.userState;
            break;
          }
        }
        final bodyIndex = region.bodyIndex;
        inserts.add(
          SensitiveRegionsCompanion.insert(
            mediaId: mediaId,
            bodyId: Value(bodyIndex == null ? null : bodyIds[bodyIndex]),
            label: region.label,
            exposed: region.exposed,
            score: region.score,
            x: box.x,
            y: box.y,
            w: box.w,
            h: box.h,
            frameNumber: Value(frameNumber),
            timestampMs: Value(timestampMs),
            modelVersion: modelVersion,
            userState: Value(userState),
            createdAt: now,
          ),
        );
      }
      final keep = <int>{
        for (final o in old)
          if (o.userState == 'confirmed' && !used.contains(o.id)) o.id,
      };
      await (_db.delete(_db.sensitiveRegions)..where(
            (r) =>
                r.mediaId.equals(mediaId) &
                _frame(r, frameNumber) &
                r.id.isNotIn(keep),
          ))
          .go();
      await _db.batch((b) => b.insertAll(_db.sensitiveRegions, inserts));
      await markChecked(mediaId, modelVersion);
    });
  }

  /// Records that this file was checked by [modelVersion] (so a file without regions is not redone
  /// forever) and recomputes `is_sensitive`.
  Future<void> markChecked(int mediaId, int modelVersion) async {
    await (_db.update(_db.media)..where((m) => m.id.equals(mediaId))).write(
      MediaCompanion(sensitiveVersion: Value(modelVersion)),
    );
    await recompute(mediaId);
  }

  /// `media.is_sensitive` from the regions of every frame, the thresholds and the user's override.
  Future<bool> recompute(int mediaId) async {
    final media = await (_db.select(
      _db.media,
    )..where((m) => m.id.equals(mediaId))).getSingleOrNull();
    if (media == null) return false;
    final rows = await (_db.select(
      _db.sensitiveRegions,
    )..where((r) => r.mediaId.equals(mediaId))).get();
    final sensitive = mediaIsSensitive([
      for (final r in rows)
        (label: r.label, score: r.score, userState: r.userState),
    ], override: media.sensitiveOverride);
    if (sensitive != media.isSensitive) {
      await (_db.update(_db.media)..where((m) => m.id.equals(mediaId))).write(
        MediaCompanion(isSensitive: Value(sensitive)),
      );
    }
    return sensitive;
  }

  /// After a threshold or policy change: every file that has regions, an override or the flag.
  Future<void> recomputeAll() async {
    final ids = await _db
        .customSelect(
          'SELECT id FROM media WHERE sensitive_override IS NOT NULL OR is_sensitive = 1 '
          'OR id IN (SELECT DISTINCT media_id FROM sensitive_regions)',
          readsFrom: {_db.media, _db.sensitiveRegions},
        )
        .map((r) => r.read<int>('id'))
        .get();
    await _db.transaction(() async {
      for (final id in ids) {
        await recompute(id);
      }
    });
  }

  /// S3 (roadmap): the files in which a counting region lies on a body of [personId] - through the
  /// body's face, an automatic / event-outfit / weak-face link, or a link made by hand. Newest first.
  Future<List<int>> mediaOfPerson(int personId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT r.media_id, r.label, r.score, r.user_state, m.taken_at
          FROM sensitive_regions r
          JOIN bodies b ON b.id = r.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          JOIN media m ON m.id = r.media_id
          WHERE COALESCE(f.person_id, b.person_id) = ?
          ''',
          variables: [Variable.withInt(personId)],
          readsFrom: {_db.sensitiveRegions, _db.bodies, _db.faces, _db.media},
        )
        .get();
    final taken = <int, int>{};
    for (final r in rows) {
      final counts = regionCounts((
        label: r.read<String>('label'),
        score: r.read<double>('score'),
        userState: r.readNullable<String>('user_state'),
      ));
      if (counts) {
        taken[r.read<int>('media_id')] = r.readNullable<int>('taken_at') ?? 0;
      }
    }
    return (taken.keys.toList()
      ..sort((a, b) => taken[b]!.compareTo(taken[a]!)));
  }

  /// The people a file's counting regions are attributed to (the reverse of [mediaOfPerson]).
  Future<Set<int>> peopleOfMedia(int mediaId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT COALESCE(f.person_id, b.person_id) AS person_id, r.label, r.score, r.user_state
          FROM sensitive_regions r
          JOIN bodies b ON b.id = r.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          WHERE r.media_id = ?
          ''',
          variables: [Variable.withInt(mediaId)],
          readsFrom: {_db.sensitiveRegions, _db.bodies, _db.faces},
        )
        .get();
    return {
      for (final r in rows)
        if (r.readNullable<int>('person_id') != null &&
            regionCounts((
              label: r.read<String>('label'),
              score: r.read<double>('score'),
              userState: r.readNullable<String>('user_state'),
            )))
          r.read<int>('person_id'),
    };
  }

  /// The user's word on one file: 'none' | 'sensitive' | null (back to automatic).
  Future<void> setOverride(int mediaId, String? override) async {
    await (_db.update(_db.media)..where((m) => m.id.equals(mediaId))).write(
      MediaCompanion(sensitiveOverride: Value(override)),
    );
    await recompute(mediaId);
  }

  /// 'dismissed' | 'confirmed' | null for one region; the file's flag follows.
  Future<void> setRegionState(int regionId, String? state) async {
    final row = await (_db.select(
      _db.sensitiveRegions,
    )..where((r) => r.id.equals(regionId))).getSingleOrNull();
    if (row == null) return;
    await (_db.update(_db.sensitiveRegions)
          ..where((r) => r.id.equals(regionId)))
        .write(SensitiveRegionsCompanion(userState: Value(state)));
    await recompute(row.mediaId);
  }
}
