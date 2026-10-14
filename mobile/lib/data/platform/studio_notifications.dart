import 'package:flutter/services.dart';

class StudioNotifications {
  static const _channel = MethodChannel('antigravity/studio_notifications');

  static Future<void> completed(
    String id, {
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<bool>('completed', {
        'id': id,
        'title': title,
        'body': body,
        'channel': title,
      });
    } on Object {
      // Notification permission is optional; it must never invalidate a saved result.
    }
  }
}
