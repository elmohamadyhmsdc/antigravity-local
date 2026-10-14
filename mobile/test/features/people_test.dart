// S07 People, S08 Person detail and S09 Face picker.

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

void main() {
  group('S07 People', () {
    appTest('an empty library says so and points to scanning', (
      tester,
      env,
    ) async {
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      expect(find.text('No people yet'), findsOneWidget);
      expect(find.text('Scan library'), findsOneWidget);
    }, session: testSession);

    appTest(
      'people show their name, face count and the unsorted card; search and sort work',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara', createdAt: 1);
        final omar = await seedPerson(env.db, name: 'Omar', createdAt: 2);
        await seedPerson(
          env.db,
          name: null,
          createdAt: 3,
        ); // unnamed -> "Person 3"
        for (var i = 0; i < 3; i++) {
          await seedFace(env.db, personId: sara, seed: i + 1);
        }
        await seedFace(env.db, personId: omar, seed: 10);
        await seedFace(env.db, seed: 20);
        await seedFace(env.db, seed: 21);

        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people')],
        );
        await _settle(tester);

        expect(find.text('Sara'), findsOneWidget);
        expect(find.text('3 faces'), findsOneWidget);
        expect(find.text('Omar'), findsOneWidget);
        expect(
          find.text('Person 3'),
          findsOneWidget,
          reason: 'an unnamed person still has a name on screen',
        );
        expect(find.byKey(const Key('unsorted-card')), findsOneWidget);
        expect(
          find.text('2 faces'),
          findsOneWidget,
          reason: 'the unsorted card counts the faces nobody owns',
        );

        // the most faces come first
        final saraAt = tester.getTopLeft(find.byKey(Key('person-$sara')));
        final omarAt = tester.getTopLeft(find.byKey(Key('person-$omar')));
        final saraFirst =
            saraAt.dy < omarAt.dy ||
            (saraAt.dy == omarAt.dy && saraAt.dx < omarAt.dx);
        expect(saraFirst, isTrue, reason: 'Sara has 3 faces, Omar 1');

        await tester.enterText(find.byKey(const Key('people-search')), 'om');
        await tester.pumpAndSettle();
        expect(find.text('Omar'), findsOneWidget);
        expect(find.text('Sara'), findsNothing);
        expect(
          find.byKey(const Key('unsorted-card')),
          findsNothing,
          reason: 'a search shows people only',
        );
      },
      session: testSession,
    );

    appTest(
      'tapping a person opens their page; the unsorted card opens the unsorted faces',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        await seedFace(env.db, personId: sara, seed: 1);
        await seedFace(env.db, seed: 2);
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people')],
        );
        await _settle(tester);

        await tester.tap(find.byKey(const Key('unsorted-card')));
        await _settle(tester);
        expect(find.text('Unsorted'), findsWidgets);
        expect(find.byKey(const Key('face-grid')), findsOneWidget);
        await tester.pageBack();
        await _settle(tester);

        await tester.tap(find.byKey(Key('person-$sara')));
        await _settle(tester);
        expect(find.byKey(const Key('tab-faces')), findsOneWidget);
        expect(find.text('Faces (1)'), findsOneWidget);
        expect(find.text('Photos & videos'), findsOneWidget);
        expect(find.text('Bodies'), findsOneWidget);
        expect(find.text('Suggestions'), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('S08 Person detail', () {
    appTest('rename, then delete (the faces survive, unsorted)', (
      tester,
      env,
    ) async {
      final p = await seedPerson(env.db, name: null);
      final face = await seedFace(env.db, personId: p, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$p')],
      );
      await _settle(tester);
      expect(find.text('Person $p'), findsWidgets);

      await tester.tap(find.byKey(const Key('person-title')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('rename-field')), 'Lina');
      await tester.tap(find.byKey(const Key('rename-save')));
      await _settle(tester);
      expect(find.text('Lina'), findsWidgets);
      expect((await env.db.select(env.db.persons).get()).single.name, 'Lina');

      await tester.tap(find.byKey(const Key('person-menu')));
      await _settle(tester);
      await tester.tap(find.text('Delete person'));
      await _settle(tester);
      expect(find.text('Delete Lina?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await _settle(tester);

      expect(await env.db.select(env.db.persons).get(), isEmpty);
      final f = (await env.db.select(env.db.faces).get()).single;
      expect(
        (f.id, f.personId),
        (face, null),
        reason: 'deleting a person never deletes their faces',
      );
    }, session: testSession);

    appTest(
      'a person that no longer exists shows a message instead of crashing',
      (tester, env) async {
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/999')],
        );
        await _settle(tester);
        expect(find.text('This person no longer exists.'), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'Suggestions: faces the PC thinks are this person can be added or rejected',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        await seedFace(env.db, personId: sara, seed: 1);
        final a = await seedFace(env.db, seed: 2);
        final b = await seedFace(env.db, seed: 3);
        for (final f in [a, b]) {
          await env.db
              .into(env.db.reviewMatches)
              .insert(
                ReviewMatchesCompanion.insert(
                  faceId: Value(f),
                  personId: sara,
                  score: 0.45,
                  margin: 0.1,
                  decision: 'suggest',
                ),
              );
        }
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
        );
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('tab-suggestions')));
        await tester.tap(find.byKey(const Key('tab-suggestions')));
        await _settle(tester);

        expect(find.text('2 faces may be Sara'), findsOneWidget);
        await tester.tap(find.byKey(Key('suggested-$b'))); // untick one
        await tester.pumpAndSettle();
        expect(find.text('Add 1 face'), findsOneWidget);
        await tester.tap(find.byKey(const Key('accept-suggested')));
        await _settle(tester);

        final faces = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect(faces[a], sara);
        expect(faces[b], isNull, reason: 'the unticked one was left alone');
      },
      session: testSession,
    );
  });

  group('S09 Face picker', () {
    appTest(
      'long-press selects faces, "Assign to" a new person moves them',
      (tester, env) async {
        final a = await seedFace(env.db, seed: 1);
        final b = await seedFace(env.db, seed: 2);
        await seedFace(env.db, seed: 3);
        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue('/people/unsorted'),
          ],
        );
        await _settle(tester);

        await tester.longPress(find.byKey(Key('face-$a')));
        await tester.pumpAndSettle();
        expect(find.text('1 selected'), findsOneWidget);
        await tester.tap(find.byKey(Key('face-$b')));
        await tester.pumpAndSettle();
        expect(find.text('2 selected'), findsOneWidget);

        await tester.tap(find.byKey(const Key('selection-assign')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('person-picker-new')));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const Key('new-person-name')),
          'Sara',
        );
        await tester.tap(find.text('Create'));
        await _settle(tester);

        final person = (await env.db.select(env.db.persons).get()).single;
        expect(person.name, 'Sara');
        final owners = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect((owners[a], owners[b]), (person.id, person.id));
        expect(
          owners.values.where((v) => v == null).length,
          1,
          reason: 'the third face was not selected',
        );
        expect(
          find.text('2 selected'),
          findsNothing,
          reason: 'the selection is cleared',
        );
      },
      session: testSession,
    );

    appTest(
      '"Not this person" removes the faces from the person and remembers it',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final a = await seedFace(env.db, personId: sara, seed: 1);
        await seedFace(env.db, personId: sara, seed: 2);
        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
        );
        await _settle(tester);

        await tester.longPress(find.byKey(Key('face-$a')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('selection-reject')));
        await _settle(tester);

        expect(
          (await env.db.select(env.db.faces).get())
              .where((f) => f.personId == sara)
              .length,
          1,
        );
        final rejections = await env.db.select(env.db.faceRejections).get();
        expect(rejections.single.faceId, a);
      },
      session: testSession,
    );

    appTest('deleting selected faces asks first', (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      final a = await seedFace(env.db, personId: sara, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
      );
      await _settle(tester);
      await tester.longPress(find.byKey(Key('face-$a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('selection-delete')));
      await _settle(tester);
      expect(find.text('Delete this face?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(await env.db.select(env.db.faces).get(), hasLength(1));

      await tester.tap(find.byKey(const Key('selection-delete')));
      await _settle(tester);
      await tester.tap(find.text('Delete').last);
      await _settle(tester);
      expect(await env.db.select(env.db.faces).get(), isEmpty);
    }, session: testSession);

    appTest('a single selected face can become the cover', (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: sara, seed: 1, quality: 0.9);
      final low = await seedFace(env.db, personId: sara, seed: 2, quality: 0.3);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
      );
      await _settle(tester);
      await tester.longPress(find.byKey(Key('face-$low')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('selection-cover')));
      await _settle(tester);
      expect(
        (await env.db.select(env.db.persons).get()).single.avatarFaceId,
        low,
      );
    }, session: testSession);
  });
}
