import 'package:flutter/services.dart';

/// Opens the app's Android player or delegates to another installed player.
class NativeVideoPlayer {
  static const MethodChannel _channel = MethodChannel(
    'antigravity/video_player',
  );

  static Future<bool> playVideo(String uri, {int? positionMs}) async {
    try {
      final success = await _channel.invokeMethod<bool>('playNativeVideo', {
        'uri': uri,
        'positionMs': positionMs,
      });
      return success ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

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
