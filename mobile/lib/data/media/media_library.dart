import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:photo_manager/photo_manager.dart';

/// One album (MediaStore bucket) the user can choose to scan.
class AlbumInfo {
  const AlbumInfo({
    required this.id,
    required this.name,
    required this.count,
    this.isAll = false,
  });

  final String id;
  final String name;
  final int count;
  final bool isAll; // the "all photos" pseudo album
}

/// One photo as MediaStore describes it. `modifiedAt`/`takenAt` are epoch milliseconds.
class AssetInfo {
  const AssetInfo({
    required this.id,
    required this.width,
    required this.height,
    required this.modifiedAt,
    required this.takenAt,
    this.kind = 'photo',
    this.durationMs,
  });

  final String id;
  final int width;
  final int height;
  final int modifiedAt;
  final int takenAt;
  final String kind;
  final int? durationMs;

  /// The scan's "did this file change?" signature: modified time + pixel size. (File size would
  /// need opening every file; an edit changes the modified time anyway.)
  bool sameSignatureAs({
    required int modifiedAt,
    required int width,
    required int height,
  }) =>
      this.modifiedAt == modifiedAt &&
      this.width == width &&
      this.height == height;
}

/// What the scan needs from the phone's photo library. Originals are only ever *read*: nothing is
/// copied into the app; the thing sent to the PC is a downscaled JPEG that exists in memory only.
abstract interface class MediaLibrary {
  Future<bool> requestAccess();

  Future<List<AlbumInfo>> albums();

  /// Photos of the chosen albums, newest first, one page at a time (a library can hold 100k).
  Stream<List<AssetInfo>> photos(Set<String> albumIds, {int pageSize = 400});

  /// The photo as a JPEG, EXIF-rotated, long side <= [maxSide]. Null when it cannot be read.
  Future<Uint8List?> downscaledJpeg(
    String assetId, {
    required int width,
    required int height,
    required int maxSide,
  });

  /// A small JPEG for grids; null when the asset is gone.
  Future<Uint8List?> thumbnail(
    String assetId, {
    required int width,
    required int height,
    int size = 256,
  });

  /// The photo for the viewer (long side about [maxSide]); null when the original is gone.
  Future<Uint8List?> viewerImage(String assetId, {int maxSide = 1800});

  /// Drops files the photo plugin cached while reading originals.
  Future<void> clearCache();
}

abstract interface class VideoMediaLibrary {
  Future<File?> videoFile(String assetId);
}

class PhotoManagerLibrary implements MediaLibrary, VideoMediaLibrary {
  @override
  Future<bool> requestAccess() async {
    final state = await PhotoManager.requestPermissionExtend();
    return state.hasAccess;
  }

  FilterOptionGroup get _newestFirst => FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate)],
  );

  @override
  Future<List<AlbumInfo>> albums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: _newestFirst,
    );
    final out = <AlbumInfo>[];
    for (final path in paths) {
      out.add(
        AlbumInfo(
          id: path.id,
          name: path.name,
          count: await path.assetCountAsync,
          isAll: path.isAll,
        ),
      );
    }
    out.sort((a, b) {
      if (a.isAll != b.isAll) return a.isAll ? -1 : 1;
      return b.count.compareTo(a.count);
    });
    return out;
  }

  @override
  Stream<List<AssetInfo>> photos(
    Set<String> albumIds, {
    int pageSize = 400,
  }) async* {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: _newestFirst,
    );
    for (final path in paths.where((p) => albumIds.contains(p.id))) {
      for (var page = 0; ; page++) {
        final assets = await path.getAssetListPaged(page: page, size: pageSize);
        if (assets.isEmpty) break;
        yield [
          for (final a in assets)
            if (a.type == AssetType.image || a.type == AssetType.video)
              AssetInfo(
                id: a.id,
                width: a.width,
                height: a.height,
                modifiedAt: (a.modifiedDateSecond ?? 0) * 1000,
                takenAt:
                    (a.createDateSecond ?? a.modifiedDateSecond ?? 0) * 1000,
                kind: a.type == AssetType.video ? 'video' : 'photo',
                durationMs: a.type == AssetType.video
                    ? a.duration * 1000
                    : null,
              ),
        ];
        if (assets.length < pageSize) break;
      }
    }
  }

  @override
  Future<File?> videoFile(String assetId) async =>
      (await AssetEntity.fromId(assetId))?.originFile;

  @override
  Future<Uint8List?> downscaledJpeg(
    String assetId, {
    required int width,
    required int height,
    required int maxSide,
  }) async {
    final entity = await AssetEntity.fromId(assetId);
    if (entity == null) return null;
    final file = await entity.originFile;
    if (file == null) return null;
    // flutter_image_compress scales so that the result is at least minWidth x minHeight (cover);
    // asking for exactly the target size on both axes gives "long side <= maxSide" for any ratio.
    final w = entity.width > 0 ? entity.width : width;
    final h = entity.height > 0 ? entity.height : height;
    final scale = math.min(1.0, maxSide / math.max(w, h));
    try {
      return await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: math.max(1, (w * scale).round()),
        minHeight: math.max(1, (h * scale).round()),
        quality: 90,
        format: CompressFormat.jpeg,
        autoCorrectionAngle: true,
        keepExif: false,
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<Uint8List?> thumbnail(
    String assetId, {
    required int width,
    required int height,
    int size = 256,
  }) async => (await AssetEntity.fromId(
    assetId,
  ))?.thumbnailDataWithSize(ThumbnailSize.square(size), quality: 80);

  @override
  Future<Uint8List?> viewerImage(String assetId, {int maxSide = 1800}) async {
    final entity = await AssetEntity.fromId(assetId);
    if (entity == null) return null;
    final ratio = entity.width / math.max(1, entity.height);
    final w = ratio >= 1 ? maxSide : (maxSide * ratio).round();
    final h = ratio >= 1 ? (maxSide / ratio).round() : maxSide;
    return entity.thumbnailDataWithSize(ThumbnailSize(w, h), quality: 90);
  }

  @override
  Future<void> clearCache() async {
    try {
      await PhotoManager.clearFileCache();
    } on Exception catch (_) {
      // a cache that cannot be cleared is only wasted space
    }
  }
}
