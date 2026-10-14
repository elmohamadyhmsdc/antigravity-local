// S10 Review (matches, new groups, duplicates, outfit links) and S11 Merge people.

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

class _Library {
  late int sara, anna, f1, f2, f3, g1, g2, g3, body;
}

/// Sara and Anna, three faces the PC thinks belong to them, a group of three new faces, the pair
/// Sara/Anna as possible duplicates, and a body matched to Sara by outfit.
Future<_Library> _seed(TestEnv env) async {
  final l = _Library();
  final db = env.db;
  l.sara = await seedPerson(db, name: 'Sara');
  l.anna = await seedPerson(db, name: 'Anna');
  await seedFace(db, personId: l.sara, seed: 1);
  await seedFace(db, personId: l.anna, seed: 2);
  l.f1 = await seedFace(db, seed: 3);
  l.f2 = await seedFace(db, seed: 4);
  l.f3 = await seedFace(db, seed: 5);
  l.g1 = await seedFace(db, seed: 6);
  l.g2 = await seedFace(db, seed: 7);
  l.g3 = await seedFace(db, seed: 8);
  for (final (face, person) in [
    (l.f1, l.sara),
    (l.f2, l.sara),
    (l.f3, l.anna),
  ]) {
    await db
        .into(db.reviewMatches)
        .insert(
          ReviewMatchesCompanion.insert(
            faceId: Value(face),
            personId: person,
            score: 0.45,
            margin: 0.1,
            decision: 'suggest',
          ),
        );
  }
  await db
      .into(db.reviewGroups)
      .insert(
        ReviewGroupsCompanion.insert(
          faceIds: '[${l.g1},${l.g2},${l.g3}]',
          cohesion: 0.55,
          quality: 0.7,
        ),
      );
  await db
      .into(db.reviewDuplicates)
      .insert(
        ReviewDuplicatesCompanion.insert(
          personA: l.sara,
          personB: l.anna,
          score: 0.55,
        ),
      );
  l.body = await seedBody(db, appearance: outfit(1));
  await db
      .into(db.reviewBodyLinks)
      .insert(
        ReviewBodyLinksCompanion.insert(
          bodyId: Value(l.body),
          personId: l.sara,
          method: 'appearance',
          confidence: 0.8,
        ),
      );
  return l;
}

Future<void> _open(WidgetTester tester, TestEnv env, String location) async {
  await env.pump(
    tester,
    extra: [initialLocationProvider.overrideWithValue(location)],
  );
  await _settle(tester);
}

