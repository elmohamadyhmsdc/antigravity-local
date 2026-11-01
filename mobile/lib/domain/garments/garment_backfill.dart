import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';

/// Roadmap Phase 7: the PC garment-tag version the phone asks for. Photos below it are asked again.
const garmentModelVersion = 1;

/// Settings key; absent / anything but 'true' = OFF. The tags are evidence for the user's own labelling and
/// nothing reads them as a filter yet, so the PC does no tagging unless the user switches this on.
const garmentTagsEnabledKey = 'garment_tags_enabled';

/// Roadmap Phase 7: asks the PC for raw garment-tag scores of the bodies in photos already scanned, one photo
/// at a time, in the background. Modelled on `SensitiveBackfill`:
///
/// * never competes with a scan: [run] stops as soon as [shouldContinue] says so;
/// * a photo without bodies (or whose bodies get no tags) is still marked as done, so it is not asked again;
/// * one transaction per photo, so stopping at any moment loses nothing;
/// * stores scores only - **no tag is a filter** until its precision on real photos has been measured.
class GarmentBackfill {
  GarmentBackfill({
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
      await db.setting(garmentTagsEnabledKey) == 'true';

  Future<void> setEnabled(bool on) =>
      db.putSetting(garmentTagsEnabledKey, on ? 'true' : 'false');

  /// Photos still to tag.
  Future<int> pending() async =>
      (await db
              .customSelect(
                "SELECT COUNT(*) AS n FROM media WHERE kind = 'photo' AND scan_status = 'done' "
                'AND garment_version < ?',
                variables: [Variable.withInt(garmentModelVersion)],
                readsFrom: {db.media},
              )
              .getSingle())
          .read<int>('n');

  /// Tags photos until none is left or [shouldContinue] turns false. Returns how many were done. Does nothing
  /// while the switch is off. Stops quietly (and leaves the rest queued) when the PC has no tagger or is busy.
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
                        m.garmentVersion.isSmallerThanValue(
                          garmentModelVersion,
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
          // no tagger on the PC / the GPU is busy / the PC is gone: try again another time
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
    if (bodies.isEmpty) {
      await _store(row.id, const [], const [], garmentModelVersion);
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
    final response = await client.analyzeGarments(bytes, [
      for (final b in bodies)
        SensitiveBodyTargetDto(
          bbox: BBox(
            x: b.bboxX * w,
            y: b.bboxY * h,
            w: b.bboxW * w,
            h: b.bboxH * h,
          ),
        ),
    ]);
    await _store(
      row.id,
      [for (final b in bodies) b.id],
      response.bodies,
      response.modelVersion < garmentModelVersion
          ? garmentModelVersion
          : response.modelVersion,
    );
    return true;
  }

  /// Replaces the tags of [bodyIds] (tags[i] belongs to bodyIds[i]) and marks the photo as done.
  Future<void> _store(
    int mediaId,
    List<int> bodyIds,
    List<List<GarmentTagDto>> tags,
    int version,
  ) => db.transaction(() async {
    for (var i = 0; i < bodyIds.length; i++) {
      await (db.delete(
        db.bodyGarmentTags,
      )..where((t) => t.bodyId.equals(bodyIds[i]))).go();
      if (i >= tags.length) continue;
      for (final tag in tags[i]) {
        await db
            .into(db.bodyGarmentTags)
            .insertOnConflictUpdate(
              BodyGarmentTagsCompanion.insert(
                bodyId: bodyIds[i],
                tag: tag.tag,
                category: tag.category,
                score: tag.score.clamp(0.0, 1.0).toDouble(),
              ),
            );
      }
    }
    await (db.update(db.media)..where((m) => m.id.equals(mediaId))).write(
      MediaCompanion(garmentVersion: Value(version)),
    );
  });
}

/// The raw tags of one body, best first (for the user's own labelling and for later precision measurement).
Future<List<BodyGarmentTagRow>> garmentTagsOf(AppDatabase db, int bodyId) =>
    (db.select(db.bodyGarmentTags)
          ..where((t) => t.bodyId.equals(bodyId))
          ..orderBy([(t) => OrderingTerm.desc(t.score)]))
        .get();
