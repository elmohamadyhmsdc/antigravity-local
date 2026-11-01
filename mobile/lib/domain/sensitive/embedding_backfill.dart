import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/embedding.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';

/// Bump when the PC's embedding model or morphology changes (`body_embeddings.MODEL_VERSION`).
const bodyEmbeddingModelVersion = 1;

/// Settings key. Absent / anything but 'false' = on; the user can switch it off.
const embeddingBackfillKey = 'body_embeddings_backfill_enabled';

/// NudeNet labels that make a patch (the PC's `body_embeddings.CHEST_LABELS | LOWER_LABELS`) and the score the
/// PC ignores below.
const _patchLabels = [
  'FEMALE_BREAST_EXPOSED',
  'MALE_BREAST_EXPOSED',
  'BELLY_EXPOSED',
  'BUTTOCKS_EXPOSED',
  'FEMALE_GENITALIA_EXPOSED',
  'MALE_GENITALIA_EXPOSED',
  'ANUS_EXPOSED',
];
const _patchMinScore = 0.5;

/// Roadmap 7.5 for photos scanned before Phase 8: asks the PC for the chest / lower-body embeddings and
/// morphology of the bodies that have exposed regions (`/v1/analyze/sensitive` with `embeddings`), one photo
/// at a time, in the background. Same discipline as `SensitiveBackfill`:
///
/// * never competes with a scan: [run] stops as soon as [shouldContinue] says so;
/// * only photos whose regions are known (`sensitive_version`), since the regions say whether there is
///   anything to embed: a photo without a patch-worthy region is marked done WITHOUT a request;
/// * one transaction per photo (embeddings + the marker), stored in place with COALESCE;
/// * stops quietly on `model_missing`, a busy GPU or a lost PC and leaves the queue as it was.
class EmbeddingBackfill {
  EmbeddingBackfill({
    required this.db,
    required this.media,
    required this.api,
    this.maxSide = 2560,
    Future<(int, int)?> Function(Uint8List)? decodeDimensions,
  }) : _decodeDimensions = decodeDimensions ?? _defaultDecodeDimensions;

  final AppDatabase db;
  final MediaLibrary media;
  final MobileApi? Function() api;
  final int maxSide;
  final Future<(int, int)?> Function(Uint8List) _decodeDimensions;

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

  Future<bool> get enabled async =>
      await db.setting(embeddingBackfillKey) != 'false';

  Future<void> setEnabled(bool on) =>
      db.putSetting(embeddingBackfillKey, on ? 'true' : 'false');

  /// Photos still to check.
  Future<int> pending() async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM media WHERE kind = 'photo' AND scan_status = 'done' "
                'AND sensitive_version >= 1 AND body_embedding_version < ?',
                variables: [Variable.withInt(bodyEmbeddingModelVersion)],
                readsFrom: {db.media},
              )
              .getSingle())
          .read<int>('n');

  Future<int> run({
    bool Function()? shouldContinue,
    void Function(int done)? onProgress,
    int? limit,
  }) async {
    if (_running || !await enabled) return 0;
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
                        m.sensitiveVersion.isBiggerOrEqualValue(1) &
                        m.bodyEmbeddingVersion.isSmallerThanValue(
                          bodyEmbeddingModelVersion,
                        ) &
                        m.id.isNotIn(skipped),
                  )
                  ..orderBy([(m) => OrderingTerm.asc(m.id)])
                  ..limit(1))
                .getSingleOrNull();
        if (next == null) break;
        try {
          if (await _one(client, next)) {
            done++;
            onProgress?.call(done);
          } else {
            skipped.add(next.id);
          }
        } on ApiException catch (e) {
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

  Future<void> _mark(int mediaId) =>
      (db.update(db.media)..where((m) => m.id.equals(mediaId))).write(
        const MediaCompanion(
          bodyEmbeddingVersion: Value(bodyEmbeddingModelVersion),
        ),
      );

  Future<bool> _one(MobileApi client, MediaRow row) async {
    final patchWorthy =
        (await db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM sensitive_regions WHERE media_id = ? AND score >= ? '
                  'AND label IN (${_patchLabels.map((_) => '?').join(',')})',
                  variables: [
                    Variable.withInt(row.id),
                    Variable.withReal(_patchMinScore),
                    for (final l in _patchLabels) Variable.withString(l),
                  ],
                  readsFrom: {db.sensitiveRegions},
                )
                .getSingle())
            .read<int>('n');
    if (patchWorthy == 0) {
      await _mark(row.id); // nothing to embed: no request, no GPU
      return true;
    }
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
                    b.mediaId.equals(row.id) &
                    b.frameNumber.isNull() &
                    b.kind.equals('person'),
              )
              ..orderBy([(b) => OrderingTerm.asc(b.id)])
              ..limit(64))
            .get();
    final response = await client.analyzeSensitive(bytes, [
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
    ], embeddings: true);
    final results = response.bodies;
    if (results == null || results.length != bodies.length) return false;
    await db.transaction(() async {
      for (var i = 0; i < bodies.length; i++) {
        final r = results[i];
        if (r.chestEmbedding == null &&
            r.buttocksEmbedding == null &&
            r.morphology == null) {
          continue;
        }
        await db.customUpdate(
          'UPDATE bodies SET chest_embedding = COALESCE(?, chest_embedding), '
          'buttocks_embedding = COALESCE(?, buttocks_embedding), morphology = COALESCE(?, morphology) WHERE id = ?',
          variables: [
            Variable<Uint8List>(
              r.chestEmbedding == null
                  ? null
                  : embeddingToBlob(r.chestEmbedding!),
            ),
            Variable<Uint8List>(
              r.buttocksEmbedding == null
                  ? null
                  : embeddingToBlob(r.buttocksEmbedding!),
            ),
            Variable<String>(
              r.morphology == null ? null : jsonEncode(r.morphology),
            ),
            Variable.withInt(bodies[i].id),
          ],
          updates: {db.bodies},
        );
      }
      await _mark(row.id);
    });
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
