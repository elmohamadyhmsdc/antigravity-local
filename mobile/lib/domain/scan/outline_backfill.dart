import 'dart:convert';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/mobile_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../geometry/outline.dart';

/// On-demand backfill of real face and body outlines for photos scanned
/// before outlines existed.
///
/// Triggers when the user opens a photo in MediaScreen, ReviewMediaViewer,
/// or HighlightedPhoto whose detections have outline == null.
///
/// Features:
/// - Skips videos and busy servers.
/// - Compresses photo identically to the scan path (<= 2560 px).
/// - Debounces per session (one request per photo).
/// - Fails silently to ensure UI never blocks or errors (falls back to geometric shapes).
class OutlineBackfill {
  OutlineBackfill({
    required this.db,
    required this.media,
    required this.api,
    this.isServerReady,
    this.maxSide = 2560,
    Future<(int, int)?> Function(Uint8List)? decodeDimensions,
  }) : _decodeDimensions = decodeDimensions ?? _defaultDecodeDimensions;

  final AppDatabase db;
  final MediaLibrary media;
  final MobileApi? Function() api;
  final bool Function()? isServerReady;
  final int maxSide;
  final Future<(int, int)?> Function(Uint8List) _decodeDimensions;

  final Set<int> _debouncedMediaIds = <int>{};

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

  /// Request outline backfill for [mediaId].
  ///
  /// Returns `true` if outlines were computed and stored, `false` if skipped or failed.
  Future<bool> backfillPhoto(
    int mediaId, {
    String? assetId,
    int? width,
    int? height,
  }) async {
    if (_debouncedMediaIds.contains(mediaId)) return false;
    _debouncedMediaIds.add(mediaId);

    try {
      final client = api();
      if (client == null) return false;
      if (isServerReady != null && !isServerReady!()) return false;

      // 1. Resolve media row if needed
      var targetAssetId = assetId;
      var targetW = width ?? 0;
      var targetH = height ?? 0;

      if (targetAssetId == null) {
        final m = await (db.select(db.media)..where((t) => t.id.equals(mediaId))).getSingleOrNull();
        if (m == null || m.kind != 'photo') return false;
        targetAssetId = m.assetId;
        targetW = m.width ?? 0;
        targetH = m.height ?? 0;
      }

      // 2. Fetch detections for this photo where outline IS NULL
      final detections = await (db.select(db.mediaDetections)
            ..where((t) => t.mediaId.equals(mediaId) & t.outline.isNull())
            ..limit(32))
          .get();

      if (detections.isEmpty) return false;

      // 3. Compress/downscale photo
      final bytes = await media.downscaledJpeg(
        targetAssetId,
        width: targetW,
        height: targetH,
        maxSide: maxSide,
      );
      if (bytes == null) return false;

      // 4. Learn image dimensions of the downscaled JPEG
      final dims = await _decodeDimensions(bytes);
      if (dims == null) return false;
      final (imgW, imgH) = dims;
      if (imgW <= 0 || imgH <= 0) return false;

      // 5. Build targets
      final targets = <OutlineTargetDto>[];
      for (final d in detections) {
        final box = BBox(
          x: d.x * imgW,
          y: d.y * imgH,
          w: d.w * imgW,
          h: d.h * imgH,
        );
        List<List<double>>? kps;
        if (d.kind == 'f') {
          final face = await (db.select(db.faces)..where((t) => t.id.equals(d.refId))).getSingleOrNull();
          if (face?.kps != null) {
            try {
              final rawKps = jsonDecode(face!.kps!) as List<dynamic>;
              kps = rawKps.map((pt) {
                final pair = pt as List<dynamic>;
                return [
                  (pair[0] as num).toDouble() * imgW,
                  (pair[1] as num).toDouble() * imgH,
                ];
              }).toList();
            } catch (_) {
              kps = null;
            }
          }
        }
        targets.add(OutlineTargetDto(
          kind: d.kind,
          bbox: box,
          kps: kps,
        ));
      }

      // 6. Call API
      final outlines = await client.analyzeOutlines(bytes, targets);
      if (outlines.length != detections.length) return false;

      // 7. Update media_detections in a single database transaction
      await db.transaction(() async {
        for (var i = 0; i < detections.length; i++) {
          final outline = outlines[i];
          if (outline != null && outline.length >= 3) {
            final d = detections[i];
            final box = targets[i].bbox;
            final encoded = encodeOutline(outline, box);
            if (encoded != null) {
              await (db.update(db.mediaDetections)..where((t) => t.id.equals(d.id)))
                  .write(MediaDetectionsCompanion(outline: Value(encoded)));
            }
          }
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
