import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/reface/reface_faces.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:antigravity_mobile/studio_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/job_tracker_test.dart' show FakeStudioApi;
import '../support/fakes.dart';
import '../support/harness.dart';
import 'studio_test.dart' show next;

DetectedFace face(int person, {int? variation, double quality = .8}) {
  final vector = Float32List(512)..[person] = variation == null ? 1 : .8;
  if (variation != null) vector[variation] = .6;
  return DetectedFace(
    bbox: const BBox(x: 0, y: 0, w: 32, h: 32),
    kps: const [],
    detScore: .99,
    embedding: vector,
    quality: FaceQuality(
      score: quality,
      version: 2,
      parts: const {},
      detScore: .99,
      facePx: 128,
      sharpness: 150,
      embeddingNorm: 22,
      pose: const Pose(yaw: 0, pitch: 0, roll: 0),
    ),
    passesGate: true,
    cropJpeg: tinyPng,
  );
}

AnalyzeImageResponse analysis(List<DetectedFace> faces) => AnalyzeImageResponse(
  modelId: 'buffalo_l@1',
  imageW: 32,
  imageH: 32,
  faces: faces,
  bodies: const [],
  pairs: const [],
);

Future<void> tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'different poses across frames use one identity instead of one identity per frame',
    () {
      DetectedFace pose(int person, int axis) {
        final original = face(person);
        return DetectedFace(
          bbox: original.bbox,
          kps: original.kps,
          detScore: .99,
          embedding: Float32List(512)
            ..[person] = .46
            ..[axis] = math.sqrt(1 - .46 * .46),
          quality: original.quality,
          passesGate: true,
          cropJpeg: tinyPng,
        );
      }

      final groups = <RefaceFaceGroup>[];
      mergeRefaceFaces(groups, [face(0), face(1)]);
      for (var frame = 0; frame < 8; frame++) {
        mergeRefaceFaces(groups, [pose(0, 20 + frame), pose(1, 40 + frame)]);
      }
      expect(groups, hasLength(2));
      expect(groups.map((group) => group.appearances), [9, 9]);
      expect(groups.every((group) => group.samples.length > 1), isTrue);
    },
  );

  test(
    'a clear view consolidates fragmented identities and preserves the selected person',
    () {
      final original = face(0);
      DetectedFace vector(double a, double b) => DetectedFace(
        bbox: original.bbox,
        kps: original.kps,
        detScore: .99,
        embedding: Float32List(512)
          ..[0] = a
          ..[1] = b,
        quality: original.quality,
        passesGate: true,
      );
      final groups = [
        RefaceFaceGroup(original)..frames.add(-10),
        RefaceFaceGroup(vector(.45, math.sqrt(1 - .45 * .45)))..frames.add(-11),
      ];
      final selected = {1};
      final a = 1 + .45, b = math.sqrt(1 - .45 * .45);
      final length = math.sqrt(a * a + b * b);
      mergeRefaceFaces(groups, [
        vector(a / length, b / length),
      ], selected: selected);
      expect(groups, hasLength(1));
      expect(selected, {0});
      expect(groups.single.appearances, 3);
    },
  );

  test(
    'lookalikes seen together cannot be consolidated even on later frames',
    () {
      final a = face(0), b = face(0, variation: 1);
      final groups = <RefaceFaceGroup>[];
      mergeRefaceFaces(groups, [a, b]);
      for (var i = 0; i < 5; i++) {
        mergeRefaceFaces(groups, [a, b]);
      }
      expect(groups, hasLength(2));
      expect(groups[0].cooccurs(groups[1]), isTrue);
      expect(groups.map((group) => group.appearances), [6, 6]);
      final copy = groups.map(RefaceFaceGroup.copy).toList();
      mergeRefaceFaces(copy, [a]);
      expect(copy, hasLength(2));
    },
  );

  appTest(
    'a failed video scan explains the error beside the retry button and retry finds faces',
    (tester, env) async {
      final video = File('${env.tmp.path}/video.mp4');
      env.targetPicker = () async => RefaceTarget.video(video);
      var attempts = 0;
      env.videoSampler = (_, _, _) async {
        if (attempts++ == 0) {
          throw PlatformException(
            code: 'video_frames_failed',
            message: 'This video could not be read. Choose it again.',
          );
        }
        return [tinyPng];
      };
      env.api.analyzeHandler = (_, _) async => analysis([face(0)]);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await pickRefaceTarget(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('reface-video-scan-error')))
            .data,
        'This video could not be read. Choose it again.',
      );
      await tapVisible(tester, const Key('reface-detect-video-faces'));
      expect(find.byKey(const Key('video-target-face-0')), findsOneWidget);
      expect(find.byKey(const Key('reface-video-scan-error')), findsNothing);
      expect(attempts, 2);
    },
    session: testSession,
  );

  appTest(
    'an empty clip scan can find the face actually shown in the preview',
    (tester, env) async {
      final video = File('${env.tmp.path}/video.mp4');
      env.targetPicker = () async => RefaceTarget.video(video);
      env.videoSampler = (_, start, _) async => [
        Uint8List.fromList([
          ...tinyPng,
          start == const Duration(seconds: 25) ? 20 : 10,
        ]),
      ];
      env.api.analyzeHandler = (bytes, _) async =>
          analysis(bytes.last == 20 ? [face(0)] : []);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await pickRefaceTarget(tester);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video-target-face-0')), findsNothing);
      final controller = env.trimController!;
      controller.value = controller.value.copyWith(
        position: const Duration(seconds: 25),
      );
      await tester.pump();
      await tapVisible(tester, const Key('reface-detect-current-frame'));
      expect(env.sampledVideoRanges.last.start, const Duration(seconds: 25));
      expect(env.sampledVideoRanges.last.count, 1);
      expect(find.byKey(const Key('video-target-face-0')), findsOneWidget);
      expect(find.text('1 person found in this clip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  test(
    'video reference poses and selected indices stay inside the API limit',
    () {
      final groups = [
        for (var person = 0; person < 16; person++)
          RefaceFaceGroup(face(person))
            ..add(face(person, variation: 100))
            ..add(face(person, variation: 101)),
      ];
      final encoded = encodeVideoTargetSelection(groups, {4, 15});
      expect(encoded['target_embeddings'], hasLength(32));
      expect(encoded['target_indices'], [8, 9, 30, 31]);
      for (final index in encoded['target_indices'] as List<int>) {
        final vector = decodeEmbedding(
          (encoded['target_embeddings'] as List)[index] as String,
        );
        expect(vector[index < 30 ? 4 : 15], greaterThanOrEqualTo(.79));
      }
    },
  );

  test(
    'repeated video people group together, but two faces in one frame remain distinct',
    () {
      final groups = <RefaceFaceGroup>[];
      mergeRefaceFaces(groups, [face(0), face(1)]);
      mergeRefaceFaces(groups, [
        face(1, variation: 10),
        face(0, variation: 11),
      ]);
      expect(groups, hasLength(2));
      expect(groups[0].samples, hasLength(2));
      expect(groups[1].samples, hasLength(2));
      mergeRefaceFaces(groups, [face(0), face(0)]);
      expect(groups, hasLength(3));
    },
  );

  test('ambiguous identity evidence stays independently selectable', () {
    final groups = <RefaceFaceGroup>[];
    mergeRefaceFaces(groups, [face(0), face(1)]);
    final ambiguous = face(0, variation: 1);
    mergeRefaceFaces(groups, [ambiguous]);
    // .8 versus .6 has a clear margin, so it matches person 0.
    expect(groups, hasLength(2));
    groups.clear();
    mergeRefaceFaces(groups, [face(0), face(1)]);
    final template = face(2);
    final equal = DetectedFace(
      bbox: template.bbox,
      kps: template.kps,
      detScore: .99,
      embedding: Float32List(512)
        ..[0] = .70710678
        ..[1] = .70710678,
      quality: template.quality,
      passesGate: true,
    );
    mergeRefaceFaces(groups, [equal]);
    expect(groups, hasLength(3));
  });

  test(
    'source pools remove duplicates, keep the best quality and stay bounded',
    () {
      final group = RefaceFaceGroup(face(0, quality: .3));
      group.add(face(0, quality: .9));
      expect(group.samples, hasLength(1));
      expect(group.representative.quality.score, .9);
      for (var i = 1; i < 40; i++) {
        group.add(face(0, variation: i));
      }
      expect(group.samples, hasLength(20));
      expect(group.encode(), hasLength(20));
      expect(
        decodeEmbedding(group.encode().first['embedding'] as String)[0],
        1,
      );
      expect(group.encode().first['pose'], {
        'yaw': 0.0,
        'pitch': 0.0,
        'roll': 0.0,
      });
    },
  );

  appTest(
    'video targets and mixed gallery sources submit distinct selected identities without library people',
    (tester, env) async {
      final target = File('${env.tmp.path}/target.mp4');
      final sourcePhoto = File('${env.tmp.path}/source1.png');
      final sourcePhoto2 = File('${env.tmp.path}/source2.png');
      final sourceVideo = File('${env.tmp.path}/source.mp4');
      await tester.runAsync(() async {
        await target.writeAsBytes([1, 2, 3]);
        await sourcePhoto.writeAsBytes([...tinyPng, 30]);
        await sourcePhoto2.writeAsBytes([...tinyPng, 31]);
        await sourceVideo.writeAsBytes([4, 5, 6]);
      });
      env.targetPicker = () async => RefaceTarget.video(target);
      env.sourceMedia = [
        XFile.fromData(
          Uint8List.fromList([...tinyPng, 30]),
          mimeType: 'image/png',
          name: 'source1.png',
        ),
        XFile.fromData(
          Uint8List.fromList([...tinyPng, 31]),
          mimeType: 'image/png',
          name: 'source2.png',
        ),
        XFile(sourceVideo.path),
      ];
      env.videoSampler = (file, start, end) async => [
        Uint8List.fromList([...tinyPng, file.path == target.path ? 10 : 32]),
      ];
      env.api.analyzeHandler = (bytes, _) async =>
          analysis(switch (bytes.last) {
            10 => [face(0), face(1)],
            30 => [face(2)],
            31 => [face(2, variation: 10), face(3)],
            _ => [face(2, variation: 11)],
          });
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/reface'),
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
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reface-reference')), findsNothing);
      await tapVisible(tester, const Key('video-target-face-1'));
      await next(tester);
      await tapVisible(tester, const Key('reface-source-media'));
      await tester.tap(find.byKey(const Key('reface-source-gallery')));
      await tester.pumpAndSettle();
      await next(tester);
      expect(
        find.text('Choose a source person and at least one face.'),
        findsOneWidget,
      );
      await tapVisible(tester, const Key('imported-source-face-0'));
      await next(tester);
      await next(tester);
      await tester.ensureVisible(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-next')));
      // File staging runs on real filesystem IO, so let asynchronous work settle.
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        final jobs = await env.db.select(env.db.jobs).get();
        if (jobs.isNotEmpty) break;
      }
      final job = (await env.db.select(env.db.jobs).get()).single;
      await tester.pumpAndSettle();
      final request = jsonDecode(job.requestJson) as Map;
      final params = request['params'] as Map;
      expect(request['type'], 'reface_video_v3');
      expect(params['target_faces'], isNull);
      expect(params['target_indices'], [1]);
      expect(
        decodeEmbedding((params['target_embeddings'] as List)[1] as String)[1],
        1,
      );
      final sources = params['source_faces'] as List;
      expect(sources, hasLength(3));
      expect(
        sources.every(
          (row) => decodeEmbedding(row['embedding'] as String)[2] >= .79,
        ),
        isTrue,
      );
      expect(job.personId, isNull);
      expect(await env.db.select(env.db.persons).get(), isEmpty);
      expect(env.sampledVideoRanges.map((request) => request.path), [
        target.path,
        sourceVideo.path,
      ]);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'changing the trim discards old targets and rejects late scan results',
    (tester, env) async {
      final video = File('${env.tmp.path}/target.mp4');
      env.targetPicker = () async => RefaceTarget.video(video);
      final first = Completer<List<Uint8List>>();
      env.videoSampler = (file, start, end) =>
          start == Duration.zero ? first.future : Future.value([tinyPng]);
      env.api.analyzeHandler = (_, _) async => analysis([face(1)]);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tester.tap(find.byKey(const Key('reface-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-source-files')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final slider = tester.widget<RangeSlider>(
        find.byKey(const Key('reface-trim-range')),
      );
      slider.onChanged!(const RangeValues(10, 1800));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('video-target-face-0')), findsOneWidget);
      final calls = env.api.analyzeCalls.length;
      first.complete([
        Uint8List.fromList([...tinyPng, 99]),
      ]);
      await tester.pumpAndSettle();
      expect(env.api.analyzeCalls, hasLength(calls));
      expect(env.sampledVideoRanges.last.start, const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
