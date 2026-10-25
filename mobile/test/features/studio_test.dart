import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> open(WidgetTester tester, TestEnv env, String route) =>
    env.pump(tester, extra: [initialLocationProvider.overrideWithValue(route)]);
Future<void> next(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('reface-next')));
  await tester.tap(find.byKey(const Key('reface-next')));
  await tester.pumpAndSettle();
}

void main() {
  appTest('Studio links to Reface and private results', (tester, env) async {
    await open(tester, env, '/studio');
    expect(find.byKey(const Key('studio-reface')), findsOneWidget);
    await tester.tap(find.byKey(const Key('studio-results')));
    await tester.pumpAndSettle();
    expect(find.text('No private results yet'), findsOneWidget);
  }, session: testSession);

  appTest(
    'offline Reface explains connection and disables detection',
    (tester, env) async {
      env.api.capabilitiesError = ApiException.network('Offline');
      await open(tester, env, '/reface');
      expect(
        find.text(
          'Connect to your paired PC to detect faces and start a new job.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('reface-target')))
            .onPressed,
        isNull,
      );
    },
    session: testSession,
  );

  appTest('photo target selection refuses an empty selection', (
    tester,
    env,
  ) async {
    env.picker.photo = tinyPng;
    await open(tester, env, '/reface');
    await tester.tap(find.byKey(const Key('reface-target')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-face-0')), findsOneWidget);
    for (final i in [0, 1]) {
      await tester.tap(find.byKey(Key('target-face-$i')));
    }
    await next(tester);
    expect(find.text('Select at least one target face.'), findsOneWidget);
    expect(await env.db.select(env.db.jobs).get(), isEmpty);
  }, session: testSession);

  appTest(
    'person source loads best faces, and quality step fits a phone',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: person, seed: 1);
      env.picker.photo = tinyPng;
      await open(tester, env, '/reface?person=$person');
      await tester.tap(find.byKey(const Key('reface-target')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      await next(tester);
      expect(find.text('Face restoration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'job details display a durable failure with a retry action',
    (tester, env) async {
      await env.db
          .into(env.db.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'local-1',
              serverId: testSession.serverId,
              type: 'reface_image_v3',
              requestJson: '{}',
              targetPath: 'work/local-1/photo.jpg',
              targetSha: 'a' * 64,
              targetSize: 1,
              status: 'failed',
              error: const Value('GPU processing failed'),
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/jobs/local-1'),
          studioApiProvider.overrideWithValue(FakeStudioApi()),
        ],
      );
      expect(find.text('GPU processing failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'private image result has comparison and persists favourites',
    (tester, env) async {
      final hash = 'a' * 64;
      await tester.runAsync(() async {
        await env.files.write('results/x/result.png', tinyPng);
        await env.files.write('results/x/original.jpg', tinyPng);
      });
      await env.db
          .into(env.db.results)
          .insert(
            ResultsCompanion.insert(
              id: 'x',
              type: 'reface_image_v3',
              path: 'results/x/result.png',
              originalPath: 'results/x/original.jpg',
              mime: 'image/png',
              sizeBytes: tinyPng.length,
              sha256: hash,
              createdAt: 1,
            ),
          );
      await open(tester, env, '/results/x');
      expect(find.byKey(const Key('result-comparison')), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Favourite'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Favourite'));
      await tester.pumpAndSettle();
      expect(
        (await env.db.select(env.db.results).get()).single.favourite,
        isTrue,
      );
    },
    session: testSession,
  );

  appTest('Legacy hides unsupported mask and realism options', (
    tester,
    env,
  ) async {
    final person = await seedPerson(env.db, name: 'Sara');
    await seedFace(env.db, personId: person, seed: 1);
    env.picker.photo = tinyPng;
    await open(tester, env, '/reface?person=$person');
    await tester.tap(find.byKey(const Key('reface-target')));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    final engine = find.byKey(const ValueKey('quality-engine-v3'));
    await tester.ensureVisible(engine);
    await tester.tap(engine);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Legacy').last);
    await tester.pumpAndSettle();
    expect(find.text('Realism preset'), findsNothing);
    expect(find.text('Use face region mask'), findsNothing);
    expect(find.byKey(const Key('reface-identity-boost')), findsNothing);
    expect(find.text('Face restoration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, session: testSession);

  appTest(
    'video reference photo keeps the video target and allows face selection',
    (tester, env) async {
      final file = File('${env.tmp.path}/target.mp4');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
      env.targetPicker = () async => RefaceTarget.video(file);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tester.tap(find.byKey(const Key('reface-target')));
      await tester.pumpAndSettle();
      env.picker.photo = tinyPng;
      await tester.ensureVisible(find.byKey(const Key('reface-reference')));
      await tester.tap(find.byKey(const Key('reface-reference')));
      await tester.pumpAndSettle();
      expect(find.text('target.mp4'), findsOneWidget);
      expect(find.byKey(const Key('target-face-0')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('target-face-0')).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('target-face-0')));
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('review offers a preview before full rendering', (tester, env) async {
    final person = await seedPerson(env.db, name: 'Sara');
    await seedFace(env.db, personId: person, seed: 1);
    env.picker.photo = tinyPng;
    await open(tester, env, '/reface?person=$person');
    await tester.tap(find.byKey(const Key('reface-target')));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    await next(tester);
    expect(find.byKey(const Key('reface-preview')), findsOneWidget);
    expect(find.text('Render a preview'), findsOneWidget);
  }, session: testSession);

  appTest('Studio preview renders at phone size', (tester, env) async {
    const key = Key('preview');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          initialLocationProvider.overrideWithValue('/studio'),
        ],
        child: const RepaintBoundary(key: key, child: App()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build').create(recursive: true);
      await File(
        'build/studio-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }, session: testSession);
}
