import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class PrivacyService {
  Future<bool> authenticate(String title, String body);
  Future<void> secure(bool enabled);
  Future<bool> exportMedia(File file, String mime);
}

class AndroidPrivacyService implements PrivacyService {
  const AndroidPrivacyService();
  static const _channel = MethodChannel('antigravity/security');
  @override
  Future<bool> authenticate(String title, String body) async =>
      await _channel.invokeMethod<bool>('authenticate', {
        'title': title,
        'body': body,
      }) ??
      false;
  @override
  Future<void> secure(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('secure', {'enabled': enabled});
    } on MissingPluginException {
      /* widget tests / unsupported platform */
    }
  }

  @override
  Future<bool> exportMedia(File file, String mime) async =>
      await _channel.invokeMethod<bool>('exportMedia', {
        'path': file.path,
        'mime': mime,
      }) ??
      false;
}
