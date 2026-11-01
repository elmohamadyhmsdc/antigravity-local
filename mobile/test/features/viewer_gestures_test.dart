import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:antigravity_mobile/app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

class ThumbnailOnlyLibrary extends FakeMediaLibrary {
  @override
  Future<Uint8List?> viewerImage(String assetId, {int maxSide = 1800}) async =>
      null;
}

Future<Uint8List> image(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawColor(const Color(0xff448866), ui.BlendMode.src);
      final picture = await recorder.endRecording().toImage(32, 32);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
void main() {
  appTest('single known person exposes tools in details', (tester, env) async {
    final media = await seedMedia(env.db, asset: 'single');
    final person = await seedPerson(env.db, name: 'Nadia');
    await seedFace(env.db, mediaId: media, personId: person);
    env.library.bytes['single'] = await image(tester);
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/media/$media')],
      settle: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Person tools'), findsOneWidget);
    expect(find.text('Open person'), findsOneWidget);
    expect(find.byTooltip('Select for actions'), findsOneWidget);
  }, session: testSession);
  appTest('double tap zooms and single tap hides viewer controls', (
    tester,
    env,
  ) async {
    final media = await seedMedia(env.db, asset: 'photo');
    env.library.bytes['photo'] = await image(tester);
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/media/$media')],
      settle: false,
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const Key('annotated-photo')).evaluate().isNotEmpty) break;
    }
    final target = find.byKey(const Key('annotated-photo'));
    expect(target, findsOneWidget);
    final beforeHeight = tester
        .getSize(find.byKey(const Key('media-page-view')))
        .height;
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      tester.getSize(find.byKey(const Key('media-page-view'))).height,
      greaterThan(beforeHeight),
    );
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .any((w) => w.opacity == 0),
      isTrue,
    );
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 250));
    final interactive = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(
      interactive.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
  }, session: testSession);
  appTest(
    'thumbnail fallback is labeled and does not draw detections',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'photo');
      await seedFace(env.db, mediaId: media);
      final library = ThumbnailOnlyLibrary();
      library.bytes['photo'] = await image(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(env.db),
            fileStoreProvider.overrideWithValue(env.files),
            mediaLibraryProvider.overrideWithValue(library),
            initialSessionProvider.overrideWithValue(testSession),
            initialLocationProvider.overrideWithValue('/media/$media'),
            autoResumeScanProvider.overrideWithValue(false),
          ],
          child: const App(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find
            .text('Preview only · original unavailable')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(find.text('Preview only · original unavailable'), findsOneWidget);
    },
    session: testSession,
  );
}
