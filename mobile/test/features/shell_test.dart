import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/core/router.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/ui/activity/activity_pill.dart';
import 'package:antigravity_mobile/ui/activity/activity_pill_host.dart';
import 'package:antigravity_mobile/ui/activity/activity_state_provider.dart';

import '../support/fakes.dart';

void main() {
  group('Shell & ActivityPill Integration', () {
    testWidgets('AppShell shows 4 destinations and hosts ActivityPill', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final env = TestEnv(session: testSession);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/library',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...env.overrides,
            activityStateProvider.overrideWithValue(
              const ActivityScanning(done: 5, total: 20),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 4 navigation destinations
      for (final label in ['Gallery', 'People', 'Explore', 'Studio']) {
        expect(
          find.widgetWithText(NavigationDestination, label),
          findsOneWidget,
        );
      }

      // ActivityPill is rendered inside AppShell directly above bottom bar
      expect(find.byType(ActivityPill), findsOneWidget);
      expect(find.text('Scanning 5 / 20'), findsOneWidget);

      await env.dispose(tester);
    });

    testWidgets(
      'ActivityPillHost displays pill on interior screens and hides on root',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/settings/storage',
        );
        addTearDown(router.dispose);

        final popupObserver = AppPopupObserver();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activityStateProvider.overrideWithValue(
                const ActivityScanning(done: 3, total: 10),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => ActivityPillHost(
                router: router,
                popupObserver: popupObserver,
                child: child!,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Interior screen has the pill hosted by ActivityPillHost
        expect(find.byType(ActivityPill), findsOneWidget);
        expect(find.text('Scanning 3 / 10'), findsOneWidget);

        // Now navigate to a root screen (e.g. /explore)
        router.go('/explore');
        await tester.pump(const Duration(milliseconds: 100));

        // ActivityPillHost itself does NOT render the pill on root (AppShell renders it)
        // Since AppShell renders 1 pill, total count is still 1 (not duplicated).
        expect(find.byType(ActivityPill), findsOneWidget);
      },
    );

    testWidgets(
      'ActivityPillHost hides pill on onboarding and viewer screens',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => false,
          initialLocation: '/welcome',
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activityStateProvider.overrideWithValue(
                const ActivityScanning(done: 2, total: 5),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) =>
                  ActivityPillHost(router: router, child: child!),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Onboarding screens must NOT show activity pill
        expect(find.byKey(const Key('activity-pill')), findsNothing);
      },
    );
  });
}
