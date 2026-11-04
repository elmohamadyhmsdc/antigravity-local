import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/features/explore/explore_collection_screen.dart';
import 'package:antigravity_mobile/features/bodies/bodies_screen.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fake_media_organizer.dart';
import '../support/harness.dart';
import '../support/seed.dart';

const _directory = String.fromEnvironment('UX_AUDIT_DIR');
const _fonts = String.fromEnvironment('UX_AUDIT_FONTS');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  if (_directory.isEmpty) return;
  final view = tester.binding.renderViews.first;
  await tester.runAsync(() async {
    final picture = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & tester.view.physicalSize,
      pixelRatio: 1 / tester.view.devicePixelRatio,
    );
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_directory).create(recursive: true);
    await File(
      '$_directory/$name.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}

Future<void> _seed(WidgetTester tester, TestEnv env) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xffb7c6bb), BlendMode.src);
    canvas.drawCircle(
      const Offset(160, 90),
      40,
      Paint()..color = const Color(0xffd6bda1),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(115, 140, 90, 150),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xff425e57),
    );
    final image = await recorder.endRecording().toImage(320, 320);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final person = await seedPerson(env.db, name: 'Nadia');
  await seedPerson(env.db, name: 'Omar');
  final media = await seedMedia(
    env.db,
    asset: 'audit-photo',
    width: 320,
    height: 320,
  );
  env.library.bytes['audit-photo'] = bytes!;
  env.library.addAlbum(
    const AlbumInfo(id: 'all', name: 'All photos', count: 1, isAll: true),
    [
      const AssetInfo(
        id: 'audit-photo',
        width: 320,
        height: 320,
        modifiedAt: 1000,
        takenAt: 1000,
      ),
    ],
  );
  await tester.runAsync(() async {
    await env.files.write('faces/audit.jpg', bytes);
    await env.files.write('results/audit.png', bytes);
    await env.files.write(
      'models/audit.safetensors',
      Uint8List.fromList([1, 2, 3]),
    );
  });
  await seedFace(
    env.db,
    personId: person,
    mediaId: media,
    cropPath: 'faces/audit.jpg',
  );
  await seedBody(
    env.db,
    mediaId: media,
    personId: person,
    cropPath: 'faces/audit.jpg',
  );
  await env.db
      .into(env.db.datasets)
      .insert(
        DatasetsCompanion.insert(
          id: 'audit-dataset',
          personId: Value(person),
          triggerWord: 'nadia_training',
          createdAt: 1,
        ),
      );
  await env.db
      .into(env.db.loras)
      .insert(
        LorasCompanion.insert(
          id: 'audit-model',
          personId: Value(person),
          path: 'models/audit.safetensors',
          triggerWord: 'nadia_model',
          createdAt: 1,
        ),
      );
  await env.db
      .into(env.db.results)
      .insert(
        ResultsCompanion.insert(
          id: 'audit-result',
          type: 'generate_lora_images',
          path: 'results/audit.png',
          originalPath: 'results/audit.png',
          mime: 'image/png',
          sizeBytes: bytes.length,
          sha256: 'test',
          personId: Value(person),
          createdAt: 1,
        ),
      );
}

