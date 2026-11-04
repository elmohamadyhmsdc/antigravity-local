import 'data/api/action_api.dart';
import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/db/open_database.dart' show databaseFileName;
import 'data/files/crop_cache.dart';
import 'data/files/crop_cutter.dart';
import 'data/files/file_store.dart';
import 'data/index/embedding_index.dart';
import 'data/index/index_loader.dart';
import 'data/media/media_library.dart';
import 'data/media/thumbnail_service.dart';
import 'data/platform/foreground_keep_alive.dart';
import 'data/platform/backup_crypto.dart';
import 'data/platform/video_frames.dart';
import 'data/repositories/app_settings.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/media_queries.dart';
import 'data/repositories/media_action_source.dart';
import 'data/repositories/video_actions_repository.dart';
import 'data/repositories/people_repository.dart';
import 'data/repositories/identity_groups.dart';
import 'data/platform/media_organizer.dart';
import 'domain/organization/person_media_organizer.dart';
import 'domain/organization/dynamic_auto_organizer.dart';
import 'data/repositories/character_repository.dart';
import 'data/repositories/kind_corrections.dart';
import 'data/repositories/review_questions.dart';
import 'data/repositories/review_repository.dart';
import 'domain/backup/backup_service.dart';
import 'domain/corrections/body_link_guard.dart';
import 'domain/corrections/correction_service.dart';
import 'domain/corrections/corrections_queries.dart';
import 'domain/corrections/targeted_detection_service.dart';

export 'domain/corrections/targeted_detection_service.dart';
import 'domain/grouping/grouping_runner.dart';
import 'domain/scan/drawn_face_sweep.dart';
import 'domain/scan/outline_backfill.dart';
import 'domain/scan/redetect.dart';
import 'domain/scan/photo_result_store.dart';
import 'domain/scan/video_compactor.dart';
import 'domain/marks/body_marks.dart';
import 'domain/marks/patch_cutter.dart';
import 'domain/pose/body_categories.dart';
import 'domain/pose/group_pose_matcher.dart';
import 'domain/pose/equipment_library.dart';
import 'domain/pose/exposed_matching.dart';
import 'domain/pose/pose_index.dart';
import 'domain/garments/garment_backfill.dart';
import 'domain/sensitive/embedding_backfill.dart';
import 'domain/sensitive/sensitive_backfill.dart';
import 'domain/storage/storage_sweeper.dart';
import 'domain/scan/scan_engine.dart';
import 'domain/scan/scan_state.dart';
import 'domain/scan/video_scan.dart';
import 'l10n/app_localizations.dart';
import 'providers.dart';

// Providers of the library features (P2): scan, people, review, backup. The data layer
// (`data/`, `domain/`) knows nothing about Riverpod; this file is the only glue.

AppLocalizations get _en => lookupAppLocalizations(const Locale('en'));

// ---- files, settings ----------------------------------------------------------------

/// Face / body crops. Overridden in main.dart (and in tests).
final fileStoreProvider = Provider<FileStore>(
  (ref) => throw UnimplementedError('fileStoreProvider must be overridden'),
);

/// Measures the phone's storage and removes files nothing refers to any more.
final storageSweeperProvider = FutureProvider<StorageSweeper>((ref) async {
  final support = await getApplicationSupportDirectory();
  return StorageSweeper(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    databaseFile: File(p.join(support.path, databaseFileName)),
    tempDirs: [await getTemporaryDirectory(), Directory.systemTemp],
  );
});

/// Face/body thumbnails as a size-capped cache, cut again from the originals when needed.
final cropCacheProvider = Provider<CropCache>((ref) {
  final cache = CropCache(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    loadOriginal: originalLoader(
      ref.watch(mediaLibraryProvider),
      Platform.isAndroid ? const AndroidVideoFrames() : null,
    ),
    cut: cutCrop,
  );
  // start-up trim; a failure only leaves more thumbnails on disk
  unawaited(cache.evict().then((_) {}, onError: (_) {}));
  return cache;
});

final appSettingsProvider = Provider<AppSettings>(
  (ref) => AppSettings(ref.watch(databaseProvider)),
);

final settingsProvider = StreamProvider<SettingsSnapshot>(
  (ref) => ref.watch(appSettingsProvider).watch(),
);
final backupCryptoProvider = Provider<BackupCrypto>(
  (ref) => const AndroidBackupCrypto(),
);

// ---- the phone's photo library ---------------------------------------------------------

