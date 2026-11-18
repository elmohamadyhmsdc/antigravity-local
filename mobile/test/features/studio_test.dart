import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/fixtures.dart';
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

  for (final video in [false, true]) {
    appTest(
      'Reface shows measured ${video ? 'video' : 'photo'} references and waits for approval',
      (tester, env) async {
        final caps = fixture('Capabilities.idle');
        (caps['engines'] as Map<String, dynamic>)['reface_pose_review'] = true;
        env.api.capabilities_ = Capabilities.fromJson(caps);
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(paths, (_) async => env.tmp.path);
        addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
        final person = await seedPerson(env.db, name: 'Sara');
        final other = await seedPerson(env.db, name: 'Other person');
        if (!video) await seedFace(env.db, personId: person, seed: 1);
        for (final (index, (id, owner)) in [
          ('wanted_model', person),
          ('newer_model', person),
          ('other_model', other),
        ].indexed) {
          await env.db
              .into(env.db.loras)
              .insert(
                LorasCompanion.insert(
                  id: id,
                  personId: Value(owner),
                  path: 'loras/$id.safetensors',
                  triggerWord: id,
                  createdAt: index + 1,
                ),
              );
        }
        if (video) {
          await env.db
              .into(env.db.datasets)
              .insert(
                DatasetsCompanion.insert(
                  id: 'training',
                  personId: Value(person),
                  triggerWord: 'wanted_model',
                  createdAt: 1,
                ),
              );
          await env.db
              .into(env.db.datasetItems)
              .insert(
                DatasetItemsCompanion.insert(
                  datasetId: 'training',
                  path: 'datasets/training/sample_face.jpg',
                  caption: 'wanted_model',
                ),
              );
          await env.db.putSetting(
            'artifact.context.wanted_model',
            jsonEncode(
              ArtifactContext(personId: person, datasetId: 'training').toJson(),
            ),
          );
        }
        final playable = File('${env.tmp.path}/reference.mp4');
        final png = (await tester.runAsync(() async {
          await env.files.write('loras/wanted_model.safetensors', tinyPng);
          if (video) {
            await playable.writeAsBytes([1, 2, 3, 4]);
            await env.files.write('datasets/training/sample_face.jpg', tinyPng);
          }
          final recorder = ui.PictureRecorder();
          ui.Canvas(
            recorder,
          ).drawColor(const Color(0xff448866), ui.BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(64, 64);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          picture.dispose();
          return data!.buffer.asUint8List();
        }))!;
        env.targetPicker = () async =>
            video ? RefaceTarget.video(playable) : RefaceTarget.photo(png);
        env.api.analyzeResult = AnalyzeImageResponse(
          modelId: 'buffalo_l@1',
          imageW: 300,
          imageH: 300,
          faces: [
            DetectedFace(
              bbox: const BBox(x: 10, y: 15, w: 140, h: 150),
              kps: const [],
              detScore: .9,
              embedding: unitVec(1),
              quality: FaceQuality(
                score: .9,
                version: 1,
                parts: const {},
                detScore: .9,
                facePx: 140,
                sharpness: 100,
                embeddingNorm: 1,
                pose: Pose(yaw: video ? -60 : 0, pitch: 0, roll: 0),
              ),
              passesGate: true,
            ),
          ],
          bodies: const [],
          pairs: const [],
        );
        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue('/reface?person=$person'),
            studioApiProvider.overrideWithValue(FakeStudioApi()),
            jobTrackerProvider.overrideWith((ref) {
              final tracker = JobTracker(
                repository: ref.read(studioRepositoryProvider),
                api: () => null,
                keepAlive: const NoKeepAlive(),
              );
              ref.onDispose(tracker.dispose);
              return tracker;
            }),
          ],
        );
        if (video) {
          await tester.tap(find.byKey(const Key('reface-all-faces')));
          await tester.pumpAndSettle();
        }
        await pickRefaceTarget(tester);
        await tester.pumpAndSettle();
        await next(tester);
        final picker = find.byKey(Key('reface-reference-model-$person'));
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(find.textContaining('newer_model'), findsOneWidget);
        expect(find.textContaining('other_model'), findsNothing);
        await tester.tap(find.textContaining('wanted_model').last);
        await tester.pumpAndSettle();
        await next(tester);
        final start = find.byKey(const Key('reface-next'));
        expect(find.text('Prepare and review references'), findsOneWidget);
        await tester.ensureVisible(start);
        await tester.tap(start);
        await settleAsync(tester);

        var jobs = await env.db.select(env.db.jobs).get();
        expect(
          jobs,
          hasLength(1),
          reason: find
              .byType(Text)
              .evaluate()
              .map((element) => (element.widget as Text).data)
              .whereType<String>()
              .join(' | '),
        );
        final audit = jobs.single;
        expect(audit.type, 'measure_reface_poses');
        final auditParams =
            (jsonDecode(audit.requestJson) as Map)['params'] as Map;
        expect(auditParams['media_kind'], video ? 'video' : 'image');
        expect(auditParams.containsKey('target_faces'), !video);
        final left = {'yaw': video ? -60 : 0, 'pitch': 0, 'roll': 0};
        final right = {'yaw': 60, 'pitch': 5, 'roll': -20};
        const posePath = 'results/test/poses.json';
        final report = jsonEncode({
          'total_frames': video ? 48 : 1,
          'decoded_frames': video ? 47 : 1,
          'unreadable_frames': video ? 1 : 0,
          'frames_without_pose': 0,
          'faces_without_pose': 0,
          'poses': [
            {...left, 'count': video ? 46 : 1, 'timestamp_ms': 0},
            if (video) {...right, 'count': 1, 'timestamp_ms': 700},
          ],
        });
        await tester.runAsync(
          () => env.files.write(
            posePath,
            Uint8List.fromList(utf8.encode(report)),
          ),
        );
        await (env.db.update(
          env.db.jobs,
        )..where((j) => j.id.equals(audit.id))).write(
          const JobsCompanion(
            status: Value('completed'),
            targetPath: Value(posePath),
          ),
        );
        await settleAsync(tester);
        jobs = await env.db.select(env.db.jobs).get();
        final generation = jobs.singleWhere((job) => job.id != audit.id);
        expect(generation.type, 'generate_lora_images');
        final generateParams =
            (jsonDecode(generation.requestJson) as Map)['params'] as Map;
        expect(generateParams['trigger_word'], 'wanted_model');
        expect(generateParams['head_poses'], [left, if (video) right]);
        expect(find.byKey(const Key('reface-angles-progress')), findsOneWidget);
        expect(tester.widget<FilledButton>(start).onPressed, isNull);

        const portrait = 'portraits/verified.png';
        await tester.runAsync(() => env.files.write(portrait, png));
        final portraitId = '${generation.id}-0';
        await env.db
            .into(env.db.results)
            .insert(
              ResultsCompanion.insert(
                id: portraitId,
                type: generation.type,
                path: portrait,
                originalPath: portrait,
                mime: 'image/png',
                sizeBytes: png.length,
                sha256: 'fixture',
                personId: Value(person),
                createdAt: 1,
              ),
            );
        await env.db.putSetting(
          'artifact.context.$portraitId',
          jsonEncode(
            ArtifactContext(personId: person, modelId: 'wanted_model').toJson(),
          ),
        );
        await (env.db.update(env.db.jobs)
              ..where((j) => j.id.equals(generation.id)))
            .write(const JobsCompanion(status: Value('completed')));
        await settleAsync(tester);
        jobs = await env.db.select(env.db.jobs).get();
        expect(jobs, hasLength(2), reason: 'Reface waits for approval');
        expect(find.text('Review Reface references'), findsOneWidget);
        expect(
          find.text(
            video
                ? '1 of 2 measured angle groups covered'
                : '1 of 1 measured angle groups covered',
          ),
          findsOneWidget,
        );
        if (video) expect(find.text('Unreadable frames (1)'), findsOneWidget);
        await tester.pageBack();
        await settleAsync(tester);
        expect(await env.db.select(env.db.jobs).get(), hasLength(2));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await settleAsync(tester);
        await tester.tap(find.byKey(const Key('reface-approve-poses')));
        await settleAsync(tester);
        jobs = await env.db.select(env.db.jobs).get();
        final render = jobs.singleWhere(
          (job) => job.type == (video ? 'reface_video' : 'reface_image'),
        );
        expect(render.type, video ? 'reface_video' : 'reface_image');
        final request = jsonDecode(render.requestJson) as Map;
        final params = request['params'] as Map;
        expect(params['source_faces'], hasLength(2));
        expect(
          (params['source_faces'] as List).last,
          containsPair('generated', true),
        );
        if (video) {
          expect(params['start_time'], 0);
          expect(env.sampledVideoRanges, isEmpty);
        }
      },
      session: testSession,
    );
  }

  appTest('no LoRA leaves the gallery reference workflow in place', (
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
    expect(find.text('Face references'), findsNothing);
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
