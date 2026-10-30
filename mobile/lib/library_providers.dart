import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/files/file_store.dart';
import 'data/index/embedding_index.dart';
import 'data/index/index_loader.dart';
import 'data/media/media_library.dart';
import 'data/media/thumbnail_service.dart';
import 'data/platform/foreground_keep_alive.dart';
import 'data/platform/backup_crypto.dart';
import 'data/repositories/app_settings.dart';
import 'data/repositories/library_repository.dart';
import 'data/repositories/media_queries.dart';
import 'data/repositories/people_repository.dart';
import 'data/repositories/character_repository.dart';
import 'data/repositories/review_repository.dart';
import 'domain/backup/backup_service.dart';
import 'domain/grouping/grouping_runner.dart';
import 'domain/scan/photo_result_store.dart';
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

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => LibraryRepository(ref.watch(databaseProvider)),
);

final mediaQueriesProvider = Provider<MediaQueries>(
  (ref) => MediaQueries(ref.watch(databaseProvider)),
);

final peopleRepositoryProvider = Provider<PeopleRepository>(
  (ref) => PeopleRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
    index: ref.watch(embeddingIndexProvider),
  ),
);

final characterRepositoryProvider = Provider<CharacterRepository>(
  (ref) => CharacterRepository(
    ref.watch(databaseProvider),
    ref.watch(fileStoreProvider),
  ),
);
final charactersProvider = StreamProvider.autoDispose<List<CharacterSummary>>(
  (ref) => ref.watch(characterRepositoryProvider).watch(),
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

final scanCountsProvider = StreamProvider.autoDispose<ScanCounts>(
  (ref) => ref.watch(libraryRepositoryProvider).watchScanCounts(),
);

// ---- grouping + scan ---------------------------------------------------------------------

final groupingRunnerProvider = Provider<GroupingRunner>(
  (ref) => GroupingRunner(
    db: ref.watch(databaseProvider),
    api: () => ref.read(mobileApiProvider),
    settings: ref.watch(appSettingsProvider),
    review: ref.watch(reviewRepositoryProvider),
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
  ),
);

final scanEngineProvider = Provider<ScanEngine>((ref) {
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
    ),
    describeVideo: (stage, progress) => switch (stage) {
      'prepare' => _en.videoPreparing((progress * 100).round()),
      'upload' => _en.videoUploading((progress * 100).round()),
      'analyze' => _en.videoAnalyzing((progress * 100).round()),
      'download' => _en.videoDownloading,
      _ => _en.videoImporting,
    },
    keepAlive: ref.watch(scanKeepAliveProvider),
    keepAliveTitle: _en.scanNotificationTitle,
    describe: (p) =>
        _en.scanNotificationText(p.done + p.failed, p.total, p.facesFound),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Live progress of the scan (idle until one starts).
final scanProgressProvider = StreamProvider<ScanProgress>((ref) async* {
  final engine = ref.watch(scanEngineProvider);
  yield engine.progress;
  yield* engine.stream;
});

// ---- backup ----------------------------------------------------------------------------------

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    db: ref.watch(databaseProvider),
    files: ref.watch(fileStoreProvider),
    settings: ref.watch(appSettingsProvider),
  ),
);
