import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/platform/media_organizer.dart';
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

  testWidgets(
    'file organization settings save changes and report empty-folder cleanup',
    (tester) async {
      int? cleanupResult;
      var cleanupCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AndroidMediaOrganizer.channel, (
        call,
      ) async {
        if (call.method == 'pruneEmptyFolders') {
          cleanupCalls++;
          return cleanupResult;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          AndroidMediaOrganizer.channel,
          null,
        ),
      );
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            fileStoreProvider.overrideWithValue(
              FileStore(Directory.systemTemp),
            ),
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

      await tester.ensureVisible(
        find.byKey(const Key('library-organization-section')),
      );
      await tester.tap(find.byKey(const Key('library-organization-section')));
      await tester.pumpAndSettle();
      final autoOrganizeFinder = find.byKey(
        const Key('settings-auto-organize'),
      );
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

      final cleanup = find.byKey(const Key('settings-prune-empty-folders'));
      await tester.ensureVisible(cleanup);
      await tester.tap(cleanup);
      await tester.pumpAndSettle();
      expect(cleanupCalls, 1);
      expect(
        find.textContaining('Allow All files access above'),
        findsOneWidget,
      );
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .removeCurrentSnackBar();
      cleanupResult = 3;
      await tester.tap(cleanup);
      await tester.pumpAndSettle();
      expect(cleanupCalls, 2);
      expect(find.text('Removed 3 empty folders'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
  );
}
