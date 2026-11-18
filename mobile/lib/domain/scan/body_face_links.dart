import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../grouping/identity_constraints.dart';

/// A face observed on a body is stronger evidence than a guessed identity.
class BodyFaceLinks {
  const BodyFaceLinks(this.db);

  final AppDatabase db;

  /// Rebind a saved detection to the face found on it. Updating one frame
  /// cannot change the owner of a reused video body view without corroboration.
  Future<int> attach(
    int bodyId,
    int faceId, {
    bool allOccurrencesAgree = false,
  }) async {
    final changed = await db.customUpdate(
      '''
      UPDATE bodies SET face_id = ?2, person_id = NULL, link_method = NULL,
        link_confidence = NULL, weak_face_embedding = NULL, weak_face_quality = NULL
      WHERE id = ?1 AND hidden = 0 AND ownership IS NULL
        AND link_method IS NOT 'manual'
        AND (face_id IS NOT ?2 OR person_id IS NOT NULL OR link_method IS NOT NULL
             OR weak_face_embedding IS NOT NULL OR weak_face_quality IS NOT NULL)
        AND NOT EXISTS (
          SELECT 1 FROM persons p LEFT JOIN faces old ON old.id = bodies.face_id
          WHERE p.grouping_locked = 1 AND (p.id = bodies.person_id OR p.id = old.person_id)
        )
        AND EXISTS (
          SELECT 1 FROM faces f LEFT JOIN faces old ON old.id = bodies.face_id
          WHERE f.id = ?2 AND f.kind = bodies.kind AND f.hidden = 0 AND f.ownership IS NULL
            AND NOT EXISTS (
              SELECT 1 FROM body_rejections r WHERE r.body_id = ?1 AND r.person_id = f.person_id
            )
            AND NOT ${bodyConflictWithPerson('?1', 'f.person_id')}
            AND (?3 OR bodies.face_id = ?2 OR old.track_id = f.track_id OR NOT EXISTS (
              SELECT 1 FROM media_detections d WHERE d.kind = 'b' AND d.ref_id = ?1
                AND (d.media_id IS NOT bodies.media_id OR d.frame_number IS NOT bodies.frame_number)
            ))
        )
      ''',
      variables: [
        Variable.withInt(bodyId),
        Variable.withInt(faceId),
        Variable.withBool(allOccurrencesAgree),
      ],
      updates: {db.bodies},
    );
    if (changed != 0) {
      await (db.delete(
        db.reviewBodyLinks,
      )..where((row) => row.bodyId.equals(bodyId))).go();
    }
    return changed;
  }

