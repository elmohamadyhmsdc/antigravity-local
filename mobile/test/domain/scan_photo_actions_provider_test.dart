import 'dart:async';

import 'package:antigravity_mobile/domain/scan/scan_engine.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_media_organizer.dart';
import '../support/seed.dart';
import 'scan_engine_test.dart' show Rig;

void main() {
  late Rig rig;
  late FakeMediaOrganizer bridge;
  late ProviderContainer container;
  late ScanEngine engine;
  late Completer<void> entered, release;
  late int person, photo;
  setUp(() async {
    rig = Rig();
    rig.pc = rig.api;
    await rig.choose();
    person = await seedPerson(rig.db, name: 'Sara');
    photo = await seedMedia(rig.db, asset: 'existing-photo');
    await seedFace(rig.db, mediaId: photo, personId: person);
    bridge = FakeMediaOrganizer()..seed('existing-photo');
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(rig.db),
        fileStoreProvider.overrideWithValue(rig.files),
        embeddingIndexProvider.overrideWithValue(rig.index),
        mediaLibraryProvider.overrideWithValue(rig.library),
        mobileApiProvider.overrideWithValue(rig.api),
        mediaOrganizerBridgeProvider.overrideWithValue(bridge),
      ],
    );
    engine = ScanEngine(
      library: rig.repo,
      media: rig.library,
      api: () => rig.api,
      settings: rig.settings,
      store: container.read(photoResultStoreProvider),
      grouping: rig.grouping,
      keepAlive: rig.keepAlive,
    );
    container.read(scanEngineLinkProvider).engine = engine;
    entered = Completer<void>();
    release = Completer<void>();
    var first = true;
    rig.api.analyzeHandler = (_, _) async {
      if (first) {
        first = false;
        entered.complete();
        await release.future;
      }
      return analysis(faces: []);
    };
  });
  tearDown(() async {
    await engine.dispose();
    container.read(scanEngineLinkProvider).engine = null;
    container.dispose();
    await rig.dispose();
  });

  test(
    'renaming during a scan defers only the move and does not pause or deadlock',
    () async {
      bridge.cancel = true;
      final scan = engine.start();
      await entered.future;
      // This is also how a batch rename / group change can reach the organizer.
      await rig.db.transaction(() async {
        await container
            .read(peopleRepositoryProvider)
            .renamePerson(person, 'New name');
      });
      expect(engine.isRunning, isTrue);
      expect(engine.progress.pausing, isFalse);
      expect(bridge.moves, isEmpty);
      expect(
        container.read(photoResultStoreProvider).pendingOrganize,
        contains(photo),
      );
      release.complete();
      await scan;
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.done, 3);
      expect(bridge.moves, hasLength(1));
      expect(bridge.originals['existing-photo']!.path, 'DCIM/Camera/');
    },
  );

  test(
    'explicit photo move waits for the scan commit and resumes after cache cleanup',
    () async {
      final organizer = container.read(personMediaOrganizerProvider);
      final plan = await organizer.plan({person});
      final scan = engine.start();
      await entered.future;
      final moving = Completer<void>(), moveRelease = Completer<void>();
      bridge.beforeWrite = () async {
        moving.complete();
        await moveRelease.future;
      };
      final move = organizer.apply(plan);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.moves, isEmpty);
      release.complete();
      await moving.future;
      expect(engine.isRunning, isTrue);
      expect(engine.progress.pausing, isFalse);
      expect(engine.progress.phase, ScanPhase.waiting);
      expect(rig.api.analyzeCalls, hasLength(1));
      moveRelease.complete();
      final results = await move;
      expect(results.single.moved, isTrue);
      await scan;
      expect(rig.library.cacheClears, greaterThan(0));
      expect(engine.mediaOrganizationActive, isFalse);
      expect(engine.progress.phase, ScanPhase.completed);
      expect(engine.progress.done, 3);
      expect(rig.keepAlive.events.where((e) => e == 'start'), hasLength(1));
      expect(rig.keepAlive.events.where((e) => e == 'stop'), hasLength(1));
    },
  );
}
