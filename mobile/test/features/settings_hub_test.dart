import 'dart:io';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/platform/privacy_service.dart';
import 'package:antigravity_mobile/features/privacy/app_lock.dart';
import 'package:antigravity_mobile/features/settings/privacy_settings_screen.dart';
import 'package:antigravity_mobile/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class _FakePrivacy implements PrivacyService {
  bool granted = true;
  @override
  Future<bool> authenticate(String title, String body) async => granted;

  @override
  Future<bool> exportMedia(File file, String mime) async => true;
}

void main() {
  group('S1 SettingsHub & S4 PrivacySettings', () {
    appTest(
      'renders settings hub with all categories and navigates to sub-screens',
      (tester, env) async {
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/settings')],
        );

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Settings'), findsWidgets);
        expect(find.byKey(const Key('settings-library')), findsOneWidget);
        expect(find.byKey(const Key('settings-privacy')), findsOneWidget);
        expect(find.byKey(const Key('settings-pc')), findsOneWidget);
        expect(find.byKey(const Key('settings-storage')), findsOneWidget);

        // Tap Library & Scan
        await tester.tap(find.byKey(const Key('settings-library')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('scan-start')), findsOneWidget);
      },
      session: testSession,
    );

    appTest('navigates to privacy settings and toggles lock', (
      tester,
      env,
    ) async {
      final privacy = _FakePrivacy();
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/settings/privacy'),
          privacyServiceProvider.overrideWithValue(privacy),
        ],
      );

      expect(find.byType(PrivacySettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('app-lock')), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final row = await (env.db.select(
        env.db.settings,
      )..where((s) => s.key.equals('privacy.app_lock'))).getSingleOrNull();
      expect(row?.value, equals('true'));
    }, session: testSession);
  });
}
