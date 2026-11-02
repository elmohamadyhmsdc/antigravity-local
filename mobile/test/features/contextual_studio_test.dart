import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/repositories/artifact_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

DetectedFace detected(BBox box) => DetectedFace(
  bbox: box,
  kps: const [],
  detScore: 1,
  embedding: Float32List(512),
  quality: const FaceQuality(
    score: 1,
    version: 1,
    parts: {},
    detScore: 1,
    facePx: 100,
    sharpness: 1,
    embeddingNorm: 1,
    pose: null,
  ),
  passesGate: true,
);
void main() {
  appTest(
    'selected target stays separate from Reface source identity',
    (tester, env) async {
      final source = await seedPerson(env.db, name: 'Source');
      final targetPerson = await seedPerson(env.db, name: 'Target');
      await seedFace(env.db, personId: source);
      final media = await seedMedia(env.db, asset: 'context-photo');
      await seedFace(
        env.db,
        personId: targetPerson,
        mediaId: media,
        x: .1,
        y: .1,
        w: .2,
        h: .2,
      );
      final detection =
          (await env.db.select(env.db.mediaDetections).get()).single;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => env.tmp.path);
      addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
      env.library.bytes['context-photo'] = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xff448866), ui.BlendMode.src);
        final image = await recorder.endRecording().toImage(32, 32);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return bytes!.buffer.asUint8List();
      }))!;
      env.api.analyzeResult = AnalyzeImageResponse(
        modelId: 'buffalo_l@1',
        imageW: 1000,
        imageH: 800,
        faces: [
          detected(const BBox(x: 100, y: 80, w: 200, h: 160)),
          detected(const BBox(x: 600, y: 80, w: 200, h: 160)),
        ],
        bodies: const [],
        pairs: const [],
      );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue(
            '/reface?person=$source&media=$media&target=${detection.id}',
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
        settle: false,
      );
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (env.api.analyzeCalls.isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Source'), findsWidgets);
      expect(find.text('Target'), findsNothing);
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-next')));
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if ((await env.db.select(env.db.jobs).get()).isNotEmpty) break;
      }
      final job = (await env.db.select(env.db.jobs).get()).single;
      final settings = await env.db.select(env.db.settings).get();
      final saved = settings
          .where((row) => row.key == 'artifact.context.${job.id}')
          .single;
      final relation = ArtifactContext.decode(saved.value)!;
      expect(
        (
          relation.mediaId,
          relation.detectionId,
          relation.personId,
          relation.targetPersonId,
        ),
        (media, detection.id, source, targetPerson),
      );
    },
    session: testSession,
  );
}
