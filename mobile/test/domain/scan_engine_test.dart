// The photo scan end to end with fakes for the phone's gallery and the PC: queueing, dedupe, grouping
// rounds, resuming after a kill, and what a busy / unreachable / revoked PC does to the scan.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
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
import 'package:drift/drift.dart' show OrderingTerm, Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
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
    grouping = GroupingRunner(db: db, api: () => pc, review: review);
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

  ScanEngine engine({
    ScanPolicy policy = const ScanPolicy(),
    Future<void> Function()? afterRun,
    ScanKeepAlive? service,
  }) => ScanEngine(
    library: repo,
    media: library,
    api: () => pc,
    settings: settings,
    store: store,
    grouping: grouping,
    keepAlive: service ?? keepAlive,
    afterRun: afterRun,
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

class _HeldStopService extends RecordingKeepAlive {
  final stopping = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> stop() async {
    if (!stopping.isCompleted) {
      stopping.complete();
      await release.future;
    }
    await super.stop();
  }
}

class _HeldCapabilitiesApi extends FakeMobileApi {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Capabilities> capabilities() async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.capabilities();
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
    'quick faces scope includes old and newly discovered media and retries only failures',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['face_only_scan'] = true;
      (caps['engines'] as Map)['sensitive_detection'] = true;
      (caps['engines'] as Map)['body_embeddings'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      await rig.choose(['cam']);
      final old = await seedMedia(rig.db, asset: 'legacy');
      final existing = await seedMedia(rig.db);
      rig.library.unreadable.add('legacy');
      rig.api.analyzeResult = analysis();
      final refresh = rig.repo.faceRefresh;
      await refresh.request();
      final engine = rig.engine();
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.paused);
      expect(engine.progress.refreshingFaces, isTrue);
      expect(engine.progress.total, 4);
      expect(engine.progress.done, 3);
      expect(engine.progress.failed, 1);
      expect(rig.api.analyzeCalls, hasLength(3));
      expect(await refresh.checkedAt(existing), isNotNull);
      expect(await refresh.checkedAt(old), isNull);
      expect(await refresh.requested(), isTrue);
      expect((await rig.repo.mediaById(old))!.scanStatus, 'done');
      expect((await rig.repo.mediaByAssetId('asset-2'))!.scanStatus, 'skipped');

      rig.library.unreadable.clear();
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.done, 4);
      expect(rig.api.analyzeCalls, hasLength(4));
      expect(rig.api.analyzeOptions.every((o) => o.facesOnly && o.detectCharacters &&
          !o.detectBodies && !o.returnSensitive && !o.returnBodyEmbeddings &&
          !o.returnOutlines), isTrue);
      expect(rig.api.groupingCalls, isEmpty);
      expect(await refresh.checkedAt(old), isNotNull);
      expect(await refresh.requested(), isFalse);
      expect((await rig.settings.load()).albumIds, ['cam']);
      await engine.dispose();
    },
  );

  test(
    'identity rescan scans only its saved files, preserves sources and resumes after offline',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      await rig.choose(['cam']);
      final p = await seedPerson(rig.db, name: 'Sara');
      final chosen = await seedMedia(rig.db, asset: 'asset-1');
      final unrelated = await seedMedia(
        rig.db,
        asset: 'asset-2',
        status: 'pending',
      );
      await seedFace(rig.db, mediaId: chosen, personId: p);
      rig.api.analyzeError = ApiException.network('offline');
      final engine = rig.engine(policy: const ScanPolicy(offlineRetries: 0));
      await engine.start(repairPersonId: p);
      expect(engine.progress.phase, ScanPhase.paused);
      expect(await rig.repo.identityRescan.personId(), p);
      rig.api.analyzeError = null;
      rig.api.analyzeResult = analysis(faces: []);
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(rig.api.analyzeCalls, hasLength(2));
      expect(
        rig.api.analyzeOptions.every(
          (o) => o.detectCharacters && o.detectBodies,
        ),
        isTrue,
      );
      expect((await rig.repo.mediaById(unrelated))!.scanStatus, 'pending');
      expect((await rig.settings.load()).albumIds, ['cam']);
      expect(await rig.repo.identityRescan.personId(), isNull);
      await engine.dispose();
    },
  );

  test(
    'library repair corrects kinds in both directions and retries grouping without re-scanning',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      await rig.choose(['cam']);
      await rig.settings.setScanBodies(false);
      final human = await seedPerson(rig.db, name: 'Human');
      final character = await rig.db
          .into(rig.db.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Character'),
              kind: const Value('character'),
              createdAt: 1,
            ),
          );
      final humanPhoto = await seedMedia(rig.db, asset: 'asset-1');
      final drawnPhoto = await seedMedia(rig.db, asset: 'asset-2');
      final unrelated = await seedMedia(
        rig.db,
        asset: 'asset-3',
        status: 'pending',
      );
      final wrongCharacter = await seedFace(
        rig.db,
        personId: character,
        mediaId: humanPhoto,
        x: .1,
        y: .125,
        w: .2,
        h: .3,
      );
      await (rig.db.update(
        rig.db.faces,
      )..where((f) => f.id.equals(wrongCharacter))).write(
        FacesCompanion(
          kind: const Value('character'),
          modelId: const Value(characterEmbeddingModelId),
          embedding: Value(
            embeddingToBlob(Float32List(characterEmbeddingDim)..[0] = 1),
          ),
        ),
      );
      // This file belongs to both profiles and must be analyzed only once.
      final bystander = await seedFace(
        rig.db,
        personId: human,
        mediaId: humanPhoto,
      );
      await PeopleRepository(
        rig.db,
        rig.files,
      ).confirmFaces([bystander], human);
      final drawnJson = fixture('AnalyzeImageResponse.character_face_body');
      final drawn = (drawnJson['characters'] as List).single as Map;
      drawn['score'] = .95;
      final drawnFace = drawn['face'] as Map;
      drawnFace['score'] = .95;
      final box = drawnFace['bbox'] as Map;
      final width = drawnJson['image_w'] as num,
          height = drawnJson['image_h'] as num;
      final wrongHuman = await seedFace(
        rig.db,
        personId: human,
        mediaId: drawnPhoto,
        x: (box['x'] as num) / width,
        y: (box['y'] as num) / height,
        w: (box['w'] as num) / width,
        h: (box['h'] as num) / height,
      );
      rig.library.bytes['asset-1'] = Uint8List.fromList([1]);
      rig.library.bytes['asset-2'] = Uint8List.fromList([2]);
      rig.api.analyzeHandler = (bytes, options) async => bytes.first == 1
          ? analysis(faces: [faceJson(unitVec(50))])
          : AnalyzeImageResponse.fromJson(drawnJson);
      rig.api.groupingError = ApiException.network('offline');
      await rig.repo.identityRescan.queueLibrary();
      final engine = rig.engine();
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.paused);
      expect(await rig.repo.identityRescan.libraryActive(), isTrue);
      expect(engine.progress.done, 2);
      expect(rig.api.analyzeOptions, hasLength(2));
      expect(
        rig.api.analyzeOptions.every(
          (o) => o.detectBodies && o.detectCharacters,
        ),
        isTrue,
      );
      final faces = await rig.db.select(rig.db.faces).get();
      expect(faces.map((f) => f.id), isNot(contains(wrongHuman)));
      expect(faces.map((f) => f.id), isNot(contains(wrongCharacter)));
      expect(faces.singleWhere((f) => f.id == bystander).personId, human);
      expect(
        faces.singleWhere((f) => f.mediaId == drawnPhoto).kind,
        'character',
      );
      expect((await rig.repo.mediaById(unrelated))!.scanStatus, 'pending');
      expect((await rig.settings.load()).albumIds, ['cam']);
      await engine.dispose();

      rig.api.groupingError = null;
      final restarted = rig.engine();
      await restarted.start(enumerate: false);
      expect(restarted.progress.phase, ScanPhase.completed);
      expect(restarted.progress.done, 2);
      expect(restarted.progress.total, 2);
      expect(rig.api.analyzeCalls, hasLength(2));
      expect(await rig.repo.identityRescan.libraryActive(), isFalse);
      expect((await rig.repo.mediaById(unrelated))!.scanStatus, 'pending');
      await restarted.dispose();
    },
  );

  test(
    're-scans added during analysis drain in order without restarting the current identity',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      final ids = <int>[];
      for (var i = 1; i <= 3; i++) {
        final p = await seedPerson(rig.db, name: 'Identity $i');
        final m = await seedMedia(rig.db, asset: 'asset-$i');
        await seedFace(rig.db, mediaId: m, personId: p, seed: i);
        ids.add(p);
      }
      final unrelated = await seedMedia(
        rig.db,
        asset: 'unrelated',
        status: 'pending',
      );
      final entered = Completer<void>(), release = Completer<void>();
      final scanned = <int?>[];
      final grouped = <int?>[];
      rig.api.analyzeHandler = (bytes, options) async {
        scanned.add(await rig.repo.identityRescan.personId());
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return analysis(faces: []);
      };
      rig.api.groupingHandler = (request) async {
        final id = await rig.repo.identityRescan.personId();
        if (grouped.isEmpty || grouped.last != id) grouped.add(id);
        return GroupingPlanResponse(mode: request.mode);
      };
      final engine = rig.engine();
      final running = engine.start(repairPersonId: ids.first);
      await entered.future;
      try {
        await engine.queueIdentityRescan(ids[1]);
        await engine.start(repairPersonId: ids[2]);
        await engine.queueIdentityRescan(ids.first);
        expect(await rig.repo.identityRescan.watchQueuedCount().first, 2);
        expect(rig.api.analyzeCalls, hasLength(1));
        expect(engine.progress.phase, ScanPhase.running);
      } finally {
        release.complete();
        await running;
      }
      expect(scanned, ids);
      expect(grouped, ids);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(await rig.repo.identityRescan.hasQueued(), isFalse);
      expect((await rig.repo.mediaById(unrelated))!.scanStatus, 'pending');
      expect(rig.keepAlive.events.where((e) => e == 'start'), hasLength(1));
      expect(rig.keepAlive.events.where((e) => e == 'stop'), hasLength(1));
      await engine.dispose();
    },
  );

  test(
    'a re-scan added during ordinary scanning runs after that scan',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      await rig.choose();
      final p = await seedPerson(rig.db);
      final m = await seedMedia(rig.db, asset: 'asset-1');
      await seedFace(rig.db, mediaId: m, personId: p);
      await seedMedia(rig.db, asset: 'asset-2', status: 'pending');
      final entered = Completer<void>(), release = Completer<void>();
      rig.api.analyzeHandler = (bytes, options) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return analysis(faces: []);
      };
      final engine = rig.engine();
      final running = engine.start(enumerate: false);
      await entered.future;
      try {
        await engine.queueIdentityRescan(p);
        expect(await rig.repo.identityRescan.personId(), isNull);
        expect(await rig.repo.identityRescan.hasQueued(), isTrue);
      } finally {
        release.complete();
        await running;
      }
      expect(
        rig.api.analyzeCalls,
        hasLength(2),
      ); // ordinary file, then saved scope
      expect(await rig.repo.identityRescan.hasQueued(), isFalse);
      expect(await rig.repo.identityRescan.personId(), isNull);
      await engine.dispose();
    },
  );

  test('pause retains waiting identities and resume drains them', () async {
    final caps = fixture('Capabilities.idle');
    (caps['engines'] as Map)['character_library_repair'] = true;
    rig.api.capabilities_ = Capabilities.fromJson(caps);
    final first = await seedPerson(rig.db);
    final second = await seedPerson(rig.db);
    final m1 = await seedMedia(rig.db);
    final m2 = await seedMedia(rig.db, asset: 'asset-2');
    await seedFace(rig.db, mediaId: m1, personId: first);
    await seedFace(rig.db, mediaId: m2, personId: second);
    final entered = Completer<void>(), release = Completer<void>();
    rig.api.analyzeHandler = (bytes, options) async {
      entered.complete();
      await release.future;
      return analysis(faces: []);
    };
    final engine = rig.engine();
    final running = engine.start(repairPersonId: first);
    await entered.future;
    await engine.queueIdentityRescan(second);
    await engine.pauseAndWait();
    release.complete();
    await running;
    expect(engine.progress.phase, ScanPhase.paused);
    expect(await rig.repo.identityRescan.personId(), first);
    expect(await rig.repo.identityRescan.hasQueued(), isTrue);
    expect((await rig.settings.load()).scanActive, isFalse);
    rig.api.analyzeHandler = null;
    rig.api.analyzeResult = analysis(faces: []);
    await engine.start(enumerate: false);
    expect(engine.progress.phase, ScanPhase.completed);
    expect(await rig.repo.identityRescan.hasQueued(), isFalse);
    expect((await rig.repo.mediaById(m2))!.scanStatus, 'done');
    await engine.dispose();
  });

  test(
    'a request during service shutdown starts after the old run settles',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      final first = await seedPerson(rig.db);
      final second = await seedPerson(rig.db);
      final m1 = await seedMedia(rig.db);
      final m2 = await seedMedia(rig.db, asset: 'asset-2');
      await seedFace(rig.db, mediaId: m1, personId: first);
      await seedFace(rig.db, mediaId: m2, personId: second);
      rig.api.analyzeResult = analysis(faces: []);
      final service = _HeldStopService();
      final engine = rig.engine(service: service);
      final running = engine.start(repairPersonId: first);
      await service.stopping.future;
      final finishedSecond = engine.stream.firstWhere(
        (p) => p.currentAssetId == 'asset-2',
      );
      await engine.queueIdentityRescan(second);
      expect(await rig.repo.identityRescan.hasQueued(), isTrue);
      service.release.complete();
      await running;
      await finishedSecond;
      await engine.stream.firstWhere((p) => p.phase == ScanPhase.completed);
      // Completed is emitted before the service has fully stopped.
      while (engine.isRunning) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(rig.api.analyzeCalls, hasLength(2));
      expect(await rig.repo.identityRescan.hasQueued(), isFalse);
      await engine.dispose();
    },
  );

  test('a request after final grouping is still drained', () async {
    final caps = fixture('Capabilities.idle');
    (caps['engines'] as Map)['character_library_repair'] = true;
    rig.api.capabilities_ = Capabilities.fromJson(caps);
    final first = await seedPerson(rig.db);
    final second = await seedPerson(rig.db);
    final m1 = await seedMedia(rig.db);
    final m2 = await seedMedia(rig.db, asset: 'asset-2');
    await seedFace(rig.db, mediaId: m1, personId: first);
    await seedFace(rig.db, mediaId: m2, personId: second);
    rig.api.analyzeResult = analysis(faces: []);
    var added = false;
    late ScanEngine engine;
    engine = rig.engine(
      afterRun: () async {
        if (!added) {
          added = true;
          await engine.queueIdentityRescan(second);
        }
      },
    );
    await engine.start(repairPersonId: first);
    expect(rig.api.analyzeCalls, hasLength(2));
    expect(await rig.repo.identityRescan.hasQueued(), isFalse);
    await engine.dispose();
  });

  test(
    'failed repair grouping pauses visibly and retains the waiting queue',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      final first = await seedPerson(rig.db);
      final second = await seedPerson(rig.db);
      final m1 = await seedMedia(rig.db);
      final m2 = await seedMedia(rig.db, asset: 'asset-2');
      await seedFace(rig.db, mediaId: m1, personId: first);
      await seedFace(rig.db, mediaId: m2, personId: second);
      await rig.repo.identityRescan.queue(first);
      await rig.repo.identityRescan.queue(second);
      rig.api.analyzeResult = analysis(faces: []);
      rig.api.groupingError = ApiException.network('offline');
      final engine = rig.engine();
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.paused);
      expect(await rig.repo.identityRescan.personId(), first);
      expect(await rig.repo.identityRescan.hasQueued(), isTrue);
      expect((await rig.repo.mediaById(m2))!.scanStatus, 'done');
      rig.api.groupingError = null;
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(rig.api.analyzeCalls, hasLength(2));
      expect(await rig.repo.identityRescan.hasQueued(), isFalse);
      await engine.dispose();
    },
  );

  test(
    'a deleted waiting identity cannot consume unrelated pending files',
    () async {
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      rig.api.capabilities_ = Capabilities.fromJson(caps);
      final person = await seedPerson(rig.db);
      await rig.repo.identityRescan.queue(person);
      await (rig.db.delete(
        rig.db.persons,
      )..where((p) => p.id.equals(person))).go();
      final unrelated = await seedMedia(rig.db, status: 'pending');
      final engine = rig.engine();
      await engine.start(enumerate: false);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(rig.api.analyzeCalls, isEmpty);
      expect((await rig.repo.mediaById(unrelated))!.scanStatus, 'pending');
      await engine.dispose();
    },
  );

  test(
    'pause during queue validation saves the request without restarting scanning',
    () async {
      final api = _HeldCapabilitiesApi();
      final caps = fixture('Capabilities.idle');
      (caps['engines'] as Map)['character_library_repair'] = true;
      api.capabilities_ = Capabilities.fromJson(caps);
      rig.pc = api;
      final p = await seedPerson(rig.db);
      final m = await seedMedia(rig.db);
      await seedFace(rig.db, mediaId: m, personId: p);
      final engine = rig.engine();
      final adding = engine.queueIdentityRescan(p);
      await api.entered.future;
      engine.pause();
      api.release.complete();
      await adding;
      expect(engine.isRunning, isFalse);
      expect(await rig.repo.identityRescan.hasQueued(), isTrue);
      expect((await rig.settings.load()).scanActive, isFalse);
      expect((await rig.repo.mediaById(m))!.scanStatus, 'done');
      expect(api.analyzeCalls, isEmpty);
      await engine.dispose();
    },
  );

  test(
    'unsupported PC refuses identity repair before changing the queue',
    () async {
      final p = await seedPerson(rig.db);
      final m = await seedMedia(rig.db);
      await seedFace(rig.db, mediaId: m, personId: p);
      final engine = rig.engine();
      await engine.start(repairPersonId: p);
      expect(engine.progress.phase, ScanPhase.paused);
      expect((await rig.repo.mediaById(m))!.scanStatus, 'done');
      expect(await rig.repo.identityRescan.personId(), isNull);
      expect(rig.api.analyzeCalls, isEmpty);
      await engine.dispose();
    },
  );

  test('a folder scan does not overwrite the saved source selection', () async {
    await rig.choose(['cam']);
    rig.library.addAlbum(
      const AlbumInfo(id: 'trip', name: 'Trips', count: 2),
      syntheticAssets(2, idStart: 100),
    );
    rig.everyPhotoHasANewFace();
    final engine = rig.engine();
    await engine.start(albumIds: {'trip'});
    expect((await rig.settings.load()).albumIds, ['cam']);
    expect((await rig.settings.load()).scanScopeAlbumIds, ['trip']);
    expect((await rig.media()).map((media) => media.assetId), [
      'asset-100',
      'asset-101',
    ]);
    expect(engine.progress.phase, ScanPhase.completed);
    await engine.dispose();
  });

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
      'files an older version scanned are redone at start, once, without re-listing',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        await rig.engine().start();
        rig.api.analyzeCalls.clear();
        await rig.db.customUpdate(
          'UPDATE media SET scan_version = ?',
          variables: [Variable.withInt(scanVersion - 1)],
        );
        rig.library.setAlbum('cam', syntheticAssets(6));

        await rig.engine().resumeIfInterrupted();
        expect(rig.api.analyzeCalls, hasLength(3));
        final rows = await rig.media();
        expect(rows, hasLength(3), reason: 'albums were not listed again');
        expect(
          rows.map((m) => (m.scanStatus, m.scanVersion)),
          everyElement(('done', scanVersion)),
        );

        rig.api.analyzeCalls.clear();
        await rig.engine().resumeIfInterrupted();
        expect(
          rig.api.analyzeCalls,
          isEmpty,
          reason: 'nothing is outdated now',
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
      'a photo that throws CompressError or Error is marked failed, the scan goes on',
      () async {
        await rig.choose();
        rig.everyPhotoHasANewFace();
        rig.library.failures['asset-2'] = CompressError(
          "Attempt to invoke virtual method 'void android.graphics.Bitmap.recycle()' on a null object reference",
          code: 'unknown',
        );
        final engine = rig.engine();
        await engine.start();
        final media = await rig.media();
        expect(media.map((m) => m.scanStatus), ['done', 'failed', 'done']);
        expect(media[1].scanError, contains('could not be read'));
        expect((engine.progress.done, engine.progress.failed), (2, 1));
      },
    );

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
