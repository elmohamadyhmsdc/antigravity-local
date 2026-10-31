import 'package:antigravity_mobile/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> action(WidgetTester tester, String id) async {
  final target = find.byKey(Key('people-action-$id'));
  if (target.evaluate().isEmpty) {
    await tester.tap(find.byKey(const Key('people-more-actions')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'long press opens person actions; hidden people can be restored from Hidden',
    (tester, env) async {
      final id = await seedPerson(env.db, name: 'Sara');
      await seedFace(env.db, personId: id, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await tester.longPress(find.byKey(Key('person-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('people-action-merge')), findsOneWidget);
      expect(find.byKey(const Key('people-action-rename')), findsOneWidget);
      await action(tester, 'hide');
      expect(find.byKey(Key('person-$id')), findsNothing);
      expect((await env.db.select(env.db.persons).get()).single.hidden, isTrue);
      await tester.ensureVisible(find.byKey(const Key('people-filter-hidden')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('people-filter-hidden')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('person-$id')), findsOneWidget);
      await tester.tap(find.byKey(Key('person-menu-$id')));
      await tester.pumpAndSettle();
      await action(tester, 'show');
      expect(
        (await env.db.select(env.db.persons).get()).single.hidden,
        isFalse,
      );
    },
    session: testSession,
  );

  appTest(
    'merge starts on the people grid and reviews keeper, name and cover',
    (tester, env) async {
      final a = await seedPerson(env.db, name: 'Sara');
      final b = await seedPerson(env.db, name: 'Person B');
      await seedFace(env.db, personId: a, seed: 1);
      await seedFace(env.db, personId: b, seed: 2);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await tester.longPress(find.byKey(Key('person-$a')));
      await tester.pumpAndSettle();
      await action(tester, 'merge');
      await tester.tap(find.byKey(Key('person-picker-$b')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('people-merge-confirm')), findsOneWidget);
      expect(find.text('Choose cover face…'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('merge-result-name')),
        'Sara together',
      );
      await tester.tap(find.byKey(const Key('people-merge-confirm')));
      await tester.pumpAndSettle();
      final kept = (await env.db.select(env.db.persons).get()).single;
      expect((kept.id, kept.name), (b, 'Sara together'));
      expect(
        (await env.db.select(env.db.faces).get()).every((f) => f.personId == b),
        isTrue,
      );
    },
    session: testSession,
  );

  appTest(
    'multiple people can be hidden together without deleting their faces',
    (tester, env) async {
      final a = await seedPerson(env.db, name: 'A');
      final b = await seedPerson(env.db, name: 'B');
      await seedFace(env.db, personId: a, seed: 1);
      await seedFace(env.db, personId: b, seed: 2);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await tester.longPress(find.byKey(Key('person-$a')));
      await tester.pumpAndSettle();
      await action(tester, 'select');
      await tester.tap(find.byKey(Key('person-$b')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('people-selection-actions')));
      await tester.pumpAndSettle();
      await action(tester, 'hide');
      expect(
        (await env.db.select(env.db.persons).get()).every((p) => p.hidden),
        isTrue,
      );
      expect(await env.db.select(env.db.faces).get(), hasLength(2));
    },
    session: testSession,
  );

  appTest(
    'face long press opens actions and creates a named person',
    (tester, env) async {
      final id = await seedFace(env.db, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/unsorted')],
      );
      await tester.longPress(find.byKey(Key('face-$id')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('people-action-assign')), findsOneWidget);
      await action(tester, 'create');
      await tester.enterText(find.byKey(const Key('action-name')), 'Lina');
      await tester.tap(find.byKey(const Key('action-name-save')));
      await tester.pumpAndSettle();
      final person = (await env.db.select(env.db.persons).get()).single;
      expect(person.name, 'Lina');
      expect(
        (await env.db.select(env.db.faces).get()).single.personId,
        person.id,
      );
    },
    session: testSession,
  );

  appTest(
    'face hiding has a separate Hidden view and undo preserves assignment',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      final id = await seedFace(env.db, personId: person, seed: 1);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$person')],
      );
      await tester.longPress(find.byKey(Key('face-$id')));
      await tester.pumpAndSettle();
      await action(tester, 'hide');
      expect(find.byKey(Key('face-$id')), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final face = (await env.db.select(env.db.faces).get()).single;
      expect((face.hidden, face.personId), (false, person));
      expect(find.byKey(Key('face-$id')), findsOneWidget);
    },
    session: testSession,
  );
}
