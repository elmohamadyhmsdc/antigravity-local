import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/db/app_database.dart';
import '../data/media/media_library.dart';
import '../data/repositories/media_queries.dart';
import '../domain/targets/target_ref.dart';
import '../features/activity/activity_screen.dart';
import '../features/activity/job_detail_screen.dart';
import '../features/analyze/analyze_screen.dart';
import '../features/backup/backup_screen.dart';
import '../features/bodies/bodies_screen.dart';
import '../features/bodies/discover_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/native_gallery.dart';
import '../features/lora/lora_screens.dart';
import '../features/marks/person_marks_screen.dart';
import '../features/media/media_screen.dart';
import '../features/merge/merge_screen.dart';
import '../features/onboarding/pair_screen.dart';
import '../features/onboarding/permissions_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/people/identity_groups_screen.dart';
import '../features/people/organize_media_screen.dart';
import '../features/people/people_screen.dart';
import '../features/people/person_detail_screen.dart';
import '../features/people/unsorted_screen.dart';
import '../features/reface/reface_screen.dart';
import '../features/restyle/restyle_screen.dart';
import '../features/results/results_screen.dart';
import '../features/review/quick_review_screen.dart';
import '../features/settings/background_screen.dart';
import '../features/settings/connection_screen.dart';
import '../features/settings/library_settings_screen.dart';
import '../features/settings/privacy_settings_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/storage/storage_screen.dart';
import '../features/studio/studio_screen.dart';
import '../features/video_actions/video_actions_screen.dart';

abstract final class Routes {
  // Shell Roots
  static const library = '/library';
  static const people = '/people';
  static const explore = '/explore';
  static const studio = '/studio';

  // Library & Viewer
  static const album = '/library/album'; // /library/album/:id
  static const media = '/media'; // /media/:id

  // People & Review
  static const characters = '/characters'; // legacy
  static const person = '/people'; // /people/:id
  static const group = '/groups'; // /groups/:id
  static const personFiles = '/people'; // /people/:id/files
  static const unsorted = '/people/unsorted';
  static const review = '/review';
  static const merge = '/merge'; // /merge/:a/:b

  // Explore
  static const exploreCollection = '/explore'; // /explore/:kind
  static const exploreCluster = '/explore'; // /explore/:kind/:id
  static const exploreAction = '/explore/actions'; // /explore/actions/:id
  static const exploreActionExample =
      '/explore/actions'; // /explore/actions/:id/example
  static const bodies = '/bodies'; // legacy
  static const marks = '/marks'; // legacy
  static const discover = '/discover'; // legacy

  // Studio
  static const studioReface = '/studio/reface';
  static const restyle = '/restyle';
  static const studioGenerate = '/studio/generate';
  static const studioDatasetsNew = '/studio/datasets/new';
  static const studioDatasets = '/studio/datasets'; // /studio/datasets/:id
  static const studioTrain = '/studio/train';
  static const studioResults = '/studio/results'; // /studio/results/:id
  static const studioModels = '/studio/models'; // /studio/models/:id

  // Legacy Studio Routes (redirected or staying until phase)
  static const reface = '/reface';
  static const lora = '/lora';
  static const loraBuild = '/lora/build';
  static const loraTrain = '/lora/train';
  static const loraGenerate = '/lora/generate';
  static const datasets = '/datasets';
  static const results = '/results';

  // Activity
  static const activity = '/activity'; // /activity and /activity/:jobId
  static const jobs = '/jobs'; // legacy

  // Settings
  static const settings = '/settings';
  static const settingsComputer = '/settings/computer';
  static const settingsLibrary = '/settings/library';
  static const settingsPrivacy = '/settings/privacy';
  static const settingsStorage = '/settings/storage';
  static const settingsBackup = '/settings/backup';
  static const settingsBackground = '/settings/background';

  // Legacy Settings Routes
  static const connection = '/connection';
  static const storage = '/storage';
  static const background = '/background';
  static const backup = '/backup';
  static const sources = '/sources';
  static const analyze = '/analyze';
  static const insights = '/insights';
  static const runningScan = '/running-scan';
  static const home = '/home';

  // Onboarding
  static const welcome = '/welcome';
  static const pair = '/pair';
  static const scan = '/pair/scan';
  static const manual = '/pair/manual';
  static const permissions = '/permissions';

