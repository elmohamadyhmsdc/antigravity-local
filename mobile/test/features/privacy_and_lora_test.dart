import 'dart:io';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/platform/privacy_service.dart';
import 'package:antigravity_mobile/features/privacy/app_lock.dart';
import 'package:antigravity_mobile/features/storage/storage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class FakePrivacy implements PrivacyService {
  bool granted = false;
  int calls = 0;
  @override
  Future<bool> authenticate(String title, String body) async {
    calls++;
    return granted;
  }

  @override
  Future<void> secure(bool enabled) async {}
  @override
  Future<bool> exportMedia(File file, String mime) async => true;
}

void main() {
  appTest(
    'a locked app hides private routes until system authentication succeeds and relocks in background',
    (tester, env) async {
      final privacy = FakePrivacy();
      await env.db.putSetting('privacy.app_lock', 'true');
      await env.pump(
        tester,
        extra: [
          privacyServiceProvider.overrideWithValue(privacy),
          initialLocationProvider.overrideWithValue('/lora'),
        ],
      );
      expect(find.text('Unlock Your Gallery'), findsOneWidget);
      expect(find.text('Build dataset'), findsNothing);
      await tester.tap(find.byKey(const Key('unlock-app')));
      await tester.pumpAndSettle();
      expect(find.text('Unlock Your Gallery'), findsOneWidget);
      privacy.granted = true;
      await tester.tap(find.byKey(const Key('unlock-app')));
      await tester.pumpAndSettle();
      expect(find.text('Build dataset'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Unlock Your Gallery'), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'Restyle keeps output private and requires a detected target',
    (tester, env) async {
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/restyle')],
      );
      expect(find.text('Describe the clothing'), findsOneWidget);
      final submit = find.byKey(const Key('restyle-submit'));
      await tester.scrollUntilVisible(
        submit,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    },
    session: testSession,
  );

  for (final route in [
    '/lora',
    '/lora/build',
    '/lora/train',
    '/lora/generate',
    '/storage',
  ]) {
    appTest('$route handles an empty library at phone size', (
      tester,
      env,
    ) async {
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue(route),
          if (route == '/storage')
            storageSizesProvider.overrideWith((ref) async => <String, int>{}),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    }, session: testSession);
  }
}
