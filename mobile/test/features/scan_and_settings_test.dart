// S05 Sources & scan (progress card, album picker), S24 Settings (library part), S26 Backup and the
// new Home tiles.

import 'dart:async';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
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

Future<void> _openSection(WidgetTester tester, String id) async {
  final section = find.byKey(Key(id));
  await tester.scrollUntilVisible(
    section,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(section);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tapAt(tester.getTopLeft(section) + const Offset(120, 28));
  await tester.pump(const Duration(milliseconds: 300));
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
      'select all chooses all individual albums allowing exclusion, and deselect all clears',
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
          const AlbumInfo(id: 'shots', name: 'Screenshots', count: 50),
          syntheticAssets(1),
        );
        env.library.addAlbum(
          const AlbumInfo(id: 'wa', name: 'WhatsApp', count: 10),
          syntheticAssets(1),
        );
        await _open(tester, env, '/sources');

        final selectAllBtn = find.byKey(const Key('albums-select-all'));
        final deselectAllBtn = find.byKey(const Key('albums-deselect-all'));

        expect(selectAllBtn, findsOneWidget);
        expect(deselectAllBtn, findsOneWidget);
        expect(tester.widget<TextButton>(selectAllBtn).onPressed, isNotNull);
        expect(tester.widget<TextButton>(deselectAllBtn).onPressed, isNull);

        // Tap "Select all": selects all individual albums (cam, shots, wa) but not "all"
        await tester.tap(selectAllBtn);
        await _settle(tester);

        expect((await env.settingsSnapshot()).albumIds, ['cam', 'shots', 'wa']);
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-all')))
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-cam')))
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-shots')))
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-wa')))
              .value,
          isTrue,
        );

        // Now selectAll is disabled because all individual albums are selected
        expect(tester.widget<TextButton>(selectAllBtn).onPressed, isNull);
        // deselectAll is enabled
        expect(tester.widget<TextButton>(deselectAllBtn).onPressed, isNotNull);

        // Exclude one album (Screenshots)
        await tester.tap(find.byKey(const Key('album-shots')));
        await _settle(tester);

        expect((await env.settingsSnapshot()).albumIds, ['cam', 'wa']);
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-shots')))
              .value,
          isFalse,
        );
        // selectAll is re-enabled because not all individual albums are selected
        expect(tester.widget<TextButton>(selectAllBtn).onPressed, isNotNull);

        // Tap "Deselect all"
        await tester.tap(deselectAllBtn);
        await _settle(tester);

        expect((await env.settingsSnapshot()).albumIds, isEmpty);
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-cam')))
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(const Key('album-wa')))
              .value,
          isFalse,
        );
        expect(tester.widget<TextButton>(deselectAllBtn).onPressed, isNull);
        expect(tester.widget<TextButton>(selectAllBtn).onPressed, isNotNull);
      },
      session: testSession,
    );

    appTest(
      'select all and deselect all are disabled while a scan is running',
      (tester, env) async {
        env.library.addAlbum(
          const AlbumInfo(id: 'cam', name: 'Camera', count: 480),
          syntheticAssets(1),
        );
        await _open(
          tester,
          env,
          '/sources',
          progress: const ScanProgress(
            phase: ScanPhase.running,
            total: 10,
            done: 2,
          ),
        );

        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('albums-select-all')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('albums-deselect-all')))
              .onPressed,
          isNull,
        );
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
      await _openSection(tester, 'library-scan-section');
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
        await _openSection(tester, 'library-scan-section');
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
    appTest(
      'Sort now stays visible while the PC works and can retry after a failed request',
      (tester, env) async {
        final person = await seedPerson(env.db);
        final face = await seedFace(env.db);
        final pending = Completer<GroupingPlanResponse>();
        env.api.groupingHandler = (_) => pending.future;
        await _open(tester, env, '/settings/library');
        await _openSection(tester, 'library-maintenance-section');
        final button = find.byKey(const Key('settings-sort-now'));
        await revealForTap(tester, button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        expect(tester.widget<ListTile>(button).onTap, isNull);
        expect(
          find.descendant(of: button, matching: find.text('Sorting faces…')),
          findsOneWidget,
        );
        expect(env.api.groupingCalls, isNotEmpty);

        env.api.groupingHandler = (request) => GroupingPlanResponse(
          mode: request.mode,
          assignments: [
            if (request.mode == 'apply' &&
                request.pending.any((f) => f.id == face))
              FaceAssignment(
                faceId: face,
                personId: person,
                score: 0.9,
                margin: 0.5,
                decision: 'auto',
              ),
          ],
        );
        pending.completeError(ApiException.timeout());
        await _settle(tester);
        expect(find.text('The PC did not answer in time.'), findsOneWidget);
        expect(tester.widget<ListTile>(button).onTap, isNotNull);

        await tester.tap(button);
        await _settle(tester);
        expect(find.textContaining('Added 1 faces'), findsOneWidget);
        expect(
          (await env.db.select(env.db.faces).get()).single.personId,
          person,
        );
      },
      session: testSession,
    );

    for (final scanning in [false, true]) {
      appTest(
        'missing outlines are counted and retry respects an active scan ($scanning)',
        (tester, env) async {
          final mediaId = await seedMedia(env.db);
          await env.db
              .into(env.db.mediaDetections)
              .insert(
                MediaDetectionsCompanion.insert(
                  mediaId: mediaId,
                  kind: 'b',
                  refId: 99,
                  x: 0.1,
                  y: 0.1,
                  w: 0.2,
                  h: 0.2,
                ),
              );
          await _open(
            tester,
            env,
            '/settings/library',
            progress: ScanProgress(
              phase: scanning ? ScanPhase.running : ScanPhase.idle,
            ),
          );
          await _openSection(tester, 'library-matching-section');
          final tile = find.byKey(const Key('settings-retry-outlines'));
          if (scanning) {
            await tester.scrollUntilVisible(
              tile,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump(const Duration(milliseconds: 100));
          } else {
            await revealForTap(tester, tile);
          }
          expect(find.textContaining('1 photo waiting'), findsOneWidget);
          final button = tester.widget<TextButton>(
            find.descendant(of: tile, matching: find.byType(TextButton)),
          );
          expect(button.onPressed, scanning ? isNull : isNotNull);
        },
        session: testSession,
      );
    }

    appTest('grouping strictness and the quality gate are saved', (
      tester,
      env,
    ) async {
      await _open(tester, env, '/settings/library');
      await _openSection(tester, 'library-matching-section');
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.textContaining('Recommended'), findsOneWidget);

      await tester.ensureVisible(find.text('Strict'));
      await _settle(tester);
      await tester.tap(find.text('Strict'));
      await _settle(tester);
      expect((await env.settingsSnapshot()).strictness, 'strict');
      expect(find.textContaining('Fewer mistakes'), findsOneWidget);

      final slider = find.byKey(const Key('quality-gate'));
      await tester.scrollUntilVisible(
        slider,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);
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
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/home')],
        );
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
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/home')],
        );
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
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/home')],
      );
      await tester.tap(find.byKey(const Key('scan-library')));
      await _settle(tester);
      expect(find.text('Library & scanning'), findsWidgets);
      expect(find.text('Albums to scan'), findsOneWidget);
    }, session: testSession);
  });
}
