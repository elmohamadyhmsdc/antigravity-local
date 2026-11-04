import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
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

/// Real I/O (files, SQLite) only moves while the test yields to the real event loop.
Future<void> settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> next(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('reface-next')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('reface-next')));
  await tester.pumpAndSettle();
}

void main() {
  appTest('Studio links to Reface and private results', (tester, env) async {
    await open(tester, env, '/studio');
    expect(find.byKey(const Key('studio-reface')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('studio-results')),
      200,
    );
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
    await pickRefaceTarget(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-face-0')), findsOneWidget);
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
      await pickRefaceTarget(tester);
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      await next(tester);
      await tester.ensureVisible(find.text('Advanced options'));
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();
      expect(find.text('Sharpening'), findsOneWidget);
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
      await env.db.putSetting(
        '${artifactContextPrefix}x',
        jsonEncode(
          const ArtifactContext(
            qualityWarnings: ['Identity likeness is unverified.'],
          ).toJson(),
        ),
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/results/x')],
        settle: false,
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const Key('result-comparison')).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byKey(const Key('result-comparison')), findsOneWidget);
      await revealForTap(
        tester,
        find.byKey(const Key('result-quality-warning')),
      );
      expect(find.text('Identity likeness is unverified.'), findsOneWidget);
      await revealForTap(tester, find.widgetWithText(FilterChip, 'Favourite'));
      await tester.tap(find.widgetWithText(FilterChip, 'Favourite'));
      await tester.pumpAndSettle();
      expect(
        (await env.db.select(env.db.results).get()).single.favourite,
        isTrue,
      );
    },
    session: testSession,
  );

  appTest(
    'one Reface pipeline explains quality and its automatic restorer',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: person, seed: 1);
      env.picker.photo = tinyPng;
      await open(tester, env, '/reface?person=$person');
      await pickRefaceTarget(tester);
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);
      expect(find.text('V2'), findsNothing);
      expect(find.text('V3 · HD'), findsNothing);
      expect(find.text('Engine'), findsNothing);
      await tester.ensureVisible(find.text('Advanced options'));
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reface-identity-boost')), findsOneWidget);
      final profile = find.byKey(const Key('reface-quality-profile'));
      await tester.ensureVisible(profile);
      await tester.tap(profile);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Quickest · skin a little soft'),
        findsOneWidget,
      );
      await tester.tap(find.text('Fast').last);
      await tester.pumpAndSettle();
      final parser = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Use face region mask'),
      );
      expect(parser.value, isFalse);
      final restorer = find.byKey(const ValueKey('restorer-fast'));
      await tester.ensureVisible(restorer);
      await tester.tap(restorer);
      await tester.pumpAndSettle();
      expect(find.text('Right now: No sharpening'), findsOneWidget);
      expect(
        find.text('Rebuilds blurry faces · can change the look'),
        findsOneWidget,
      );
      await tester.tap(find.text('Rebuilds blurry faces').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('reface-restorer-description')))
            .data,
        contains('fidelity'),
      );
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'video finds its own people and allows target face selection without a reference photo',
    (tester, env) async {
      final file = File('${env.tmp.path}/target.mp4');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
      env.targetPicker = () async => RefaceTarget.video(file);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await pickRefaceTarget(tester);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('target.mp4'), findsOneWidget);
      expect(find.byKey(const Key('reface-reference')), findsNothing);
      expect(find.byKey(const Key('video-target-face-0')), findsOneWidget);
      expect(find.byKey(const Key('video-target-face-1')), findsOneWidget);
      expect(env.sampledVideoRanges, hasLength(1));
      await tester.ensureVisible(find.byKey(const Key('video-target-face-0')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('video-target-face-0')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('video-target-face-0')));
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('review offers a preview before full rendering', (tester, env) async {
    final person = await seedPerson(env.db, name: 'Sara');
    await seedFace(env.db, personId: person, seed: 1);
    env.picker.photo = tinyPng;
    await open(tester, env, '/reface?person=$person');
    await pickRefaceTarget(tester);
    await tester.tap(find.byKey(const Key('target-face-0')));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);
    expect(find.byKey(const Key('reface-preview')), findsOneWidget);
    expect(find.text('Render a preview'), findsOneWidget);
  }, session: testSession);

  appTest(
    'review checks the target against the source before anything is queued',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      await seedFace(
        env.db,
        personId: person,
        seed: 1,
      ); // one real source face: a thin identity
      env.picker.photo = tinyPng;
      await open(tester, env, '/reface?person=$person');
      await pickRefaceTarget(tester);
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);

      expect(find.byKey(const Key('reface-preflight')), findsOneWidget);
      expect(
        find.textContaining('Takes a few seconds on your PC'),
        findsOneWidget,
        reason: 'the chosen quality says how long it takes for this photo',
      );
      expect(find.textContaining('Target: 1 face'), findsOneWidget);
      expect(find.textContaining('Only 1 real source face'), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'review offers to draw the missing head angles with the person\'s LoRA and queues exactly those',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: person, seed: 1);
      await env.db
          .into(env.db.loras)
          .insert(
            LorasCompanion.insert(
              id: 'sara-lora',
              personId: Value(person),
              path: 'loras/sara.safetensors',
              triggerWord: 'sksara',
              createdAt: 1,
            ),
          );
      await tester.runAsync(
        () => env.files.write('loras/sara.safetensors', tinyPng),
      );
      env.picker.photo = tinyPng;
      await open(tester, env, '/reface?person=$person');
      await pickRefaceTarget(tester);
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await next(tester);
      await next(tester);

      // the placeholder photo is not a decodable image once real time passes; that is not under test here
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (!'${details.exception}'.contains('Codec failed')) {
          previous?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = previous);
      final button = find.byKey(const Key('reface-generate-angles'));
      await tester.ensureVisible(button);
      expect(find.textContaining('Generate 3 missing angles'), findsOneWidget);
      await tester.tap(button);
      await settleAsync(tester);

      final jobs = await tester.runAsync(
        () => env.db.select(env.db.jobs).get(),
      );
      jobs!;
      expect(jobs.single.type, 'generate_lora_images');
      final params =
          (jsonDecode(jobs.single.requestJson) as Map)['params'] as Map;
      expect(params['angles'], ['frontal', 'frontal', 'frontal']);
      expect(params['num_images'], 3);
      expect(params['trigger_word'], 'sksara');
      expect(params['prompt'], contains('sksara'));
      expect(params.containsKey('multi_angle'), isFalse);
      expect(find.byKey(const Key('reface-angles-progress')), findsOneWidget);
      expect(find.byKey(const Key('reface-generate-angles')), findsNothing);

      // a failed generation is reported, and Reface is still allowed to start with what the source has
      await (env.db.update(
        env.db.jobs,
      )..where((j) => j.id.equals(jobs.single.id))).write(
        const JobsCompanion(
          status: Value('failed'),
          error: Value('GPU out of memory'),
        ),
      );
      await settleAsync(tester);
      expect(find.textContaining('GPU out of memory'), findsOneWidget);
      expect(find.byKey(const Key('reface-generate-angles')), findsOneWidget);
      expect(find.byKey(const Key('reface-next')), findsOneWidget);
    },
    session: testSession,
  );

  appTest('no LoRA, no offer: the card only names the gap', (
    tester,
    env,
  ) async {
    final person = await seedPerson(env.db, name: 'Sara');
    await seedFace(env.db, personId: person, seed: 1);
    env.picker.photo = tinyPng;
    await open(tester, env, '/reface?person=$person');
    await pickRefaceTarget(tester);
    await tester.tap(find.byKey(const Key('target-face-0')));
    await tester.pumpAndSettle();
    await next(tester);
    await next(tester);

    expect(find.byKey(const Key('reface-preflight')), findsOneWidget);
    expect(find.byKey(const Key('reface-generate-angles')), findsNothing);
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
