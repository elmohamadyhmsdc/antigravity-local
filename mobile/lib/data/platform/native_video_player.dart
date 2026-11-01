import 'package:flutter/services.dart';

/// Launches the native Android video player via ACTION_VIEW intent.
class NativeVideoPlayer {
  static const MethodChannel _channel = MethodChannel('antigravity/video_player');

  static Future<bool> openVideo(String uri, {String? title}) async {
    try {
      final success = await _channel.invokeMethod<bool>('openNativePlayer', {
        'uri': uri,
        'title': title ?? 'Video',
      });
      return success ?? false;
    } on PlatformException {
      return false;
    }
  }
}
