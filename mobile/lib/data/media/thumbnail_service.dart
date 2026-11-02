import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'media_library.dart';

/// Grid thumbnails of the user's photos, kept in an LRU memory cache
/// with synchronous peek so scrolling and remounting are instantaneous.
class ThumbnailService {
  ThumbnailService(this._library, {this.capacity = 2000});

  final MediaLibrary _library;
  final int capacity;
  final _cache = <String, Future<Uint8List?>>{};
  final _syncCache = <String, Uint8List>{};

  /// Synchronously returns cached bytes if already resolved in memory.
  Uint8List? getSync(String assetId, {int size = 256}) {
    final key = '$assetId@$size';
    final hit = _syncCache.remove(key);
    if (hit != null) {
      _syncCache[key] = hit; // MRU order
      return hit;
    }
    return null;
  }

  Future<Uint8List?> get(
    String assetId, {
    int width = 0,
    int height = 0,
    int size = 256,
  }) {
    final key = '$assetId@$size';

    // 1. Check synchronous cache first
    final cached = getSync(assetId, size: size);
    if (cached != null) {
      return Future.value(cached);
    }

    // 2. Check pending future in cache
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used goes last
      return hit;
    }

    // 3. Initiate fetch from library
    final future = _library
        .thumbnail(assetId, width: width, height: height, size: size)
        .then((bytes) {
          if (bytes != null) {
            _syncCache.remove(key);
            _syncCache[key] = bytes;
            while (_syncCache.length > capacity) {
              _syncCache.remove(_syncCache.keys.first);
            }
          } else {
            _cache.remove(key);
          }
          return bytes;
        })
        .catchError((_) {
          _cache.remove(key);
          return null;
        });

    _cache[key] = future;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  /// Triggers background preheating of thumbnails on the native platform loader (e.g. Glide).
  void preheat(List<String> assetIds, {int size = 256}) {
    if (assetIds.isEmpty) return;
    final lib = _library;
    if (lib is PhotoManagerLibrary) {
      lib.preheatThumbnails(assetIds, size: size).ignore();
      return;
    }
    try {
      final ThumbnailOption option;
      if (Platform.isIOS || Platform.isMacOS) {
        option = ThumbnailOption.ios(
          size: ThumbnailSize.square(size),
          quality: 75,
        );
      } else {
        option = ThumbnailOption(
          size: ThumbnailSize.square(size),
          quality: 75,
          frame: 0,
        );
      }
      PhotoManager.plugin
          .requestCacheAssetsThumbnail(assetIds, option)
          .ignore();
    } catch (_) {}
  }

  void clear() {
    _cache.clear();
    _syncCache.clear();
  }
}
