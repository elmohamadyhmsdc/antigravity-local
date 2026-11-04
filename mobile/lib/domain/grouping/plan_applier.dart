import 'package:drift/drift.dart';

import '../../data/api/dtos/grouping.dart';
import '../../data/db/app_database.dart';
import 'identity_evidence.dart';

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
        'UPDATE faces SET person_id = ? WHERE id = ? AND person_id IS NULL AND review_dismissed = 0 AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = faces.id AND r.person_id = ?) AND EXISTS (SELECT 1 FROM persons p WHERE p.id = ? AND p.grouping_locked = 0) AND (faces.media_id IS NULL OR NOT EXISTS (SELECT 1 FROM faces o WHERE o.person_id = ? AND o.media_id = faces.media_id AND o.frame_number IS faces.frame_number))',
        variables: [
          Variable.withInt(a.personId),
          Variable.withInt(a.faceId),
          Variable.withInt(a.personId),
          Variable.withInt(a.personId),
          Variable.withInt(a.personId),
        ],
        updates: {_db.faces},
      );
    }

    for (final g in plan.groups) {
      if (!g.autoCreate || g.faceIds.isEmpty) continue;
      final rows = await _db
          .customSelect(
            'SELECT id, quality_score FROM faces WHERE person_id IS NULL AND review_dismissed = 0 AND id IN (${List.filled(g.faceIds.length, '?').join(',')})',
            variables: [for (final id in g.faceIds) Variable.withInt(id)],
            readsFrom: {_db.faces},
          )
          .get();
      if (rows.length != g.faceIds.length) {
        continue; // part of the group was sorted meanwhile: ask again next round
      }
      if (await _fromOneFile(g.faceIds)) {
        continue; // one appearance in one video is not a person yet (Review still offers it)
      }
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

    // A video track is one appearance: once some of its faces have a person (and no other
    // person), the rest follow - unless the user refused that very pair.
    assigned += await _db.customUpdate(
      '''
      WITH owner AS (
        SELECT track_id, MIN(person_id) AS pid FROM faces
        WHERE track_id IS NOT NULL AND person_id IS NOT NULL
        GROUP BY track_id HAVING COUNT(DISTINCT person_id) = 1
      )
      UPDATE faces SET person_id = (SELECT pid FROM owner WHERE owner.track_id = faces.track_id)
      WHERE person_id IS NULL AND review_dismissed = 0
        AND track_id IN (SELECT track_id FROM owner)
        AND NOT EXISTS (
          SELECT 1 FROM face_rejections r JOIN owner o ON o.pid = r.person_id
          WHERE r.face_id = faces.id AND o.track_id = faces.track_id)
        AND EXISTS (
          SELECT 1 FROM persons p JOIN owner o ON o.pid = p.id
          WHERE o.track_id = faces.track_id AND p.grouping_locked = 0)
      ''',
      updates: {_db.faces},
    );
    return FacePlanResult(
      assigned: assigned,
      newPeople: newPeople,
      facesInNewPeople: inNew,
    );
  });

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
          isClothingOnlyLink(l.method)) {
        continue;
      }
      linked += await _db.customUpdate(
        "UPDATE bodies SET person_id = ?, link_method = ?, link_confidence = ? WHERE id = ? AND person_id IS NULL AND (ownership IS NULL OR ownership != 'none') AND hidden = 0 AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = bodies.id AND r.person_id = ?) AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.id = bodies.face_id AND f.person_id IS NOT NULL) AND NOT EXISTS (SELECT 1 FROM body_distinct d JOIN bodies o ON (o.id = CASE WHEN d.body_a = bodies.id THEN d.body_b ELSE d.body_a END) WHERE (d.body_a = bodies.id OR d.body_b = bodies.id) AND o.person_id = ?)",
        variables: [
          Variable.withInt(l.personId),
          Variable.withString(l.method),
          Variable.withReal(l.confidence),
          Variable.withInt(l.bodyId),
          Variable.withInt(l.personId),
          Variable.withInt(l.personId),
        ],
        updates: {_db.bodies},
      );
    }
    return linked;
  });

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