final mediaLibraryProvider = Provider<MediaLibrary>(
  (ref) => PhotoManagerLibrary(),
);

final mediaLocationProvider = FutureProvider.autoDispose
    .family<MediaLocation?, String>((ref, assetId) async {
      final library = ref.watch(mediaLibraryProvider);
      if (library is! MediaLocationLibrary) return null;
      try {
        return await (library as MediaLocationLibrary).location(assetId);
      } on Object {
        return null; // The viewer remains usable after access was revoked.
      }
    });

final thumbnailServiceProvider = Provider<ThumbnailService>(
  (ref) => ThumbnailService(ref.watch(mediaLibraryProvider)),
);

/// The albums to choose from on the Sources screen.
final albumsProvider = FutureProvider.autoDispose<List<AlbumInfo>>((ref) async {
  final library = ref.watch(mediaLibraryProvider);
  if (!await library.requestAccess()) return const [];
  return library.albums();
});

// ---- identity index --------------------------------------------------------------------

final embeddingIndexProvider = Provider<EmbeddingIndex>((ref) {
  final db = ref.watch(databaseProvider);
  final index = LazyEmbeddingIndex(() async {
    final real = await IsolateEmbeddingIndex.spawn();
    await loadFacesIntoIndex(db, real);
    return real;
  });
  ref.onDispose(index.dispose);
  return index;
});

// ---- repositories ------------------------------------------------------------------------

final videoActionsRepositoryProvider = Provider<VideoActionsRepository>(
  (ref) => VideoActionsRepository(
    ref.watch(databaseProvider),
    remoteMatcher: () {
      final status = ref.read(serverStatusProvider).value;
      final caps = status is ServerReady
          ? status.capabilities
          : status is ServerBusy
          ? status.capabilities
          : null;
      final api = ref.read(mobileApiProvider);
      return caps?.supportsOperation('action_match', 'person') == true &&
              api is ActionMatchApi
          ? api as ActionMatchApi
          : null;
    },
  ),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(databaseProvider)),
);

final mediaQueriesProvider = Provider<MediaQueries>(
  (ref) => MediaQueries(ref.watch(databaseProvider)),
);

final mediaActionSourceProvider = Provider<MediaActionSource>(
  (ref) => MediaActionSource(
    repository: ref.watch(libraryRepositoryProvider),
    queries: ref.watch(mediaQueriesProvider),
    library: ref.watch(mediaLibraryProvider),
  ),
);

/// "This is a person / a character" corrections (files, faces, bodies, whole people).
final kindCorrectionsProvider = Provider<KindCorrections>(
  (ref) => KindCorrections(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
  ),
);

final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
    autoOrganizer: ref.watch(dynamicAutoOrganizerProvider),
  ),
);

final characterRepositoryProvider = Provider<CharacterRepository>(
  (ref) => CharacterRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
  ),
);

/// The same repository as people, scoped to drawn characters (kind = 'character').
final characterPeopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
    kind: 'character',
    autoOrganizer: ref.watch(dynamicAutoOrganizerProvider),
  ),
);

/// People or characters, by kind ('person' | 'character').
final peopleRepositoryByKindProvider =
    Provider.family<PeopleRepository, String>(
      (ref, kind) => ref.watch(
        kind == 'character'
            ? characterPeopleRepositoryProvider
            : peopleRepositoryProvider,
      ),
    );

/// The review plan of one kind.
final reviewRepositoryByKindProvider =
    Provider.family<ReviewRepository, String>(
      (ref, kind) => ref.watch(
        kind == 'character'
            ? characterReviewRepositoryProvider
            : reviewRepositoryProvider,
      ),
    );

PeopleRepository peopleRepositoryFor(WidgetRef ref, String kind) =>
    ref.read(peopleRepositoryByKindProvider(kind));

ReviewRepository reviewRepositoryFor(WidgetRef ref, String kind) =>
    ref.read(reviewRepositoryByKindProvider(kind));

/// Pending review decisions / unsorted faces / questions of one kind.
final reviewCountsByKindProvider = StreamProvider.autoDispose
    .family<ReviewCounts, String>(
      (ref, kind) =>
          ref.watch(reviewRepositoryByKindProvider(kind)).watchCounts(),
    );

final reviewQuestionsByKindProvider = StreamProvider.autoDispose
    .family<List<ReviewQuestion>, String>(
      (ref, kind) =>
          ref.watch(reviewRepositoryByKindProvider(kind)).watchQuestions(),
    );

