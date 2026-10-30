import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/features/storage/storage_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void _narrowWithLargeText(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = 1.8;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

void main() {
  appTest(
    'storage summarizes real categories and separates saved-file removal',
    (tester, env) async {
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/storage'),
          storageSizesProvider.overrideWith(
            (ref) async => {
              'results': 16 * 1048576,
              'loras': 32 * 1048576,
              'work': 2 * 1048576,
            },
          ),
        ],
      );
      expect(find.text('50.0 MB'), findsOneWidget);
      expect(find.text('Character models'), findsOneWidget);
      expect(find.byKey(const Key('storage-delete-results')), findsNothing);
      await revealForTap(tester, find.byKey(const Key('storage-saved-files')));
      await tester.tap(find.byKey(const Key('storage-saved-files')));
      await tester.pumpAndSettle();
      await revealForTap(
        tester,
        find.byKey(const Key('storage-delete-results')),
      );
      await tester.tap(find.byKey(const Key('storage-delete-results')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('backup actions stay on screen with large text', (tester, env) async {
    _narrowWithLargeText(tester);
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/backup')],
    );
    final export = tester.getRect(find.byKey(const Key('backup-export')));
    final restore = tester.getRect(find.byKey(const Key('backup-restore')));
    expect(export.top, greaterThanOrEqualTo(0));
    expect(restore.bottom, lessThanOrEqualTo(740));
    expect(tester.takeException(), isNull);
  }, session: testSession);

  appTest(
    'faces can be selected with an explicit action and a normal tap',
    (tester, env) async {
      final face = await seedFace(env.db, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/unsorted')],
      );
      await tester.tap(find.byKey(const Key('face-selection-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('face-$face')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('face-selection-mode')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-assign')), findsNothing);
      expect(find.text('Select faces'), findsOneWidget);
    },
    session: testSession,
  );

  appTest('manual pairing action stays above the keyboard', (
    tester,
    env,
  ) async {
    _narrowWithLargeText(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/pair/manual')],
    );
    expect(
      tester.getRect(find.byKey(const Key('connect'))).bottom,
      lessThanOrEqualTo(460),
    );
    expect(tester.takeException(), isNull);
  });

  appTest(
    'a failed job exposes retry without scrolling through details',
    (tester, env) async {
      _narrowWithLargeText(tester);
      await env.db
          .into(env.db.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'redesign-failed',
              serverId: testSession.serverId,
              type: 'reface_image',
              requestJson: '{}',
              targetPath: 'work/redesign-failed/photo.jpg',
              targetSha: 'a' * 64,
              targetSize: 1,
              status: 'failed',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/jobs/redesign-failed'),
        ],
      );
      expect(find.byKey(const Key('job-resume')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('result sharing stays visible beneath a large image', (
    tester,
    env,
  ) async {
    _narrowWithLargeText(tester);
    await tester.runAsync(() async {
      await env.files.write('results/redesign/result.png', tinyPng);
    });
    await env.db
        .into(env.db.results)
        .insert(
          ResultsCompanion.insert(
            id: 'redesign-result',
            type: 'reface_image',
            path: 'results/redesign/result.png',
            originalPath: 'results/redesign/result.png',
            mime: 'image/png',
            sizeBytes: tinyPng.length,
            sha256: 'b' * 64,
            createdAt: 1,
          ),
        );
    await env.pump(
      tester,
      extra: [
        initialLocationProvider.overrideWithValue('/results/redesign-result'),
      ],
    );
    expect(find.byKey(const Key('share-result')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, session: testSession);
}
