import 'dart:async';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/platform/background_execution.dart';
import 'package:antigravity_mobile/data/platform/foreground_keep_alive.dart';
import 'package:antigravity_mobile/features/settings/background_screen.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class FakeBackground implements BackgroundExecution {
  var current = const BackgroundStatus(supported: true);
  var requests = 0, settings = 0;
  @override
  Future<BackgroundStatus> status() async => current;
  @override
  Future<void> request() async {
    requests++;
    current = const BackgroundStatus(
      supported: true,
      notifications: true,
      unrestricted: true,
    );
  }

  @override
  Future<void> openSettings() async {
    settings++;
  }
}

class FakeForeground implements ForegroundBackend {
  bool active = false, refuse = false;
  Completer<void>? starting;
  final calls = <String>[];
  @override
  Future<bool> get running async => active;
  @override
  Future<void> start(String title, String text) async {
    calls.add('start:$text');
    if (starting != null) await starting!.future;
    if (refuse) throw StateError('OS refused background service');
    active = true;
  }

  @override
  Future<void> update(String title, String text) async {
    calls.add('update:$text');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    active = false;
  }
}

void main() {
  test(
    'a pending scan start cannot race Studio or stop its notification',
    () async {
      final backend = FakeForeground()..starting = Completer<void>();
      final service = ForegroundServiceCoordinator(backend);
      final scan = service.acquire('scan', 'Scan', '1 of 20');
      final studio = service.acquire('studio', 'Studio', '2 jobs');
      final stopScan = service.release('scan');
      await Future<void>.delayed(Duration.zero);
      expect(backend.calls, ['start:1 of 20']);
      backend.starting!.complete();
      await Future.wait([scan, studio, stopScan]);
      expect(backend.calls, [
        'start:1 of 20',
        'update:1 of 20 • 2 jobs',
        'update:2 jobs',
      ]);
      expect(backend.active, isTrue);
      await service.release('studio');
      expect(backend.calls.last, 'stop');
      expect(backend.active, isFalse);
    },
  );

  test(
    'service refusal is visible and a later progress update retries',
    () async {
      final backend = FakeForeground()..refuse = true;
      final service = ForegroundServiceCoordinator(backend);
      await service.acquire('scan', 'Scan', '1 of 20');
      expect(service.error.value, isA<StateError>());
      backend.refuse = false;
      await service.update('scan', '2 of 20');
      expect(service.error.value, isNull);
      expect(backend.active, isTrue);
      await service.release('scan');
    },
  );

  appTest(
    'background setup requests permissions and refreshes on return',
    (tester, env) async {
      final service = FakeBackground();
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/background'),
          backgroundExecutionProvider.overrideWithValue(service),
        ],
      );
      expect(find.text('Background work'), findsOneWidget);
      await tester.tap(find.byKey(const Key('background-enable')));
      await tester.pumpAndSettle();
      expect(service.requests, 1);
      expect(find.byKey(const Key('background-enable')), findsNothing);
      service.current = const BackgroundStatus(supported: true, running: true);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Background service is running'), findsOneWidget);
      expect(find.byKey(const Key('background-enable')), findsOneWidget);
      expect(await env.db.setting('background.prompted'), 'true');
    },
    session: testSession,
  );

  for (final allow in [false, true]) {
    appTest(
      'first work permission prompt: allow=$allow is optional and remembered',
      (tester, env) async {
        final service = FakeBackground();
        var started = 0;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...env.overrides,
              backgroundExecutionProvider.overrideWithValue(service),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Consumer(
                builder: (context, ref, _) => Scaffold(
                  body: FilledButton(
                    onPressed: () async {
                      await prepareBackgroundForWork(context, ref);
                      started++;
                    },
                    child: const Text('Start work'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start work'));
        await tester.pumpAndSettle();
        expect(started, 0);
        await tester.tap(
          find.text(allow ? 'Allow background work' : 'Continue for now'),
        );
        await tester.pumpAndSettle();
        expect(started, 1);
        expect(service.requests, allow ? 1 : 0);
        await tester.tap(find.text('Start work'));
        await tester.pumpAndSettle();
        expect(started, 2);
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  }
}
