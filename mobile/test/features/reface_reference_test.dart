import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> acceptExperimental(WidgetTester tester) async {
  final next = find.byKey(const Key('reface-next'));
  expect(tester.widget<FilledButton>(next).onPressed, isNull);
  final consent = find.byKey(const Key('reface-experimental-consent'));
  expect(tester.widget<CheckboxListTile>(consent).value, isFalse);
  await tester.ensureVisible(consent);
  await tester.tap(consent);
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'choosing a character source after replace-all restores explicit target selection',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Hero');
      await (env.db.update(env.db.persons)..where((p) => p.id.equals(person)))
          .write(const PersonsCompanion(kind: Value('character')));
      final face = await seedFace(
        env.db,
        personId: person,
        embedding: Float32List(768)..[1] = 1,
      );
      await (env.db.update(
        env.db.faces,
      )..where((f) => f.id.equals(face))).write(
        const FacesCompanion(
          kind: Value('character'),
          modelId: Value(characterEmbeddingModelId),
        ),
      );
      env.picker.photo = tinyPng;
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tester.tap(find.byKey(const Key('reface-all-faces')));
      await tester.pumpAndSettle();
      await pickRefaceTarget(tester);
      await tester.ensureVisible(find.byKey(const Key('reface-next')));
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reface-person')));
      await tester.tap(find.byKey(const Key('reface-person')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hero'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Back').last);
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('reface-all-faces')))
            .value,
        isFalse,
      );
      expect(find.byKey(const Key('target-face-0')), findsOneWidget);
    },
    session: testSession,
  );
  appTest(
    'character target photo uses its explicitly selected normalized face box',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Alice');
      final source = await seedFace(
        env.db,
        personId: person,
        cropPath: 'faces/alice.jpg',
      );
      await tester.runAsync(() => env.files.write('faces/alice.jpg', tinyPng));
      final image = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xff778899), ui.BlendMode.src);
        final rendered = await recorder.endRecording().toImage(32, 32);
        final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
        rendered.dispose();
        return data!.buffer.asUint8List();
      }))!;
      env.picker.photo = image;
      env.api.analyzeResult = AnalyzeImageResponse(
        modelId: 'buffalo_l@1',
        imageW: 1000,
        imageH: 800,
        faces: const [],
        bodies: const [],
        pairs: const [],
        characters: [
          DetectedCharacter(
            bbox: const BBox(x: 100, y: 80, w: 200, h: 300),
            score: .9,
            descriptor: const [],
            face: CharacterFace(
              bbox: const BBox(x: 150, y: 100, w: 100, h: 160),
              score: .9,
              embedding: Float32List(768)..[2] = 1,
              cropJpeg: image,
            ),
          ),
        ],
      );
      final json = fixture('Capabilities.idle');
      json['operations'] = [
        for (final kind in ['person', 'character'])
          {
            'operation': 'reface_reference',
            'kind': kind,
            'media_types': ['photo', 'video'],
            'available': true,
            'engine': 'reference',
            'experimental': true,
            'identity_models': [],
          },
      ];
      env.api.capabilities_ = Capabilities.fromJson(json);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => env.tmp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
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
      await tester.tap(find.byKey(const Key('reface-target-kind-person')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anime character').last);
      await tester.pumpAndSettle();
      await pickRefaceTarget(tester);
      await tester.ensureVisible(find.byKey(const Key('target-face-0')));
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('reference-source-face')),
      );
      await tester.tap(find.byKey(const Key('reference-source-face')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Face $source').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reface-next')));
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      await acceptExperimental(tester);
      await tester.ensureVisible(find.byKey(const Key('reface-next')));
      await tester.tap(find.byKey(const Key('reface-next')));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final job = (await env.db.select(env.db.jobs).get()).single;
      final params =
          (jsonDecode(job.requestJson) as Map<String, dynamic>)['params']
              as Map<String, dynamic>;
      expect(params['source_kind'], 'person');
      expect(params['target_kind'], 'character');
      final box =
          ((params['target_regions'] as List).single['boxes'] as List).single
              as Map<String, dynamic>;
      expect(box, {'x': .15, 'y': .125, 'w': .1, 'h': .2});
    },
    session: testSession,
  );
  for (final characterTarget in [false, true]) {
    appTest(
      'reference video preserves ${characterTarget ? 'character' : 'human'} target embedding without converting CCIP source',
      (tester, env) async {
        final person = await seedPerson(env.db, name: 'Hero');
        await (env.db.update(env.db.persons)..where((p) => p.id.equals(person)))
            .write(const PersonsCompanion(kind: Value('character')));
        final source = await seedFace(
          env.db,
          personId: person,
          embedding: Float32List(768)..[1] = 1,
          cropPath: 'faces/hero.jpg',
        );
        await (env.db.update(
          env.db.faces,
        )..where((f) => f.id.equals(source))).write(
          const FacesCompanion(
            kind: Value('character'),
            modelId: Value(characterEmbeddingModelId),
          ),
        );
        final video = File('${env.tmp.path}/target.mp4');
        await tester.runAsync(() async {
          await video.writeAsBytes([1, 2, 3]);
          await env.files.write('faces/hero.jpg', tinyPng);
        });
        env.targetPicker = () async => RefaceTarget.video(video);
        if (characterTarget) {
          env.api.analyzeResult = AnalyzeImageResponse(
            modelId: 'buffalo_l@1',
            imageW: 1000,
            imageH: 800,
            faces: const [],
            bodies: const [],
            pairs: const [],
            characters: [
              DetectedCharacter(
                bbox: const BBox(x: 100, y: 80, w: 200, h: 300),
                score: .9,
                descriptor: const [],
                face: CharacterFace(
                  bbox: const BBox(x: 150, y: 100, w: 100, h: 160),
                  score: .9,
                  embedding: Float32List(768)..[2] = 1,
                ),
              ),
            ],
          );
        }
        final json = fixture('Capabilities.idle');
        json['operations'] = [
          for (final kind in ['person', 'character'])
            {
              'operation': 'reface_reference',
              'kind': kind,
              'media_types': ['photo', 'video'],
              'available': true,
              'engine': 'reference',
              'experimental': true,
              'identity_models': [],
            },
        ];
        env.api.capabilities_ = Capabilities.fromJson(json);
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
        if (characterTarget) {
          await tester.tap(find.byKey(const Key('reface-target-kind-person')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Anime character').last);
          await tester.pumpAndSettle();
        }
        await pickRefaceTarget(tester);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('video-target-face-0')),
        );
        await tester.tap(find.byKey(const Key('video-target-face-0')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('reface-next')));
        await tester.tap(find.byKey(const Key('reface-next')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('reference-source-face')),
        );
        await tester.tap(find.byKey(const Key('reference-source-face')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Face $source').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('reface-next')));
        await tester.tap(find.byKey(const Key('reface-next')));
        await tester.pumpAndSettle();
        await acceptExperimental(tester);
        await tester.ensureVisible(find.byKey(const Key('reface-next')));
        await tester.tap(find.byKey(const Key('reface-next')));
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        final job = (await env.db.select(env.db.jobs).get()).single;
        expect(job.type, 'reface_video_reference');
        final request = jsonDecode(job.requestJson) as Map<String, dynamic>;
        final params = request['params'] as Map<String, dynamic>;
        expect(params['source_kind'], 'character');
        expect(params['target_kind'], characterTarget ? 'character' : 'person');
        final target = params['target_identity'] as Map<String, dynamic>;
        expect(
          target['model_id'],
          characterTarget ? characterEmbeddingModelId : 'buffalo_l@1',
        );
        final dim = characterTarget ? 768 : 512;
        expect(
          decodeVector(target['embedding'] as String, dim),
          hasLength(dim),
        );
        expect(params['end_time'], greaterThan(params['start_time'] as num));
      },
      session: testSession,
    );
  }
  for (final capable in [false, true]) {
    appTest(
      'character source uses explicit pixels and ${capable ? 'queues reference photo' : 'blocks legacy PC'}',
      (tester, env) async {
        final person = await seedPerson(env.db, name: 'Hero');
        await (env.db.update(env.db.persons)..where((p) => p.id.equals(person)))
            .write(const PersonsCompanion(kind: Value('character')));
        final source = await seedFace(
          env.db,
          personId: person,
          embedding: Float32List(768)..[1] = 1,
          cropPath: 'faces/hero.jpg',
        );
        await (env.db.update(
          env.db.faces,
        )..where((f) => f.id.equals(source))).write(
          const FacesCompanion(
            kind: Value('character'),
            modelId: Value(characterEmbeddingModelId),
          ),
        );
        Future<Uint8List> picture(int color) async => (await tester.runAsync(
          () async {
            final recorder = ui.PictureRecorder();
            ui.Canvas(recorder).drawColor(Color(color), ui.BlendMode.src);
            final image = await recorder.endRecording().toImage(32, 32);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return data!.buffer.asUint8List();
          },
        ))!;
        final crop = await picture(0xff224488);
        await tester.runAsync(() => env.files.write('faces/hero.jpg', crop));
        env.picker.photo = await picture(0xff886622);
        if (capable) {
          final json = fixture('Capabilities.idle');
          json['operations'] = [
            for (final kind in ['person', 'character'])
              {
                'operation': 'reface_reference',
                'kind': kind,
                'media_types': ['photo', 'video'],
                'available': true,
                'engine': 'reference',
                'experimental': true,
                'identity_models': [],
              },
          ];
          env.api.capabilities_ = Capabilities.fromJson(json);
        }
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        messenger.setMockMethodCallHandler(paths, (_) async => env.tmp.path);
        addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
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
        await pickRefaceTarget(tester);
        await tester.ensureVisible(find.byKey(const Key('target-face-0')));
        await tester.tap(find.byKey(const Key('target-face-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reface-next')));
        await tester.pumpAndSettle();
        final reference = find.byKey(const Key('reference-source-face'));
        await tester.ensureVisible(reference);
        await tester.tap(reference);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Face $source').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('reface-next')));
        await tester.tap(find.byKey(const Key('reface-next')));
        await tester.pumpAndSettle();
        await acceptExperimental(tester);
        await tester.ensureVisible(find.byKey(const Key('reface-next')));
        await tester.tap(find.byKey(const Key('reface-next')));
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        final jobs = await env.db.select(env.db.jobs).get();
        if (!capable) {
          expect(jobs, isEmpty);
          expect(find.textContaining('Update the PC server'), findsWidgets);
        } else {
          final job = jobs.single;
          expect(job.type, 'reface_image_reference');
          final request = jsonDecode(job.requestJson) as Map<String, dynamic>;
          final params = request['params'] as Map<String, dynamic>;
          expect(params['source_kind'], 'character');
          expect(params['target_kind'], 'person');
          expect(params['experimental_acknowledged'], isTrue);
          expect((params['target_regions'] as List).single['frame'], 0);
          final inputs = request['inputs'] as Map<String, dynamic>;
          final files = jsonDecode(job.inputFiles) as Map<String, dynamic>;
          final staged = await tester.runAsync(
            () => env.files
                .resolve(files[inputs['source_reference']] as String)
                .readAsBytes(),
          );
          expect(staged, crop);
        }
      },
      session: testSession,
    );
  }
}
