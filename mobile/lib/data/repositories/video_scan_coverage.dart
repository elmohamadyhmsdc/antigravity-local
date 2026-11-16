import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'app_settings.dart';

/// Coverage is separate from scan_status: a completed quick pass is indexed,
/// but has not had the denser detailed pass. No library-wide scan version bump.
class VideoScanCoverage {
  VideoScanCoverage(this.db);
  final AppDatabase db;
  static const prefix = 'video.coverage.';
  static const detailPrefix = 'video.detail.';
  static const activePrefix = 'video.coverage.active.';
  static String assetKey(String assetId, int modifiedAt, int? durationMs) =>
      jsonEncode([assetId, modifiedAt, durationMs]);
  static const detailedPendingSql =
      "EXISTS (SELECT 1 FROM settings s WHERE "
      "s.key = '$detailPrefix' || media.id)";

  static Map<String, dynamic> signature(MediaRow media) => {
    'asset': media.assetId,
    'modified': media.modifiedAt,
    'duration': media.durationMs,
    'width': media.width,
    'height': media.height,
  };

  static VideoScanMode? decode(
    String? raw, {
    required String assetId,
    required int modifiedAt,
    required int? durationMs,
  }) {
    try {
      final value = jsonDecode(raw ?? 'null');
      if (value is! Map ||
          value['asset'] != assetId ||
          value['modified'] != modifiedAt ||
          value['duration'] != durationMs) {
        return null;
      }
      return switch (value['mode']) {
        'quick' => VideoScanMode.quick,
        'detailed' => VideoScanMode.detailed,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  Future<VideoScanMode?> mode(MediaRow media) async => decode(
    await db.setting('$prefix${media.id}'),
    assetId: media.assetId,
    modifiedAt: media.modifiedAt,
    durationMs: media.durationMs,
  );

  Future<Set<String>> quickAssets() async {
    final rows = await db
        .customSelect(
          '''
      SELECT m.asset_id, m.modified_at, m.duration_ms, s.value FROM media m
      JOIN settings s ON s.key = '$prefix' || m.id WHERE m.kind = 'video'
    ''',
          readsFrom: {db.media, db.settings},
        )
        .get();
    return {
      for (final row in rows)
        if (decode(
              row.read<String>('value'),
              assetId: row.read<String>('asset_id'),
              modifiedAt: row.read<int>('modified_at'),
              durationMs: row.readNullable<int>('duration_ms'),
            ) ==
            VideoScanMode.quick)
          assetKey(
            row.read<String>('asset_id'),
            row.read<int>('modified_at'),
            row.readNullable<int>('duration_ms'),
          ),
    };
  }

  Stream<VideoScanMode?> watch(MediaRow media) =>
      (db.select(db.settings)..where((s) => s.key.equals('$prefix${media.id}')))
          .watchSingleOrNull()
          .map(
            (row) => decode(
              row?.value,
              assetId: media.assetId,
              modifiedAt: media.modifiedAt,
              durationMs: media.durationMs,
            ),
          );

  Future<bool> detailRequested(MediaRow media) async =>
      await db.setting('$detailPrefix${media.id}') ==
      jsonEncode(signature(media));

  Future<VideoScanMode> requestedMode(
    MediaRow media,
    VideoScanMode preferred,
  ) async => await detailRequested(media) ? VideoScanMode.detailed : preferred;

  Future<VideoScanMode?> activeMode(MediaRow media) async => decode(
    await db.setting('$activePrefix${media.id}'),
    assetId: media.assetId,
    modifiedAt: media.modifiedAt,
    durationMs: media.durationMs,
  );

  Future<void> pinMode(MediaRow media, VideoScanMode mode) => db.putSetting(
    '$activePrefix${media.id}',
    jsonEncode({...signature(media), 'mode': mode.name}),
  );

  /// Does not discard an in-flight grid. A request made during a quick scan
  /// becomes pending only after that pass has committed.
  Future<bool> requestDetailed(int mediaId) => db.transaction(() async {
    final media = await (db.select(
      db.media,
    )..where((m) => m.id.equals(mediaId))).getSingleOrNull();
    if (media == null || media.kind != 'video') {
      return false;
    }
    if (media.scanStatus != 'done' && await detailRequested(media)) {
      return true;
    }
    if (media.scanStatus == 'done' &&
        media.scanError == null &&
        await mode(media) != VideoScanMode.quick) {
      return false;
    }
    await db.putSetting('$detailPrefix$mediaId', jsonEncode(signature(media)));
    if (media.scanStatus != 'scanning') {
      await _requeue(mediaId);
    }
    return true;
  });

  Future<void> _requeue(int mediaId) async {
    await (db.delete(db.settings)..where(
          (s) => s.key.isIn([
            'video.job.$mediaId',
            'video.local.$mediaId',
            '$activePrefix$mediaId',
          ]),
        ))
        .go();
    await (db.update(db.media)..where((m) => m.id.equals(mediaId))).write(
      const MediaCompanion(
        scanStatus: Value('pending'),
        lastScannedFrame: Value(0),
        scanAttempts: Value(0),
        scanError: Value(null),
      ),
    );
  }

  /// Called in the video completion transaction, after its done row is stored.
  /// Warnings do not grant coverage; the previous completed coverage stays valid.
  Future<void> complete(
    MediaRow media,
    VideoScanMode completedMode, {
    required bool clean,
  }) async {
    if (!clean) {
      if (completedMode == VideoScanMode.quick &&
          await detailRequested(media)) {
        await _requeue(media.id);
      }
      return;
    }
    final retainedMode = await mode(media) == VideoScanMode.detailed
        ? VideoScanMode.detailed
        : completedMode;
    await db.putSetting(
      '$prefix${media.id}',
      jsonEncode({...signature(media), 'mode': retainedMode.name}),
    );
    await (db.delete(
      db.settings,
    )..where((s) => s.key.equals('$activePrefix${media.id}'))).go();
    if (completedMode == VideoScanMode.detailed) {
      await (db.delete(
        db.settings,
      )..where((s) => s.key.equals('$detailPrefix${media.id}'))).go();
    } else if (await detailRequested(media)) {
      await _requeue(media.id);
    }
  }
}
