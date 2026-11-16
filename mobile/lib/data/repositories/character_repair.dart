import 'package:drift/drift.dart';

import '../api/dtos/analyze.dart';
import '../db/app_database.dart';
import 'kind_corrections.dart';

typedef _Box = ({double x, double y, double w, double h});

/// One repair per affected file with the revised character analyzer.
class CharacterRepair {
  CharacterRepair(this.db);

  final AppDatabase db;
  static const settingPrefix = 'scan.character_repair.v1.';
  static const _sessionKey = 'scan.character_repair_active';

  static const pendingSql =
      "EXISTS (SELECT 1 FROM settings s "
      "WHERE s.key = '$settingPrefix' || media.id AND s.value = 'pending')";

  Future<bool> sessionActive() async => await db.setting(_sessionKey) == '1';
  Future<void> setSessionActive(bool active) =>
      db.putSetting(_sessionKey, active ? '1' : '0');

  Future<bool> pending(int mediaId) async =>
      await db.setting('$settingPrefix$mediaId') == 'pending';

  Future<void> finish(int mediaId) =>
      db.putSetting('$settingPrefix$mediaId', 'done');

  /// Only queue already catalogued media that actually contains character
  /// detections. A retry preserves the checkpoint of a failed repair.
  Future<int> enqueue() => db.transaction(() async {
    await db.customInsert(
      '''
      INSERT OR IGNORE INTO settings (key, value)
      SELECT ? || m.id, 'pending'
      FROM media m
      WHERE m.scan_status = 'done' AND m.kind IN ('photo', 'video')
        AND NOT EXISTS (
          SELECT 1 FROM kind_overrides k
          WHERE k.asset_id = m.asset_id AND k.part IS NULL AND k.kind = 'character'
        )
        AND EXISTS (
          SELECT 1 FROM media_detections d
          WHERE d.media_id = m.id AND (
            (d.kind = 'f' AND EXISTS (
              SELECT 1 FROM faces f WHERE f.id = d.ref_id AND f.kind = 'character'
            )) OR (d.kind = 'b' AND EXISTS (
              SELECT 1 FROM bodies b WHERE b.id = d.ref_id AND b.kind = 'character'
            ))
          )
        )
      ''',
      variables: [Variable.withString(settingPrefix)],
      updates: {db.settings},
    );
    // Finished videos may retain an obsolete cursor if Android was killed
    // immediately after committing the previous completion.
    await db.customUpdate(
      '''
      DELETE FROM settings
      WHERE key IN (
        SELECT 'video.job.' || media.id FROM media
        WHERE scan_status = 'done' AND $pendingSql
        UNION ALL
        SELECT 'video.local.' || media.id FROM media
        WHERE scan_status = 'done' AND $pendingSql
      )
      ''',
      updates: {db.settings},
    );
    return db.customUpdate(
      '''
      UPDATE media
      SET last_scanned_frame = CASE WHEN scan_status = 'done' THEN 0 ELSE last_scanned_frame END,
          scan_status = 'pending', scan_attempts = 0, scan_error = NULL
      WHERE scan_status IN ('done', 'failed', 'skipped')
        AND EXISTS (
          SELECT 1 FROM settings s WHERE s.key = ? || media.id AND s.value = 'pending'
        )
      ''',
      variables: [Variable.withString(settingPrefix)],
      updates: {db.media},
    );
  });

