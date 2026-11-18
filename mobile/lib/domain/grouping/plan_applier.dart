import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/api/dtos/grouping.dart';
import '../../data/db/app_database.dart';
import '../scan/drawn_faces.dart';
import '../scan/video_tracks.dart';
import 'identity_evidence.dart';
import 'identity_constraints.dart';

class FacePlanResult {
  const FacePlanResult({
    this.assigned = 0,
    this.newPeople = 0,
    this.facesInNewPeople = 0,
  });

  final int assigned; // faces added to people the user already had
  final int newPeople;
  final int facesInNewPeople;

  bool get changedAnything => assigned > 0 || newPeople > 0;
}

/// Turns the PC's decisions into database changes - each in ONE transaction, so a killed app never
/// leaves half a grouping round behind. Anything the user did since the plan was requested wins:
/// a face that has a person by now is left alone, a person that was deleted is not resurrected.
class PlanApplier {
  PlanApplier(this._db, {this.kind = 'person', DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// 'person' or 'character': new people are created as, and links are cleared only for, this kind.
  final String kind;

  /// Round 1 (`apply`, match + cluster): confident matches go to existing people, big cohesive
  /// groups become new people (real ids, the best-quality face as cover).
  Future<FacePlanResult> applyFacePlan(
    GroupingPlanResponse plan,
  ) => _db.transaction(() async {
    final people = await _personIds();
    var assigned = 0, newPeople = 0, inNew = 0;

    for (final a in plan.assignments) {
      if (!a.isAuto || !people.contains(a.personId)) continue;
      assigned += await _db.customUpdate(
        // the last NOT EXISTS is the one-person-per-frame rule against faces the person already has
        "UPDATE faces SET person_id = ?1 WHERE id = ?2 AND person_id IS NULL AND review_dismissed = 0 AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = faces.id AND r.person_id = ?3) AND EXISTS (SELECT 1 FROM persons p WHERE p.id = ?4 AND p.grouping_locked = 0) AND NOT ${faceConflictWithPerson('faces.id', '?5')} AND faces.hidden = 0 AND (faces.ownership IS NULL OR faces.ownership != 'none') AND faces.kind = ?6",
        variables: [
          Variable.withInt(a.personId),
          Variable.withInt(a.faceId),
          Variable.withInt(a.personId),
          Variable.withInt(a.personId),
          Variable.withInt(a.personId),
          Variable.withString(kind),
        ],
        updates: {_db.faces},
      );
    }

    for (final g in plan.groups) {
      if (!g.autoCreate || g.faceIds.isEmpty) continue;
      final rows = await _db
          .customSelect(
            "SELECT id, quality_score FROM faces WHERE person_id IS NULL AND review_dismissed = 0 AND hidden = 0 AND (ownership IS NULL OR ownership != 'none') AND kind = ? AND id IN (${List.filled(g.faceIds.length, '?').join(',')})",
            variables: [
              Variable.withString(kind),
              for (final id in g.faceIds) Variable.withInt(id),
            ],
            readsFrom: {_db.faces},
          )
          .get();
      if (rows.length != g.faceIds.length) {
        continue; // part of the group was sorted meanwhile: ask again next round
      }
      if (await _fromOneFile(g.faceIds)) {
        continue; // one appearance in one video is not a person yet (Review still offers it)
      }
      if (await _groupHasConflict(g.faceIds)) continue;
      final quality = {
        for (final r in rows)
          r.read<int>('id'): r.read<double>('quality_score'),
      };
      final personId = await _db
          .into(_db.persons)
          .insert(
            PersonsCompanion.insert(
              kind: Value(kind),
              createdAt: _clock().millisecondsSinceEpoch,
            ),
          );
      await _db.customUpdate(
        'UPDATE faces SET person_id = ? WHERE person_id IS NULL AND id IN (${List.filled(g.faceIds.length, '?').join(',')})',
        variables: [
          Variable.withInt(personId),
          for (final id in g.faceIds) Variable.withInt(id),
        ],
        updates: {_db.faces},
      );
      int? best;
      for (final id in g.faceIds) {
        if (best == null || quality[id]! > quality[best]!) {
          best = id; // first of the best, like max()
        }
      }
      await (_db.update(_db.persons)..where((p) => p.id.equals(personId)))
          .write(PersonsCompanion(avatarFaceId: Value(best)));
      newPeople++;
      inNew += g.faceIds.length;
    }

    // A track can switch subjects between samples. Its owner is useful only
    // when the individual view also matches an assigned view.
    final trackMatches = await _matchingTrackViews();
    for (var offset = 0; offset < trackMatches.length; offset += 400) {
      final ids = trackMatches.skip(offset).take(400).toList();
      assigned += await _db.customUpdate(
        '''
      WITH owner AS (
        SELECT track_id, MIN(person_id) AS pid FROM faces
        WHERE track_id IS NOT NULL AND person_id IS NOT NULL AND hidden = 0
          AND kind = ?1 AND (ownership IS NULL OR ownership != 'none')
          AND NOT EXISTS (SELECT 1 FROM review_doubtful d WHERE d.face_id = faces.id AND d.person_id = faces.person_id)
        GROUP BY track_id HAVING COUNT(DISTINCT person_id) = 1
      )
      UPDATE faces SET person_id = (SELECT pid FROM owner WHERE owner.track_id = faces.track_id)
      WHERE person_id IS NULL AND review_dismissed = 0 AND hidden = 0 AND kind = ?1
        AND faces.id IN (${List.filled(ids.length, '?').join(',')})
        AND (ownership IS NULL OR ownership != 'none')
        AND NOT EXISTS (SELECT 1 FROM faces suspect JOIN review_doubtful d ON d.face_id = suspect.id AND d.person_id = suspect.person_id WHERE suspect.track_id = faces.track_id)
        AND track_id IN (SELECT track_id FROM owner)
        AND NOT ${faceConflictWithPerson('faces.id', '(SELECT pid FROM owner WHERE owner.track_id = faces.track_id)')}
        AND NOT EXISTS (
          SELECT 1 FROM faces incompatible WHERE incompatible.track_id = faces.track_id
            AND (incompatible.kind != faces.kind OR incompatible.model_id != faces.model_id))
        AND NOT EXISTS (
          SELECT 1 FROM face_rejections r JOIN owner o ON o.pid = r.person_id
          WHERE r.face_id = faces.id AND o.track_id = faces.track_id)
        AND EXISTS (
          SELECT 1 FROM persons p JOIN owner o ON o.pid = p.id
          WHERE o.track_id = faces.track_id AND p.grouping_locked = 0)
      ''',
        variables: [
          Variable.withString(kind),
          for (final id in ids) Variable.withInt(id),
        ],
        updates: {_db.faces},
      );
    }
    return FacePlanResult(
      assigned: assigned,
      newPeople: newPeople,
      facesInNewPeople: inNew,
    );
  });

  Future<List<int>> _matchingTrackViews() async {
    final matches = <int>{};
    final dim = kind == 'character' ? characterEmbeddingDim : embeddingDim;
    final floor = kind == 'character' ? .86 : trackIdentityCosine;
    var after = 0;
    while (true) {
      final rows = await _db
          .customSelect(
            '''
      WITH pending AS (
        SELECT f.id, f.embedding, f.track_id, f.kind, f.model_id FROM faces f
        WHERE f.id > ?1 AND f.kind = ?2 AND f.person_id IS NULL AND f.track_id IS NOT NULL
          AND f.hidden = 0 AND f.review_dismissed = 0 AND f.ownership IS NOT 'none'
          AND EXISTS (SELECT 1 FROM faces owner WHERE owner.track_id = f.track_id
            AND owner.kind = f.kind AND owner.model_id = f.model_id AND owner.person_id IS NOT NULL
            AND owner.hidden = 0 AND owner.ownership IS NOT 'none')
        ORDER BY f.id LIMIT 500
      )
      SELECT f.id, f.embedding, anchor.embedding AS anchor_embedding
      FROM pending f JOIN faces anchor ON anchor.track_id = f.track_id
        AND anchor.kind = f.kind AND anchor.model_id = f.model_id
      WHERE anchor.person_id IS NOT NULL AND anchor.hidden = 0 AND anchor.ownership IS NOT 'none'
      ORDER BY f.id
      ''',
            variables: [Variable.withInt(after), Variable.withString(kind)],
          )
          .get();
      if (rows.isEmpty) return matches.toList();
      after = rows.last.read<int>('id');
      for (final row in rows) {
        final id = row.read<int>('id');
        if (matches.contains(id)) continue;
        final candidate = row.read<Uint8List>('embedding');
        final anchor = row.read<Uint8List>('anchor_embedding');
        if (candidate.length != dim * 4 || anchor.length != dim * 4) continue;
        final a = vectorFromBlob(candidate), b = vectorFromBlob(anchor);
        if (kind == 'person' && (isDrawnFace(a) || isDrawnFace(b))) continue;
        final score = faceSimilarity(a, b);
        if (score.isFinite && score >= floor) matches.add(id);
      }
    }
  }

  /// Round 2 (`apply`, bodies): the outfit / weak-face links are re-derived (the old derived ones
  /// are cleared first, links made by hand stay), then the confident ones are applied.
  Future<int> applyBodyPlan(
    GroupingPlanResponse plan,
  ) => _db.transaction(() async {
    await _db.customUpdate(
      "UPDATE bodies SET person_id = NULL, link_method = NULL, link_confidence = NULL WHERE link_method IN ('appearance', 'weak_face', 'event_outfit') AND bodies.kind = ? AND NOT EXISTS (SELECT 1 FROM persons p WHERE p.id = bodies.person_id AND p.grouping_locked = 1)",
      variables: [Variable.withString(kind)],
      updates: {_db.bodies},
    );
    final people = await _personIds();
    var linked = 0;
    for (final l in plan.bodyLinks) {
      if (!l.isAuto ||
          !people.contains(l.personId) ||
          !l.confidence.isFinite ||
          l.confidence < 0 ||
          l.confidence > 1 ||
          isClothingOnlyLink(l.method)) {
        continue;
      }
      linked += await _db.customUpdate(
        "UPDATE bodies SET person_id = ?1, link_method = ?2, link_confidence = ?3 WHERE id = ?4 AND person_id IS NULL AND face_id IS NULL AND link_method IS NOT 'manual' AND (ownership IS NULL OR ownership != 'none') AND hidden = 0 AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = bodies.id AND r.person_id = ?5) AND NOT ${bodyConflictWithPerson('bodies.id', '?6')} AND bodies.kind = ?7",
        variables: [
          Variable.withInt(l.personId),
          Variable.withString(l.method),
          Variable.withReal(l.confidence),
          Variable.withInt(l.bodyId),
          Variable.withInt(l.personId),
          Variable.withInt(l.personId),
          Variable.withString(kind),
        ],
        updates: {_db.bodies},
      );
    }
    return linked;
  });

  Future<bool> _groupHasConflict(List<int> ids) async {
    final marks = List.filled(ids.length, '?').join(',');
    final conflicts = await _db
        .customSelect(
          '''
      WITH members AS (SELECT id FROM faces WHERE id IN ($marks)),
      occurrences AS (
        SELECT f.id, f.media_id, f.frame_number FROM faces f JOIN members x ON x.id = f.id
        WHERE f.media_id IS NOT NULL
        UNION
        SELECT d.ref_id, d.media_id, d.frame_number FROM media_detections d
        JOIN members x ON x.id = d.ref_id JOIN media m ON m.id = d.media_id
        WHERE d.kind = 'f' AND (m.kind = 'photo' OR d.frame_number IS NOT NULL)
      )
      SELECT 1 FROM occurrences GROUP BY media_id, frame_number
      HAVING COUNT(DISTINCT id) > 1 LIMIT 1
    ''',
          variables: [for (final id in ids) Variable.withInt(id)],
        )
        .get();
    return conflicts.isNotEmpty;
  }

  /// True when every face of the group comes from the same file. A photo cannot give two faces of
  /// one person, so this is a video: one stranger passing through it yields several views and would
  /// otherwise become a "person" of its own. Faces seen in other files (duplicates of a stored face
  /// are linked through media_detections) count as other files; a face with no file counts as unknown.
  Future<bool> _fromOneFile(List<int> faceIds) async {
    final marks = List.filled(faceIds.length, '?').join(',');
    final vars = [for (final id in faceIds) Variable.withInt(id)];
    final row = await _db
        .customSelect(
          '''
          SELECT COUNT(DISTINCT m) AS files, SUM(m IS NULL) AS unknown FROM (
            SELECT media_id AS m FROM faces WHERE id IN ($marks)
            UNION ALL
            SELECT media_id AS m FROM media_detections WHERE kind = 'f' AND ref_id IN ($marks)
          )
          ''',
          variables: [...vars, ...vars],
          readsFrom: {_db.faces, _db.mediaDetections},
        )
        .getSingle();
    return row.read<int>('files') == 1 &&
        (row.readNullable<int>('unknown') ?? 0) == 0;
  }

  Future<Set<int>> _personIds() async => {
    for (final r
        in await _db
            .customSelect(
              'SELECT id FROM persons WHERE grouping_locked = 0 AND kind = ?',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.persons},
            )
            .get())
      r.read<int>('id'),
  };
}