void main() {
  group('Review', () {
    appTest('the header and the tabs count what needs a decision', (
      tester,
      env,
    ) async {
      await _seed(env);
      await _open(tester, env, '/review');
      expect(
        find.text('Review (6)'),
        findsOneWidget,
        reason: '3 matches + 1 group + 1 duplicate + 1 outfit link',
      );
      expect(find.text('Matches (3)'), findsOneWidget);
      expect(find.text('New groups (1)'), findsOneWidget);
      expect(find.text('Duplicates (1)'), findsOneWidget);
      expect(find.text('Outfits (1)'), findsOneWidget);
    }, session: testSession);

    appTest('an empty review says there is nothing to do', (tester, env) async {
      await _open(tester, env, '/review');
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('No faces waiting to be matched'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('review-tab-groups')));
      await tester.tap(find.byKey(const Key('review-tab-groups')));
      await _settle(tester);
      expect(find.text('No new groups to review'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('review-tab-duplicates')),
      );
      await tester.tap(find.byKey(const Key('review-tab-duplicates')));
      await _settle(tester);
      expect(find.text('No people look like duplicates'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('review-tab-outfits')));
      await tester.tap(find.byKey(const Key('review-tab-outfits')));
      await _settle(tester);
      expect(find.text('No outfit matches to review'), findsOneWidget);
    }, session: testSession);

    group('Matches', () {
      appTest('accept only the faces that stay ticked', (tester, env) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        expect(find.byKey(Key('match-card-${l.sara}')), findsOneWidget);
        expect(find.byKey(Key('match-card-${l.anna}')), findsOneWidget);

        await tester.tap(find.byKey(Key('match-face-${l.f2}'))); // untick
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(Key('match-card-${l.sara}')),
            matching: find.text('Add 1 face'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(Key('match-accept-${l.sara}')));
        await _settle(tester);

        final owner = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect(owner[l.f1], l.sara);
        expect(owner[l.f2], isNull);
        expect(find.text('Matches (2)'), findsOneWidget);
      }, session: testSession);

      appTest(
        '"Not them" remembers the rejection and the suggestion is gone',
        (tester, env) async {
          final l = await _seed(env);
          await _open(tester, env, '/review');
          await tester.tap(find.byKey(Key('match-reject-${l.anna}')));
          await _settle(tester);
          final rejections = await env.db.select(env.db.faceRejections).get();
          expect(rejections.map((r) => (r.faceId, r.personId)), [
            (l.f3, l.anna),
          ]);
          expect(find.byKey(Key('match-card-${l.anna}')), findsNothing);
        },
        session: testSession,
      );

      appTest(
        '"Accept all" asks first, then sorts every suggested face',
        (tester, env) async {
          final l = await _seed(env);
          await _open(tester, env, '/review');
          await tester.tap(find.byKey(const Key('accept-all-matches')));
          await _settle(tester);
          await tester.tap(find.text('Cancel'));
          await _settle(tester);
          expect(
            (await env.db.select(env.db.faces).get())
                .where((f) => f.personId != null)
                .length,
            2,
            reason: 'cancel changes nothing',
          );

          await tester.tap(find.byKey(const Key('accept-all-matches')));
          await _settle(tester);
          await tester.tap(find.text('Accept').last);
          await _settle(tester);
          final owner = {
            for (final f in await env.db.select(env.db.faces).get())
              f.id: f.personId,
          };
          expect(
            (owner[l.f1], owner[l.f2], owner[l.f3]),
            (l.sara, l.sara, l.anna),
          );
          expect(find.text('No faces waiting to be matched'), findsOneWidget);
        },
        session: testSession,
      );
    });

    group('New groups', () {
      Future<void> groupsTab(WidgetTester tester) async {
        await tester.ensureVisible(find.byKey(const Key('review-tab-groups')));
        await tester.tap(find.byKey(const Key('review-tab-groups')));
        await _settle(tester);
      }

      appTest('create a person from a group, with a name', (tester, env) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        await groupsTab(tester);
        final id = (await env.db.select(env.db.reviewGroups).get()).single.id;
        await tester.enterText(find.byKey(Key('group-name-$id')), 'Lina');
        await tester.tap(find.byKey(Key('group-create-$id')));
        await _settle(tester);

        final lina = (await env.db.select(env.db.persons).get()).firstWhere(
          (p) => p.name == 'Lina',
        );
        final owners = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect(
          [owners[l.g1], owners[l.g2], owners[l.g3]],
          [lina.id, lina.id, lina.id],
        );
        expect(lina.avatarFaceId, isNotNull);
        expect(find.text('No new groups to review'), findsOneWidget);
      }, session: testSession);

      appTest(
        '"Not a person" hides the faces from later suggestions',
        (tester, env) async {
          await _seed(env);
          await _open(tester, env, '/review');
          await groupsTab(tester);
          final id = (await env.db.select(env.db.reviewGroups).get()).single.id;
          await tester.tap(find.byKey(Key('group-dismiss-$id')));
          await _settle(tester);
          final dismissed = (await env.db.select(env.db.faces).get())
              .where((f) => f.reviewDismissed)
              .length;
          expect(dismissed, 3);
          expect(find.text('No new groups to review'), findsOneWidget);
        },
        session: testSession,
      );

      appTest('add the whole group to someone who already exists', (
        tester,
        env,
      ) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        await groupsTab(tester);
        final id = (await env.db.select(env.db.reviewGroups).get()).single.id;
        await tester.tap(find.byKey(Key('group-add-$id')));
        await _settle(tester);
        await tester.tap(find.byKey(Key('person-picker-${l.anna}')));
        await _settle(tester);
        final owners = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect(
          [owners[l.g1], owners[l.g2], owners[l.g3]],
          [l.anna, l.anna, l.anna],
        );
      }, session: testSession);

      appTest(
        '"Create N people" turns every group into a person at once',
        (tester, env) async {
          await _seed(env);
          await _open(tester, env, '/review');
          await groupsTab(tester);
          await tester.tap(find.byKey(const Key('create-all-groups')));
          await _settle(tester);
          expect((await env.db.select(env.db.persons).get()).length, 3);
          expect(find.text('No new groups to review'), findsOneWidget);
        },
        session: testSession,
      );
    });

    group('Duplicates and S11 Merge', () {
      Future<int> compare(WidgetTester tester, _Library l) async {
        await tester.ensureVisible(
          find.byKey(const Key('review-tab-duplicates')),
        );
        await tester.tap(find.byKey(const Key('review-tab-duplicates')));
        await _settle(tester);
        expect(find.text('55% alike'), findsOneWidget);
        await tester.tap(find.byKey(Key('dup-compare-${l.sara}-${l.anna}')));
        await _settle(tester);
        return l.sara;
      }

      appTest(
        '"They are different people" is remembered and the pair is not suggested again',
        (tester, env) async {
          final l = await _seed(env);
          await _open(tester, env, '/review');
          await tester.ensureVisible(
            find.byKey(const Key('review-tab-duplicates')),
          );
          await tester.tap(find.byKey(const Key('review-tab-duplicates')));
          await _settle(tester);
          await tester.tap(find.byKey(Key('dup-distinct-${l.sara}-${l.anna}')));
          await _settle(tester);
          final pair =
              (await env.db.select(env.db.personDistinct).get()).single;
          expect((pair.personA, pair.personB), (l.sara, l.anna));
          expect(find.text('No people look like duplicates'), findsOneWidget);
        },
        session: testSession,
      );

      appTest(
        'compare shows both people and the PC\'s score; merging moves everything and opens the result',
        (tester, env) async {
          final l = await _seed(env);
          await seedFace(env.db, personId: l.anna, seed: 40);
          await _open(tester, env, '/review');
          await compare(tester, l);

          expect(find.text('Merge people'), findsOneWidget);
          expect(find.byKey(const Key('merge-score')), findsOneWidget);
          expect(find.text('55% alike'), findsOneWidget);
          expect(
            find.text('Merge Anna into Sara'),
            findsOneWidget,
            reason: 'by default the first person is kept',
          );

          await tester.tap(find.text('Keep B'));
          await tester.pumpAndSettle();
          expect(find.text('Merge Sara into Anna'), findsOneWidget);
          await tester.tap(find.text('Keep A'));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('merge-confirm')));
          await _settle(tester);
          expect(find.text('Merge these people?'), findsOneWidget);
          await tester.tap(find.text('Merge').last);
          await _settle(tester);

          final people = await env.db.select(env.db.persons).get();
          expect(people.map((p) => p.name), ['Sara'], reason: 'Anna is gone');
          final faces = await env.db.select(env.db.faces).get();
          expect(
            faces.where((f) => f.personId == l.sara).length,
            3,
            reason: "Sara's 1 + Anna's 2",
          );
          expect(
            find.byKey(const Key('person-title')),
            findsOneWidget,
            reason: 'the merged person opens',
          );
        },
        session: testSession,
      );

      appTest(
        '"They are different people" on the merge screen records it and leaves',
        (tester, env) async {
          final l = await _seed(env);
          await _open(tester, env, '/merge/${l.sara}/${l.anna}');
          await tester.tap(find.byKey(const Key('merge-distinct')));
          await _settle(tester);
          expect(
            await env.db.select(env.db.personDistinct).get(),
            hasLength(1),
          );
          expect(await env.db.select(env.db.persons).get(), hasLength(2));
        },
        session: testSession,
      );

      appTest(
        'a pair the PC did not flag can still be compared and says so',
        (tester, env) async {
          final a = await seedPerson(env.db, name: 'Ola');
          final b = await seedPerson(env.db, name: 'Mona');
          await _open(tester, env, '/merge/$a/$b');
          expect(find.text('Not flagged by your PC'), findsOneWidget);
        },
        session: testSession,
      );
    });

    group('Outfit links', () {
      Future<void> outfits(WidgetTester tester) async {
        await tester.ensureVisible(find.byKey(const Key('review-tab-outfits')));
        await tester.tap(find.byKey(const Key('review-tab-outfits')));
        await _settle(tester);
      }

      appTest('accepting links the body to the person by hand', (
        tester,
        env,
      ) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        await outfits(tester);
        await tester.tap(find.byKey(Key('outfit-accept-${l.body}')));
        await _settle(tester);
        final b = (await env.db.select(env.db.bodies).get()).single;
        expect((b.personId, b.linkMethod), (l.sara, 'manual'));
        expect(find.text('No outfit matches to review'), findsOneWidget);
      }, session: testSession);

      appTest('rejecting remembers it', (tester, env) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        await outfits(tester);
        await tester.tap(find.byKey(Key('outfit-reject-${l.body}')));
        await _settle(tester);
        expect(
          (await env.db.select(env.db.bodyRejections).get()).single.personId,
          l.sara,
        );
        expect(
          (await env.db.select(env.db.bodies).get()).single.personId,
          isNull,
        );
      }, session: testSession);

      appTest('"Accept all" links every suggested body', (tester, env) async {
        final l = await _seed(env);
        await _open(tester, env, '/review');
        await outfits(tester);
        await tester.tap(find.byKey(const Key('accept-all-outfits')));
        await _settle(tester);
        expect(
          (await env.db.select(env.db.bodies).get()).single.personId,
          l.sara,
        );
      }, session: testSession);
    });
  });
}