  /// Remove only observations positively matched to an eligible human face.
  /// Called within the transaction that stores the new human detections.
  Future<Set<int>> reconcile(
    MediaRow media,
    AnalyzeImageResponse analysis, {
    required Set<int> humanFaces,
    required int? frameNumber,
    required int? timestampMs,
    bool bothKinds = false,
  }) async {
    final removed = <int>{};
    final verified = {
      for (final i in humanFaces)
        if (analysis.faces[i].detScore >= .75 &&
            analysis.faces[i].quality.facePx >= 48)
          i,
    };
    final corrections = await KindOverrideStore(db).forAsset(media.assetId);
    final explicit = corrections.dtos(timestampMs: timestampMs);

    _Box box(BBox value) {
      final b = value.normalized(analysis.imageW, analysis.imageH);
      return (x: b.x, y: b.y, w: b.w, h: b.h);
    }

    final realFaces = [for (final i in verified) box(analysis.faces[i].bbox)];
    final realBodies = [
      for (final pair in analysis.pairs)
        if (verified.contains(pair.faceIndex) &&
            pair.bodyIndex >= 0 &&
            pair.bodyIndex < analysis.bodies.length)
          box(analysis.bodies[pair.bodyIndex].bbox),
    ];
    final newFaces = [
      for (final c in analysis.characters)
        if (c.face case final face?) box(face.bbox),
    ];
    final newBodies = [
      for (final c in analysis.characters)
        if (c.body case final body?)
          box(body.bbox)
        else if (c.face == null)
          box(c.bbox),
    ];

    if (verified.isNotEmpty && corrections.forceKind != 'character') {
      removed.addAll(
        await _reconcileKind(
          media,
          oldKind: 'character',
          frameNumber: frameNumber,
          timestampMs: timestampMs,
          replacementFaces: realFaces,
          replacementBodies: realBodies,
          survivingFaces: newFaces,
          survivingBodies: newBodies,
          explicit: explicit,
        ),
      );
    }
    if (!bothKinds || corrections.forceKind == 'person') return removed;
    // A drawn face must actually have been stored with its identity vector.
    // A body-only or low-confidence cartoon hypothesis cannot erase a human.
    final characters = [
      for (final c in analysis.characters)
        if (c.score >= .75 &&
            c.face != null &&
            c.face!.score >= .75 &&
            c.face!.embedding != null &&
            c.face!.bbox.w >= 32 &&
            c.face!.bbox.h >= 32)
          c,
    ];
    if (characters.isEmpty) return removed;
    removed.addAll(
      await _reconcileKind(
        media,
        oldKind: 'person',
        frameNumber: frameNumber,
        timestampMs: timestampMs,
        replacementFaces: [for (final c in characters) box(c.face!.bbox)],
        replacementBodies: [
          for (final c in characters)
            if (c.body != null) box(c.body!.bbox),
        ],
        survivingFaces: [
          for (final i in humanFaces) box(analysis.faces[i].bbox),
        ],
        survivingBodies: [
          for (final pair in analysis.pairs)
            if (humanFaces.contains(pair.faceIndex) &&
                pair.bodyIndex >= 0 &&
                pair.bodyIndex < analysis.bodies.length)
              box(analysis.bodies[pair.bodyIndex].bbox),
        ],
        explicit: explicit,
      ),
    );
    return removed;
  }

