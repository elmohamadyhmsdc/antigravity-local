import 'package:flutter/services.dart';

import '../../domain/export/crop_math.dart';

/// One decoded original: a photo as stored (with its EXIF [orientation]) or a video frame
/// (always upright, orientation 1). Sizes are the stored pixels.
class SourceFrame {
  const SourceFrame({
    required this.rawWidth,
    required this.rawHeight,
    this.orientation = 1,
  });

  final int rawWidth, rawHeight;

  /// EXIF orientation 1..8.
  final int orientation;

  int get width => uprightSize(rawWidth, rawHeight, orientation).width;
  int get height => uprightSize(rawWidth, rawHeight, orientation).height;
}

/// Native-resolution access to the user's original photos and videos. The originals are only
/// read; nothing is copied or uploaded. One source is open at a time ([open] replaces it).
abstract interface class CropSource {
  /// Null when the original is gone or cannot be decoded here. [timeMs] picks the video frame.
  Future<SourceFrame?> open({
    required String assetId,
    required bool video,
    int? timeMs,
  });

  /// [rect] is in the upright pixel space of the open [SourceFrame]; the JPEG is scaled to
  /// [outWidth] x [outHeight]. Null when the pixels cannot be produced.
  Future<Uint8List?> crop(
    SourceFrame frame,
    PxRect rect, {
    required int outWidth,
    required int outHeight,
    int quality = 95,
  });

  Future<void> close();
}

class AndroidCropSource implements CropSource {
  const AndroidCropSource();

  static const _channel = MethodChannel('antigravity/crop_export');

  @override
  Future<SourceFrame?> open({
    required String assetId,
    required bool video,
    int? timeMs,
  }) async {
    try {
      final info = await _channel
          .invokeMapMethod<String, dynamic>('open', {
            'assetId': assetId,
            'video': video,
            'timeMs': timeMs ?? 0,
          })
          .timeout(const Duration(seconds: 60));
      final w = (info?['width'] as num?)?.toInt() ?? 0;
      final h = (info?['height'] as num?)?.toInt() ?? 0;
      if (w <= 0 || h <= 0) return null;
      final o = (info?['orientation'] as num?)?.toInt() ?? 1;
      return SourceFrame(
        rawWidth: w,
        rawHeight: h,
        orientation: o >= 1 && o <= 8 ? o : 1,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Uint8List?> crop(
    SourceFrame frame,
    PxRect rect, {
    required int outWidth,
    required int outHeight,
    int quality = 95,
  }) async {
    final raw = uprightToRaw(
      rect,
      frame.orientation,
      frame.rawWidth,
      frame.rawHeight,
    );
    try {
      return await _channel
          .invokeMethod<Uint8List>('crop', {
            'left': raw.left,
            'top': raw.top,
            'width': raw.width,
            'height': raw.height,
            'orientation': frame.orientation,
            'outWidth': outWidth,
            'outHeight': outHeight,
            'quality': quality,
          })
          .timeout(const Duration(seconds: 60));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _channel.invokeMethod<void>('close');
    } on PlatformException {
      /* nothing open */
    } on MissingPluginException {
      /* not on Android */
    }
  }
}
