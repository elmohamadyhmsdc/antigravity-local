import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/equipment_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/equipment_library.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<int> _photo(AppDatabase db, String asset) async {
  final media = await seedMedia(db, asset: asset, width: 600, height: 400);
  const points = [
    [50, 10],
    [54, 8],
    [46, 8],
    [58, 10],
    [42, 10],
    [65, 25],
    [35, 25],
    [72, 43],
    [28, 43],
    [74, 60],
    [26, 60],
    [59, 55],
    [41, 55],
    [61, 75],
    [39, 75],
    [65, 95],
    [35, 95],
  ];
  for (final offset in [0, 80]) {
    final id = await seedBody(db, mediaId: media);
    await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
      BodiesCompanion(
        kpts: Value(
          jsonEncode([
            for (final p in points) [(p[0] + offset) / 600, p[1] / 400, .9],
          ]),
        ),
        extent: const Value('full'),
      ),
    );
  }
  return media;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _tab(WidgetTester tester, String name) async {
  final tab = find.byKey(Key('bodies-tab-$name'));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await _settle(tester);
}

Future<void> _preview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('BODY_PREVIEW_DIR');
  if (directory.isEmpty) return;
  final view = tester.binding.renderViews.first;
  await tester.runAsync(() async {
    final image = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & tester.view.physicalSize,
      pixelRatio: 2 / tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('BODY_PREVIEW_FONT_DIR');
    if (fonts.isEmpty) return;
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      roboto.addFont(
        File(
          '$fonts/roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await roboto.load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });
  appTest(
    'a group action can be named, found and corrected without naming either person',
    (tester, env) async {
      final source = await _photo(env.db, 'source');
      final similar = await _photo(env.db, 'similar');
      final matchBodies = await (env.db.select(
        env.db.bodies,
      )..where((b) => b.mediaId.equals(similar))).get();
      await EquipmentLibrary(
        db: env.db,
        media: FakeMediaLibrary(),
        api: () => null,
      ).store(
        similar,
        matchBodies,
        const EquipmentResponse(
          version: 1,
          objects: [
            EquipmentObject(
              key: 'racket',
              label: 'racket',
              bodyIndex: 0,
              box: BBox(x: .1, y: .1, w: .2, h: .2),
            ),
          ],
        ),
      );
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await _tab(tester, 'groups');
      expect(find.byKey(Key('group-photo-$source')), findsOneWidget);
      final name = find.byKey(Key('group-name-$source'));
      await tester.ensureVisible(name);
      await tester.pumpAndSettle();
      await tester.tap(name);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('group-pose-name')),
        'Partner stretch',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('group-pose-save')));
      await _settle(tester);
      expect(find.text('Partner stretch'), findsOneWidget);
      await _preview(tester, 'group-pose-matches');
      expect(find.byKey(Key('group-match-$similar')), findsOneWidget);
      final equipmentFilter = find.byKey(const Key('group-equipment-racket'));
      await tester.ensureVisible(equipmentFilter);
      await tester.pumpAndSettle();
      await tester.tap(equipmentFilter);
      await tester.pumpAndSettle();
      final remove = find.byKey(Key('group-reject-$similar'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await _settle(tester);
      expect(find.byKey(Key('group-match-$similar')), findsNothing);
      expect(await env.db.select(env.db.persons).get(), isEmpty);
      final category =
          (await env.db.select(env.db.poseCategories).get()).single;
      expect((category.name, category.kind), ('Partner stretch', 'group_pose'));
    },
    session: testSession,
  );

  appTest(
    'equipment labels filter photos and can be renamed, reassigned or removed',
    (tester, env) async {
      final media = await _photo(env.db, 'equipment');
      final bodies = await env.db.select(env.db.bodies).get();
      final service = EquipmentLibrary(
        db: env.db,
        media: FakeMediaLibrary(),
        api: () => null,
      );
      await service.store(
        media,
        bodies,
        const EquipmentResponse(
          version: 1,
          objects: [
            EquipmentObject(
              key: 'racket',
              label: 'racket',
              bodyIndex: 0,
              box: BBox(x: .1, y: .1, w: .2, h: .2),
            ),
          ],
        ),
      );
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await _tab(tester, 'equipment');
      await tester.tap(find.byKey(const Key('equipment-filter-racket')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('equipment-review-$media')));
      await _settle(tester);
      final object = (await service.objects()).single;
      await tester.ensureVisible(
        find.byKey(Key('equipment-edit-${object.id}')),
      );
      await tester.tap(find.byKey(Key('equipment-edit-${object.id}')));
      await tester.pumpAndSettle();
      await _preview(tester, 'equipment-correction');
      await tester.enterText(
        find.byKey(const Key('equipment-label')),
        'Tennis racket',
      );
      await tester.tap(find.byKey(const Key('equipment-owner')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Person 2').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('equipment-save')));
      await tester.pumpAndSettle();
      final corrected = (await service.objects()).single;
      expect(
        (corrected.label, corrected.bodyId, corrected.state),
        ('tennis racket', bodies[1].id, 'confirmed'),
      );
      await tester.tap(find.byKey(Key('equipment-reject-${object.id}')));
      await tester.pumpAndSettle();
      expect(await service.objects(), isEmpty);
    },
    session: testSession,
  );

  appTest(
    'visual pose browsing works with large text on a small phone',
    (tester, env) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _photo(env.db, 'poses');
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await _tab(tester, 'poses');
      await _preview(tester, 'visual-pose-browser');
      final standing = find.byKey(const Key('pose-visual-standing'));
      await tester.ensureVisible(standing);
      await tester.pumpAndSettle();
      await tester.tap(standing);
      await _settle(tester);
      expect(find.text('Standing · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
