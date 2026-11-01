// Opt-in synthetic UI captures: no device media or network access.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/video_actions_repository.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

const previewDir = String.fromEnvironment('GALLERY_PREVIEW_DIR');
const previewFonts = String.fromEnvironment('GALLERY_PREVIEW_FONT_DIR');

Future<Uint8List> _synthetic(WidgetTester tester, int index) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final colors = [
        const Color(0xffb6a997),
        const Color(0xff91a99c),
        const Color(0xff9eabb5),
        const Color(0xffc2aa9f),
      ];
      canvas.drawColor(colors[index % colors.length], ui.BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(0, 180, 400, 220),
        Paint()..color = const Color(0xff536b5c),
      );
      canvas.drawCircle(
        Offset(100.0 + index * 12 % 180, 130),
        52,
        Paint()..color = const Color(0xffe5c8a8),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(55.0 + index * 12 % 180, 190, 95, 160),
          const Radius.circular(32),
        ),
        Paint()..color = const Color(0xff3d5151),
      );
      final image = await recorder.endRecording().toImage(400, 400);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;

Future<void> _capture(WidgetTester tester, String name) async {
  final view = tester.binding.renderViews.first;
  await tester.runAsync(() async {
    final image = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & tester.view.physicalSize,
      pixelRatio: 2 / tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(previewDir).create(recursive: true);
    await File(
      '$previewDir/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
  expect(tester.takeException(), isNull, reason: name);
}

void main() {
  setUpAll(() async {
    if (previewDir.isEmpty || previewFonts.isEmpty) return;
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      roboto.addFont(
        File(
          '$previewFonts/roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$previewFonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  appTest('capture Gallery-first screens with synthetic content', (
    tester,
    env,
  ) async {
    if (previewDir.isEmpty || previewFonts.isEmpty) return;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    final images = <Uint8List>[];
    for (var i = 0; i < 12; i++) {
      images.add(await _synthetic(tester, i));
    }
    final assets = <AssetInfo>[];
    for (var i = 0; i < 12; i++) {
      final id = 'preview-$i';
      env.library.bytes[id] = images[i];
      assets.add(
        AssetInfo(
          id: id,
          width: 400,
          height: 400,
          modifiedAt: 1720000000000 - (i ~/ 6) * 86400000,
          takenAt: 1720000000000 - (i ~/ 6) * 86400000,
        ),
      );
    }
    env.library.addAlbum(
      const AlbumInfo(id: 'all', name: 'All photos', count: 12, isAll: true),
      assets,
    );
    env.library.addAlbum(
      const AlbumInfo(id: 'camera', name: 'Camera', count: 12),
      assets,
    );
    final person = await seedPerson(env.db, name: 'Nadia');
    final second = await seedPerson(env.db, name: 'Omar');
    final media = await seedMedia(
      env.db,
      asset: 'preview-0',
      width: 400,
      height: 400,
      takenAt: 1720000000000,
    );
    await tester.runAsync(() async {
      await env.files.write('faces/preview.jpg', images[0]);
      await env.files.write(
        'loras/preview.safetensors',
        Uint8List.fromList([1, 2, 3]),
      );
    });
    await seedFace(
      env.db,
      personId: person,
      mediaId: media,
      cropPath: 'faces/preview.jpg',
    );
    await seedFace(
      env.db,
      personId: second,
      cropPath: 'faces/preview.jpg',
      seed: 2,
    );
    final body = await seedBody(env.db, mediaId: media, personId: person);
    final points = [
      [.5, .2],
      [.53, .19],
      [.47, .19],
      [.56, .2],
      [.44, .2],
      [.65, .27],
      [.35, .27],
      [.67, .37],
      [.33, .37],
      [.68, .47],
      [.32, .47],
      [.56, .53],
      [.44, .53],
      [.56, .70],
      [.44, .70],
      [.56, .87],
      [.44, .87],
    ];
    await (env.db.update(env.db.bodies)..where((b) => b.id.equals(body))).write(
      BodiesCompanion(
        kpts: Value(
          jsonEncode([
            for (final p in points) [...p, .9],
          ]),
        ),
        extent: const Value('full'),
      ),
    );
    final actionsRepo = VideoActionsRepository(env.db);
    final action = await actionsRepo.saveAction('Greeting');
    await actionsRepo.addPhotoExample(
      actionId: action,
      mediaId: media,
      participantIds: [person],
    );
    await env.db
        .into(env.db.loras)
        .insert(
          LorasCompanion.insert(
            id: 'preview-model',
            personId: Value(person),
            path: 'loras/preview.safetensors',
            triggerWord: 'nadia',
            createdAt: 1,
          ),
        );

    Future<void> open(String route, {ScanProgress? progress}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await env.pump(
        tester,
        settle: false,
        extra: [
          initialLocationProvider.overrideWithValue(route),
          if (progress != null)
            scanProgressProvider.overrideWith((ref) => Stream.value(progress)),
        ],
      );
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await open('/library');
    expect(find.byKey(const Key('native-gallery-grid')), findsOneWidget);
    await _capture(tester, '01-gallery-photos');
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    await _capture(tester, '02-gallery-folders');
    await open('/people');
    expect(find.text('Nadia'), findsOneWidget);
    await _capture(tester, '03-people');
    await open('/discover');
    expect(find.text('Poses'), findsOneWidget);
    await _capture(tester, '04-discover');
    await open('/media/$media');
    expect(find.byKey(const Key('media-page-view')), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await _capture(tester, '05-photo');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsWidgets);
    final imageRect = tester.getRect(find.byKey(const Key('annotated-photo')));
    expect(
      imageRect.top,
      lessThan(tester.getTopLeft(find.text('Details').last).dy),
    );
    expect(imageRect.height, greaterThan(60));
    expect(find.text('nadia').hitTestable(), findsOneWidget);
    expect(
      find.byTooltip('Generate with this reference').hitTestable(),
      findsOneWidget,
    );
    await _capture(tester, '06-photo-details');
    await open('/people/$person');
    expect(find.text('Media'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await _capture(tester, '07-person-media');
    await tester.tap(find.text('Models'));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('nadia'), findsOneWidget);
    expect(find.text('Prepare training'), findsOneWidget);
    expect(find.text('Training tasks'), findsNothing);
    expect(find.text('Datasets'), findsNothing);
    expect(find.text('Related results'), findsNothing);
    await _capture(tester, '08-person-models');
    await open('/studio');
    expect(find.byKey(const Key('studio-reface')), findsOneWidget);
    await _capture(tester, '09-studio');
    await open(
      '/running-scan',
      progress: ScanProgress(
        phase: ScanPhase.paused,
        pauseReason: PauseReason.user,
        total: 120,
        done: 47,
        currentAssetId: 'preview-0',
        currentKind: 'photo',
        previewBytes: images[0],
      ),
    );
    expect(find.byKey(const Key('scan-progress-card')), findsOneWidget);
    await _capture(tester, '10-running-scan');
    await open('/discover');
    await revealForTap(tester, find.text('Actions'));
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Greeting'), findsOneWidget);
    await _capture(tester, '12-actions-catalog');
    await tester.tap(find.text('Greeting'));
    await tester.pumpAndSettle();
    expect(find.text('Examples'), findsOneWidget);
    expect(find.text('Find similar activities'), findsOneWidget);
    await _capture(tester, '13-action-details');
    tester.view.physicalSize = const Size(640, 1688);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await open('/discover');
    expect(find.text('Discover'), findsWidgets);
    await _capture(tester, '11-discover-dark-large');
  }, session: testSession);
}
