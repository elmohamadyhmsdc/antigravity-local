import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../secrets/secret_store.dart';
import 'app_database.dart';

const _dbKeyName = 'db.key';
const databaseFileName = 'antigravity.db';

class DatabaseEncryptionException implements Exception {
  DatabaseEncryptionException(this.message);
  final String message;
  @override
  String toString() => 'DatabaseEncryptionException: $message';
}

/// 256-bit random key as 64 hex chars (used as a raw SQLCipher key).
String generateDatabaseKey([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
    32,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// The database key lives in the Android Keystore (secure storage), created on first launch.
Future<String> readOrCreateDatabaseKey(
  SecretStore secrets, {
  Random? random,
}) async {
  final existing = await secrets.read(_dbKeyName);
  if (existing != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
    return existing;
  }
  final key = generateDatabaseKey(random);
  await secrets.write(_dbKeyName, key);
  return key;
}

/// `PRAGMA cipher_version` answers with a version string on SQLCipher and with nothing at all
/// on plain SQLite. Plain SQLite would store faces unencrypted, so we refuse to continue.
void requireSqlCipher(Object? cipherVersion) {
  if (cipherVersion == null || '$cipherVersion'.isEmpty) {
    throw DatabaseEncryptionException(
      'This build of SQLite has no SQLCipher support, so the library would be stored unencrypted. '
      'Check the `hooks: user_defines: sqlite3: source: sqlcipher` entry in pubspec.yaml.',
    );
  }
}

/// Keys the connection (raw 256-bit key) and PROVES SQLCipher is what is running.
void applyDatabaseKey(Database db, String hexKey) {
  assert(RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey));
  final version = db.select('PRAGMA cipher_version');
  requireSqlCipher(version.isEmpty ? null : version.first.values.first);
  db.execute('PRAGMA key = "x\'$hexKey\'"');
  // Forces the key to be checked now: a wrong key fails here ("file is not a database").
  db.select('SELECT count(*) FROM sqlite_master');
}

/// Opens (creating if needed) an encrypted database file.
AppDatabase openEncryptedDatabase(File file, String hexKey) {
  return AppDatabase(
    NativeDatabase.createInBackground(
      file,
      setup: (db) => applyDatabaseKey(db, hexKey),
    ),
  );
}

/// App start-up: key from the Keystore, file in the app's private documents folder.
Future<AppDatabase> openAppDatabase({SecretStore? secrets}) async {
  final store = secrets ?? FlutterSecretStore(const FlutterSecureStorage());
  final key = await readOrCreateDatabaseKey(store);
  final dir =
      await getApplicationSupportDirectory(); // private to the app, not backed up
  return openEncryptedDatabase(File(p.join(dir.path, databaseFileName)), key);
}
