import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('antigravity/backup');

/// Streams the staged archive into the document chosen in Android Files.
Future<bool> saveBackupFile(File source) async {
  final saved = await _channel.invokeMethod<bool>('save', {
    'source': source.path,
  });
  if (saved == null) throw StateError('Android Files returned no save result.');
  return saved;
}
