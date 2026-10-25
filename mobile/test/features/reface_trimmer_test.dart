import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:antigravity_mobile/app.dart' show initialLocationProvider;
import 'package:antigravity_mobile/features/reface/reface_video_trimmer.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../support/fake_video_controller.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

Widget preview(
  FakeTrimVideoController controller,
  ValueChanged<VideoTrimSelection> changed, {
  bool active = true,
}) => ProviderScope(
  overrides: [
    refaceVideoControllerProvider.overrideWithValue((_) => controller),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: RefaceVideoTrimmer(
            file: File('fixture.mp4'),
            active: active,
            onChanged: changed,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test(
    'time labels and transport values support minutes and hours without manual arithmetic',
    () {
      expect(trimTime(const Duration(minutes: 25, seconds: 25)), '25:25');
      expect(
        trimTime(const Duration(hours: 1, minutes: 25, seconds: 25)),
        '1:25:25',
      );
      const selection = VideoTrimSelection(
        start: Duration(minutes: 25, seconds: 25),
        end: Duration(minutes: 26, seconds: 25),
        duration: Duration(minutes: 30),
      );
      expect(selection.startSeconds, 1525);
      expect(selection.endSeconds, 1585);
    },
  );

  test(
    'combined picker recognises videos and HEIC photos even without a filename extension',
    () async {
      final tmp = await Directory.systemTemp.createTemp('reface-media_');
      try {
        final mp4 = File('${tmp.path}/mp4-cache');
        final heic = File('${tmp.path}/heic-cache');
        await mp4.writeAsBytes([0, 0, 0, 24, ...ascii.encode('ftypmp42')]);
        await heic.writeAsBytes([0, 0, 0, 24, ...ascii.encode('ftypheic')]);
        expect(await isVideoTarget(XFile(mp4.path)), isTrue);
        expect(await isVideoTarget(XFile(heic.path)), isFalse);
        expect(await isVideoTarget(XFile('cached.mov')), isTrue);
        expect(await isVideoTarget(XFile('cached.jpg')), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    },
  );

  appTest(
    'one target button offers Gallery and Files, preserving the target on cancellation',
    (tester, env) async {
      final file = File('${env.tmp.path}/clip.mp4');
      await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
      var picks = 0;
      env.targetPicker = () async =>
          picks++ == 0 ? RefaceTarget.photo(tinyPng) : RefaceTarget.video(file);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      expect(find.byKey(const Key('reface-target')), findsOneWidget);
      expect(find.text('Choose photo or video'), findsOneWidget);
      expect(find.text('Choose a photo'), findsNothing);
      expect(find.text('Choose a video'), findsNothing);
      await pickRefaceTarget(tester, source: 'gallery');
      await tester.pumpAndSettle();
      expect(env.lastTargetSource, RefaceMediaSource.gallery);
      expect(find.byKey(const Key('target-face-0')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('reface-target')));
      await tester.tap(find.byKey(const Key('reface-target')));
      await tester.pumpAndSettle();
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(picks, 1);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(find.byKey(const Key('target-face-0')), findsOneWidget);
      await pickRefaceTarget(tester);
      expect(env.lastTargetSource, RefaceMediaSource.files);
      expect(picks, 2);
      expect(find.byKey(const Key('reface-trim-range')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('target-face-0')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  testWidgets(
    'moving either trim handle seeks the preview and updates readable boundaries',
    (tester) async {
      final controller = FakeTrimVideoController(File('fixture.mp4'));
      VideoTrimSelection? selected;
      await tester.pumpWidget(preview(controller, (value) => selected = value));
      await tester.pumpAndSettle();
      var slider = tester.widget<RangeSlider>(
        find.byKey(const Key('reface-trim-range')),
      );
      slider.onChanged!(const RangeValues(1525, 1800));
      await tester.pumpAndSettle();
      expect(selected!.startSeconds, 1525);
      expect(find.text('25:25'), findsOneWidget);
      expect(controller.seeks.last, const Duration(minutes: 25, seconds: 25));
      slider = tester.widget<RangeSlider>(
        find.byKey(const Key('reface-trim-range')),
      );
      slider.onChanged!(const RangeValues(1525, 1585));
      await tester.pumpAndSettle();
      expect(selected!.endSeconds, 1585);
      expect(find.text('26:25'), findsOneWidget);
      expect(controller.seeks.last.inMilliseconds, 1584999);
      expect(find.text('Selected clip: 1:00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reface-start-earlier')));
      await tester.pumpAndSettle();
      expect(selected!.startSeconds, 1524);
      expect(controller.seeks.last.inSeconds, 1524);
    },
  );

  testWidgets(
    'dragging the start thumb works on a narrow phone and cannot invert the clip',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = FakeTrimVideoController(File('fixture.mp4'));
      VideoTrimSelection? selected;
      await tester.pumpWidget(preview(controller, (value) => selected = value));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const Key('reface-trim-range')));
      final drag = await tester.startGesture(
        Offset(rect.left + 24, rect.center.dy),
      );
      await drag.moveBy(const Offset(70, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(selected!.startSeconds, greaterThan(0));
      expect(controller.seeks, isNotEmpty);
      final slider = tester.widget<RangeSlider>(
        find.byKey(const Key('reface-trim-range')),
      );
      slider.onChanged!(const RangeValues(1799.9, 1800));
      await tester.pumpAndSettle();
      expect(
        selected!.endSeconds - selected!.startSeconds,
        greaterThanOrEqualTo(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'playback stays inside the chosen clip and pauses when its step is hidden',
    (tester) async {
      final controller = FakeTrimVideoController(File('fixture.mp4'));
      await tester.pumpWidget(preview(controller, (_) {}));
      await tester.pumpAndSettle();
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(10, 1800),
      );
      await tester.pumpAndSettle();
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(10, 20),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-trim-play')));
      await tester.pumpAndSettle();
      expect(controller.value.isPlaying, isTrue);
      expect(controller.value.position.inSeconds, 10);
      controller.value = controller.value.copyWith(
        position: const Duration(seconds: 21),
        isPlaying: true,
      );
      await tester.pumpAndSettle();
      expect(controller.value.isPlaying, isFalse);
      expect(controller.value.position.inMilliseconds, 19999);
      await controller.play();
      await tester.pumpWidget(preview(controller, (_) {}, active: false));
      await tester.pumpAndSettle();
      expect(controller.value.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(controller.didDispose, isTrue);
    },
  );
}
