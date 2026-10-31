import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'file_store.dart';

/// Face and body thumbnails are a cache, not data: the database keeps every box, so a crop that
/// was evicted is cut again from the original photo or video frame the first time it is shown.
/// The covers of people are never evicted.
const defaultCropCacheBytes = 300 * 1024 * 1024;

enum CropKind { face, body }

/// The PC's preview sizes (`FACE_CROP_MAX_PX`, `BODY_CROP_MAX_HEIGHT` in mobile_api/schemas.py).
const faceCropMaxSide = 256;
const bodyCropMaxHeight = 384;

/// Where to cut, in pixels of a [width] x [height] picture, and the output size - the same
/// framing as analysis.face_crop (the box plus 20% of its longer side all round) and
/// analysis.body_crop (6% / 4% padding, at most [bodyCropMaxHeight] high).
({int left, int top, int width, int height, int outWidth, int outHeight})
cropPixels(
  CropKind kind,
  ({double x, double y, double w, double h}) box,
  int width,
  int height,
) {
  final x1 = box.x * width, y1 = box.y * height;
  final x2 = (box.x + box.w) * width, y2 = (box.y + box.h) * height;
  final padX = kind == CropKind.face
      ? math.max(x2 - x1, y2 - y1) * 0.2
      : (x2 - x1) * 0.06;
  final padY = kind == CropKind.face
      ? math.max(x2 - x1, y2 - y1) * 0.2
      : (y2 - y1) * 0.04;
  final left = (x1 - padX).floor().clamp(0, width - 1);
  final top = (y1 - padY).floor().clamp(0, height - 1);
  // the epsilon keeps 0.6 * 1000 = 600.0000000000001 from rounding up a pixel
  final right = (x2 + padX - 1e-6).ceil().clamp(left + 1, width);
  final bottom = (y2 + padY - 1e-6).ceil().clamp(top + 1, height);
  final w = right - left, h = bottom - top;
  final scale = kind == CropKind.face
      ? math.min(1.0, faceCropMaxSide / math.max(w, h))
      : math.min(1.0, bodyCropMaxHeight / h);
  return (
    left: left,
    top: top,
    width: w,
    height: h,
    outWidth: math.max(1, (w * scale).round()),
    outHeight: math.max(1, (h * scale).round()),
  );
}

/// The original a crop was cut from, upright, as an encoded picture (null = gone/unreadable).
typedef OriginalLoader =
    Future<Uint8List?> Function(String assetId, bool video, int? timestampMs);

/// Cuts [box] (normalised) out of [source] and returns a JPEG framed like the PC's crops.
typedef CropCutter =
    Future<Uint8List?> Function(
      Uint8List source,
      CropKind kind,
      ({double x, double y, double w, double h}) box,
    );

class CropCache {
  CropCache({
    required this._db,
    required this._files,
    required this._loadOriginal,
    required this._cut,
    this.capBytes = defaultCropCacheBytes,
    int maxConcurrent = 2,
  }) : _slots = maxConcurrent;

  final AppDatabase _db;
  final FileStore _files;
  final OriginalLoader _loadOriginal;
  final CropCutter _cut;
  final int capBytes;

  int _slots;
  final _waiting = <Completer<void>>[];
  final _inFlight = <String, Future<File?>>{};
  final _touched = <String>{};
  final _failed = <String>{};

  static (CropKind, int)? parse(String relative) {
    final m = RegExp(
      r'^(faces|bodies)/(\d+)\.jpg$',
    ).firstMatch(relative.replaceAll('\\', '/'));
    if (m == null) return null;
    return (
      m.group(1) == 'faces' ? CropKind.face : CropKind.body,
      int.parse(m.group(2)!),
    );
  }

  /// The crop file, cut again from the original when it was evicted. Null when it cannot be
  /// produced (not a face/body crop, the row or the original is gone).
  Future<File?> ensure(String? relative) {
    if (relative == null || relative.isEmpty) return Future.value(null);
    // (a block body: returning the removed future would make it wait for itself)
    return _inFlight[relative] ??= _ensure(relative).whenComplete(() {
      _inFlight.remove(relative);
    });
  }

  Future<File?> _ensure(String relative) async {
    final file = _files.resolve(relative);
    if (await file.exists()) {
      // most recently shown = last to be evicted; once per run is enough
      if (_touched.add(relative)) {
        try {
          await file.setLastModified(DateTime.now());
        } on FileSystemException {
          /* only the eviction order suffers */
        }
      }
      return file;
    }
    final target = parse(relative);
    if (target == null || _failed.contains(relative)) return null;
    await _acquire();
    try {
      final bytes = await _regenerate(target.$1, target.$2);
      if (bytes == null) {
        _failed.add(relative);
        return null;
      }
      await _files.write(relative, bytes);
      _touched.add(relative);
      return file;
    } finally {
      _release();
    }
  }

  Future<Uint8List?> _regenerate(CropKind kind, int id) async {
    final row = await _db
        .customSelect(
          '''
          SELECT m.asset_id, m.kind, t.timestamp_ms, t.bbox_x, t.bbox_y, t.bbox_w, t.bbox_h
          FROM ${kind == CropKind.face ? 'faces' : 'bodies'} t JOIN media m ON m.id = t.media_id
          WHERE t.id = ?
          ''',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    try {
      final original = await _loadOriginal(
        row.read<String>('asset_id'),
        row.read<String>('kind') == 'video',
        row.readNullable<int>('timestamp_ms'),
      );
      if (original == null) return null;
      return await _cut(original, kind, (
        x: row.read<double>('bbox_x'),
        y: row.read<double>('bbox_y'),
        w: row.read<double>('bbox_w'),
        h: row.read<double>('bbox_h'),
      ));
    } catch (_) {
      return null;
    }
  }

  Future<void> _acquire() async {
    if (_slots > 0) {
      _slots--;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _slots++;
    }
  }

  /// Bytes the face/body crops take now.
  Future<int> size() async {
    var total = 0;
    for (final (_, stat) in await _crops()) {
      total += stat.size;
    }
    return total;
  }

  /// Deletes the least recently shown crops until they fit in [cap] (default [capBytes]).
  /// People's covers stay. Returns the bytes freed.
  Future<int> evict({int? cap}) async {
    final limit = cap ?? capBytes;
    final crops = await _crops();
    var total = crops.fold<int>(0, (sum, c) => sum + c.$2.size);
    if (total <= limit) return 0;
    final covers = {
      for (final r
          in await _db
              .customSelect(
                'SELECT avatar_face_id FROM persons WHERE avatar_face_id IS NOT NULL',
              )
              .get())
        _files.faceCropPath(r.read<int>('avatar_face_id')),
    };
    crops.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var freed = 0;
    for (final (relative, stat) in crops) {
      if (total <= limit) break;
      if (covers.contains(relative) || _inFlight.containsKey(relative)) {
        continue;
      }
      await _files.delete(relative);
      _touched.remove(relative);
      total -= stat.size;
      freed += stat.size;
    }
    return freed;
  }

  Future<List<(String, FileStat)>> _crops() async {
    final out = <(String, FileStat)>[];
    for (final folder in [FileStore.facesFolder, FileStore.bodiesFolder]) {
      final dir = Directory('${_files.root.path}/$folder');
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        out.add((
          '$folder/${entity.uri.pathSegments.last}',
          await entity.stat(),
        ));
      }
    }
    return out;
  }
}
