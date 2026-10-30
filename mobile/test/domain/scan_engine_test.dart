// The photo scan end to end with fakes for the phone's gallery and the PC: queueing, dedupe, grouping
// rounds, resuming after a kill, and what a busy / unreachable / revoked PC does to the scan.

import 'dart:async';
import 'dart:io';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_runner.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/scan/scan_engine.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

class Rig {
  Rig() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_scan_');
    files = FileStore(Directory('${tmp.path}/crops'));
    settings = AppSettings(db);
    repo = LibraryRepository(db);
    store = PhotoResultStore(db: db, files: files, index: index);
    review = ReviewRepository(db, PeopleRepository(db, files, index: index));
    grouping = GroupingRunner(
      db: db,
      api: () => pc,
      settings: settings,
      review: review,
    );
    library.addAlbum(
      const AlbumInfo(id: 'cam', name: 'Camera', count: 3),
      syntheticAssets(3),
    );
  }

  late final AppDatabase db;
  late final Directory tmp;
  late final FileStore files;
  late final AppSettings settings;
  late final LibraryRepository repo;
  late final PhotoResultStore store;
  late final ReviewRepository review;
  late final GroupingRunner grouping;
  final index = InMemoryEmbeddingIndex();
  final library = FakeMediaLibrary();
  final api = FakeMobileApi();
  final keepAlive = RecordingKeepAlive();
  final delays = <Duration>[];
  FakeMobileApi? pc;
  Future<void> Function()? onDelay;
  var _face = 0;

  /// Each photo shows one new person.
  void everyPhotoHasANewFace() {
    api.analyzeHandler = (bytes, options) async => analysis(
      faces: [faceJson(unitVec(1000 + _face++))],
      modelId: 'buffalo_l@1',
    );
  }

  ScanEngine engine({ScanPolicy policy = const ScanPolicy()}) => ScanEngine(
    library: repo,
    media: library,
    api: () => pc,
    settings: settings,
    store: store,
    grouping: grouping,
    keepAlive: keepAlive,
    policy: policy,
    delay: (d) async {
      delays.add(d);
      await onDelay?.call();
    },
  );

  Future<List<MediaRow>> media() =>
      (db.select(db.media)..orderBy([(m) => OrderingTerm.asc(m.id)])).get();
  Future<int> faces() async => (await db.select(db.faces).get()).length;

  Future<void> choose([List<String> albums = const ['cam']]) =>
      settings.setAlbumIds(albums);

  Future<void> dispose() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  }
}

