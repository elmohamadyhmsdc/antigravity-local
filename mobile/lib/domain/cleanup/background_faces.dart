import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../grouping/grouping_config.dart';

/// What a scan stopped storing, found in what it stored before: tiny faces and the small faces of a
/// crowd photo. New scans never store them (`face_quality.MIN_FACE_PX` / `drop_background`); this finds
/// the ones already in the library so they can be hidden (never deleted: hidden faces come back with
/// one tap, and the originals are untouched).
///
/// A face is background when
///  - it is smaller than [groupingMinFacePx] (40 px; 32 for drawn characters), or
///  - its photo / video frame holds at least [crowdMinFaces] faces and it is under [backgroundRel] of the
///    biggest face there (and under [backgroundMaxPx]).
/// Faces the user vouched for (`face_confirmations`) and faces already hidden are never listed.
class BackgroundFaces {
  BackgroundFaces(this._db);

  final AppDatabase _db;

  /// Same numbers as `face_quality.py` (CROWD_MIN_FACES / BACKGROUND_REL / BACKGROUND_MAX_PX).
  static const crowdMinFaces = 3;
  static const backgroundRel = 0.40;
  static const backgroundMaxPx = 120.0;

  /// Ids of the faces to hide.
  Future<List<int>> find() async {
    final out = <int>{};
    final tiny = await _db
        .customSelect(
          '''
          SELECT f.id FROM faces f
          WHERE f.hidden = 0 AND f.face_px < CASE WHEN f.kind = 'character' THEN ? ELSE ? END
            AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id AND c.person_id IS f.person_id)
          ''',
          variables: [
            Variable.withReal(groupingMinCharacterFacePx),
            Variable.withReal(groupingMinFacePx),
          ],
          readsFrom: {_db.faces, _db.faceConfirmations},
        )
        .get();
    for (final r in tiny) {
      out.add(r.read<int>('id'));
    }

    // crowds: per (file, frame), the faces that are far smaller than the biggest
    final crowd = await _db
        .customSelect(
          '''
          SELECT f.id, f.face_px, g.biggest
          FROM faces f
          JOIN (SELECT media_id AS m, COALESCE(frame_number, -1) AS fr, COUNT(*) AS n, MAX(face_px) AS biggest
                FROM faces WHERE media_id IS NOT NULL AND hidden = 0 AND kind = 'person'
                GROUP BY media_id, COALESCE(frame_number, -1) HAVING COUNT(*) >= ?) g
            ON g.m = f.media_id AND g.fr = COALESCE(f.frame_number, -1)
          WHERE f.hidden = 0 AND f.kind = 'person'
            AND f.face_px < MIN(?, ? * g.biggest)
            AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id AND c.person_id IS f.person_id)
          ''',
          variables: [
            Variable.withInt(crowdMinFaces),
            Variable.withReal(backgroundMaxPx),
            Variable.withReal(backgroundRel),
          ],
          readsFrom: {_db.faces, _db.faceConfirmations},
        )
        .get();
    for (final r in crowd) {
      out.add(r.read<int>('id'));
    }
    return out.toList()..sort();
  }

  Future<void> hide(Iterable<int> ids) => _set(ids, true);

  /// Undo: the faces are visible (and counted) again.
  Future<void> restore(Iterable<int> ids) => _set(ids, false);

  Future<void> _set(Iterable<int> ids, bool hidden) =>
      _db.transaction(() async {
        final all = ids.toList();
        for (var i = 0; i < all.length; i += 500) {
          final chunk = all.sublist(
            i,
            i + 500 > all.length ? all.length : i + 500,
          );
          await (_db.update(_db.faces)..where((f) => f.id.isIn(chunk))).write(
            FacesCompanion(hidden: Value(hidden)),
          );
        }
      });
}
