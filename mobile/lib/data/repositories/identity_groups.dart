import 'package:drift/drift.dart';

import '../../domain/organization/dynamic_auto_organizer.dart';
import '../db/app_database.dart';

typedef IdentityGroupSummary = ({
  int id,
  String name,
  int people,
  int characters,
});

/// One organizing group per identity; both real people and drawn characters use
/// the same groups, while their visual identity models remain separate.
class IdentityGroupsRepository {
  IdentityGroupsRepository(this.db, {this.autoOrganizer});
  final AppDatabase db;
  final DynamicAutoOrganizer? autoOrganizer;

  Stream<List<IdentityGroupSummary>> watch() => db
      .customSelect(
        '''
    SELECT g.id, g.name,
      SUM(CASE WHEN p.kind = 'person' THEN 1 ELSE 0 END) AS people_count,
      SUM(CASE WHEN p.kind = 'character' THEN 1 ELSE 0 END) AS character_count
    FROM identity_groups g LEFT JOIN persons p ON p.group_id = g.id
    GROUP BY g.id ORDER BY g.name_key, g.id''',
        readsFrom: {db.identityGroups, db.persons},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            (
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              people: r.read<int>('people_count'),
              characters: r.read<int>('character_count'),
            ),
        ],
      );

  String _name(String name) {
    final value = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty || value.length > 80) {
      throw ArgumentError('Use a group name of 1–80 characters');
    }
    return value;
  }

  Future<int> create(String name) async {
    final value = _name(name);
    final existing = await (db.select(
      db.identityGroups,
    )..where((g) => g.nameKey.equals(value.toLowerCase()))).getSingleOrNull();
    if (existing != null) return existing.id;
    return db
        .into(db.identityGroups)
        .insert(
          IdentityGroupsCompanion.insert(
            name: value,
            nameKey: value.toLowerCase(),
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<void> rename(int id, String name) async {
    final value = _name(name);
    await (db.update(db.identityGroups)..where((g) => g.id.equals(id))).write(
      IdentityGroupsCompanion(
        name: Value(value),
        nameKey: Value(value.toLowerCase()),
      ),
    );
  }

  Future<void> assign(Iterable<int> people, int? groupId) =>
      db.transaction(() async {
        if (groupId != null &&
            await (db.select(
                  db.identityGroups,
                )..where((g) => g.id.equals(groupId))).getSingleOrNull() ==
                null) {
          throw ArgumentError('This group no longer exists');
        }
        final ids = people.toSet().toList();
        for (var start = 0; start < ids.length; start += 300) {
          await (db.update(db.persons)
                ..where((p) => p.id.isIn(ids.skip(start).take(300))))
              .write(PersonsCompanion(groupId: Value(groupId)));
        }
      });
      if (autoOrganizer != null) {
        for (final pId in people) {
          await autoOrganizer!.syncPersonGroup(pId);
        }
      }

  /// The group is removed; identities and originals stay in the library.
  Future<void> delete(int id) =>
      (db.delete(db.identityGroups)..where((g) => g.id.equals(id))).go();
}
