import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app.dart';
import 'data/db/open_database.dart';
import 'data/files/file_store.dart';
import 'data/repositories/session_store.dart';
import 'data/secrets/secret_store.dart';
import 'library_providers.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    const secrets = FlutterSecretStore(FlutterSecureStorage());
    final db = await openAppDatabase(secrets: secrets);
    final session = await SessionStore(db, secrets).load();
    final files = await FileStore.open();
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          fileStoreProvider.overrideWithValue(files),
          secretStoreProvider.overrideWithValue(secrets),
          initialSessionProvider.overrideWithValue(session),
        ],
        child: const App(),
      ),
    );
  } catch (error) {
    runApp(StartupErrorApp(error: error));
  }
}
