import 'dart:io';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/features/reface/reface_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest(
    'Reface action stays visible with large text on a narrow phone',
    (tester, env) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );

      expect(find.text('Step 1 of 4'), findsOneWidget);
      expect(
        find.byKey(const Key('reface-next')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose and detect a photo, or choose a video.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('Reface going back preserves target selection', (tester, env) async {
    env.picker.photo = tinyPng;
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/reface')],
    );
    await pickRefaceTarget(tester);
    await tester.tap(find.byKey(const Key('reface-next')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-face-0')), findsOneWidget);
    expect(find.byKey(const Key('reface-next')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, session: testSession);

  appTest(
    'an unmatched library filter can be reset without leaving',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'redesign-photo');
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/library')],
      );
      await tester.ensureVisible(find.byKey(const Key('filter-failed')));
      await tester.tap(find.byKey(const Key('filter-failed')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('media-$media')), findsNothing);

      await tester.tap(find.byKey(const Key('library-clear-filters')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('media-$media')), findsOneWidget);
      expect(find.byKey(const Key('library-clear-filters')), findsNothing);
    },
    session: testSession,
  );

  appTest(
    'Reface keeps the video controller and trim when going back',
    (tester, env) async {
      final video = File('${env.tmp.path}/redesign-target.mp4');
      await tester.runAsync(() => video.writeAsBytes([1, 2, 3]));
      env.targetPicker = () async => RefaceTarget.video(video);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/reface')],
      );
      await tester.tap(find.byKey(const Key('reface-all-faces')));
      await pickRefaceTarget(tester);
      await tester.pumpAndSettle();
      final controller = env.trimController!;
      final range = find.byKey(const Key('reface-trim-range'));
      final slider = tester.widget<RangeSlider>(range);
      slider.onChanged!(RangeValues(12, slider.values.end));
      await tester.pumpAndSettle();
      // The trimmer handles one moved handle per gesture.
      tester.widget<RangeSlider>(range).onChanged!(const RangeValues(12, 24));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      expect(controller.didDispose, isFalse);
      await tester.tap(find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();

      expect(identical(env.trimController, controller), isTrue);
      expect(
        tester.widget<RangeSlider>(range).values,
        const RangeValues(12, 24),
      );
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest('an unmatched people search explains how to recover', (
    tester,
    env,
  ) async {
    final person = await seedPerson(env.db, name: 'Mariam');
    await seedFace(env.db, personId: person, seed: 1);
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/people')],
    );
    await tester.enterText(find.byKey(const Key('people-search')), 'no match');
    await tester.pumpAndSettle();
    expect(find.text('No people match your search'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear search'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('person-$person')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('people-search')))
          .controller!
          .text,
      isEmpty,
    );
  }, session: testSession);

  appTest(
    'training keeps advanced fields behind an explicit action',
    (tester, env) async {
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/lora/train')],
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const Key('train-submit')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const Key('train-advanced')));
      await tester.tap(find.byKey(const Key('train-advanced')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
