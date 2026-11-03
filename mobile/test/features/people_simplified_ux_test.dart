import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _preview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('PEOPLE_PREVIEW_DIR');
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

Future<void> _moreActions(WidgetTester tester) async {
  final more = find.byKey(const Key('people-more-actions'));
  await tester.ensureVisible(more);
  await tester.tap(more);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    const fonts = String.fromEnvironment('PEOPLE_PREVIEW_FONT_DIR');
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
    'switching collections keeps the people search when returning',
    (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      await seedPerson(env.db, name: 'Omar');
      await seedPerson(env.db, name: 'Mariam');
      await seedPerson(env.db, name: 'Youssef');
      await seedPerson(env.db, name: 'Lina');
      await seedPerson(env.db, name: 'Nour');
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await _preview(tester, 'people');
      await tester.enterText(find.byKey(const Key('people-search')), 'Sara');
      await tester.tap(find.byKey(const Key('open-characters')));
      await tester.pumpAndSettle();
      expect(find.text('No characters yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-people')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('person-$sara')), findsOneWidget);
      expect(find.text('Omar'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('people-search')))
            .controller!
            .text,
        'Sara',
      );
    },
    session: testSession,
  );

  appTest('an empty favorites filter can be cleared in place', (
    tester,
    env,
  ) async {
    final sara = await seedPerson(env.db, name: 'Sara');
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/people')],
    );
    await tester.tap(find.byKey(const Key('people-filter-favorites')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('person-$sara')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Clear filters'));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('person-$sara')), findsOneWidget);
  }, session: testSession);

  appTest(
    'the compact person menu keeps every album tool available',
    (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: sara, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
      );
      await _preview(tester, 'person-detail');
      await tester.tap(find.byKey(const Key('person-menu')));
      await tester.pumpAndSettle();
      await _preview(tester, 'person-actions');
      await _moreActions(tester);
      for (final id in [
        'rename',
        'add',
        'cover',
        'merge',
        'suggestions',
        'hide',
        'pin',
        'favorite',
        'media',
        'split',
        'distinct',
        'redetect',
        'lock',
        'studio',
        'toCharacters',
        'export',
        'details',
        'marks',
        'bodies',
        'exportTraining',
        'delete',
      ]) {
        expect(
          find.byKey(Key('people-action-$id')),
          findsOneWidget,
          reason: '$id remains reachable',
        );
      }
      expect(find.text('Organize'), findsOneWidget);
      expect(find.text('Matching & corrections'), findsOneWidget);
      expect(find.text('Photos, export & tools'), findsOneWidget);
      final export = find.byKey(const Key('people-action-exportTraining'));
      await tester.ensureVisible(export);
      await tester.tap(export);
      await tester.pumpAndSettle();
      expect(find.text('Export for training'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'character tools stay isolated and People works from a direct link',
    (tester, env) async {
      final hero = await env.db
          .into(env.db.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Hero'),
              kind: const Value('character'),
              createdAt: 1,
            ),
          );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/characters')],
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('people-search')))
            .decoration!
            .hintText,
        'Search characters',
      );
      await tester.tap(find.byKey(Key('person-$hero')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('person-menu')));
      await tester.pumpAndSettle();
      await _moreActions(tester);
      expect(find.byKey(const Key('people-action-toPeople')), findsOneWidget);
      expect(
        find.byKey(const Key('people-action-exportTraining')),
        findsOneWidget,
      );
      for (final id in ['marks', 'bodies']) {
        expect(find.byKey(Key('people-action-$id')), findsOneWidget);
      }
      // Reface is people-only: a character has no Studio entry
      expect(find.byKey(const Key('people-action-studio')), findsNothing);
      await tester.tap(find.byKey(const Key('people-actions-close')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-people')));
      await tester.pumpAndSettle();
      expect(find.text('No people yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'narrow phones support large text, selection and scrollable tools',
    (tester, env) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final sara = await seedPerson(env.db, name: 'Sara Mahmoud');
      await seedFace(env.db, personId: sara, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await _preview(tester, 'people-large-text');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('people-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('person-$sara')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('people-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('person-$sara')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('person-menu')));
      await tester.pumpAndSettle();
      await _moreActions(tester);
      final marks = find.byKey(const Key('people-action-marks'));
      await tester.ensureVisible(marks);
      await tester.tap(marks);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );

  appTest(
    'search and review controls scroll when the keyboard opens',
    (tester, env) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final sara = await seedPerson(env.db, name: 'Sara');
      final face = await seedFace(env.db, seed: 1);
      await env.db
          .into(env.db.reviewMatches)
          .insert(
            ReviewMatchesCompanion.insert(
              faceId: Value(face),
              personId: sara,
              score: .45,
              margin: .1,
              decision: 'suggest',
            ),
          );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      expect(find.byKey(const Key('people-review-banner')), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('people-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Sara');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(Key('person-$sara')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('person-$sara')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
