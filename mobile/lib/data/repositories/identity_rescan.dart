import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// A durable snapshot of one identity's files, including duplicate occurrences
/// and videos. Queue ownership is separate from the library-wide repair.
class IdentityRescan {
  IdentityRescan(this.db);

  final AppDatabase db;
  static const prefix = 'scan.identity_rescan.media.';
  static const _personKey = 'scan.identity_rescan.person';
  static const _queueKey = 'scan.identity_rescan.queue';
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

  Future<List<({int personId, List<int> mediaIds})>> _queued() async {
    final saved = await db.setting(_queueKey);
    if (saved == null || saved.isEmpty) return [];
    return [
      for (final item in jsonDecode(saved) as List)
        (
          personId: (item['personId'] as num).toInt(),
          mediaIds: (item['mediaIds'] as List).cast<int>(),
        ),
    ];
  }

  Future<void> _saveQueue(List<({int personId, List<int> mediaIds})> queue) =>
      db.putSetting(
        _queueKey,
        jsonEncode([
          for (final item in queue)
            {'personId': item.personId, 'mediaIds': item.mediaIds},
        ]),
      );

  Future<bool> hasQueued() async => (await _queued()).isNotEmpty;

  Future<Set<int>> reservedPersonIds() async => {
    if (await personId() case final int id) id,
    for (final item in await _queued()) item.personId,
  };

  Stream<int> watchQueuedCount() =>
      (db.select(
        db.settings,
      )..where((s) => s.key.equals(_queueKey))).watchSingleOrNull().map(
        (row) => row == null ? 0 : (jsonDecode(row.value) as List).length,
      );

  /// Snapshot now, without touching the active scan or any video checkpoints.
  /// Repeated taps on an active/waiting identity join its existing request.
  Future<void> queue(int personId) => db.transaction(() async {
    final queued = await _queued();
    if (await this.personId() == personId ||
        queued.any((item) => item.personId == personId)) {
      return;
    }
    queued.add((personId: personId, mediaIds: await _snapshot(personId)));
    await _saveQueue(queued);
  });

  /// Activate one waiting snapshot only after the previous identity settles.
  Future<void> activateNext() => db.transaction(() async {
    if (await personId() != null) return;
    final queued = await _queued();
    while (queued.isNotEmpty) {
      final next = queued.removeAt(0);
      final person = await (db.select(
        db.persons,
      )..where((p) => p.id.equals(next.personId))).getSingleOrNull();
      if (person == null) continue;
      await _activate(next.personId, next.mediaIds);
      break;
    }
    await _saveQueue(queued);
  });

  Future<void> retarget(int sourceId, int targetId) => db.transaction(() async {
    if (await personId() == sourceId) {
      await db.putSetting(_personKey, '$targetId');
    }
    final merged = <int, Set<int>>{};
    for (final item in await _queued()) {
      final id = item.personId == sourceId ? targetId : item.personId;
      (merged[id] ??= <int>{}).addAll(item.mediaIds);
    }
    await _saveQueue([
      for (final entry in merged.entries)
        (personId: entry.key, mediaIds: entry.value.toList()),
    ]);
  });

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
    return _activate(personId, await _snapshot(personId));
  });

  Future<List<int>> _snapshot(int personId) async {
    final person = await (db.select(
      db.persons,
    )..where((p) => p.id.equals(personId))).getSingleOrNull();
    if (person == null) throw StateError('This identity no longer exists.');
    final rows = await db
        .customSelect(
          '''SELECT m.id FROM media m
      WHERE m.kind IN ('photo', 'video') AND m.id IN (
        SELECT media_id FROM faces WHERE person_id = ?1 AND hidden = 0
        UNION SELECT b.media_id FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
          WHERE COALESCE(f.person_id, b.person_id) = ?1 AND b.hidden = 0
        UNION SELECT d.media_id FROM media_detections d JOIN faces f
          ON d.kind = 'f' AND f.id = d.ref_id WHERE f.person_id = ?1 AND f.hidden = 0
        UNION SELECT d.media_id FROM media_detections d JOIN bodies b
          ON d.kind = 'b' AND b.id = d.ref_id LEFT JOIN faces f ON f.id = b.face_id
          WHERE COALESCE(f.person_id, b.person_id) = ?1 AND b.hidden = 0
      )''',
          variables: [Variable.withInt(personId)],
          readsFrom: {db.media, db.faces, db.bodies, db.mediaDetections},
        )
        .get();
    return [for (final row in rows) row.read<int>('id')];
  }

  Future<int> _activate(int personId, List<int> mediaIds) async {
    await (db.delete(db.settings)..where((s) => s.key.like('$prefix%'))).go();
    // Chunk implicitly through individual settings writes: a large identity must
    // not exceed SQLite's bind-variable limit.
    for (final id in mediaIds) {
      await db.putSetting('$prefix$id', 'pending');
    }
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
  }
}
