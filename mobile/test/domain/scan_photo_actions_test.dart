import 'dart:async';

import 'package:antigravity_mobile/domain/scan/redetect.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';
import '../support/fakes.dart' show syntheticAssets;
import 'scan_engine_test.dart' show Rig;

void main() {
  late Rig rig;
  setUp(() async {
    rig = Rig();
    rig.pc = rig.api;
    await rig.choose();
  });
  tearDown(() => rig.dispose());

  test(
    'redetect waits for the current commit, then the same scan continues',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var requests = 0, live = 0, maximum = 0;
      rig.api.analyzeHandler = (_, _) async {
        live++;
        if (live > maximum) maximum = live;
        if (++requests == 1) {
          entered.complete();
          await release.future;
        }
        live--;
        return analysis(faces: []);
      };
      final engine = rig.engine();
      final target = await seedMedia(rig.db, asset: 'old-photo');
      final redetector = Redetector(
        db: rig.db,
        files: rig.files,
        index: rig.index,
        store: rig.store,
        media: rig.library,
        settings: rig.settings,
        api: () => rig.api,
        runExclusive: engine.runLibraryAction,
      );
      final scan = engine.start();
      await entered.future;
      var committedBeforeAction = false;
      final action = engine.runLibraryAction(() async {
        committedBeforeAction =
            (await rig.media())
                .firstWhere((m) => m.assetId == 'asset-1')
                .scanStatus ==
            'done';
        return redetector.photo(target, RedetectPart.both);
      });
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      release.complete();
      expect(await action, isNotNull);
      await scan;
      expect(committedBeforeAction, isTrue);
      expect(maximum, 1);
      expect(requests, 4);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.done, 3);
      expect((await rig.media()).every((m) => m.scanStatus == 'done'), isTrue);
      expect(rig.keepAlive.events.where((e) => e == 'start'), hasLength(1));
      expect(rig.keepAlive.events.where((e) => e == 'stop'), hasLength(1));
      await engine.dispose();
    },
  );

  test(
    'a failed photo action does not fail or pause the scan; actions stay FIFO',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      rig.api.analyzeHandler = (_, _) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        return analysis(faces: []);
      };
      final engine = rig.engine();
      final scan = engine.start();
      await entered.future;
      final order = <int>[];
      final failed = engine.runLibraryAction<void>(() async {
        order.add(1);
        throw StateError('Redetect failed');
      });
      final failure = expectLater(failed, throwsStateError);
      final next = engine.runLibraryAction(() async {
        order.add(2);
        await engine.runLibraryAction(() async => order.add(3));
      });
      release.complete();
      await failure;
      await next;
      await scan;
      expect(order, [1, 2, 3]);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.failed, 0);
      expect(engine.progress.done, 3);
      await engine.dispose();
    },
  );

  test('Pause during a photo action remains a user pause', () async {
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    rig.api.analyzeHandler = (_, _) async {
      if (first) {
        first = false;
        entered.complete();
        await release.future;
      }
      return analysis(faces: []);
    };
    final engine = rig.engine();
    final scan = engine.start();
    await entered.future;
    final actionEntered = Completer<void>(), actionRelease = Completer<void>();
    final action = engine.runLibraryAction(() async {
      actionEntered.complete();
      await actionRelease.future;
    });
    release.complete();
    await actionEntered.future;
    engine.pause();
    actionRelease.complete();
    await action;
    await scan;
    expect(engine.progress.pauseReason, PauseReason.user);
    expect(engine.progress.done, 1);
    expect(rig.api.analyzeCalls, hasLength(1));
    await engine.resumeAfterConnectionRestored();
    expect(rig.api.analyzeCalls, hasLength(1));
    await engine.dispose();
  });

  test(
    'starting a scan waits for an idle photo action to release the library',
    () async {
      final engine = rig.engine();
      final entered = Completer<void>(), release = Completer<void>();
      final action = engine.runLibraryAction(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final scan = engine.start();
      await Future<void>.delayed(Duration.zero);
      expect(rig.api.analyzeCalls, isEmpty);
      release.complete();
      await action;
      await scan;
      expect(engine.progress.phase, ScanPhase.completed);
      await engine.dispose();
    },
  );

  test(
    'photo actions after Pause wait for an abandoned upload without committing it',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      rig.api.analyzeHandler = (_, _) async {
        entered.complete();
        await release.future;
        return analysis(faces: []);
      };
      final engine = rig.engine();
      final scan = engine.start();
      await entered.future;
      engine.pause();
      var applied = false;
      final action = engine.runLibraryAction(() async => applied = true);
      await Future<void>.delayed(Duration.zero);
      expect(applied, isFalse);
      release.complete();
      await action;
      await scan;
      expect(applied, isTrue);
      expect(engine.progress.pauseReason, PauseReason.user);
      expect(
        (await rig.media()).every((m) => m.scanStatus == 'pending'),
        isTrue,
      );
      await engine.dispose();
    },
  );

  test('actions queued during scan shutdown are not left waiting', () async {
    final engine = rig.engine(afterRun: () async {});
    var applied = false;
    rig.keepAlive.events.clear();
    final sub = engine.stream.listen((progress) {
      if (progress.phase == ScanPhase.completed) {
        unawaited(engine.runLibraryAction(() async => applied = true));
      }
    });
    await engine.start();
    await Future<void>.delayed(Duration.zero);
    expect(applied, isTrue);
    expect(engine.progress.phase, ScanPhase.completed);
    await sub.cancel();
    await engine.dispose();
  });
  test(
    'redetect of a pending item leaves a complete scan progress count',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      rig.api.analyzeHandler = (_, _) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        return analysis(faces: []);
      };
      final engine = rig.engine();
      final redetector = Redetector(
        db: rig.db,
        files: rig.files,
        index: rig.index,
        store: rig.store,
        media: rig.library,
        settings: rig.settings,
        api: () => rig.api,
        runExclusive: engine.runLibraryAction,
      );
      final scan = engine.start();
      await entered.future;
      final target = (await rig.media()).firstWhere(
        (m) => m.assetId == 'asset-2',
      );
      final action = redetector.photo(target.id, RedetectPart.both);
      release.complete();
      await action;
      await scan;
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.done, 2);
      expect(engine.progress.total, 2);
      expect((await rig.media()).every((m) => m.scanStatus == 'done'), isTrue);
      await engine.dispose();
    },
  );
  test(
    'delayed work from an old scan does not inherit a newer scan lease',
    () async {
      Zone? oldScanZone;
      final engine = rig.engine(
        afterRun: () async => oldScanZone ??= Zone.current,
      );
      rig.api.analyzeHandler = (_, _) async => analysis(faces: []);
      await engine.start();
      final entered = Completer<void>(), release = Completer<void>();
      var first = true;
      rig.library.setAlbum('cam', syntheticAssets(4));
      rig.api.analyzeHandler = (_, _) async {
        if (first) {
          first = false;
          entered.complete();
          await release.future;
        }
        return analysis(faces: []);
      };
      final scan = engine.start();
      await entered.future;
      var applied = false;
      final action = oldScanZone!.run(
        () => engine.runLibraryAction(() async => applied = true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(applied, isFalse);
      release.complete();
      await action;
      await scan;
      expect(applied, isTrue);
      expect(engine.progress.phase, ScanPhase.completed);
      await engine.dispose();
    },
  );
}
