import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// A durable snapshot of one identity's files, including duplicate occurrences
/// and videos. Queue ownership is separate from the library-wide repair.
class IdentityRescan {
  IdentityRescan(this.db);

  final AppDatabase db;
  static const prefix = 'scan.identity_rescan.media.';
  static const _personKey = 'scan.identity_rescan.person';
  static const pendingSql =
      "EXISTS (SELECT 1 FROM settings s "
      "WHERE s.key = '$prefix' || media.id AND s.value = 'pending')";

  Future<int?> personId() async =>
      int.tryParse(await db.setting(_personKey) ?? '');

  Future<bool> pending(int mediaId) async =>
      await db.setting('$prefix$mediaId') == 'pending';

  Future<void> finish(int mediaId) async {
    if (await pending(mediaId)) await db.putSetting('$prefix$mediaId', 'done');
  }

  Future<void> endSession() => db.putSetting(_personKey, '');

  Future<void> retarget(int sourceId, int targetId) async {
    if (await personId() == sourceId) {
      await db.putSetting(_personKey, '$targetId');
    }
  }

  Future<bool> hasPending() async =>
      (await db
              .customSelect(
                'SELECT 1 FROM media WHERE $pendingSql LIMIT 1',
                readsFrom: {db.media, db.settings},
              )
              .get())
          .isNotEmpty;

  Future<void> retryIncomplete() => db.transaction(() async {
    await db.customUpdate(
      '''DELETE FROM settings WHERE key IN (
        SELECT 'video.job.' || media.id FROM media WHERE scan_status = 'done' AND $pendingSql
        UNION ALL SELECT 'video.local.' || media.id FROM media WHERE scan_status = 'done' AND $pendingSql
      )''',
      updates: {db.settings},
    );
    await db.customUpdate(
      '''UPDATE media SET last_scanned_frame = CASE WHEN scan_status = 'done' THEN 0 ELSE last_scanned_frame END,
        scan_status = 'pending', scan_attempts = 0, scan_error = NULL
        WHERE scan_status IN ('failed', 'done', 'skipped') AND $pendingSql''',
      updates: {db.media},
    );
  });

  /// Explicitly starting again resets video cursors once. Resuming uses the
  /// saved scope and checkpoints without calling this method.
  Future<int> enqueue(int personId) => db.transaction(() async {
    final person = await (db.select(
      db.persons,
    )..where((p) => p.id.equals(personId))).getSingleOrNull();
    if (person == null) throw StateError('This identity no longer exists.');
    await (db.delete(db.settings)..where((s) => s.key.like('$prefix%'))).go();
    await db.customInsert(
      '''INSERT INTO settings (key, value)
      SELECT ?1 || m.id, 'pending' FROM media m
      WHERE m.kind IN ('photo', 'video') AND m.id IN (
        SELECT media_id FROM faces WHERE person_id = ?2 AND hidden = 0
        UNION SELECT b.media_id FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
          WHERE COALESCE(f.person_id, b.person_id) = ?2 AND b.hidden = 0
        UNION SELECT d.media_id FROM media_detections d JOIN faces f
          ON d.kind = 'f' AND f.id = d.ref_id WHERE f.person_id = ?2 AND f.hidden = 0
        UNION SELECT d.media_id FROM media_detections d JOIN bodies b
          ON d.kind = 'b' AND b.id = d.ref_id LEFT JOIN faces f ON f.id = b.face_id
          WHERE COALESCE(f.person_id, b.person_id) = ?2 AND b.hidden = 0
      )''',
      variables: [Variable.withString(prefix), Variable.withInt(personId)],
      updates: {db.settings},
    );
    await db.customUpdate(
      '''DELETE FROM settings WHERE key IN (
        SELECT 'video.job.' || media.id FROM media WHERE $pendingSql
        UNION ALL SELECT 'video.local.' || media.id FROM media WHERE $pendingSql
      )''',
      updates: {db.settings},
    );
    final count = await db.customUpdate(
      '''UPDATE media SET scan_status = 'pending', scan_attempts = 0,
        scan_error = NULL, last_scanned_frame = 0 WHERE $pendingSql''',
      updates: {db.media},
    );
    await db.putSetting(_personKey, '$personId');
    return count;
  });
}
