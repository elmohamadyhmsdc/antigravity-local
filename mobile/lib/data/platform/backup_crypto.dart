import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class BackupCrypto {
  Future<void> encrypt(File source, File target, String password);
  Future<void> decrypt(File source, File target, String password);
}

class AndroidBackupCrypto implements BackupCrypto {
  const AndroidBackupCrypto();
  static const _channel = MethodChannel('antigravity/backup');
  Future<void> _run(
    String method,
    File source,
    File target,
    String password,
  ) async {
    final completed = await _channel.invokeMethod<bool>(method, {
      'source': source.path,
      'target': target.path,
      'password': password,
    });
    if (completed != true) {
      throw StateError('The backup could not be encrypted or unlocked.');
    }
  }

  @override
  Future<void> encrypt(File source, File target, String password) =>
      _run('encrypt', source, target, password);
  @override
  Future<void> decrypt(File source, File target, String password) =>
      _run('decrypt', source, target, password);

  static Future<bool> isEncrypted(File file) async {
    final input = await file.open();
    try {
      return ascii.decode(await input.read(8), allowInvalid: true) ==
          'AGBAK02\n';
    } finally {
      await input.close();
    }
  }
}
