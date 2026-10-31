import 'package:flutter/services.dart';

/// What the phone's decoder reports about a library video.
class VideoProbe {
  const VideoProbe({
    required this.durationMs,
    required this.fps,
    this.frameCount,
  });

  final int durationMs;
  final double fps;
  final int? frameCount;

  /// Frames in the video: the container's count when it has one, else duration x rate.
  int get totalFrames => frameCount != null && frameCount! > 0
      ? frameCount!
      : (durationMs * fps / 1000).floor();
}

/// Decodes sampled frames of a library video on the phone (the library scan sends
/// these JPEGs instead of uploading the whole video).
abstract interface class LocalVideoFrames {
  /// Null when the phone cannot read the video (the scan then uploads it instead).
  Future<VideoProbe?> probe(String assetId);

  /// One JPEG per time (null where that frame is unreadable), long side <= [maxSide].
  Future<List<Uint8List?>> frames(
    String assetId,
    List<int> timesMs, {
    int maxSide = 2048,
  });

  /// Releases the decoder kept open between batches.
  Future<void> close();
}

class AndroidVideoFrames implements LocalVideoFrames {
  const AndroidVideoFrames();

  static const _channel = MethodChannel('antigravity/video_scan');

  @override
  Future<VideoProbe?> probe(String assetId) async {
    try {
      final info = await _channel
          .invokeMapMethod<String, dynamic>('probe', {'assetId': assetId})
          .timeout(const Duration(seconds: 30));
      final duration = (info?['durationMs'] as num?)?.toInt() ?? 0;
      final fps = (info?['fps'] as num?)?.toDouble() ?? 0;
      if (duration <= 0 || !fps.isFinite || fps <= 0 || fps > 1000) return null;
      return VideoProbe(
        durationMs: duration,
        fps: fps,
        frameCount: (info?['frameCount'] as num?)?.toInt(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<List<Uint8List?>> frames(
    String assetId,
    List<int> timesMs, {
    int maxSide = 2048,
  }) async {
    final frames = await _channel
        .invokeListMethod<Uint8List?>('frames', {
          'assetId': assetId,
          'timesMs': timesMs,
          'maxSide': maxSide,
        })
        .timeout(const Duration(seconds: 120));
    return frames ?? List.filled(timesMs.length, null);
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
