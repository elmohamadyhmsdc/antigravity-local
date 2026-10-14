import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/analyze/analyze_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/media/media_screen.dart';
import '../features/merge/merge_screen.dart';
import '../features/people/people_screen.dart';
import '../features/people/person_detail_screen.dart';
import '../features/people/unsorted_screen.dart';
import '../features/onboarding/manual_pair_screen.dart';
import '../features/onboarding/permissions_screen.dart';
import '../features/onboarding/qr_scan_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/review/review_screen.dart';
import '../features/scan/sources_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shared/placeholder_screen.dart';
import '../features/shell/app_shell.dart';
import '../l10n/app_localizations.dart';

abstract final class Routes {
  static const home = '/home';
  static const people = '/people';
  static const library = '/library';
  static const studio = '/studio';
  static const jobs = '/jobs';
  static const settings = '/settings';
  static const analyze = '/analyze';
  static const media = '/media'; // S06, /media/:id
  static const unsorted = '/people/unsorted';
  static const review = '/review'; // S10
  static const merge = '/merge'; // S11, /merge/:a/:b
  static const sources = '/sources'; // S05
  static const backup = '/backup'; // S26
  static const welcome = '/welcome'; // S01
  static const scan = '/pair/scan';
  static const manual = '/pair/manual';
  static const permissions = '/permissions'; // S02

  /// Screens that make sense (and are reachable) before a PC is paired.
  static bool isOnboarding(String location) =>
      location == welcome || location.startsWith('/pair/');
}

/// Back to the previous screen, or to [fallback] when this screen was opened directly.
void leave(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// `agmobile://pair?...` (a tapped pairing link) arrives as a location with that scheme.
String welcomeForLink(Uri link) => Uri(
  path: Routes.welcome,
  queryParameters: {'link': link.toString()},
).toString();

GoRouter createRouter({
  required bool Function() isPaired,
  Listenable? refresh,
  String? initialLocation,
}) {
  return GoRouter(
    initialLocation:
        initialLocation ?? (isPaired() ? Routes.home : Routes.welcome),
    refreshListenable: refresh,
    redirect: (context, state) {
      if (state.uri.scheme == 'agmobile') return welcomeForLink(state.uri);
      final location = state.uri.path;
      final paired = isPaired();
      if (!paired && !Routes.isOnboarding(location)) return Routes.welcome;
      // Just paired (or a stale back-stack entry): leave the pairing screens, S02 shows the permissions.
      if (paired &&
          (location == Routes.welcome || location.startsWith('/pair/'))) {
        return location == Routes.welcome &&
                state.uri.queryParameters.containsKey('link')
            ? null
            : Routes.permissions;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) =>
            WelcomeScreen(link: state.uri.queryParameters['link']),
      ),
      GoRoute(
        path: Routes.scan,
        builder: (context, state) => const QrScanScreen(),
      ),
      GoRoute(
        path: Routes.manual,
        builder: (context, state) => const ManualPairScreen(),
      ),
      GoRoute(
        path: Routes.permissions,
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(
        path: Routes.analyze,
        builder: (context, state) => const AnalyzeScreen(),
      ),
      GoRoute(
        path: Routes.unsorted,
        builder: (context, state) => const UnsortedScreen(),
      ),
      GoRoute(
        path: '${Routes.people}/:id',
        builder: (context, state) => PersonDetailScreen(
          personId: int.parse(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '${Routes.media}/:id',
        builder: (context, state) =>
            MediaScreen(mediaId: int.parse(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '${Routes.merge}/:a/:b',
        builder: (context, state) => MergeScreen(
          a: int.parse(state.pathParameters['a']!),
          b: int.parse(state.pathParameters['b']!),
        ),
      ),
      GoRoute(
        path: Routes.review,
        builder: (context, state) => const ReviewScreen(),
      ),
      GoRoute(
        path: Routes.sources,
        builder: (context, state) => const SourcesScreen(),
      ),
      GoRoute(
        path: Routes.backup,
        builder: (context, state) => const BackupScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.people,
                builder: (context, state) => const PeopleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.library,
                builder: (context, state) => const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.studio,
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return PlaceholderScreen(
                    title: l10n.navStudio,
                    description: l10n.studioPlaceholder,
                    phase: 'P4',
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.jobs,
                builder: (context, state) {
                  final l10n = AppLocalizations.of(context);
                  return PlaceholderScreen(
                    title: l10n.navJobs,
                    description: l10n.jobsPlaceholder,
                    phase: 'P4',
                  );
                },
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
