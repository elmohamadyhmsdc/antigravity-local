import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/api/studio_api.dart';
import 'data/db/app_database.dart';
import 'data/platform/foreground_keep_alive.dart';
import 'data/platform/studio_notifications.dart';
import 'dart:ui';
import 'l10n/app_localizations.dart';
import 'data/repositories/studio_repository.dart';
import 'data/repositories/lora_repository.dart';
import 'domain/jobs/job_tracker.dart';
import 'domain/scan/scan_state.dart';
import 'library_providers.dart';
import 'providers.dart';

final studioApiProvider = Provider<StudioApi?>((ref) {
  final api = ref.watch(mobileApiProvider);
  return api is StudioApi ? api as StudioApi : null;
});
final studioRepositoryProvider = Provider<StudioRepository>(
  (ref) => StudioRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
  ),
);
final studioKeepAliveProvider = Provider<ScanKeepAlive>(
  (ref) => const ForegroundServiceKeepAlive(
    channelName: 'Studio jobs',
    channelDescription: 'Uploads and private results',
  ),
);
final jobTrackerProvider = Provider<JobTracker>((ref) {
  final tracker = JobTracker(
    repository: ref.watch(studioRepositoryProvider),
    api: () => ref.read(studioApiProvider),
    keepAlive: ref.watch(studioKeepAliveProvider),
    onCompleted: (id) {
      final l10n = lookupAppLocalizations(const Locale('en'));
      return StudioNotifications.completed(
        id,
        title: l10n.privateResults,
        body: l10n.studioResultReady,
      );
    },
  );
  ref.onDispose(tracker.dispose);
  return tracker;
});
final jobsProvider = StreamProvider<List<JobRow>>(
  (ref) => ref.watch(studioRepositoryProvider).watchJobs(),
);
final jobProvider = StreamProvider.autoDispose.family<JobRow?, String>(
  (ref, id) => ref.watch(studioRepositoryProvider).watchJob(id),
);
final resultsProvider = StreamProvider<List<ResultRow>>(
  (ref) => ref.watch(studioRepositoryProvider).watchResults(),
);
final resultProvider = StreamProvider.autoDispose.family<ResultRow?, String>(
  (ref, id) => ref.watch(studioRepositoryProvider).watchResult(id),
);
final loraRepositoryProvider = Provider<LoraRepository>(
  (ref) =>
      LoraRepository(ref.watch(databaseProvider), ref.watch(fileStoreProvider)),
);
final datasetsProvider = StreamProvider<List<DatasetRow>>(
  (ref) => ref.watch(loraRepositoryProvider).watchDatasets(),
);
final lorasProvider = StreamProvider<List<LoraRow>>(
  (ref) => ref.watch(loraRepositoryProvider).watchLoras(),
);
final datasetItemsProvider = StreamProvider.autoDispose
    .family<List<DatasetItemRow>, String>(
      (ref, id) => ref.watch(loraRepositoryProvider).watchItems(id),
    );
