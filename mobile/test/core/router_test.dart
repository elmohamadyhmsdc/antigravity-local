import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:antigravity_mobile/core/router.dart';
import 'package:antigravity_mobile/features/lora/curation_review_screen.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';

import '../support/fakes.dart';

Widget _buildApp(GoRouter router, [List<Override> extra = const []]) {
  return ProviderScope(
    overrides: extra,
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('Router P3 Redirects & Route Navigation', () {
    testWidgets(
      'P3 redirect: /jobs redirects to /activity with query params preserved',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/jobs?view=failed',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/activity',
        );
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .uri
              .queryParameters['view'],
          'failed',
        );
      },
    );

    testWidgets('P3 redirect: /jobs/:id redirects to /activity/:id', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/jobs/job-42',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/activity/job-42',
      );
    });

    testWidgets('P3 redirect: /results/:id redirects to /studio/results/:id', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/results/res-10',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/results/res-10',
      );
    });

    testWidgets(
      'P3 redirect: /lora/model/:id redirects to /studio/models/:id',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/lora/model/mod-5',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/studio/models/mod-5',
        );
      },
    );

    testWidgets('P3 redirect: /lora/build redirects to /studio/datasets/new', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/lora/build?person=12',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/datasets/new',
      );
      expect(
        router
            .routerDelegate
            .currentConfiguration
            .uri
            .queryParameters['person'],
        '12',
      );
    });

    testWidgets(
      'P3 redirect: /datasets/:id redirects to /studio/datasets/:id',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/datasets/ds-99',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/studio/datasets/ds-99',
        );
      },
    );

    testWidgets('P3 redirect: /lora/train redirects to /studio/train', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/lora/train?dataset=ds-1',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/train',
      );
      expect(
        router
            .routerDelegate
            .currentConfiguration
            .uri
            .queryParameters['dataset'],
        'ds-1',
      );
    });

    testWidgets('P3 redirect: /lora/generate redirects to /studio/generate', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/lora/generate?id=lora-1',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/generate',
      );
      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['id'],
        'lora-1',
      );
    });

    testWidgets(
      'P3 redirect: /reface redirects to /studio/reface translating legacy target',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!details.toString().contains('overflowed')) {
            prevOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = prevOnError);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/reface?media=10&target=20&person=3',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/studio/reface',
        );
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .uri
              .queryParameters['target'],
          'media:10,det:20',
        );
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .uri
              .queryParameters['person'],
          '3',
        );
      },
    );

    testWidgets('P3 redirect: /discover redirects to /explore', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/discover',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(router.routerDelegate.currentConfiguration.uri.path, '/explore');
    });

    testWidgets('P3 redirect: /connection redirects to /settings/computer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/connection',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/settings/computer',
      );
    });

    testWidgets('P3 redirect: /storage redirects to /settings/storage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/storage',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/settings/storage',
      );
    });

    testWidgets('P3 redirect: /background redirects to /settings/background', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/background',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/settings/background',
      );
    });

    testWidgets('P3 redirect: /backup redirects to /settings/backup', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/backup',
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(_buildApp(router));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/settings/backup',
      );
    });

    testWidgets(
      'pairing redirect: /pair redirects to /permissions when isPaired is true',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => true,
          initialLocation: '/pair',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          '/permissions',
        );
      },
    );

    testWidgets(
      'pairing redirect: /pair remains on /pair when isPaired is false',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => false,
          initialLocation: '/pair',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(router.routerDelegate.currentConfiguration.uri.path, '/pair');
      },
    );

    testWidgets(
      'pairing deep link: agmobile scheme forwards to /welcome with link',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final router = createRouter(
          isPaired: () => false,
          initialLocation:
              '/welcome?link=agmobile%3A%2F%2Fpair%3Fhost%3D192.168.1.5',
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router));
        await tester.pump(const Duration(milliseconds: 100));

        expect(router.routerDelegate.currentConfiguration.uri.path, '/welcome');
        expect(
          router
              .routerDelegate
              .currentConfiguration
              .uri
              .queryParameters['link'],
          'agmobile://pair?host=192.168.1.5',
        );
      },
    );

    testWidgets('legacy routes not yet redirected in P3 stay accessible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final env = TestEnv(session: testSession);

      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (!details.toString().contains('overflowed') &&
            !details.toString().contains('A RenderFlex overflowed')) {
          prevOnError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = prevOnError);

      final unredirectedRoutes = [
        '/lora',
        '/results',
        '/analyze',
        '/home',
        '/bodies',
        '/marks',
        '/characters',
      ];

      for (final path in unredirectedRoutes) {
        final router = createRouter(
          isPaired: () => true,
          initialLocation: path,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(_buildApp(router, env.overrides));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          path,
          reason: '$path should remain directly accessible in P3',
        );
      }
      await env.dispose(tester);
    });

    testWidgets('curation route /studio/curation/:id opens directly', (
      tester,
    ) async {
      final env = TestEnv(session: testSession);
      final router = createRouter(
        isPaired: () => true,
        initialLocation: '${Routes.studioCuration}/15?name=Sara',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router, env.overrides));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/curation/15',
      );
      expect(find.byType(CurationReviewScreen), findsOneWidget);
      await env.dispose(tester);
    });

    testWidgets('curation route /studio/curation/:placeholder/:id redirects safely', (
      tester,
    ) async {
      final env = TestEnv(session: testSession);
      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/studio/curation/:id/155?name=Jelly%20Bean%20Brains',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router, env.overrides));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/studio/curation/155',
      );
      expect(find.byType(CurationReviewScreen), findsOneWidget);
      await env.dispose(tester);
    });

    testWidgets('root / redirects to /library', (tester) async {
      final env = TestEnv(session: testSession);
      final router = createRouter(
        isPaired: () => true,
        initialLocation: '/',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildApp(router, env.overrides));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        Routes.library,
      );
      await env.dispose(tester);
    });
  });
}