  Future<Set<int>> _reconcileKind(
    MediaRow media, {
    required String oldKind,
    required int? frameNumber,
    required int? timestampMs,
    required List<_Box> replacementFaces,
    required List<_Box> replacementBodies,
    required List<_Box> survivingFaces,
    required List<_Box> survivingBodies,
    required List<KindOverrideDto> explicit,
  }) async {
    final observations = await db
        .customSelect(
          '''
      WITH current_media AS (
        SELECT * FROM media_detections
        WHERE media_id = ?1 AND (
          (?2 IS NULL AND frame_number IS NULL) OR
          (?2 IS NOT NULL AND (
            (?3 IS NULL AND frame_number = ?2) OR
            (?3 IS NOT NULL AND (
              (timestamp_ms IS NULL AND frame_number = ?2) OR
              ABS(timestamp_ms - ?3) <= 250
            ))
          ))
        )
      )
      SELECT d.id, d.kind, d.ref_id, d.x, d.y, d.w, d.h, f.person_id, NULL AS face_id
      FROM current_media d JOIN faces f ON d.kind = 'f' AND f.id = d.ref_id
      WHERE f.kind = ?4 AND f.hidden = 0 AND f.review_dismissed = 0
        AND f.ownership IS NULL
        AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id)
        AND NOT EXISTS (SELECT 1 FROM identity_set_faces i WHERE i.face_id = f.id)
        AND NOT EXISTS (SELECT 1 FROM bodies b WHERE b.face_id = f.id AND b.link_method = 'manual')
        AND NOT EXISTS (
          SELECT 1 FROM persons p WHERE p.id = f.person_id AND p.grouping_locked = 1
        )
      UNION ALL
      SELECT d.id, d.kind, d.ref_id, d.x, d.y, d.w, d.h, b.person_id, b.face_id
      FROM current_media d JOIN bodies b ON d.kind = 'b' AND b.id = d.ref_id
      WHERE b.kind = ?4 AND b.hidden = 0 AND b.ownership IS NULL
        AND b.link_method IS NOT 'manual'
        AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = b.face_id)
        AND NOT EXISTS (SELECT 1 FROM identity_set_faces i WHERE i.face_id = b.face_id)
        AND NOT EXISTS (
          SELECT 1 FROM persons p
          WHERE p.grouping_locked = 1 AND (
            p.id = b.person_id OR p.id = (SELECT f.person_id FROM faces f WHERE f.id = b.face_id)
          )
        )
      ''',
          variables: [
            Variable.withInt(media.id),
            Variable<int>(frameNumber),
            Variable<int>(timestampMs),
            Variable.withString(oldKind),
          ],
          readsFrom: {
            db.mediaDetections,
            db.faces,
            db.bodies,
            db.persons,
            db.faceConfirmations,
            db.identitySetFaces,
          },
        )
        .get();

    _Box fromRow(QueryRow row) => (
      x: row.read<double>('x'),
      y: row.read<double>('y'),
      w: row.read<double>('w'),
      h: row.read<double>('h'),
    );
    bool matches(QueryRow row, Iterable<_Box> boxes, String part) => boxes.any(
      (candidate) => sameDetectionBox(fromRow(row), candidate, part),
    );
    bool explicitlyKept(QueryRow row, String part) => explicit.any(
      (o) =>
          o.kind == oldKind &&
          o.part == part &&
          sameDetectionBox(fromRow(row), o.box, part),
    );

    final faces = [
      for (final d in observations)
        if (d.read<String>('kind') == 'f' &&
            !explicitlyKept(d, 'face') &&
            !matches(d, survivingFaces, 'face') &&
            matches(d, replacementFaces, 'face'))
          d,
    ];
    final faceIds = {for (final row in faces) row.read<int>('ref_id')};
    final bodies = [
      for (final d in observations)
        if (d.read<String>('kind') == 'b' &&
            !explicitlyKept(d, 'body') &&
            !matches(d, survivingBodies, 'body') &&
            (faceIds.contains(d.readNullable<int>('face_id')) ||
                matches(d, replacementBodies, 'body')))
          d,
    ];
    if (faces.isEmpty && bodies.isEmpty) return {};
    final people = <int>{};
    for (final row in [...faces, ...bodies]) {
      final pid = row.readNullable<int>('person_id');
      if (pid != null) people.add(pid);
      await (db.delete(
        db.mediaDetections,
      )..where((d) => d.id.equals(row.read<int>('id')))).go();
    }

    // A character track can still have confirmed appearances at other times.
    for (final id in bodies.map((r) => r.read<int>('ref_id')).toSet()) {
      await db.customUpdate(
        "DELETE FROM bodies WHERE id = ? AND NOT EXISTS "
        "(SELECT 1 FROM media_detections WHERE kind = 'b' AND ref_id = bodies.id)",
        variables: [Variable.withInt(id)],
        updates: {db.bodies},
      );
    }
    final removed = <int>{};
    for (final id in faceIds) {
      final deleted = await db.customUpdate(
        "DELETE FROM faces WHERE id = ? AND NOT EXISTS "
        "(SELECT 1 FROM media_detections WHERE kind = 'f' AND ref_id = faces.id)",
        variables: [Variable.withInt(id)],
        updates: {db.faces},
      );
      if (deleted > 0) removed.add(id);
    }
    for (final id in people) {
      await db.customUpdate(
        '''
        UPDATE persons SET hidden = 1, avatar_face_id = NULL
        WHERE id = ? AND kind = ? AND COALESCE(TRIM(name), '') = ''
          AND grouping_locked = 0 AND pinned = 0 AND favorite = 0 AND group_id IS NULL
          AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.person_id = persons.id)
          AND NOT EXISTS (SELECT 1 FROM bodies b WHERE b.person_id = persons.id)
        ''',
        variables: [Variable.withInt(id), Variable.withString(oldKind)],
        updates: {db.persons},
      );
    }
    return removed;
  }
}
