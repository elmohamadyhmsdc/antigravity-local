import 'dart:io';

import 'package:antigravity_mobile/data/platform/backup_crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('antigravity/backup');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'native bridge receives file paths; incomplete native work cannot succeed silently',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'encrypt';
          });
      const crypto = AndroidBackupCrypto();
      await crypto.encrypt(
        File('/private/source'),
        File('/private/target'),
        'a long password',
      );
      expect(calls.single.method, 'encrypt');
      expect(calls.single.arguments, {
        'source': '/private/source',
        'target': '/private/target',
        'password': 'a long password',
      });
      await expectLater(
        crypto.decrypt(
          File('/private/source'),
          File('/private/target'),
          'a long password',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'encrypted envelope detection keeps legacy ZIP archives compatible',
    () async {
      final dir = Directory.systemTemp.createTempSync('ag_envelope_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/backup.agbackup');
      await file.writeAsBytes('AGBAK02\nextra bytes'.codeUnits);
      expect(await AndroidBackupCrypto.isEncrypted(file), isTrue);
      for (final bytes in [
        <int>[],
        [0x50, 0x4b, 0x03, 0x04],
        'AGBAK03\n'.codeUnits,
      ]) {
        await file.writeAsBytes(bytes);
        expect(await AndroidBackupCrypto.isEncrypted(file), isFalse);
      }
    },
  );
}
