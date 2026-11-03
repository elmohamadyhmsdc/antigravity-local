import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/sensitive_store.dart';
import 'sensitive_policy.dart';

/// Roadmap section 8.3: asks the PC for exposed / covered regions of the photos scanned before the
/// feature existed (`media.sensitive_version` below the PC model version), one photo at a time, in the
/// background. Modelled on `OutlineBackfill`, but a queue instead of an on-demand call:
///
/// * never competes with a scan: [run] stops as soon as [shouldContinue] says so (a scan started, the
///   user paused, storage maintenance, the server is not ready);
/// * a photo without regions is still marked as checked, so it is not asked again;
/// * one transaction per photo, so stopping at any moment loses nothing;
/// * videos are covered by the video scan (S4), not here.
class SensitiveBackfill {
  SensitiveBackfill({
    required this.db,
    required this.media,
    required this.api,
    this.maxSide = 2560,
    Future<(int, int)?> Function(Uint8List)? decodeDimensions,
  }) : _decodeDimensions = decodeDimensions ?? _defaultDecodeDimensions,
       _store = SensitiveStore(db);

  final AppDatabase db;
  final MediaLibrary media;
  final MobileApi? Function() api;
  final int maxSide;
  final Future<(int, int)?> Function(Uint8List) _decodeDimensions;
  final SensitiveStore _store;

  bool _running = false;
  bool get isRunning => _running;

  static Future<(int, int)?> _defaultDecodeDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  /// Photos still to check.
  Future<int> pending() async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM media WHERE kind = 'photo' AND scan_status = 'done' "
                'AND sensitive_version < ?',
                variables: [Variable.withInt(sensitiveModelVersion)],
                readsFrom: {db.media},
              )
              .getSingle())
          .read<int>('n');

  /// Checks photos until none is left or [shouldContinue] turns false. Returns how many were done.
  /// Stops quietly (and leaves the rest queued) when the PC has no model or is busy.
  Future<int> run({
    bool Function()? shouldContinue,
    void Function(int done)? onProgress,
    int? limit,
  }) async {
    if (_running) return 0;
    _running = true;
    var done = 0;
    final skipped = <int>{};
    try {
      while ((limit == null || done < limit) &&
          (shouldContinue?.call() ?? true)) {
        final client = api();
        if (client == null) break;
        final next =
            await (db.select(db.media)
                  ..where(
                    (m) =>
                        m.kind.equals('photo') &
                        m.scanStatus.equals('done') &
                        m.sensitiveVersion.isSmallerThanValue(
                          sensitiveModelVersion,
                        ) &
                        m.id.isNotIn(skipped),
                  )
                  ..orderBy([(m) => OrderingTerm.asc(m.id)])
                  ..limit(1))
                .getSingleOrNull();
        if (next == null) break;
        try {
          final ok = await _one(client, next);
          if (!ok) skipped.add(next.id);
          if (ok) {
            done++;
            onProgress?.call(done);
          }
        } on ApiException catch (e) {
          // no model on the PC / the GPU is busy / the PC is gone: try again another time
          if (e.code == 'model_missing' ||
              e.code == 'gpu_busy' ||
              e.retryable) {
            break;
          }
          skipped.add(next.id);
        } catch (_) {
          skipped.add(next.id);
        }
      }
    } finally {
      _running = false;
    }
    return done;
  }

  Future<bool> _one(MobileApi client, MediaRow row) async {
    final bytes = await media.downscaledJpeg(
      row.assetId,
      width: row.width ?? 0,
      height: row.height ?? 0,
      maxSide: maxSide,
    );
    if (bytes == null) return false;
    final dims = await _decodeDimensions(bytes);
    if (dims == null || dims.$1 <= 0 || dims.$2 <= 0) return false;
    final (w, h) = dims;

    final bodies =
        await (db.select(db.bodies)
              ..where(
                (b) =>
                    // people AND drawn characters: both get the same regions
                    b.mediaId.equals(row.id) & b.frameNumber.isNull(),
              )
              ..orderBy([(b) => OrderingTerm.asc(b.id)])
              ..limit(64))
            .get();
    final targets = [
      for (final b in bodies)
        SensitiveBodyTargetDto(
          bbox: BBox(
            x: b.bboxX * w,
            y: b.bboxY * h,
            w: b.bboxW * w,
            h: b.bboxH * h,
          ),
          kpts: _pixelKpts(b.kpts, w, h),
        ),
    ];
    final response = await client.analyzeSensitive(bytes, targets);
    await _store.replaceRegions(
      row.id,
      response.regions,
      imageW: w,
      imageH: h,
      bodyIds: {for (var i = 0; i < bodies.length; i++) i: bodies[i].id},
      modelVersion: response.modelVersion < sensitiveModelVersion
          ? sensitiveModelVersion
          : response.modelVersion,
    );
    return true;
  }

  static List<List<double>>? _pixelKpts(String? json, int w, int h) {
    if (json == null) return null;
    try {
      final raw = jsonDecode(json) as List<dynamic>;
      if (raw.length != 17) return null;
      return [
        for (final p in raw)
          [
            (p[0] as num).toDouble() * w,
            (p[1] as num).toDouble() * h,
            (p[2] as num).toDouble(),
          ],
      ];
    } catch (_) {
      return null;
    }
  }
}