final charactersProvider = StreamProvider.autoDispose<List<PersonSummary>>(
  (ref) => ref.watch(characterPeopleRepositoryProvider).watchPeople(),
);

final characterUnsortedCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(characterPeopleRepositoryProvider).watchUnsortedCount(),
);

final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(
    ref.watch(databaseProvider),
    ref.watch(peopleRepositoryProvider),
  ),
);

final peopleProvider = StreamProvider.autoDispose<List<PersonSummary>>(
  (ref) => ref.watch(peopleRepositoryProvider).watchPeople(),
);

final unsortedCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(peopleRepositoryProvider).watchUnsortedCount(),
);

final reviewCountsProvider = StreamProvider.autoDispose<ReviewCounts>(
  (ref) => ref.watch(reviewRepositoryProvider).watchCounts(),
);

/// The quick review's queue (snoozed questions left out), highest impact first.
final reviewQuestionsProvider =
    StreamProvider.autoDispose<List<ReviewQuestion>>(
      (ref) => ref.watch(reviewRepositoryProvider).watchQuestions(),
    );

final scanCountsProvider = StreamProvider.autoDispose<ScanCounts>(
  (ref) => ref.watch(libraryRepositoryProvider).watchScanCounts(),
);

// ---- grouping + scan ---------------------------------------------------------------------

final characterReviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(
    ref.watch(databaseProvider),
    ref.watch(characterPeopleRepositoryProvider),
  ),
);

final characterGroupingRunnerProvider = Provider<GroupingRunner>(
  (ref) => GroupingRunner(
    db: ref.watch(databaseProvider),
    api: () => ref.read(mobileApiProvider),
    settings: ref.watch(appSettingsProvider),
    review: ref.watch(characterReviewRepositoryProvider),
    kind: 'character',
  ),
);

/// Sorts people, then drawn characters with the same steps and their own thresholds.
final groupingRunnerProvider = Provider<GroupingRunner>(
  (ref) => GroupingRunner(
    db: ref.watch(databaseProvider),
    api: () => ref.read(mobileApiProvider),
    settings: ref.watch(appSettingsProvider),
    review: ref.watch(reviewRepositoryProvider),
    then: ref.watch(characterGroupingRunnerProvider),
  ),
);

final scanKeepAliveProvider = Provider<ScanKeepAlive>(
  (ref) => ForegroundServiceKeepAlive(
    channelName: _en.scanChannelName,
    channelDescription: _en.scanChannelDescription,
  ),
);

final photoResultStoreProvider = Provider<PhotoResultStore>(
  (ref) => PhotoResultStore(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
    autoOrganizer: ref.watch(dynamicAutoOrganizerProvider),
  ),
);

/// "Detect faces/bodies again" for one photo or every photo of a person.
final redetectorProvider = Provider<Redetector>(
  (ref) => Redetector(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
    store: ref.watch(photoResultStoreProvider),
    media: ref.watch(mediaLibraryProvider),
    settings: ref.watch(appSettingsProvider),
    api: () => ref.read(mobileApiProvider),
  ),
);

final videoCompactorProvider = Provider<VideoCompactor>(
  (ref) => VideoCompactor(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
  ),
);

/// Removes the drawn (anime/cartoon) faces older scans put in People; runs once at start-up.
final drawnFaceSweepProvider = Provider<DrawnFaceSweep>(
  (ref) => DrawnFaceSweep(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
  ),
);

/// Scanned videos that still keep a face/body row per frame (scanned before tracking).
final videosToCompactProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(videoCompactorProvider).watchPendingCount(),
);

