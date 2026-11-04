// Roadmap Phase 6 UI: marking a tattoo, a person's Tattoos screen, the search, Quick Review suggestions,
// and the real patch cutter on a generated picture.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart'
    show AnalyzeMarksResponse, MarkMatchDto;
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/marks/body_marks.dart';
import 'package:antigravity_mobile/domain/marks/mark_geometry.dart';
import 'package:antigravity_mobile/domain/marks/patch_cutter.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

const standing = <List<double>>[
  [500, 300],
  [530, 280],
  [470, 280],
  [560, 290],
  [440, 290],
  [650, 400],
  [350, 400],
  [670, 550],
  [330, 550],
  [680, 700],
  [320, 700],
  [560, 800],
  [440, 800],
  [560, 1050],
  [440, 1050],
  [560, 1300],
  [440, 1300],
];

String kpts(List<List<double>> pts) => jsonEncode([
  for (final p in pts) [p[0] / 1000, p[1] / 1500, 0.9],
]);

Future<int> bodyWith(
  AppDatabase db,
  int media, {
  int? person,
  bool crop = true,
}) async {
  final id = await seedBody(
    db,
    mediaId: media,
    personId: person,
    linkMethod: person == null ? null : 'manual',
    cropPath: crop ? 'bodies/x.jpg' : null,
  );
  await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
    BodiesCompanion(kpts: Value(kpts(standing)), extent: const Value('full')),
  );
  return id;
}

final cut = Uint8List.fromList([7, 7, 7]);
Future<Uint8List?> fakeCutter(MediaRow media, MarkRect rect) async => cut;

