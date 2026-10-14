import 'package:drift/drift.dart';

import '../../data/api/dtos/grouping.dart';
import '../../data/db/app_database.dart';

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
  PlanApplier(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

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
        'UPDATE faces SET person_id = ? WHERE id = ? AND person_id IS NULL',
        variables: [Variable.withInt(a.personId), Variable.withInt(a.faceId)],
        updates: {_db.faces},
      );
    }

    for (final g in plan.groups) {
      if (!g.autoCreate || g.faceIds.isEmpty) continue;
      final rows = await _db
          .customSelect(
            'SELECT id, quality_score FROM faces WHERE person_id IS NULL AND id IN (${List.filled(g.faceIds.length, '?').join(',')})',
            variables: [for (final id in g.faceIds) Variable.withInt(id)],
            readsFrom: {_db.faces},
          )
          .get();
      if (rows.length != g.faceIds.length) {
        continue; // part of the group was sorted meanwhile: ask again next round
      }
      final quality = {
        for (final r in rows)
          r.read<int>('id'): r.read<double>('quality_score'),
      };
      final personId = await _db
          .into(_db.persons)
          .insert(
            PersonsCompanion.insert(createdAt: _clock().millisecondsSinceEpoch),
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
      "UPDATE bodies SET person_id = NULL, link_method = NULL, link_confidence = NULL WHERE link_method IN ('appearance', 'weak_face')",
      updates: {_db.bodies},
    );
    final people = await _personIds();
    var linked = 0;
    for (final l in plan.bodyLinks) {
      if (!l.isAuto || !people.contains(l.personId)) continue;
      linked += await _db.customUpdate(
        'UPDATE bodies SET person_id = ?, link_method = ?, link_confidence = ? WHERE id = ? AND person_id IS NULL',
        variables: [
          Variable.withInt(l.personId),
          Variable.withString(l.method),
          Variable.withReal(l.confidence),
          Variable.withInt(l.bodyId),
        ],
        updates: {_db.bodies},
      );
    }
    return linked;
  });

  Future<Set<int>> _personIds() async => {
    for (final r
        in await _db
            .customSelect('SELECT id FROM persons', readsFrom: {_db.persons})
            .get())
      r.read<int>('id'),
  };
}