// ignore: omit_obvious_property_types - an explicit type breaks the inference cycle through afterRun
final Provider<ScanEngine> scanEngineProvider = Provider<ScanEngine>((ref) {
  final engine = ScanEngine(
    library: ref.watch(libraryRepositoryProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
    settings: ref.watch(appSettingsProvider),
    store: ref.watch(photoResultStoreProvider),
    grouping: ref.watch(groupingRunnerProvider),
    videoScan: VideoScan(
      db: ref.watch(databaseProvider),
      store: ref.watch(photoResultStoreProvider),
      settings: ref.watch(appSettingsProvider),
      localFrames: Platform.isAndroid ? const AndroidVideoFrames() : null,
    ),
    describeVideo: (stage, progress) => switch (stage) {
      'prepare' => _en.videoPreparing((progress * 100).floor()),
      'upload' => _en.videoUploading((progress * 100).floor()),
      'analyze' => _en.videoAnalyzing((progress * 100).floor()),
      'download' => _en.videoDownloading,
      'queue' => _en.videoWaiting,
      'verify' => _en.videoVerifying,
      'finish' => _en.videoFinishing,
      _ => _en.videoImporting,
    },
    keepAlive: ref.watch(scanKeepAliveProvider),
    keepAliveTitle: _en.scanNotificationTitle,
    describe: (p) => p.video != null
        ? '${p.message ?? _en.scanRunning} · ${_en.scanNotificationText(p.done + p.failed, p.total, p.facesFound + p.video!.facesFound)}'
        : _en.scanNotificationText(p.done + p.failed, p.total, p.facesFound),
    afterRun: () async {
      await ref.read(cropCacheProvider).evict();
      // Roadmap section 8.3: photos scanned before the feature get their regions in the background,
      // only while no scan runs, the user did not pause, and the PC is ready.
      Future<void>.delayed(const Duration(seconds: 10), () async {
        final scan = ref.read(scanEngineProvider);
        // pose descriptors of the bodies this pass added (cheap, local, no PC involved)
        await ref
            .read(poseIndexProvider)
            .rebuild(shouldContinue: () => !scan.isRunning);
        // saved pose / outfit categories look at the new bodies (a body the user removed stays removed)
        final categories = ref.read(bodyCategoriesProvider);
        await categories.rescoreAllPoses();
        await categories.rescoreAllOutfits();
        bool idle() =>
            !scan.isRunning &&
            scan.progress.phase != ScanPhase.paused &&
            ref.read(serverStatusProvider).value is ServerReady;
        await ref.read(sensitiveBackfillProvider).run(shouldContinue: idle);
        // then the DINOv2 pass for photos scanned before Phase 8 (regions are known by now)
        await ref.read(embeddingBackfillProvider).run(shouldContinue: idle);
        // garment tags (Phase 7) only while the user switched them on; evidence, never a filter
        await ref.read(garmentBackfillProvider).run(shouldContinue: idle);
        final status = ref.read(serverStatusProvider).value;
        if (status is ServerReady && status.capabilities.engines.equipment) {
          await ref.read(equipmentLibraryProvider).run(shouldContinue: idle);
        }
      });
    },
  );
  final link = ref.read(scanEngineLinkProvider);
  link.engine = engine;
  ref.onDispose(() {
    if (identical(link.engine, engine)) link.engine = null;
    engine.dispose();
  });
  return engine;
});

final embeddingBackfillProvider = Provider<EmbeddingBackfill>((ref) {
  return EmbeddingBackfill(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
  );
});

final poseIndexProvider = Provider<PoseIndex>(
  (ref) => PoseIndex(ref.watch(databaseProvider)),
);

final exposedMatcherProvider = Provider<ExposedMatcher>(
  (ref) => ExposedMatcher(ref.watch(databaseProvider)),
);

/// Cuts a rotated rectangle out of the original photo (tests replace it).
final patchCutterProvider = Provider<PatchCutter>(
  (ref) => UiPatchCutter(ref.watch(mediaLibraryProvider)).call,
);

final bodyMarkStoreProvider = Provider<BodyMarkStore>(
  (ref) =>
      BodyMarkStore(ref.watch(databaseProvider), ref.watch(fileStoreProvider)),
);

final markMatcherProvider = Provider<MarkMatcher>(
  (ref) => MarkMatcher(
    ref.watch(databaseProvider),
    ref.watch(bodyMarkStoreProvider),
    () => ref.read(mobileApiProvider),
  ),
);

final exposedClustersProvider = Provider<ExposedClusters>(
  (ref) => ExposedClusters(ref.watch(databaseProvider)),
);

final bodyCategoriesProvider = Provider<BodyCategories>(
  (ref) => BodyCategories(
    ref.watch(databaseProvider),
    poses: ref.watch(poseIndexProvider),
  ),
);

final garmentBackfillProvider = Provider<GarmentBackfill>((ref) {
  return GarmentBackfill(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
  );
});

final sensitiveBackfillProvider = Provider<SensitiveBackfill>((ref) {
  return SensitiveBackfill(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
  );
});

/// Live progress of the scan (idle until one starts).
final scanProgressProvider = StreamProvider<ScanProgress>((ref) async* {
  final engine = ref.watch(scanEngineProvider);
  yield engine.progress;
  yield* engine.stream;
});

// ---- backup ----------------------------------------------------------------------------------

final outlineBackfillProvider = Provider<OutlineBackfill>((ref) {
  return OutlineBackfill(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
    isServerReady: () {
      final status = ref.read(serverStatusProvider).value;
      return status is ServerReady;
    },
  );
});

final pendingOutlinesProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(outlineBackfillProvider).watchPending(),
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    settings: ref.watch(appSettingsProvider),
  ),
);