  /// Screens that make sense (and are reachable) before a PC is paired.
  static bool isOnboarding(String location) =>
      location == welcome ||
      location == pair ||
      location.startsWith('/pair/') ||
      location == permissions ||
      location == connection ||
      location == settingsComputer;
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
  List<NavigatorObserver>? observers,
}) {
  return GoRouter(
    initialLocation: initialLocation ?? Routes.library,
    refreshListenable: refresh,
    observers: observers,
    redirect: (context, state) {
      if (state.uri.scheme == 'agmobile') return welcomeForLink(state.uri);
      final location = state.uri.path;
      final paired = isPaired();
      // Just paired (or a stale back-stack entry): leave the pairing screens, S02 shows the permissions.
      if (paired &&
          (location == Routes.welcome ||
              location == Routes.pair ||
              location.startsWith('/pair/'))) {
        return location == Routes.welcome &&
                state.uri.queryParameters.containsKey('link')
            ? null
            : Routes.permissions;
      }
      return null;
    },
    routes: [
      // -----------------------------------------------------------------------
      // Onboarding Routes
      // -----------------------------------------------------------------------
      GoRoute(
        path: Routes.welcome,
        builder: (context, state) =>
            WelcomeScreen(link: state.uri.queryParameters['link']),
      ),
      GoRoute(
        path: Routes.pair,
        builder: (context, state) => PairScreen(
          initialHost: state.uri.queryParameters['host'],
          initialPort: int.tryParse(state.uri.queryParameters['port'] ?? ''),
          initialTab: state.uri.queryParameters['tab'] == 'manual' ? 1 : 0,
        ),
      ),
      GoRoute(path: Routes.scan, redirect: (context, state) => Routes.pair),
      GoRoute(
        path: Routes.manual,
        redirect: (context, state) => Uri(
          path: Routes.pair,
          queryParameters: {
            'tab': 'manual',
            if (state.uri.queryParameters['host'] != null)
              'host': state.uri.queryParameters['host']!,
            if (state.uri.queryParameters['port'] != null)
              'port': state.uri.queryParameters['port']!,
          },
        ).toString(),
      ),
      GoRoute(
        path: Routes.permissions,
        builder: (context, state) => const PermissionsScreen(),
      ),

      // -----------------------------------------------------------------------
      // Library & Viewer Routes
      // -----------------------------------------------------------------------
      GoRoute(
        path: '${Routes.album}/:id',
        builder: (context, state) {
          final album = state.extra is AlbumInfo
              ? state.extra as AlbumInfo
              : AlbumInfo(
                  id: state.pathParameters['id']!,
                  name: state.uri.queryParameters['name'] ?? 'Album',
                  count:
                      int.tryParse(state.uri.queryParameters['count'] ?? '') ??
                      0,
                );
          return FolderScreen(album: album);
        },
      ),
      GoRoute(
        path: '${Routes.media}/:id',
        builder: (context, state) {
          final personId = int.tryParse(
            state.uri.queryParameters['personId'] ?? '',
          );
          final scanName = state.uri.queryParameters['scan'];
          final scan = scanName != null
              ? ScanFilter.values.firstWhere(
                  (s) => s.name == scanName,
                  orElse: () => ScanFilter.all,
                )
              : ScanFilter.all;
          final hasFaces = state.uri.queryParameters['hasFaces'] == null
              ? null
              : state.uri.queryParameters['hasFaces'] == 'true';
          final kind = state.uri.queryParameters['kind'];
          final filter =
              (personId != null ||
                  scan != ScanFilter.all ||
                  hasFaces != null ||
                  kind != null)
              ? MediaFilter(
                  personId: personId,
                  scan: scan,
                  hasFaces: hasFaces,
                  kind: kind,
                )
              : null;
          return MediaScreen(
            mediaId: int.parse(state.pathParameters['id']!),
            initialTimestampMs: int.tryParse(
              state.uri.queryParameters['at'] ?? '',
            ),
            filter: filter,
            collection: state.extra is MediaCollectionContext
                ? state.extra as MediaCollectionContext
                : null,
          );
        },
      ),

      // -----------------------------------------------------------------------
      // People, Groups & Review Routes
      // (Order static routes before variable ones!)
      // -----------------------------------------------------------------------
      GoRoute(
        path: Routes.characters,
        builder: (context, state) => const PeopleScreen(kind: 'character'),
      ),
      GoRoute(
        path: Routes.unsorted,
        builder: (context, state) => UnsortedScreen(
          kind: state.uri.queryParameters['kind'] == 'character'
              ? 'character'
              : 'person',
        ),
      ),
      GoRoute(
        path: '${Routes.person}/:id/files',
        builder: (context, state) => OrganizePersonMediaScreen(
          personIds: {int.parse(state.pathParameters['id']!)},
        ),
      ),
      GoRoute(
        path: '${Routes.person}/:id',
        builder: (context, state) => PersonDetailScreen(
          personId: int.parse(state.pathParameters['id']!),
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '${Routes.group}/:id',
        builder: (context, state) =>
            GroupMediaScreen(groupId: int.parse(state.pathParameters['id']!)),
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
        builder: (context, state) => ReviewEntryScreen(
          view: state.uri.queryParameters['view'],
          kind: state.uri.queryParameters['kind'] == 'character'
              ? 'character'
              : 'person',
        ),
      ),

      // -----------------------------------------------------------------------
      // Explore Routes
      // (Static actions before variable kinds!)
      // -----------------------------------------------------------------------
      GoRoute(
        path: '${Routes.exploreAction}/:id/example',
        builder: (context, state) => ActionExampleScreen(
          actionId: state.pathParameters['id']!,
          media: state.extra is MediaRow ? state.extra as MediaRow : null,
        ),
      ),
      GoRoute(
        path: '${Routes.exploreAction}/:id',
        builder: (context, state) => VideoActionDetailScreen(
          actionId: state.pathParameters['id']!,
          personId: int.tryParse(state.uri.queryParameters['personId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '${Routes.explore}/:kind/:id',
        builder: (context, state) => BodiesScreen(
          personId: int.tryParse(state.uri.queryParameters['personId'] ?? ''),
          initialSimilar: int.tryParse(
            state.uri.queryParameters['similar'] ?? '',
          ),
          initialSimilarColours: int.tryParse(
            state.uri.queryParameters['colours'] ?? '',
          ),
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '${Routes.explore}/:kind',
        builder: (context, state) => BodiesScreen(
          personId: int.tryParse(state.uri.queryParameters['personId'] ?? ''),
          initialSimilar: int.tryParse(
            state.uri.queryParameters['similar'] ?? '',
          ),
          initialSimilarColours: int.tryParse(
            state.uri.queryParameters['colours'] ?? '',
          ),
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: Routes.bodies,
        builder: (context, state) => BodiesScreen(
          personId: int.tryParse(state.uri.queryParameters['personId'] ?? ''),
          initialSimilar: int.tryParse(
            state.uri.queryParameters['similar'] ?? '',
          ),
          initialSimilarColours: int.tryParse(
            state.uri.queryParameters['colours'] ?? '',
          ),
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: Routes.marks,
        builder: (context, state) => PersonMarksScreen(
          personId:
              int.tryParse(state.uri.queryParameters['personId'] ?? '') ?? 0,
        ),
      ),

      // -----------------------------------------------------------------------
      // Studio Routes
      // -----------------------------------------------------------------------
      GoRoute(
        path: Routes.studioReface,
        builder: (context, state) {
          final target = TargetRef.fromQueryParams(state.uri.queryParameters);
          return RefaceScreen(
            personId: target.personId,
            faceId: target.faceId,
            identitySetId: target.identitySetId,
            targetMediaId: target.mediaId,
            targetDetectionId: target.detectionId,
          );
        },
      ),
      GoRoute(
        path: Routes.restyle,
        builder: (context, state) => RestyleScreen(
          targetMediaId: int.tryParse(state.uri.queryParameters['media'] ?? ''),
          targetDetectionId: int.tryParse(
            state.uri.queryParameters['target'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: Routes.studioGenerate,
        builder: (context, state) => LoraGenerateScreen(
          loraId: state.uri.queryParameters['id'],
          referenceMediaId: int.tryParse(
            state.uri.queryParameters['media'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: Routes.studioDatasetsNew,
        builder: (context, state) => DatasetBuildScreen(
          personId: int.tryParse(state.uri.queryParameters['person'] ?? ''),
          mediaId: int.tryParse(state.uri.queryParameters['media'] ?? ''),
        ),
      ),
      GoRoute(
        path: '${Routes.studioDatasets}/:id',
        builder: (context, state) =>
            DatasetScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.studioTrain,
        builder: (context, state) =>
            LoraTrainScreen(datasetId: state.uri.queryParameters['dataset']),
      ),
      GoRoute(
        path: '${Routes.studioResults}/:id',
        builder: (context, state) =>
            ResultDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '${Routes.studioModels}/:id',
        builder: (context, state) =>
            ModelDetailScreen(id: state.pathParameters['id']!),
      ),
      GoRoute(
        path: Routes.lora,
        builder: (context, state) => const LoraScreen(),
      ),
      GoRoute(
        path: Routes.results,
        builder: (context, state) => const ResultsScreen(),
      ),

      // -----------------------------------------------------------------------
      // Activity Routes
      // -----------------------------------------------------------------------
      GoRoute(
        path: '${Routes.activity}/:jobId',
        builder: (context, state) =>
            JobDetailScreen(id: state.pathParameters['jobId']!),
      ),
      GoRoute(
        path: Routes.activity,
        builder: (context, state) => const ActivityScreen(),
      ),

      // -----------------------------------------------------------------------
      // Settings Routes
      // -----------------------------------------------------------------------
      GoRoute(
        path: Routes.settingsComputer,
        builder: (context, state) => const ConnectionScreen(),
      ),
      GoRoute(
        path: Routes.settingsLibrary,
        builder: (context, state) => const LibrarySettingsScreen(),
      ),
      GoRoute(
        path: Routes.settingsPrivacy,
        builder: (context, state) => const PrivacySettingsScreen(),
      ),
      GoRoute(
        path: Routes.settingsStorage,
        builder: (context, state) => const StorageScreen(),
      ),
      GoRoute(
        path: Routes.settingsBackup,
        builder: (context, state) => const BackupScreen(),
      ),
      GoRoute(
        path: Routes.settingsBackground,
        builder: (context, state) => const BackgroundScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),

      // Legacy Settings & Status Routes (Phase P4 Redirects)
      GoRoute(
        path: Routes.sources,
        redirect: (context, state) => Routes.settingsLibrary,
      ),
      GoRoute(
        path: Routes.analyze,
        builder: (context, state) => AnalyzeScreen(
          characters: state.uri.queryParameters['characters'] == 'true',
        ),
      ),
      GoRoute(
        path: Routes.insights,
        redirect: (context, state) => Routes.settingsLibrary,
      ),
      GoRoute(
        path: Routes.runningScan,
        redirect: (context, state) => Routes.activity,
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),

      // -----------------------------------------------------------------------
      // Phase P3 Redirects (from 07 §3)
      // -----------------------------------------------------------------------
      GoRoute(
        path: Routes.jobs,
        redirect: (context, state) => Uri(
          path: Routes.activity,
          queryParameters: state.uri.queryParameters.isEmpty
              ? null
              : state.uri.queryParameters,
        ).toString(),
      ),
      GoRoute(
        path: '${Routes.jobs}/:id',
        redirect: (context, state) =>
            '${Routes.activity}/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '${Routes.results}/:id',
        redirect: (context, state) =>
            '${Routes.studioResults}/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: '${Routes.lora}/model/:id',
        redirect: (context, state) =>
            '${Routes.studioModels}/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: Routes.loraBuild,
        redirect: (context, state) => Uri(
          path: Routes.studioDatasetsNew,
          queryParameters: state.uri.queryParameters.isEmpty
              ? null
              : state.uri.queryParameters,
        ).toString(),
      ),
      GoRoute(
        path: '${Routes.datasets}/:id',
        redirect: (context, state) =>
            '${Routes.studioDatasets}/${state.pathParameters['id']}',
      ),
      GoRoute(
        path: Routes.loraTrain,
        redirect: (context, state) => Uri(
          path: Routes.studioTrain,
          queryParameters: state.uri.queryParameters.isEmpty
              ? null
              : state.uri.queryParameters,
        ).toString(),
      ),
      GoRoute(
        path: Routes.loraGenerate,
        redirect: (context, state) => Uri(
          path: Routes.studioGenerate,
          queryParameters: state.uri.queryParameters.isEmpty
              ? null
              : state.uri.queryParameters,
        ).toString(),
      ),
      GoRoute(
        path: Routes.reface,
        redirect: (context, state) {
          final target = TargetRef.fromQueryParams(state.uri.queryParameters);
          final params = target.toQueryParams();
          return Uri(
            path: Routes.studioReface,
            queryParameters: params.isEmpty ? null : params,
          ).toString();
        },
      ),
      GoRoute(
        path: Routes.discover,
        redirect: (context, state) => Routes.explore,
      ),
      GoRoute(
        path: Routes.connection,
        redirect: (context, state) => Routes.settingsComputer,
      ),
      GoRoute(
        path: Routes.storage,
        redirect: (context, state) => Routes.settingsStorage,
      ),
      GoRoute(
        path: Routes.background,
        redirect: (context, state) => Routes.settingsBackground,
      ),
      GoRoute(
        path: Routes.backup,
        redirect: (context, state) => Routes.settingsBackup,
      ),

      // -----------------------------------------------------------------------
      // Shell Route (4 Bottom Navigation Tabs)
      // -----------------------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
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
                path: Routes.people,
                builder: (context, state) => const PeopleScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.explore,
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.studio,
                builder: (context, state) => const StudioScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