void main() {
  late Rig rig;
  setUp(() {
    rig = Rig();
    rig.pc = rig.api;
  });
  tearDown(() => rig.dispose());

  test(
    'prepares only the next photo while the current photo is being analysed',
    () async {
      await rig.choose();
      final entered = Completer<void>(), release = Completer<void>();
      var call = 0;
      rig.api.analyzeHandler = (bytes, options) async {
        if (call++ == 0) {
          entered.complete();
          await release.future;
        }
        return analysis(faces: [], modelId: 'buffalo_l@1');
      };
      final running = rig.engine().start();
      await entered.future;
      for (
        var attempt = 0;
        attempt < 100 && !rig.library.reads.contains('asset-2');
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(rig.library.reads, ['asset-1', 'asset-2']);
      final current = await rig.media();
      expect(current.map((m) => m.scanStatus), [
        'scanning',
        'pending',
        'pending',
      ]);
      release.complete();
      await running;
      expect(rig.library.reads, ['asset-1', 'asset-2', 'asset-3']);
    },
  );

  test(
    'preview follows the claimed photo and clears when the queue finishes',
    () async {
      await rig.choose();
      final engine = rig.engine();
      final seen = <String>[];
      rig.api.analyzeHandler = (bytes, options) async {
        expect(engine.progress.currentKind, 'photo');
        expect(engine.progress.previewBytes, same(bytes));
        seen.add(engine.progress.currentAssetId!);
        return analysis(faces: [], modelId: 'buffalo_l@1');
      };
      await engine.start();
      expect(seen, ['asset-1', 'asset-2', 'asset-3']);
      expect(engine.progress.currentAssetId, isNull);
      expect(engine.progress.previewBytes, isNull);
    },
  );

  test(
    'network recovery cannot restart a scan while backup maintenance owns the library',
    () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      rig.api.analyzeError = ApiException.network('offline');
      final engine = rig.engine(policy: const ScanPolicy(offlineRetries: 0));
      await engine.start();
      await engine.pauseAndWait();
      rig.api.analyzeError = null;
      await engine.resumeAfterConnectionRestored();
      expect(engine.progress.phase, ScanPhase.paused);
      expect(await rig.faces(), 0);
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.completed);
    },
  );

  test(
    'connection recovery resumes an offline pause, preserving a user pause',
    () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      rig.api.analyzeError = ApiException.network('network changed');
      final engine = rig.engine(policy: const ScanPolicy(offlineRetries: 0));
      await engine.start();
      expect(engine.progress.pauseReason, PauseReason.offline);
      rig.api.analyzeError = null;
      await engine.resumeAfterConnectionRestored();
      expect(engine.progress.phase, ScanPhase.completed);
      expect(await rig.faces(), 3);
      final entered = Completer<void>(), release = Completer<void>();
      rig.library.setAlbum('cam', syntheticAssets(6));
      rig.api.analyzeHandler = (bytes, options) async {
        entered.complete();
        await release.future;
        return analysis(
          faces: [faceJson(unitVec(9000))],
          modelId: 'buffalo_l@1',
        );
      };
      final scan = engine.start();
      await entered.future;
      engine.pause();
      release.complete();
      await scan;
      expect(engine.progress.pauseReason, PauseReason.user);
      await engine.resumeAfterConnectionRestored();
      expect(engine.progress.pauseReason, PauseReason.user);
    },
  );

  test(
    'maintenance waits for the in-flight photo to commit before returning',
    () async {
      await rig.choose();
      final entered = Completer<void>();
      final release = Completer<void>();
      rig.api.analyzeHandler = (bytes, options) async {
        entered.complete();
        await release.future;
        return analysis(
          faces: [faceJson(unitVec(1000))],
          modelId: 'buffalo_l@1',
        );
      };
      final engine = rig.engine();
      final scan = engine.start();
      await entered.future;
      var settled = false;
      final maintenance = engine.pauseAndWait().then((_) => settled = true);
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      release.complete();
      await maintenance;
      await scan;
      expect(engine.isRunning, isFalse);
      expect(await rig.faces(), 1);
      expect((await rig.media()).map((m) => m.scanStatus), [
        'done',
        'pending',
        'pending',
      ]);
      expect(engine.progress.phase, ScanPhase.paused);
    },
  );

  test(
    'a scan lists the chosen albums, analyses every photo, groups and finishes',
    () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      final engine = rig.engine();
      final phases = <ScanPhase>[];
      final sub = engine.stream.listen((p) => phases.add(p.phase));
      addTearDown(sub.cancel);

      await engine.start();

      final media = await rig.media();
      expect(media.map((m) => m.scanStatus), ['done', 'done', 'done']);
      expect(await rig.faces(), 3);
      expect(
        phases,
        containsAllInOrder([
          ScanPhase.preparing,
          ScanPhase.running,
          ScanPhase.completed,
        ]),
      );
      final p = engine.progress;
      expect(
        (p.phase, p.total, p.done, p.failed, p.facesFound),
        (ScanPhase.completed, 3, 3, 0, 3),
      );
      expect(
        await rig.settings.load().then((s) => s.scanActive),
        isFalse,
        reason: 'a finished scan is not resumed at start-up',
      );
      expect(
        (await rig.settings.load()).modelId,
        'buffalo_l@1',
        reason: 'the library remembers its embedding model',
      );
      expect(rig.keepAlive.events.first, 'start');
      expect(rig.keepAlive.events.last, 'stop');
      expect(
        rig.library.cacheClears,
        greaterThan(0),
        reason: 'cached copies of the originals are dropped',
      );
      expect(
        rig.api.groupingCalls.where((c) => c.mode == 'review'),
        isNotEmpty,
        reason: 'the scan ends with a grouping run',
      );

      // what was asked of the PC
      expect(
        rig.api.analyzeOptions.first.modelId,
        isNull,
        reason: 'the first photo decides the model',
      );
      expect(
        rig.api.analyzeOptions.last.modelId,
        'buffalo_l@1',
        reason: 'every later photo insists on it',
      );
      expect(
        rig.api.analyzeOptions.every(
          (o) => o.detectBodies && o.minQuality == 0.4,
        ),
        isTrue,
      );

      engine.dismiss();
      expect(
        engine.progress.phase,
        ScanPhase.idle,
        reason: 'the finished summary can be closed',
      );
    },
  );

  test(
    'the quality gate, body option and picture size from Settings reach the PC and the photo reader',
    () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      await rig.settings.setQualityGate(0.6);
      await rig.settings.setScanBodies(false);
      await rig.settings.setMaxSide(1600);
      await rig.engine().start();
      expect(
        rig.api.analyzeOptions.every(
          (o) => !o.detectBodies && o.minQuality == 0.6,
        ),
        isTrue,
      );
      expect(rig.library.maxSides, [1600, 1600, 1600]);
    },
  );

  test('a second scan of an unchanged library does no work', () async {
    await rig.choose();
    rig.everyPhotoHasANewFace();
    await rig.engine().start();
    final calls = rig.api.analyzeCalls.length;
    await rig.engine().start();
    expect(
      rig.api.analyzeCalls.length,
      calls,
      reason: 'already scanned and unchanged: skipped',
    );
    expect(await rig.faces(), 3);
  });

  test('a new photo in the album is the only one scanned next time', () async {
    await rig.choose();
    rig.everyPhotoHasANewFace();
    await rig.engine().start();
    rig.library.setAlbum('cam', syntheticAssets(4));
    await rig.engine().start();
    expect(rig.api.analyzeCalls.length, 4);
    expect(await rig.faces(), 4);
  });

  group('killed and resumed', () {
    test(
      'pausing stops after the current photo; a new engine (the app after a restart) finishes the rest exactly once',
      () async {
        rig.library.setAlbum('cam', syntheticAssets(5));
        await rig.choose();
        rig.everyPhotoHasANewFace();
        final first = rig.engine();
        var calls = 0;
        final inner = rig.api.analyzeHandler!;
        rig.api.analyzeHandler = (bytes, options) async {
          if (++calls == 2) {
            first
                .pause(); // the user taps Pause while photo 2 is being analysed
          }
          return inner(bytes, options);
        };
        await first.start();

        expect(first.progress.phase, ScanPhase.paused);
        expect(first.progress.pauseReason, PauseReason.user);
        var statuses = (await rig.media()).map((m) => m.scanStatus).toList();
        expect(statuses, [
          'done',
          'done',
          'pending',
          'pending',
          'pending',
        ], reason: 'photo 2 was finished, not abandoned');
        expect(
          (await rig.settings.load()).scanActive,
          isFalse,
          reason: 'a deliberate pause is not auto-resumed',
        );

        // the app is killed while a photo is half way: it stays "scanning" and the flag says a scan was on
        await (rig.db.update(rig.db.media)
              ..where((m) => m.assetId.equals('asset-3')))
            .write(const MediaCompanion(scanStatus: Value('scanning')));
        await rig.settings.setScanActive(true);

        final second = rig.engine();
        await second.resumeIfInterrupted();
        statuses = (await rig.media()).map((m) => m.scanStatus).toList();
        expect(statuses, everyElement('done'));
        expect(
          await rig.faces(),
          5,
          reason: 'no photo was scanned twice, no face duplicated',
        );
        expect(
          rig.library.reads,
          ['asset-1', 'asset-2', 'asset-3', 'asset-4', 'asset-5'],
          reason: 'asset-3 was read once: it never got an answer before',
        );
        expect(second.progress.phase, ScanPhase.completed);
        expect(
          second.progress.total,
          3,
          reason: "the second run's progress counts only what was left",
        );
      },
    );

    test(
      'resumeIfInterrupted does nothing unless a scan was running',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        await rig.engine().resumeIfInterrupted();
        expect(rig.api.analyzeCalls, isEmpty);
        expect(
          (await rig.media()),
          isEmpty,
          reason: 'and it did not even list the albums',
        );
      },
    );

    test(
      'resuming does not re-list the albums (photos taken meanwhile wait for the next scan)',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        await rig.engine().start();
        rig.library.setAlbum('cam', syntheticAssets(6));
        await rig.settings.setScanActive(true);
        await rig.engine().resumeIfInterrupted();
        expect((await rig.media()).length, 3);
      },
    );
  });

  group('a busy or unreachable PC', () {
    test(
      'resource pressure pauses with the photo pending and explains why',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'resource_pressure',
              message: 'Free system RAM is below 1024 MiB.',
              retryable: true,
              statusCode: 503,
              retryAfter: Duration(seconds: 15),
            );
        final engine = rig.engine(policy: const ScanPolicy(busyRetries: 1));
        await engine.start();
        expect(engine.progress.phase, ScanPhase.paused);
        expect(engine.progress.pauseReason, PauseReason.pcBusy);
        expect(engine.progress.message, contains('RAM'));
        expect(
          (await rig.media()).map((m) => m.scanStatus),
          everyElement('pending'),
        );
        expect(
          rig.delays.fold<Duration>(Duration.zero, (sum, delay) => sum + delay),
          const Duration(seconds: 15),
        );
      },
    );

    test(
      'a busy GPU is waited out with the PC\'s Retry-After and the photo is not given up on',
      () async {
        await rig.choose();
        rig.library.setAlbum('cam', syntheticAssets(2));
        rig.everyPhotoHasANewFace();
        final inner = rig.api.analyzeHandler!;
        var busy = 2;
        rig.api.analyzeHandler = (bytes, options) async {
          if (busy-- > 0) {
            throw const ApiException(
              code: 'gpu_busy',
              message: 'A train_lora job is running on the GPU.',
              retryable: true,
              statusCode: 503,
              retryAfter: Duration(seconds: 15),
            );
          }
          return inner(bytes, options);
        };
        final engine = rig.engine();
        final phases = <ScanPhase>[];
        final sub = engine.stream.listen((p) => phases.add(p.phase));
        addTearDown(sub.cancel);

        await engine.start();

        expect(engine.progress.phase, ScanPhase.completed);
        expect(
          phases,
          contains(ScanPhase.waiting),
          reason: 'the progress card shows "waiting for your PC"',
        );
        final waited = rig.delays.fold<Duration>(
          Duration.zero,
          (a, b) => a + b,
        );
        expect(
          waited,
          const Duration(seconds: 30),
          reason: 'two busy answers x Retry-After 15 s, slept in short slices',
        );
        final media = await rig.media();
        expect(media.map((m) => m.scanStatus), ['done', 'done']);
        expect(
          media.first.scanAttempts,
          1,
          reason: 'waiting is not an attempt',
        );
        expect(
          rig.api.analyzeCalls.length,
          4,
          reason: '2 refused + 2 answered',
        );
      },
    );

    test(
      'a GPU that stays busy pauses the scan by itself, the photo goes back to the queue, nothing is lost',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'gpu_busy',
              message: 'busy',
              retryable: true,
              statusCode: 503,
              retryAfter: Duration(seconds: 15),
            );
        final engine = rig.engine(policy: const ScanPolicy(busyRetries: 3));
        await engine.start();

        expect(
          (engine.progress.phase, engine.progress.pauseReason),
          (ScanPhase.paused, PauseReason.pcBusy),
        );
        final media = await rig.media();
        expect(media.map((m) => m.scanStatus), [
          'pending',
          'pending',
          'pending',
        ]);
        expect(media.first.scanAttempts, 0);
        expect(
          rig.api.analyzeCalls.length,
          4,
          reason: 'the first try + 3 retries',
        );
        expect((await rig.settings.load()).scanActive, isFalse);
        expect(
          rig.keepAlive.events.last,
          'stop',
          reason: 'the foreground service is released',
        );

        // later the GPU is free: Resume continues exactly there
        rig.everyPhotoHasANewFace();
        await engine.start(enumerate: false);
        expect(
          (await rig.media()).map((m) => m.scanStatus),
          everyElement('done'),
        );
      },
    );

    test(
      'an unreachable PC is retried with growing waits, then the scan pauses',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw ApiException.network('refused');
        final engine = rig.engine(policy: const ScanPolicy(offlineRetries: 3));
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.offline);
        final waited = rig.delays.fold<Duration>(
          Duration.zero,
          (a, b) => a + b,
        );
        expect(
          waited,
          const Duration(seconds: 21),
          reason: '3 s + 6 s + 12 s, doubling each time, slept in short slices',
        );
        expect(
          (await rig.media()).every((m) => m.scanStatus == 'pending'),
          isTrue,
        );
      },
    );

    test('the PC coming back mid-retry carries on without pausing', () async {
      await rig.choose();
      rig.library.setAlbum('cam', syntheticAssets(1));
      rig.everyPhotoHasANewFace();
      final inner = rig.api.analyzeHandler!;
      var down = 2;
      rig.api.analyzeHandler = (bytes, options) async {
        if (down-- > 0) throw ApiException.timeout();
        return inner(bytes, options);
      };
      final engine = rig.engine();
      await engine.start();
      expect(engine.progress.phase, ScanPhase.completed);
    });

    test(
      'Pause tapped while waiting for a busy PC takes effect at once',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'gpu_busy',
              message: 'busy',
              retryable: true,
              statusCode: 503,
              retryAfter: Duration(seconds: 15),
            );
        final engine = rig.engine();
        rig.onDelay = () async => engine.pause();
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.user);
        expect(
          rig.delays.length,
          1,
          reason: 'it did not sleep out the rest of the 15 s',
        );
        expect((await rig.media()).first.scanStatus, 'pending');
      },
    );

    test(
      'a PC that no longer knows this phone pauses the scan with "pair again"',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'unauthorized',
              message: 'Missing or invalid device token.',
              statusCode: 401,
            );
        final engine = rig.engine();
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.revoked);
        expect((await rig.media()).first.scanStatus, 'pending');
      },
    );

    test(
      'a PC that switched face-recognition models never gets its vectors mixed into this library',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        final inner = rig.api.analyzeHandler!;
        var calls = 0;
        rig.api.analyzeHandler = (bytes, options) async {
          if (++calls == 2) {
            return analysis(
              faces: [faceJson(unitVec(5))],
              modelId: 'arcface_new@2',
            );
          }
          return inner(bytes, options);
        };
        final engine = rig.engine();
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.modelMismatch);
        expect(await rig.faces(), 1, reason: 'the odd photo stored nothing');
        expect((await rig.media()).map((m) => m.scanStatus), [
          'done',
          'pending',
          'pending',
        ]);
      },
    );

    test(
      'the PC refusing the model with 409 model_mismatch pauses too',
      () async {
        await rig.choose();
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'model_mismatch',
              message: 'This server embeds with buffalo_l@2, not buffalo_l@1.',
              statusCode: 409,
            );
        final engine = rig.engine();
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.modelMismatch);
      },
    );
  });

  group('photos that cannot be scanned', () {
    test(
      'an unreadable photo is marked failed with a reason, the scan goes on',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        rig.library.unreadable.add('asset-2');
        final engine = rig.engine();
        await engine.start();
        final media = await rig.media();
        expect(media.map((m) => m.scanStatus), ['done', 'failed', 'done']);
        expect(media[1].scanError, contains('could not be read'));
        expect((engine.progress.done, engine.progress.failed), (2, 1));
      },
    );

    test(
      "a photo the PC refuses for good (bad image) is failed, not retried forever",
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        final inner = rig.api.analyzeHandler!;
        rig.api.analyzeHandler = (bytes, options) async {
          if (rig.api.analyzeCalls.length == 2) {
            throw const ApiException(
              code: 'bad_image',
              message: 'The file is not a readable image.',
              statusCode: 400,
            );
          }
          return inner(bytes, options);
        };
        await rig.engine().start();
        final media = await rig.media();
        expect(media.map((m) => m.scanStatus), ['done', 'failed', 'done']);
        expect(media[1].scanError, 'The file is not a readable image.');
      },
    );

    test(
      'a server hiccup is retried twice, then the photo is failed',
      () async {
        await rig.choose();
        rig.library.setAlbum('cam', syntheticAssets(1));
        rig.api.analyzeHandler = (bytes, options) async =>
            throw const ApiException(
              code: 'internal',
              message: 'Image analysis failed on the server.',
              retryable: true,
              statusCode: 500,
            );
        await rig.engine().start();
        expect(rig.api.analyzeCalls.length, 3);
        expect((await rig.media()).single.scanStatus, 'failed');
      },
    );

    test('failed photos get another chance on the next scan', () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      rig.library.unreadable.add('asset-2');
      await rig.engine().start();
      rig.library.unreadable.clear();
      await rig.engine().start();
      expect((await rig.media()).map((m) => m.scanStatus), [
        'done',
        'done',
        'done',
      ]);
    });
  });

  group('starting', () {
    test('without a paired PC the scan does not start', () async {
      await rig.choose();
      rig.pc = null;
      final engine = rig.engine();
      await engine.start();
      expect(engine.progress.pauseReason, PauseReason.notPaired);
      expect(rig.keepAlive.events, isEmpty);
    });

    test(
      'without photo permission or albums it says what is missing',
      () async {
        rig.library.access = false;
        final engine = rig.engine();
        await engine.start();
        expect(engine.progress.pauseReason, PauseReason.noAccess);

        rig.library.access = true;
        await engine.start(); // no album chosen yet
        expect(engine.progress.pauseReason, PauseReason.noAlbums);
        expect(rig.keepAlive.events.last, 'stop');
      },
    );

    test(
      'photos waiting from an earlier scan but outside the albums chosen now are left out',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        final oldId = await seedMedia(
          rig.db,
          asset: 'from-another-album',
          status: 'pending',
        );
        await rig.engine().start();
        final old = await rig.repo.mediaById(oldId);
        expect(old!.scanStatus, 'skipped');
        expect(rig.library.reads, isNot(contains('from-another-album')));
      },
    );

    test('a second start while one is running does nothing', () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      final engine = rig.engine();
      final a = engine.start();
      final b = engine.start();
      await Future.wait([a, b]);
      expect(rig.api.analyzeCalls.length, 3);
    });
  });

  group('grouping while scanning', () {
    test(
      'faces are sorted into people every so often, not only at the end',
      () async {
        rig.library.setAlbum('cam', syntheticAssets(101));
        await rig.choose();
        rig.everyPhotoHasANewFace();
        await rig.engine().start();
        final reviews = rig.api.groupingCalls
            .where((c) => c.mode == 'review')
            .length;
        expect(
          reviews,
          1,
          reason:
              'review is deferred to the end; the in-scan pass only matches/clusters',
        );
        expect(
          rig.api.groupingCalls
              .where((c) => c.mode == 'apply' && c.stages.contains('match'))
              .length,
          greaterThanOrEqualTo(2),
        );
        expect(await rig.faces(), 101);
      },
    );

    test('the PC being unable to group does not fail the scan', () async {
      await rig.choose();
      rig.everyPhotoHasANewFace();
      rig.api.groupingError = ApiException.network('refused');
      final engine = rig.engine();
      await engine.start();
      expect(engine.progress.phase, ScanPhase.completed);
      expect((await rig.media()).every((m) => m.scanStatus == 'done'), isTrue);
    });
  });

  test(
    'the scan progress knows how many photos, faces and bodies it found',
    () async {
      await rig.choose();
      rig.library.setAlbum('cam', syntheticAssets(2));
      var n = 0;
      rig.api.analyzeHandler = (bytes, options) async => analysis(
        faces: [faceJson(unitVec(2000 + n++))],
        bodies: [bodyJson(appearance: outfit(n))],
        pairs: [(0, 0)],
      );
      final engine = rig.engine();
      await engine.start();
      expect(
        (
          engine.progress.done,
          engine.progress.facesFound,
          engine.progress.bodiesFound,
        ),
        (2, 2, 2),
      );
    },
  );
}