final groupPoseMatcherProvider = Provider<GroupPoseMatcher>(
  (ref) => GroupPoseMatcher(ref.watch(databaseProvider)),
);
final equipmentLibraryProvider = Provider<EquipmentLibrary>(
  (ref) => EquipmentLibrary(
    db: ref.watch(databaseProvider),
    media: ref.watch(mediaLibraryProvider),
    api: () => ref.read(mobileApiProvider),
  ),
);

final identityGroupsRepositoryProvider = Provider<IdentityGroupsRepository>(
  (ref) => IdentityGroupsRepository(
    ref.watch(databaseProvider),
    autoOrganizer: ref.watch(dynamicAutoOrganizerProvider),
  ),
);
final identityGroupsProvider =
    StreamProvider.autoDispose<List<IdentityGroupSummary>>(
      (ref) => ref.watch(identityGroupsRepositoryProvider).watch(),
    );

final mediaOrganizerBridgeProvider = Provider<MediaOrganizerBridge>(
  (ref) => const AndroidMediaOrganizer(),
);

/// The running [ScanEngine], for callbacks of providers the engine itself depends on.
class ScanEngineLink {
  ScanEngine? engine;
}

final scanEngineLinkProvider = Provider<ScanEngineLink>(
  (ref) => ScanEngineLink(),
);

final personMediaOrganizerProvider = Provider<PersonMediaOrganizer>(
  (ref) => PersonMediaOrganizer(
    db: ref.watch(databaseProvider),
    bridge: ref.watch(mediaOrganizerBridgeProvider),
    beforeMove: () async {
      // not ref.read(scanEngineProvider): the engine depends on this organizer (through the result store),
      // and Riverpod refuses that read as a cycle in debug builds - every move then failed with
      // "CircularDependencyError". No engine yet means no scan is running.
      final engine = ref.read(scanEngineLinkProvider).engine;
      if (engine != null) {
        engine.mediaOrganizationActive = true;
        await engine.pauseAndWait();
      }
    },
    afterMove: () {
      ref.read(scanEngineLinkProvider).engine?.mediaOrganizationActive = false;
      ref.read(thumbnailServiceProvider).clear();
      unawaited(
        ref.read(mediaLibraryProvider).clearCache().catchError((Object _) {}),
      );
    },
    rootFolder: () async {
      final bridge = ref.read(mediaOrganizerBridgeProvider);
      return bridge is AndroidMediaOrganizer && await bridge.hasAllFilesAccess()
          ? PersonMediaOrganizer.topRoot
          : PersonMediaOrganizer.dcimRoot;
    },
  ),
);

/// Where organized photos go now (shown on the Organize screen).
final organizeRootProvider = FutureProvider.autoDispose<String>((ref) async {
  final bridge = ref.watch(mediaOrganizerBridgeProvider);
  return bridge is AndroidMediaOrganizer && await bridge.hasAllFilesAccess()
      ? PersonMediaOrganizer.topRoot
      : PersonMediaOrganizer.dcimRoot;
});

final dynamicAutoOrganizerProvider = Provider<DynamicAutoOrganizer>((ref) {
  return DynamicAutoOrganizer(
    db: ref.watch(databaseProvider),
    organizer: ref.watch(personMediaOrganizerProvider),
  );
});

final bodyLinkGuardProvider = Provider<BodyLinkGuard>((ref) {
  return BodyLinkGuard(ref.watch(databaseProvider));
});

final correctionServiceProvider = Provider<CorrectionService>((ref) {
  return CorrectionService(
    db: ref.watch(databaseProvider),
    peopleRepo: ref.watch(peopleRepositoryProvider),
    bodyLinkGuard: ref.watch(bodyLinkGuardProvider),
    autoOrganizer: ref.watch(dynamicAutoOrganizerProvider),
  );
});

final correctionsQueriesProvider = Provider<CorrectionsQueries>((ref) {
  return CorrectionsQueries(ref.watch(databaseProvider));
});

final targetedDetectionServiceProvider = Provider<TargetedDetectionService>((
  ref,
) {
  return TargetedDetectionService(db: ref.watch(databaseProvider));
});
