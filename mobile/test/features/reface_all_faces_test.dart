import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart' show seedPerson, seedFace;
import 'reface_direct_identity_test.dart' show analysis, face, tapVisible;
import 'studio_test.dart' show next;

void main() {
  for (final video in [false, true]) {
    for (final profile in ['fast', 'balanced', 'detail']) {
      appTest(
        '$profile uses unified Reface for all ${video ? 'video' : 'photo'} faces without target analysis or selection',
        (tester, env) async {
          final person = await seedPerson(env.db, name: 'Source');
          await seedFace(env.db, personId: person, seed: 1);
          final target = File('${env.tmp.path}/target.mp4');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          const paths = MethodChannel('plugins.flutter.io/path_provider');
          messenger.setMockMethodCallHandler(paths, (_) async => env.tmp.path);
          addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
          final photo = video
              ? tinyPng
              : (await tester.runAsync(() async {
                  final recorder = ui.PictureRecorder();
                  ui.Canvas(
                    recorder,
                  ).drawColor(const Color(0xff448866), ui.BlendMode.src);
                  final image = await recorder.endRecording().toImage(32, 32);
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  image.dispose();
                  return data!.buffer.asUint8List();
                }))!;
          if (video) {
            await tester.runAsync(() => target.writeAsBytes([1, 2, 3]));
          }
          env.targetPicker = () async =>
              video ? RefaceTarget.video(target) : RefaceTarget.photo(photo);
          await env.pump(
            tester,
            extra: [
              initialLocationProvider.overrideWithValue(
                '/reface?person=$person',
              ),
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
          await tapVisible(tester, const Key('reface-all-faces'));
          await pickRefaceTarget(tester);
          await tester.pump(const Duration(milliseconds: 600));
          await tester.pumpAndSettle();
          expect(env.api.analyzeCalls, isEmpty);
          expect(env.sampledVideoRanges, isEmpty);
          expect(find.byKey(const Key('video-target-face-0')), findsNothing);
          expect(find.byKey(const Key('target-face-0')), findsNothing);
          await next(tester);
          await next(tester);
          if (profile != 'balanced') {
            final picker = find.byKey(const Key('reface-quality-profile'));
            await tester.ensureVisible(picker);
            await tester.tap(picker);
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(profile == 'fast' ? 'Fast' : 'More detail').last,
            );
            await tester.pumpAndSettle();
          }
          await next(tester);
          expect(find.text('Replace all faces'), findsWidgets);
          final submit = find.byKey(const Key('reface-next'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          await tester.tap(submit);
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump();
            if ((await env.db.select(env.db.jobs).get()).isNotEmpty) break;
          }
          final job = (await env.db.select(env.db.jobs).get()).single;
          final request = jsonDecode(job.requestJson) as Map;
          final params = request['params'] as Map;
          expect(request['type'], 'reface_${video ? 'video' : 'image'}');
          expect(params['quality_profile'], profile);
          expect(params['use_parser'], profile != 'fast');
          for (final selection in [
            'target_faces',
            'target_embeddings',
            'target_indices',
          ]) {
            expect(params.containsKey(selection), isFalse);
          }
          expect(params['source_faces'], hasLength(1));
          if (video) {
            expect(
              params['end_time'],
              greaterThan(params['start_time'] as num),
            );
          }
          expect(tester.takeException(), isNull);
        },
        session: testSession,
      );
    }
  }

  appTest(
    'turning all faces off analyses the photo and restores selection',
    (tester, env) async {
      env.targetPicker = () async => RefaceTarget.photo(tinyPng);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tapVisible(tester, const Key('reface-all-faces'));
      await pickRefaceTarget(tester);
      expect(env.api.analyzeCalls, isEmpty);
      await tapVisible(tester, const Key('reface-all-faces'));
      expect(env.api.analyzeCalls, hasLength(1));
      expect(find.byKey(const Key('target-face-0')), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'all faces cancels pending video discovery and selected mode rescans',
    (tester, env) async {
      env.targetPicker = () async =>
          RefaceTarget.video(File('${env.tmp.path}/target.mp4'));
      final pending = Completer<List<Uint8List>>();
      var samples = 0;
      env.videoSampler = (_, _, _) =>
          samples++ == 0 ? pending.future : Future.value([tinyPng]);
      env.api.analyzeHandler = (_, _) async => analysis([face(0)]);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tester.tap(find.byKey(const Key('reface-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-source-files')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(samples, 1);
      final toggle = find.byKey(const Key('reface-all-faces'));
      await tester.ensureVisible(toggle);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      pending.complete([tinyPng]);
      await tester.pumpAndSettle();
      expect(env.api.analyzeCalls, isEmpty);
      expect(find.byKey(const Key('reface-video-scan-status')), findsNothing);
      await tapVisible(tester, const Key('reface-all-faces'));
      expect(samples, 2);
      expect(find.byKey(const Key('video-target-face-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
