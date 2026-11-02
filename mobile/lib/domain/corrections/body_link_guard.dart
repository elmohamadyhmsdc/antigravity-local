import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';

class BodyLinkGuard {
  const BodyLinkGuard(this.db);
  final AppDatabase db;

  /// Check whether an automatic process can link [bodyId] to [personId].
  /// Returns false if:
  /// - body has ownership == 'none'
  /// - body is hidden
  /// - body is in body_rejections for personId
  /// - body is marked distinct from any other body currently assigned to personId
  Future<bool> canAutoLink(int bodyId, int personId) async {
    final body = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(bodyId))).getSingleOrNull();
    if (body == null) return false;
    if (body.ownership == 'none' || body.hidden) return false;

    // Check body_rejections
    final rejected =
        await (db.select(db.bodyRejections)..where(
              (r) => r.bodyId.equals(bodyId) & r.personId.equals(personId),
            ))
            .getSingleOrNull();
    if (rejected != null) return false;

    // Check body_distinct against bodies of personId
    final distinctBodies = await getDistinctBodyIds(bodyId);
    if (distinctBodies.isEmpty) return true;

    final conflict =
        await (db.select(db.bodies)..where(
              (b) => b.personId.equals(personId) & b.id.isIn(distinctBodies),
            ))
            .get();
    return conflict.isEmpty;
  }

  /// Finds all body IDs marked distinct from [bodyId]
  Future<Set<int>> getDistinctBodyIds(int bodyId) async {
    final rows = await db
        .customSelect(
          'SELECT body_a, body_b FROM body_distinct WHERE body_a = ? OR body_b = ?',
          variables: [Variable.withInt(bodyId), Variable.withInt(bodyId)],
          readsFrom: {db.bodyDistinct},
        )
        .get();

    final result = <int>{};
    for (final row in rows) {
      final a = row.read<int>('body_a');
      final b = row.read<int>('body_b');
      result.add(a == bodyId ? b : a);
    }
    return result;
  }

  /// For person merge: returns body IDs from [sourcePersonId] that conflict with [targetPersonId].
  Future<List<int>> findMergeConflicts(
    int sourcePersonId,
    int targetPersonId,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT s.id AS source_body_id
      FROM bodies s
      JOIN body_distinct d ON (d.body_a = s.id OR d.body_b = s.id)
      JOIN bodies t ON (t.id = CASE WHEN d.body_a = s.id THEN d.body_b ELSE d.body_a END)
      WHERE s.person_id = ? AND t.person_id = ?
      ''',
          variables: [
            Variable.withInt(sourcePersonId),
            Variable.withInt(targetPersonId),
          ],
          readsFrom: {db.bodies, db.bodyDistinct},
        )
        .get();

    return rows.map((r) => r.read<int>('source_body_id')).toSet().toList();
  }

  /// Manual link: clears distinct conflicts for [bodyId] with bodies of [personId].
  Future<void> onManualLink(int bodyId, int personId) async {
    await db.customUpdate(
      '''
      DELETE FROM body_distinct
      WHERE (body_a = ?1 AND body_b IN (SELECT id FROM bodies WHERE person_id = ?2))
         OR (body_b = ?1 AND body_a IN (SELECT id FROM bodies WHERE person_id = ?2))
      ''',
      variables: [Variable.withInt(bodyId), Variable.withInt(personId)],
      updates: {db.bodyDistinct},
    );
  }
}
