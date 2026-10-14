import 'dart:convert';

import '../db/app_database.dart';

abstract final class SettingKeys {
  static const strictness = 'grouping.strictness';
  static const qualityGate = 'quality.gate';
  static const albumIds = 'scan.albums';
  static const scanBodies = 'scan.bodies';
  static const maxSide = 'scan.max_side';
  static const scanActive = 'scan.active';
  static const modelId = 'library.model_id';
  static const lastBackupAt = 'backup.last_at';

  /// Keys that describe the library itself and travel inside a backup. `scan.active` and anything
  /// about the paired PC stay on this phone.
  static const backedUp = [
    strictness,
    qualityGate,
    albumIds,
    scanBodies,
    maxSide,
    modelId,
  ];
}

const strictnessChoices = ['strict', 'balanced', 'loose'];

const minQualityGate = 0.20;
const maxQualityGate = 0.80;
const defaultQualityGate = 0.40; // face_quality.DEFAULT_MIN_QUALITY on the PC
const defaultMaxSide = 2560;
const maxSideChoices = [1600, 2048, 2560, 3072];

/// Everything the user can tune, read as one immutable snapshot.
class SettingsSnapshot {
  const SettingsSnapshot({
    this.strictness = 'balanced',
    this.qualityGate = defaultQualityGate,
    this.albumIds = const [],
    this.scanBodies = true,
    this.maxSide = defaultMaxSide,
    this.scanActive = false,
    this.modelId,
    this.lastBackupAt,
  });

  factory SettingsSnapshot.fromMap(Map<String, String> m) {
    final strictness = m[SettingKeys.strictness];
    final gate = double.tryParse(m[SettingKeys.qualityGate] ?? '');
    final side = int.tryParse(m[SettingKeys.maxSide] ?? '');
    List<String> albums = const [];
    try {
      final decoded = jsonDecode(m[SettingKeys.albumIds] ?? '[]');
      if (decoded is List) albums = [for (final a in decoded) '$a'];
    } on FormatException {
      albums = const [];
    }
    final backup = int.tryParse(m[SettingKeys.lastBackupAt] ?? '');
    return SettingsSnapshot(
      strictness: strictnessChoices.contains(strictness)
          ? strictness!
          : 'balanced',
      qualityGate: gate == null
          ? defaultQualityGate
          : gate.clamp(minQualityGate, maxQualityGate).toDouble(),
      albumIds: albums,
      scanBodies: (m[SettingKeys.scanBodies] ?? '1') != '0',
      maxSide: side == null ? defaultMaxSide : side.clamp(800, 4096),
      scanActive: m[SettingKeys.scanActive] == '1',
      modelId: m[SettingKeys.modelId],
      lastBackupAt: backup == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(backup),
    );
  }

  final String
  strictness; // strict | balanced | loose (person_linking.STRICTNESS)
  final double qualityGate; // faces below this quality are not stored
  final List<String>
  albumIds; // MediaStore bucket ids chosen on the Sources screen
  final bool scanBodies;
  final int maxSide; // long side of the picture sent to the PC
  final bool
  scanActive; // a scan was started and not finished/paused: resume it after a restart
  final String? modelId; // embedding model of this library (never mix models)
  final DateTime? lastBackupAt;
}

/// Typed access to the `settings` table (a key/value store inside the encrypted database).
class AppSettings {
  AppSettings(this._db);

  final AppDatabase _db;

  Future<Map<String, String>> _all() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final r in rows) r.key: r.value};
  }

  Future<SettingsSnapshot> load() async =>
      SettingsSnapshot.fromMap(await _all());

  Stream<SettingsSnapshot> watch() => _db
      .select(_db.settings)
      .watch()
      .map(
        (rows) =>
            SettingsSnapshot.fromMap({for (final r in rows) r.key: r.value}),
      );

  Future<void> _put(String key, String value) => _db.putSetting(key, value);

  Future<void> setStrictness(String value) {
    assert(strictnessChoices.contains(value));
    return _put(SettingKeys.strictness, value);
  }

  Future<void> setQualityGate(double value) => _put(
    SettingKeys.qualityGate,
    value.clamp(minQualityGate, maxQualityGate).toStringAsFixed(2),
  );

  Future<void> setAlbumIds(Iterable<String> ids) =>
      _put(SettingKeys.albumIds, jsonEncode(ids.toSet().toList()..sort()));

  Future<void> setScanBodies(bool value) =>
      _put(SettingKeys.scanBodies, value ? '1' : '0');

  Future<void> setMaxSide(int value) => _put(SettingKeys.maxSide, '$value');

  Future<void> setScanActive(bool value) =>
      _put(SettingKeys.scanActive, value ? '1' : '0');

  Future<void> setModelId(String value) => _put(SettingKeys.modelId, value);

  Future<void> setLastBackupAt(DateTime value) =>
      _put(SettingKeys.lastBackupAt, '${value.millisecondsSinceEpoch}');

  /// Replaces (or removes) a batch of raw keys - used by a backup restore.
  Future<void> putRaw(Map<String, String> values) async {
    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.settings, [
        for (final e in values.entries)
          SettingsCompanion.insert(key: e.key, value: e.value),
      ]);
    });
  }

  Future<Map<String, String>> rawBackedUp() async {
    final all = await _all();
    return {
      for (final k in SettingKeys.backedUp)
        if (all.containsKey(k)) k: all[k]!,
    };
  }
}
