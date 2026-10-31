import 'dart:convert';

import '../db/app_database.dart';

abstract final class SettingKeys {
  static const strictness = 'grouping.strictness';
  static const qualityGate = 'quality.gate';
  static const albumIds = 'scan.albums';
  static const scanBodies = 'scan.bodies';

  /// Albums the user marked as anime/cartoon: scanned for characters (plus clear real faces).
  static const characterAlbumIds = 'scan.character_albums';
  static const scanVideos = 'scan.videos';
  static const frameInterval = 'scan.frame_interval';
  static const adaptiveVideoSampling = 'scan.adaptive_video_sampling';
  static const maxSide = 'scan.max_side';
  static const scanActive = 'scan.active';
  static const modelId = 'library.model_id';
  static const lastBackupAt = 'backup.last_at';

  /// Show scores as numbers and open Review on the four tabs (a per-phone display choice).
  static const reviewAdvanced = 'review.advanced';

  /// Keys that describe the library itself and travel inside a backup. `scan.active` and anything
  /// about the paired PC stay on this phone.
  static const backedUp = [
    strictness,
    qualityGate,
    albumIds,
    scanBodies,
    characterAlbumIds,
    scanVideos,
    frameInterval,
    adaptiveVideoSampling,
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
    this.characterAlbumIds = const [],
    this.scanVideos = true,
    this.frameInterval = 1.0,
    this.adaptiveVideoSampling = true,
    this.maxSide = defaultMaxSide,
    this.scanActive = false,
    this.modelId,
    this.lastBackupAt,
    this.reviewAdvanced = false,
  });

  factory SettingsSnapshot.fromMap(Map<String, String> m) {
    final strictness = m[SettingKeys.strictness];
    final gate = double.tryParse(m[SettingKeys.qualityGate] ?? '');
    final side = int.tryParse(m[SettingKeys.maxSide] ?? '');
    List<String> ids(String key) {
      try {
        final decoded = jsonDecode(m[key] ?? '[]');
        if (decoded is List) return [for (final a in decoded) '$a'];
      } on FormatException {
        /* treated as none chosen */
      }
      return const [];
    }

    final backup = int.tryParse(m[SettingKeys.lastBackupAt] ?? '');
    return SettingsSnapshot(
      strictness: strictnessChoices.contains(strictness)
          ? strictness!
          : 'balanced',
      qualityGate: gate == null
          ? defaultQualityGate
          : gate.clamp(minQualityGate, maxQualityGate).toDouble(),
      albumIds: ids(SettingKeys.albumIds),
      scanBodies: (m[SettingKeys.scanBodies] ?? '1') != '0',
      characterAlbumIds: ids(SettingKeys.characterAlbumIds),
      scanVideos: (m[SettingKeys.scanVideos] ?? '1') != '0',
      adaptiveVideoSampling: m[SettingKeys.adaptiveVideoSampling] != '0',
      frameInterval:
          (double.tryParse(m[SettingKeys.frameInterval] ?? '') ?? 1.0).clamp(
            0.25,
            60,
          ),
      maxSide: side == null ? defaultMaxSide : side.clamp(800, 4096),
      scanActive: m[SettingKeys.scanActive] == '1',
      modelId: m[SettingKeys.modelId],
      lastBackupAt: backup == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(backup),
      reviewAdvanced: m[SettingKeys.reviewAdvanced] == '1',
    );
  }

  final String
  strictness; // strict | balanced | loose (person_linking.STRICTNESS)
  final double qualityGate; // faces below this quality are not stored
  final List<String>
  albumIds; // MediaStore bucket ids chosen on the Sources screen
  final bool scanBodies;
  final List<String>
  characterAlbumIds; // subset of albumIds marked anime/cartoon
  final bool scanVideos;
  final double frameInterval;
  final bool adaptiveVideoSampling;
  final int maxSide; // long side of the picture sent to the PC
  final bool
  scanActive; // a scan was started and not finished/paused: resume it after a restart
  final String? modelId; // embedding model of this library (never mix models)
  final DateTime? lastBackupAt;

  /// Percentages, link methods and the four-tab Review instead of words and the quick review.
  final bool reviewAdvanced;
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

  /// The next explicit scan rescans files whose album was marked or unmarked
  /// (`LibraryRepository.syncAssets` compares each file's `illustrated` flag).
  Future<void> setCharacterAlbumIds(Iterable<String> ids) => _put(
    SettingKeys.characterAlbumIds,
    jsonEncode(ids.toSet().toList()..sort()),
  );

  Future<void> setScanVideos(bool value) =>
      _put(SettingKeys.scanVideos, value ? '1' : '0');

  Future<void> setFrameInterval(double value) =>
      _put(SettingKeys.frameInterval, value.clamp(0.25, 60).toString());

  Future<void> setAdaptiveVideoSampling(bool value) =>
      _put(SettingKeys.adaptiveVideoSampling, value ? '1' : '0');

  Future<void> setMaxSide(int value) => _put(SettingKeys.maxSide, '$value');

  Future<void> setScanActive(bool value) =>
      _put(SettingKeys.scanActive, value ? '1' : '0');

  Future<void> setModelId(String value) => _put(SettingKeys.modelId, value);

  Future<void> setReviewAdvanced(bool value) =>
      _put(SettingKeys.reviewAdvanced, value ? '1' : '0');

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
