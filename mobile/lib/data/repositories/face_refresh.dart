import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// The faces-only queue is independent of the normal and detailed scan state.
class FaceRefresh {
  FaceRefresh(this.db);

  final AppDatabase db;
  static const settingsPrefix = 'scan.face_refresh.';
  static const _session = '${settingsPrefix}session';
  static const _items = '${settingsPrefix}media.';
  static const _videoKeys = '${settingsPrefix}video.';
  static const evidencePrefix = '${settingsPrefix}face.';
  static const checkedPrefix = '${settingsPrefix}checked.';

  Future<bool> requested() async =>
      (await db.setting(_session) ?? '').isNotEmpty;
  Future<bool> needsScope() async => await db.setting(_session) == 'queued';
  Stream<bool> watchRequested() =>
      (db.select(db.settings)..where((row) => row.key.equals(_session)))
          .watchSingleOrNull()
          .map((row) => row?.value.isNotEmpty ?? false)
          .distinct();

  Future<void> request() => db.transaction(() async {
    if (!await requested()) await db.putSetting(_session, 'queued');
  });

  Future<void> activate() => db.transaction(() async {
    await _clearQueue();
    await db.customInsert(
      "INSERT INTO settings (key, value) SELECT '$_items' || id, 'pending' "
      "FROM media WHERE kind IN ('photo', 'video')",
      updates: {db.settings},
    );
    await db.putSetting(_session, 'active');
  });

  Future<void> retryFailed() async {
    await (db.update(db.settings)
          ..where((s) => s.key.like('$_items%') & s.value.equals('failed')))
        .write(const SettingsCompanion(value: Value('pending')));
  }

  Future<({int total, int done})> counts() async {
    final row = await db
        .customSelect(
          "SELECT COUNT(*) AS total, COALESCE(SUM(s.value = 'done'), 0) AS done "
          "FROM media m JOIN settings s ON s.key = '$_items' || m.id",
          readsFrom: {db.settings, db.media},
        )
        .getSingle();
    return (total: row.read<int>('total'), done: row.read<int>('done'));
  }

  Future<MediaRow?> next({int? afterId}) async {
    final query = db.select(db.media)
      ..where(
        (m) =>
            m.id.isBiggerThanValue(afterId ?? 0) &
            const CustomExpression<bool>(
              "EXISTS (SELECT 1 FROM settings s "
              "WHERE s.key = '$_items' || media.id AND s.value = 'pending')",
            ),
      )
      ..orderBy([(m) => OrderingTerm.asc(m.id)])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<void> fail(int id) => db.putSetting('$_items$id', 'failed');
  Future<void> finish(int id) async {
    await db.putSetting('$_items$id', 'done');
    await db.putSetting(
      '$checkedPrefix$id',
      '${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  Future<bool> finished(int id) async =>
      await db.setting('$_items$id') == 'done';
  Future<void> end() => db.transaction(() async {
    await _clearQueue();
    await db.putSetting(_session, '');
  });

  Future<int> _clearQueue() => (db.delete(
    db.settings,
  )..where((s) => s.key.like('$_items%') | s.key.like('$_videoKeys%'))).go();

  Future<int?> checkedAt(int mediaId) async =>
      int.tryParse(await db.setting('$checkedPrefix$mediaId') ?? '');

  String videoKey(String part, int id) => '$_videoKeys$part.$id';

  Future<int> cursor(MediaRow media) async {
    final value = await db.setting(videoKey('cursor', media.id));
    final signature = _videoSignature(media);
    return value != null && value.startsWith(signature)
        ? int.tryParse(value.substring(signature.length)) ?? 0
        : 0;
  }

  Future<void> advance(MediaRow media, int frame) => db.putSetting(
    videoKey('cursor', media.id),
    '${_videoSignature(media)}${frame + 1}',
  );

  static String _videoSignature(MediaRow media) =>
      '${media.modifiedAt}/${media.durationMs}/${media.width}/${media.height}/';

  Future<void> finishVideo(MediaRow media, {required bool clean}) async {
    await (db.delete(
      db.settings,
    )..where((s) => s.key.equals(videoKey('cursor', media.id)))).go();
    if (clean) {
      await finish(media.id);
    } else {
      await fail(media.id);
    }
  }

  Future<void> recordFaces(Iterable<int> ids, int measuredAt) async {
    if (ids.isEmpty) return;
    await db.batch(
      (batch) => batch.insertAll(db.settings, [
        for (final id in ids)
          SettingsCompanion.insert(
            key: '$evidencePrefix$id',
            value: '$measuredAt',
          ),
      ], mode: InsertMode.insertOrReplace),
    );
  }
}
