import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/media/media_library.dart';
import '../../data/media/thumbnail_service.dart';
import '../../library_providers.dart';

class LoadedImage {
  const LoadedImage(
    this.bytes,
    this.width,
    this.height, {
    this.fallback = false,
  });
  final Uint8List bytes;
  final int width, height;
  final bool fallback;
}

final viewerImageCacheProvider = Provider<ViewerImageCache>((ref) {
  final cache = ViewerImageCache(
    ref.watch(mediaLibraryProvider),
    ref.watch(thumbnailServiceProvider),
  );
  ref.onDispose(cache.clear);
  return cache;
});

/// Encoded viewer previews only. Flutter separately bounds decoded image memory.
class ViewerImageCache {
  ViewerImageCache(
    this.library,
    this.thumbnails, {
    this.maxBytes = 24 * 1024 * 1024,
    this.capacity = 12,
  });
  final MediaLibrary library;
  final ThumbnailService thumbnails;
  final int maxBytes, capacity;
  final _images = <String, LoadedImage>{};
  final _pending = <String, Future<LoadedImage?>>{};
  var _bytes = 0;
  var _generation = 0;

  LoadedImage? peek(String id) {
    final image = _images.remove(id);
    if (image != null) _images[id] = image;
    return image;
  }

  Future<LoadedImage?> get(String id) {
    final cached = peek(id);
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(id, () {
      final generation = _generation;
      return _load(id).then((image) {
        if (generation != _generation) return image;
        _pending.remove(id);
        if (image != null && image.bytes.lengthInBytes <= maxBytes) {
          _images[id] = image;
          _bytes += image.bytes.lengthInBytes;
          while (_bytes > maxBytes || _images.length > capacity) {
            _bytes -= _images.remove(_images.keys.first)!.bytes.lengthInBytes;
          }
        }
        return image;
      });
    });
  }

  Future<LoadedImage?> _load(String id) async {
    try {
      var bytes = await library.viewerImage(id);
      final fallback = bytes == null;
      bytes ??= await thumbnails.get(id);
      if (bytes == null || bytes.isEmpty) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          return LoadedImage(
            bytes,
            descriptor.width,
            descriptor.height,
            fallback: fallback,
          );
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (_) {
      return null; // Retry a missing/failed preview on the next visit.
    }
  }

  void clear() {
    _generation++;
    _images.clear();
    _pending.clear();
    _bytes = 0;
  }
}