  /// Repair saved single-subject frames, including duplicate photos and
  /// compacted video views. A shared view must have evidence at every recorded
  /// occurrence, and every occurrence must point to the same face or track.
  Future<int> repairIsolated(String kind) => db.transaction(() async {
    final rows = await db
        .customSelect(
          r'''
      WITH observations(part, ref_id, media_id, frame_number, x, y, w, h) AS (
        SELECT d.kind, d.ref_id, d.media_id, d.frame_number, d.x, d.y, d.w, d.h
        FROM media_detections d WHERE d.kind IN ('f', 'b')
        UNION ALL
        SELECT 'f', f.id, f.media_id, f.frame_number, f.bbox_x, f.bbox_y, f.bbox_w, f.bbox_h
        FROM faces f WHERE f.media_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM media_detections d WHERE d.kind = 'f' AND d.ref_id = f.id
            AND d.media_id = f.media_id AND d.frame_number IS f.frame_number
        )
        UNION ALL
        SELECT 'b', b.id, b.media_id, b.frame_number, b.bbox_x, b.bbox_y, b.bbox_w, b.bbox_h
        FROM bodies b WHERE b.media_id IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM media_detections d WHERE d.kind = 'b' AND d.ref_id = b.id
            AND d.media_id = b.media_id AND d.frame_number IS b.frame_number
        )
      ), isolated AS (
        SELECT o.media_id, o.frame_number,
          MAX(CASE WHEN o.part = 'f' THEN o.ref_id END) AS face_id,
          MAX(CASE WHEN o.part = 'f' THEN o.x END) AS fx,
          MAX(CASE WHEN o.part = 'f' THEN o.y END) AS fy,
          MAX(CASE WHEN o.part = 'f' THEN o.w END) AS fw,
          MAX(CASE WHEN o.part = 'f' THEN o.h END) AS fh,
          MAX(CASE WHEN o.part = 'b' THEN o.ref_id END) AS body_id,
          MAX(CASE WHEN o.part = 'b' THEN o.x END) AS bx,
          MAX(CASE WHEN o.part = 'b' THEN o.y END) AS by,
          MAX(CASE WHEN o.part = 'b' THEN o.w END) AS bw,
          MAX(CASE WHEN o.part = 'b' THEN o.h END) AS bh
        FROM observations o JOIN media m ON m.id = o.media_id
        WHERE m.kind = 'photo' OR (m.kind = 'video' AND o.frame_number IS NOT NULL)
        GROUP BY o.media_id, o.frame_number
        HAVING SUM(o.part = 'f') = 1 AND SUM(o.part = 'b') = 1
      ), body_occurrences AS (
        SELECT ref_id, COUNT(*) AS n FROM observations WHERE part = 'b' GROUP BY ref_id
      ), evidence AS MATERIALIZED (
        SELECT b.id AS body_id, f.id AS face_id, COALESCE(f.track_id, f.id) AS face_track
        FROM isolated i
        JOIN faces f ON f.id = i.face_id
        JOIN bodies b ON b.id = i.body_id
        WHERE b.kind = ? AND f.kind = b.kind
          AND b.score >= .55 AND f.det_score >= .65 AND f.face_px >= 32
          AND b.hidden = 0 AND b.ownership IS NULL AND b.link_method IS NOT 'manual'
          AND f.hidden = 0 AND f.ownership IS NULL
          AND i.bw > 0 AND i.bh > 0 AND i.fw > 0 AND i.fh > 0
          AND i.fw BETWEEN .10 * i.bw AND .85 * i.bw
          AND i.fh <= .55 * i.bh
          AND i.fx + i.fw / 2 BETWEEN i.bx + .12 * i.bw AND i.bx + .88 * i.bw
          AND i.fy + i.fh / 2 BETWEEN i.by AND i.by + .36 * i.bh
          AND MAX(0, MIN(i.fx + i.fw, i.bx + i.bw) - MAX(i.fx, i.bx))
            * MAX(0, MIN(i.fy + i.fh, i.by + i.bh) - MAX(i.fy, i.by))
            >= .75 * i.fw * i.fh
          AND (i.media_id IS NOT b.media_id OR i.frame_number IS NOT b.frame_number
            OR NOT EXISTS (
              SELECT COUNT(*) FROM json_each(CASE WHEN json_valid(b.kpts) THEN b.kpts ELSE '[]' END) k
              WHERE k.type = 'array' AND CAST(k.key AS INTEGER) BETWEEN 0 AND 4
                AND json_extract(k.value, '$[2]') >= .5
              HAVING COUNT(*) >= 3 AND SUM(
                json_extract(k.value, '$[0]') BETWEEN i.fx - .25 * i.fw AND i.fx + 1.25 * i.fw
                AND json_extract(k.value, '$[1]') BETWEEN i.fy - .25 * i.fh AND i.fy + 1.25 * i.fh
              ) = 0
            ))
      )
      SELECT e.body_id,
        COALESCE(MAX(CASE WHEN e.face_id = b.face_id THEN e.face_id END), MIN(e.face_id)) AS face_id
      FROM evidence e JOIN body_occurrences n ON n.ref_id = e.body_id
      JOIN bodies b ON b.id = e.body_id
      GROUP BY e.body_id
      HAVING COUNT(*) = n.n AND COUNT(DISTINCT e.face_track) = 1
        AND (b.face_id IS NULL OR SUM(e.face_id = b.face_id) = 0
             OR b.person_id IS NOT NULL OR b.link_method IS NOT NULL
             OR b.weak_face_embedding IS NOT NULL)
      ''',
          variables: [Variable.withString(kind)],
          readsFrom: {db.media, db.mediaDetections, db.bodies, db.faces},
        )
        .get();
    var repaired = 0;
    for (final row in rows) {
      repaired += await attach(
        row.read<int>('body_id'),
        row.read<int>('face_id'),
        allOccurrencesAgree: true,
      );
    }
    return repaired;
  });
}