void main() {
  setUpAll(() async {
    if (_fonts.isEmpty) return;
    final font = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      font.addFont(
        File(
          '$_fonts/roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await font.load();
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$_fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  for (final screen in [
    ('01-gallery', '/library'),
    ('02-people', '/people'),
    ('03-explore', '/explore'),
    ('04-studio', '/studio'),
    ('05-settings', '/settings'),
    ('06-library-settings', '/settings/library'),
    ('07-review', '/review?view=hub'),
    ('08-activity', '/activity'),
    ('09-restyle', '/restyle'),
    ('10-train', '/studio/train'),
    ('11-generate', '/studio/generate'),
    ('12-person', '/people/1'),
    ('13-poses', '/explore/poses'),
    ('14-outfits', '/explore/outfits'),
    ('15-areas', '/explore/areas'),
    ('16-equipment', '/explore/equipment'),
    ('17-groups', '/explore/groupPoses'),
    ('18-privacy', '/settings/privacy'),
    ('19-storage', '/settings/storage'),
    ('20-backup', '/settings/backup'),
    ('21-background', '/settings/background'),
    ('22-review-details', '/review?view=all'),
    ('23-reface', '/reface'),
    ('24-photo', '/media/1'),
  ]) {
    appTest('walk through ${screen.$1}', (tester, env) async {
      await _seed(tester, env);
      await env.pump(
        tester,
        settle: false,
        extra: [initialLocationProvider.overrideWithValue(screen.$2)],
      );
      await _settle(tester);
      await _capture(tester, screen.$1);
      if (screen.$1 == '04-studio') {
        await tester.tap(find.text('My Library'));
        await _settle(tester);
        await _capture(tester, '04b-studio-library');
        expect(find.byKey(const Key('result-audit-result')), findsOneWidget);
        await tester.tap(find.byKey(const Key('studio-library-models')));
        await _settle(tester);
        expect(
          find.byKey(const Key('studio-model-audit-model')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('result-audit-result')), findsNothing);
        await _capture(tester, '04c-studio-models');
        await tester.tap(find.byKey(const Key('studio-library-datasets')));
        await _settle(tester);
        expect(
          find.byKey(const Key('studio-dataset-audit-dataset')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('studio-model-audit-model')), findsNothing);
        await _capture(tester, '04d-studio-datasets');
        await tester.tap(find.byKey(const Key('studio-library-results')));
        await _settle(tester);
      }
      if (screen.$1 == '12-person') {
        await tester.tap(find.byKey(const Key('person-menu')));
        await _settle(tester);
        await _capture(tester, '12b-person-actions');
      }
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _settle(tester);
      await _capture(tester, '${screen.$1}-large-text');
    }, session: testSession);
  }

  appTest(
    'Explore opens the intended tab with one app bar and keeps Areas available',
    (tester, env) async {
      await _seed(tester, env);
      await env.pump(
        tester,
        settle: false,
        extra: [initialLocationProvider.overrideWithValue('/explore')],
      );
      await _settle(tester);
      await tester.tap(find.text('Poses'));
      await _settle(tester);
      final collection = find.byType(ExploreCollectionView);
      expect(
        find.descendant(of: collection, matching: find.byType(AppBar)),
        findsOneWidget,
      );
      expect(
        DefaultTabController.of(
          tester.element(find.byKey(const Key('bodies-tab-poses'))),
        ).index,
        1,
      );
      expect(find.byKey(const Key('filter-no-owner')), findsNothing);
      await tester.pageBack();
      await _settle(tester);
      await tester.ensureVisible(find.text('Areas'));
      await tester.tap(find.text('Areas'));
      await _settle(tester);
      expect(
        DefaultTabController.of(
          tester.element(find.byKey(const Key('bodies-tab-areas'))),
        ).index,
        5,
      );
      expect(find.byType(BodiesScreen), findsOneWidget);
      expect(await env.db.setting('body_clusters_enabled'), isNot('true'));
    },
    session: testSession,
  );

  appTest(
    'Review queue links select their category and Back returns to the hub',
    (tester, env) async {
      await env.pump(
        tester,
        settle: false,
        extra: [initialLocationProvider.overrideWithValue('/review?view=hub')],
      );
      await _settle(tester);
      await tester.ensureVisible(find.byKey(const Key('queue-duplicates')));
      await tester.tap(find.byKey(const Key('queue-duplicates')));
      await _settle(tester);
      expect(
        DefaultTabController.of(
          tester.element(find.byKey(const Key('review-tab-duplicates'))),
        ).index,
        2,
      );
      await tester.pageBack();
      await _settle(tester);
      expect(find.byKey(const Key('queue-groups')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('queue-body-links')));
      await tester.tap(find.byKey(const Key('queue-body-links')));
      await _settle(tester);
      expect(
        DefaultTabController.of(
          tester.element(find.byKey(const Key('review-tab-outfits'))),
        ).index,
        3,
      );
    },
    session: testSession,
  );

  appTest(
    'excluding a body detection leaves the face with the same ID intact and supports Undo',
    (tester, env) async {
      await _seed(tester, env);
      await env.pump(
        tester,
        settle: false,
        extra: [
          initialLocationProvider.overrideWithValue('/media/1'),
          mediaOrganizerBridgeProvider.overrideWithValue(FakeMediaOrganizer()),
        ],
      );
      await _settle(tester);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-bodies')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('box-b-1')));
      await _settle(tester);
      await expandActionSections(tester);
      final exclude = find.byKey(const Key('action-sheet-notARealThing'));
      await tester.ensureVisible(exclude);
      await tester.pumpAndSettle();
      await tester.tap(exclude);
      await _settle(tester);
      expect((await env.db.select(env.db.faces).get()).single.id, 1);
      expect((await env.db.select(env.db.bodies).get()).single.hidden, isTrue);
      for (var i = 0; i < 30 && find.text('Undo').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await _capture(tester, '25-exclude-feedback');
      await tester.tap(find.text('Undo'));
      await _settle(tester);
      expect((await env.db.select(env.db.bodies).get()).single.hidden, isFalse);
    },
    session: testSession,
  );
}
