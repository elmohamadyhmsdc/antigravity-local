// S05 Sources & scan (progress card, album picker), S24 Settings (library part), S26 Backup and the
// new Home tiles.

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

Future<void> _open(
  WidgetTester tester,
  TestEnv env,
  String location, {
  ScanProgress? progress,
}) async {
  await env.pump(
    tester,
    settle: progress?.isActive != true,
    extra: [
      initialLocationProvider.overrideWithValue(location),
      if (progress != null)
        scanProgressProvider.overrideWith((ref) => Stream.value(progress)),
    ],
  );
  if (progress?.isActive == true) {
    await tester.pump(const Duration(milliseconds: 100));
  } else {
    await _settle(tester);
  }
}

void main() {
  group('the scan progress card (every state of the scan)', () {
    appTest(
      'shows the media currently being scanned and a video frame timestamp',
      (tester, env) async {
        await _open(
          tester,
          env,
          '/sources',
          progress: const ScanProgress(
            phase: ScanPhase.running,
            total: 1,
            currentAssetId: 'video-current',
            currentKind: 'video',
            previewTimestampMs: 65000,
          ),
        );
        expect(find.byKey(const Key('scan-media-preview')), findsOneWidget);
        expect(find.text('Current video frame · 1:05'), findsOneWidget);
      },
      session: testSession,
    );

    appTest('preparing: counts the photos found so far', (tester, env) async {
      await _open(
        tester,
        env,
        '/sources',
        progress: const ScanProgress(phase: ScanPhase.preparing, found: 1234),
      );
      expect(find.text('Listing your photos…'), findsOneWidget);
      expect(find.text('1234 photos found'), findsOneWidget);
    }, session: testSession);

    appTest(
      'running: photos, faces, failures and the time left; Pause is offered',
      (tester, env) async {
        await _open(
          tester,
          env,
          '/sources',
          progress: const ScanProgress(
            phase: ScanPhase.running,
            total: 200,
            done: 40,
            failed: 2,
            facesFound: 57,
            facesLinked: 3,
            eta: Duration(minutes: 7),
          ),
        );
        expect(find.text('Scanning…'), findsOneWidget);
        expect(find.text('42 of 200 photos'), findsOneWidget);
        expect(find.text('57 new faces'), findsOneWidget);
        expect(find.text('3 seen before'), findsOneWidget);
        expect(find.text('2 photos could not be read'), findsOneWidget);
        expect(find.text('about 7 min left'), findsOneWidget);
        expect(find.byKey(const Key('scan-pause')), findsOneWidget);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byKey(const Key('scan-progress-bar')),
        );
        expect(bar.value, closeTo(0.21, 1e-9));
      },
      session: testSession,
    );

    appTest('running while the PC sorts faces says so', (tester, env) async {
      await _open(
        tester,
        env,
        '/sources',
        progress: const ScanProgress(
          phase: ScanPhase.running,
          total: 10,
          done: 5,
          grouping: true,
        ),
      );
      expect(find.text('Sorting faces into people…'), findsOneWidget);
    }, session: testSession);

    appTest('waiting for a busy PC', (tester, env) async {
      await _open(
        tester,
        env,
        '/sources',
        progress: const ScanProgress(
          phase: ScanPhase.waiting,
          total: 10,
          done: 5,
          message: 'A train_lora job is running on the GPU.',
        ),
      );
      expect(find.text('Waiting for your PC…'), findsOneWidget);
      expect(
        find.text('A train_lora job is running on the GPU.'),
        findsOneWidget,
      );
    }, session: testSession);

    for (final (reason, text) in [
      (PauseReason.user, 'You paused the scan.'),
      (
        PauseReason.noAccess,
        'Photo access is off. Allow it in Android settings.',
      ),
      (
        PauseReason.pcBusy,
        "Your PC's GPU stayed busy for several minutes. Resume when its other job is done.",
      ),
      (
        PauseReason.offline,
        'The PC could not be reached. Check that the server is running on the same Wi-Fi, then resume.',
      ),
      (
        PauseReason.modelMismatch,
        'Your PC now uses a different face-recognition model than this library. Switch the PC back, or start a new library.',
      ),
    ]) {
      appTest(
        'paused (${reason.name}): says why and offers Resume',
        (tester, env) async {
          await _open(
            tester,
            env,
            '/sources',
            progress: ScanProgress(
              phase: ScanPhase.paused,
              pauseReason: reason,
              total: 10,
              done: 4,
            ),
          );
          expect(find.text('Scan paused'), findsOneWidget);
          expect(find.text(text), findsOneWidget);
          expect(find.byKey(const Key('scan-resume')), findsOneWidget);
        },
        session: testSession,
      );
    }

    appTest(
      'paused because the PC revoked this phone: no Resume, it must be paired again',
      (tester, env) async {
        await _open(
          tester,
          env,
          '/sources',
          progress: const ScanProgress(
            phase: ScanPhase.paused,
            pauseReason: PauseReason.revoked,
          ),
        );
        expect(
          find.text('This phone was removed on the PC. Pair again to scan.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('scan-resume')), findsNothing);
      },
      session: testSession,
    );

    appTest(
      'completed: the summary and a button to the decisions waiting',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final face = await seedFace(env.db, seed: 1);
        await env.db
            .into(env.db.reviewMatches)
            .insert(
              ReviewMatchesCompanion.insert(
                faceId: Value(face),
                personId: sara,
                score: 0.4,
                margin: 0.1,
                decision: 'suggest',
              ),
            );
        await _open(
          tester,
          env,
          '/sources',
          progress: const ScanProgress(
            phase: ScanPhase.completed,
            total: 200,
            done: 198,
            failed: 2,
            facesFound: 310,
          ),
        );
        expect(find.text('Scan finished'), findsOneWidget);
        expect(find.text('198 photos scanned · 310 new faces'), findsOneWidget);
        expect(find.text('1 to review'), findsOneWidget);
      },
      session: testSession,
    );

    appTest('idle: nothing is shown', (tester, env) async {
      await _open(tester, env, '/sources');
      expect(find.byKey(const Key('scan-progress-card')), findsNothing);
    }, session: testSession);
  });

  group('S05 Sources', () {
    appTest(
      'albums come from the phone; choosing them is remembered',
      (tester, env) async {
        env.library.addAlbum(
          const AlbumInfo(id: 'all', name: 'Recent', count: 540, isAll: true),
          syntheticAssets(1),
        );
        env.library.addAlbum(
          const AlbumInfo(id: 'cam', name: 'Camera', count: 480),
          syntheticAssets(1),
        );
        env.library.addAlbum(
          const AlbumInfo(id: 'shots', name: 'Screenshots', count: 1),
          syntheticAssets(1),
        );
        await _open(tester, env, '/sources');

        expect(find.text('All photos & videos'), findsOneWidget);
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('480 items'), findsOneWidget);
        expect(find.text('1 item'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('scan-start')),
          200,
        );
        expect(find.text('Choose albums first'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('scan-start')))
              .onPressed,
          isNull,
        );

        await tester.scrollUntilVisible(
          find.byKey(const Key('album-cam')),
          -200,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('album-cam')));
        await _settle(tester);
        expect((await env.settingsSnapshot()).albumIds, ['cam']);
        await tester.scrollUntilVisible(
          find.byKey(const Key('scan-start')),
          200,
        );
        expect(find.text('Scan now'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('scan-start')))
              .onPressed,
          isNotNull,
        );

        await tester.scrollUntilVisible(
          find.byKey(const Key('album-cam')),
          -200,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('album-cam')));
        await _settle(tester);
        expect((await env.settingsSnapshot()).albumIds, isEmpty);
      },
      session: testSession,
    );

    appTest(
      'without photo access it explains and offers to ask again',
      (tester, env) async {
        env.library.access = false;
        await _open(tester, env, '/sources');
        expect(find.text('No photo access'), findsOneWidget);
        expect(find.text('Allow photo access'), findsOneWidget);
      },
      session: testSession,
    );

    appTest('the scan options are stored', (tester, env) async {
      env.library.addAlbum(
        const AlbumInfo(id: 'cam', name: 'Camera', count: 3),
        syntheticAssets(3),
      );
      await _open(tester, env, '/sources');
      await revealForTap(tester, find.byKey(const Key('scan-bodies')));
      await tester.tap(find.byKey(const Key('scan-bodies')));
      await _settle(tester);
      expect((await env.settingsSnapshot()).scanBodies, isFalse);
    }, session: testSession);

    appTest(
      'adaptive video sampling is enabled by default and manual sampling is optional',
      (tester, env) async {
        await _open(tester, env, '/sources');
        expect((await env.settingsSnapshot()).adaptiveVideoSampling, isTrue);
        expect(find.byKey(const Key('video-frame-interval')), findsNothing);
        final automatic = find.byKey(const Key('adaptive-video-sampling'));
        await revealForTap(tester, automatic);
        await tester.tap(automatic);
        await _settle(tester);
        expect((await env.settingsSnapshot()).adaptiveVideoSampling, isFalse);
        expect(find.byKey(const Key('video-frame-interval')), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('S24 Settings', () {
    appTest('grouping strictness and the quality gate are saved', (
      tester,
      env,
    ) async {
      await _open(tester, env, '/settings');
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.textContaining('Recommended'), findsOneWidget);

      await tester.tap(find.text('Strict'));
      await _settle(tester);
      expect((await env.settingsSnapshot()).strictness, 'strict');
      expect(find.textContaining('Fewer mistakes'), findsOneWidget);

      final slider = find.byKey(const Key('quality-gate'));
      await tester.drag(slider, const Offset(200, 0));
      await _settle(tester);
      final gate = (await env.settingsSnapshot()).qualityGate;
      expect(
        gate,
        greaterThan(0.40),
        reason: 'dragging right raises the minimum quality',
      );
      expect(gate, lessThanOrEqualTo(0.80));
    }, session: testSession);

    appTest(
      'it links to Sources, to Backup and shows the paired PC',
      (tester, env) async {
        await _open(tester, env, '/settings');
        await tester.scrollUntilVisible(
          find.byKey(const Key('settings-pc')),
          200,
        );
        expect(find.text('RTX-PC'), findsOneWidget);
        expect(find.text('192.168.1.20:8443'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('settings-backup')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('settings-backup')));
        await _settle(tester);
        expect(find.text('Backup & restore'), findsWidgets);
      },
      session: testSession,
    );
  });

  group('S26 Backup', () {
    appTest('an empty library has nothing to back up yet', (tester, env) async {
      await _open(tester, env, '/backup');
      expect(find.text('No backup yet'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('backup-export')))
            .onPressed,
        isNull,
      );
      await revealForTap(
        tester,
        find.text(
          'Backups are encrypted by default. Keep the password safe; it is never stored by the app. Older unencrypted backups can still be restored.',
        ),
      );
      expect(
        find.text(
          'Backups are encrypted by default. Keep the password safe; it is never stored by the app. Older unencrypted backups can still be restored.',
        ),
        findsOneWidget,
      );
    }, session: testSession);

    appTest(
      'a library can be backed up, and the last backup time is shown',
      (tester, env) async {
        await seedFace(env.db, seed: 1);
        await env.db.putSetting(
          'backup.last_at',
          '${DateTime(2026, 10, 1, 9, 5).millisecondsSinceEpoch}',
        );
        await _open(tester, env, '/backup');
        expect(find.textContaining('Last backup'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('backup-export')))
              .onPressed,
          isNotNull,
        );
        expect(find.text('0 people · 1 faces · 0 photos'), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('Home', () {
    appTest(
      'offers to scan, lists what needs a decision, and nags about a missing backup',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        await seedFace(env.db, personId: sara, seed: 1);
        final loose = await seedFace(env.db, seed: 2);
        await env.db
            .into(env.db.reviewMatches)
            .insert(
              ReviewMatchesCompanion.insert(
                faceId: Value(loose),
                personId: sara,
                score: 0.4,
                margin: 0.1,
                decision: 'suggest',
              ),
            );
        await env.pump(tester);
        await _settle(tester);

        expect(find.byKey(const Key('scan-library')), findsOneWidget);
        expect(find.text('1 decision needs you'), findsOneWidget);
        await revealForTap(tester, find.byKey(const Key('backup-reminder')));
        expect(find.byKey(const Key('backup-reminder')), findsOneWidget);
        expect(find.text('You have never made a backup'), findsOneWidget);

        await revealForTap(
          tester,
          find.byKey(const Key('needs-review')),
          delta: -180,
        );
        await tester.tap(find.byKey(const Key('needs-review')));
        await _settle(tester);
        expect(find.text('Quick review'), findsOneWidget);
        expect(find.text('Is this Sara?'), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'a recent backup silences the reminder; an empty library never nags',
      (tester, env) async {
        await env.pump(tester);
        await _settle(tester);
        expect(
          find.byKey(const Key('backup-reminder')),
          findsNothing,
          reason: 'nothing to lose yet',
        );
        expect(find.byKey(const Key('needs-review')), findsNothing);

        await seedFace(env.db, seed: 1);
        await env.db.putSetting(
          'backup.last_at',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        await _settle(tester);
        expect(find.byKey(const Key('backup-reminder')), findsNothing);
      },
      session: testSession,
    );

    appTest('"Scan library" opens Sources', (tester, env) async {
      await env.pump(tester);
      await tester.tap(find.byKey(const Key('scan-library')));
      await _settle(tester);
      expect(find.text('Sources & scan'), findsWidgets);
      expect(find.text('Albums to scan'), findsOneWidget);
    }, session: testSession);
  });
}
