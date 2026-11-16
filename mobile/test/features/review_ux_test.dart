import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/features/review/review_action_scope.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> preview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('REVIEW_UX_PREVIEW_DIR');
  if (directory.isEmpty) return;
  final view = tester.binding.renderViews.first;
  await tester.runAsync(() async {
    final image = await (view.debugLayer! as OffsetLayer).toImage(
      Offset.zero & tester.view.physicalSize,
      pixelRatio: 1 / tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    const font = String.fromEnvironment('REVIEW_UX_PREVIEW_FONT');
    if (font.isEmpty) return;
    final directory = File(font).parent.path;
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family);
      for (final weight in ['regular', 'medium', 'bold']) {
        loader.addFont(
          File(
            '$directory/roboto-$weight.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$directory/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
  });

  appTest(
    'compact People toolbar leaves room for identities and discloses filters',
    (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      for (final name in ['Omar', 'Mariam', 'Lina', 'Nour', 'Youssef']) {
        await seedPerson(env.db, name: name);
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      expect(find.byKey(const Key('people-filter-favorites')), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(Key('person-$sara'))).dy,
        lessThan(230),
      );
      await preview(tester, 'people-compact');
      await tester.tap(find.byKey(const Key('people-filters')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('people-filter-favorites')), findsOneWidget);
      await tester.tap(find.byKey(const Key('people-filter-favorites')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('people-filters')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'Favorites'), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'a large review builds visible cards and saves both checkbox outcomes',
    (tester, env) async {
      final people = <int>[];
      final faces = <int>[];
      for (var i = 0; i < 80; i++) {
        final person = await seedPerson(env.db, name: 'Person $i');
        people.add(person);
        for (var j = 0; j < (i == 0 ? 3 : 2); j++) {
          final face = await seedFace(env.db, seed: i * 2 + j);
          faces.add(face);
          await env.db
              .into(env.db.reviewMatches)
              .insert(
                ReviewMatchesCompanion.insert(
                  faceId: Value(face),
                  personId: person,
                  score: .7,
                  margin: .1,
                  decision: 'suggest',
                ),
              );
        }
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/review?view=all')],
      );
      expect(find.byKey(Key('match-card-${people.last}')), findsNothing);
      await tester.tap(find.byKey(Key('match-select-${faces[1]}')));
      await tester.pumpAndSettle();
      await preview(tester, 'review-selection');
      await tester.tap(find.byKey(Key('match-accept-${people.first}')));
      await tester.pumpAndSettle();
      final rejected = await env.db.select(env.db.faceRejections).get();
      expect(rejected.map((r) => (r.faceId, r.personId)), [
        (faces[1], people.first),
      ]);
      expect(find.byKey(Key('match-card-${people.first}')), findsNothing);
      // Even a stale grouping plan cannot ask the rejected pair again.
      await env.db
          .into(env.db.reviewMatches)
          .insert(
            ReviewMatchesCompanion.insert(
              faceId: Value(faces[1]),
              personId: people.first,
              score: .9,
              margin: .2,
              decision: 'suggest',
            ),
          );
      await tester.pumpAndSettle();
      expect(find.byKey(Key('match-card-${people.first}')), findsNothing);
    },
    session: testSession,
  );

  for (final kind in ['person', 'character']) {
    appTest('quick $kind group keeps unchecked faces separate', (
      tester,
      env,
    ) async {
      final faces = [
        for (var i = 0; i < 3; i++) await seedFace(env.db, seed: i),
      ];
      if (kind == 'character') {
        await env.db
            .update(env.db.faces)
            .write(const FacesCompanion(kind: Value('character')));
      }
      await env.db
          .into(env.db.reviewGroups)
          .insert(
            ReviewGroupsCompanion.insert(
              kind: Value(kind),
              faceIds: '[${faces.join(',')}]',
              cohesion: .6,
              quality: .8,
            ),
          );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue(
            '/review?view=quick&kind=$kind',
          ),
        ],
      );
      await tester.tap(find.byKey(Key('quick-group-face-${faces.last}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick-group-name')), 'Nour');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick-yes')));
      await tester.pumpAndSettle();
      final identity = (await env.db.select(env.db.persons).get()).single;
      expect(identity.kind, kind);
      final rejected =
          (await env.db.select(env.db.faceRejections).get()).single;
      expect((rejected.faceId, rejected.personId), (faces.last, identity.id));
      expect(find.byKey(const Key('quick-all-done')), findsOneWidget);
    }, session: testSession);
  }

  testWidgets(
    'saving is visible, blocks duplicate taps, and restores actions after failure',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      var fail = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ReviewActionScope(
              child: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () => ReviewActionScope.run(context, () async {
                      calls++;
                      if (fail) throw StateError('Save failed');
                      await pending.future;
                    }),
                    child: const Text('Save'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Saving decisions…'), findsOneWidget);
      expect(calls, 1);
      await preview(tester, 'review-saving');
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSavingIndicator), findsNothing);
      fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('Save failed'), findsOneWidget);
      expect(find.byType(ReviewSavingIndicator), findsNothing);
      fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(calls, 3);
    },
  );
}
