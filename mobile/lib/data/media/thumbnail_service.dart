import 'dart:typed_data';

import 'media_library.dart';

/// Grid thumbnails of the user's photos, kept in a small LRU so scrolling back is instant.
/// (MediaStore does the real caching; this only avoids repeating the platform call.)
class ThumbnailService {
  ThumbnailService(this._library, {this.capacity = 500});

  final MediaLibrary _library;
  final int capacity;
  final _cache = <String, Future<Uint8List?>>{};

  Future<Uint8List?> get(
    String assetId, {
    int width = 0,
    int height = 0,
    int size = 256,
  }) {
    final key = '$assetId@$size';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // most recently used goes last
      return hit;
    }
    final future = _library.thumbnail(
      assetId,
      width: width,
      height: height,
      size: size,
    );
    _cache[key] = future;
    while (_cache.length > capacity) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  void clear() => _cache.clear();
}