void main() {
  appTest(
    'marking a tattoo stores the area, its position and the patch for the body\'s person',
    (tester, env) async {
      final lina = await seedPerson(env.db, name: 'Lina');
      final media = await seedMedia(
        env.db,
        asset: 'm',
        width: 1000,
        height: 1500,
      );
      final body = await bodyWith(env.db, media, person: lina);
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/bodies'),
          patchCutterProvider.overrideWithValue(fakeCutter),
        ],
      );
      await tester.tap(find.byKey(Key('body-$body')));
      await tester.pumpAndSettle();
      await expandActionSections(tester);
      await tester.ensureVisible(find.byKey(const Key('action-mark-tattoo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-mark-tattoo')));
      await tester.pumpAndSettle();
      expect(find.text('Mark a tattoo'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('mark-save')))
            .onPressed,
        isNull,
        reason: 'place it first',
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('mark-picture'))),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('mark-save')));
      await _real(tester);

      final mark = await env.db.select(env.db.bodyMarks).getSingle();
      expect(
        (mark.personId, mark.sourceBodyId, mark.segment),
        (lina, body, 'r_upper_arm'),
      );
      expect(mark.patchPath, 'marks/${mark.id}.png');
      expect(
        await tester.runAsync(
          () => env.files.resolve(mark.patchPath).readAsBytes(),
        ),
        cut,
      );
      expect(mark.anchor, contains('"c"'));
      expect(
        find.text('Tattoo saved. Search for it from the person\'s page.'),
        findsOneWidget,
      );
    },
    session: testSession,
  );

  appTest('a body nobody owns cannot be marked, and says why', (
    tester,
    env,
  ) async {
    final media = await seedMedia(
      env.db,
      asset: 'm',
      width: 1000,
      height: 1500,
    );
    final body = await bodyWith(env.db, media);
    await tester.runAsync(() => PoseIndex(env.db).rebuild());
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/bodies')],
    );
    await tester.tap(find.byKey(Key('body-$body')));
    await tester.pumpAndSettle();
    await expandActionSections(tester);
    await tester.ensureVisible(find.byKey(const Key('action-mark-tattoo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-mark-tattoo')));
    await tester.pumpAndSettle();
    expect(
      find.text('Marking needs a body that belongs to a known person.'),
      findsOneWidget,
    );
    expect(await env.db.select(env.db.bodyMarks).get(), isEmpty);
  }, session: testSession);

  appTest(
    'the person\'s Tattoos screen searches, queues Quick Review suggestions and links on a yes',
    (tester, env) async {
      final lina = await seedPerson(env.db, name: 'Lina');
      final media = await seedMedia(
        env.db,
        asset: 'src',
        width: 1000,
        height: 1500,
        takenAt: 1,
      );
      await bodyWith(env.db, media, person: lina);
      final candidateMedia = await seedMedia(
        env.db,
        asset: 'cand',
        width: 1000,
        height: 1500,
        takenAt: 2,
      );
      final hit = await bodyWith(env.db, candidateMedia);
      final miss = await bodyWith(
        env.db,
        await seedMedia(
          env.db,
          asset: 'cand2',
          width: 1000,
          height: 1500,
          takenAt: 3,
        ),
      );
      final store = BodyMarkStore(env.db, env.files);
      final anchor = anchorFor(_pose(), 'r_forearm', (
        x: 310,
        y: 590,
        w: 40,
        h: 60,
      ))!;
      final markId = await store.create(
        personId: lina,
        segment: 'r_forearm',
        anchor: anchor,
        patch: Uint8List.fromList([9]),
      );
      env.api.marksHandler = (count) => AnalyzeMarksResponse(
        results: [
          for (var i = 0; i < count; i++)
            MarkMatchDto(
              index: i,
              inliers: i == 0 ? 40 : 2,
              matches: 50,
              inlierRatio: i == 0 ? 0.8 : 0.1,
              mirrored: false,
            ),
        ],
      );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/marks?personId=$lina'),
          patchCutterProvider.overrideWithValue(fakeCutter),
        ],
      );
      expect(find.byKey(Key('mark-$markId')), findsOneWidget);
      await tester.tap(find.byKey(Key('mark-search-$markId')));
      await _real(tester);
      expect(env.api.markCalls.single.reference, [9]);
      final shown = [
        hit,
        miss,
      ].where((b) => find.byKey(Key('hit-$b')).evaluate().isNotEmpty).toList();
      expect(
        shown,
        hasLength(1),
        reason: 'only the strong match is a suggestion',
      );
      expect(find.text('Strong match'), findsOneWidget);

      final queued = await env.db.select(env.db.reviewBodyLinks).get();
      expect(
        queued.map((r) => (r.bodyId, r.personId, r.method, r.confidence)),
        [(shown.single, lina, 'tattoo', 0.95)],
      );

      await tester.tap(find.byKey(Key('hit-yes-${shown.single}')));
      await tester.pumpAndSettle();
      final linked = await (env.db.select(
        env.db.bodies,
      )..where((b) => b.id.equals(shown.single))).getSingle();
      expect((linked.personId, linked.linkMethod), (lina, 'manual'));
      expect(find.byKey(Key('hit-${shown.single}')), findsNothing);

      await tester.tap(find.byKey(Key('mark-delete-$markId')));
      await tester.pumpAndSettle();
      expect(await env.db.select(env.db.bodyMarks).get(), isEmpty);
      expect(
        find.text(
          'No tattoos marked yet. Open a photo of this person, tap their body and choose Mark a tattoo.',
        ),
        findsOneWidget,
      );
    },
    session: testSession,
  );

  group('the real patch cutter', () {
    /// A 100 x 60 picture: the left half red, the right half blue.
    Future<Uint8List> picture() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 50, 60),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      canvas.drawRect(
        const ui.Rect.fromLTWH(50, 0, 50, 60),
        ui.Paint()..color = const ui.Color(0xFF0000FF),
      );
      final image = await recorder.endRecording().toImage(100, 60);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    Future<List<int>> pixel(Uint8List png, int x, int y) async {
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      final data = (await image.toByteData())!;
      final i = (y * image.width + x) * 4;
      return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
    }

    Future<(int, int)> size(Uint8List png) async {
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      return (image.width, image.height);
    }

    testWidgets(
      'cuts the rectangle upright, scaled to the decoded image, and refuses tiny ones',
      (tester) async {
        await tester.runAsync(() async {
          final library = FakeMediaLibrary()..bytes['p'] = await picture();
          final cutter = UiPatchCutter(library);
          // the database knows this photo as 200 x 120: the rectangle is in THOSE pixels, the decoded image is 100 x 60
          final media = MediaRow(
            id: 1,
            assetId: 'p',
            kind: 'photo',
            sizeBytes: 0,
            modifiedAt: 0,
            width: 200,
            height: 120,
            scanStatus: 'done',
            scanVersion: 0,
            lastScannedFrame: 0,
            scanAttempts: 0,
            illustrated: false,
            isSensitive: false,
            sensitiveVersion: 0,
            bodyEmbeddingVersion: 0,
            garmentVersion: 0,
          );
          // the whole picture, not turned
          final whole = (await cutter(
            media,
            const MarkRect(
              cx: 100,
              cy: 60,
              width: 200,
              height: 120,
              angleDegrees: 0,
            ),
          ))!;
          expect(await size(whole), (100, 60));
          expect(await pixel(whole, 10, 30), [255, 0, 0]);
          expect(await pixel(whole, 90, 30), [0, 0, 255]);
          // the same area turned by 90 degrees: the left/right halves become top/bottom
          final turned = (await cutter(
            media,
            const MarkRect(
              cx: 100,
              cy: 60,
              width: 120,
              height: 120,
              angleDegrees: 90,
            ),
          ))!;
          final (w, h) = await size(turned);
          expect((w, h), (60, 60));
          final top = await pixel(turned, 30, 5),
              bottom = await pixel(turned, 30, 55);
          expect(
            top,
            isNot(bottom),
            reason: 'the halves are now above each other',
          );
          expect(
            await pixel(turned, 5, 30),
            await pixel(turned, 55, 30),
            reason: 'and left/right are equal',
          );
          // far too small to be a tattoo
          expect(
            await cutter(
              media,
              const MarkRect(
                cx: 100,
                cy: 60,
                width: 10,
                height: 10,
                angleDegrees: 0,
              ),
            ),
            isNull,
          );
          // the photo is gone
          expect(
            await UiPatchCutter(FakeMediaLibrary())(
              media,
              const MarkRect(
                cx: 1,
                cy: 1,
                width: 100,
                height: 100,
                angleDegrees: 0,
              ),
            ),
            isNull,
          );
        });
      },
    );
  });
}

Pose _pose() => Pose.fromJson(kpts(standing), 1000, 1500, extent: 'full')!;

/// Real file IO and codecs need real time; the continuations after them need a pump.
Future<void> _real(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}
