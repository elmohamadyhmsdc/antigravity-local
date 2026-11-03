import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/features/settings/library_settings_screen.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AppSettings appSettings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    appSettings = AppSettings(db);
  });

  tearDown(() async => db.close());

  testWidgets('LibrarySettingsScreen toggles auto-organize and save-sidecar settings', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          fileStoreProvider.overrideWithValue(FileStore(Directory.systemTemp)),
          appSettingsProvider.overrideWithValue(appSettings),
          albumsProvider.overrideWith((ref) => Future.value([])),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LibrarySettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final autoOrganizeFinder = find.byKey(const Key('settings-auto-organize'));
    final saveSidecarFinder = find.byKey(const Key('settings-save-sidecar'));

    expect(autoOrganizeFinder, findsOneWidget);
    expect(saveSidecarFinder, findsOneWidget);

    // Initial state: true by default
    SwitchListTile autoTile = tester.widget(autoOrganizeFinder);
    expect(autoTile.value, isTrue);

    // Toggle off
    await tester.tap(autoOrganizeFinder);
    await tester.pump();

    final snapshot1 = await appSettings.load();
    expect(snapshot1.autoOrganizeEnabled, isFalse);

    // Toggle save sidecar off
    await tester.tap(saveSidecarFinder);
    await tester.pump();

    final snapshot2 = await appSettings.load();
    expect(snapshot2.saveSidecarEnabled, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
