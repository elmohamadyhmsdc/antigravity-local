import 'dart:io';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'media_library.dart';

/// Grid thumbnails of the user's photos, kept in an LRU memory cache
/// with synchronous peek so scrolling and remounting are instantaneous.
class ThumbnailService {
  ThumbnailService(
    this._library, {
    this.capacity = 2000,
    this.maxBytes = 24 * 1024 * 1024,
  });

  final MediaLibrary _library;
  final int capacity;
  final int maxBytes;
  final _pending = <String, Future<Uint8List?>>{};
  final _syncCache = <String, Uint8List>{};
  var _bytes = 0;
  var _generation = 0;

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

    final cached = getSync(assetId, size: size);
    if (cached != null) return Future.value(cached);

    return _pending.putIfAbsent(key, () {
      final generation = _generation;
      return Future<Uint8List?>.sync(
        () => _library.thumbnail(
          assetId,
          width: width,
          height: height,
          size: size,
        ),
      ).catchError((_) => null).then((bytes) {
        if (generation != _generation) return bytes;
        _pending.remove(key);
        if (bytes != null &&
            bytes.isNotEmpty &&
            bytes.lengthInBytes <= maxBytes) {
          _syncCache[key] = bytes;
          _bytes += bytes.lengthInBytes;
          while (_bytes > maxBytes || _syncCache.length > capacity) {
            _bytes -= _syncCache.remove(_syncCache.keys.first)!.lengthInBytes;
          }
        }
        return bytes == null || bytes.isEmpty ? null : bytes;
      });
    });
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
    _generation++;
    _pending.clear();
    _syncCache.clear();
    _bytes = 0;
  }
}
