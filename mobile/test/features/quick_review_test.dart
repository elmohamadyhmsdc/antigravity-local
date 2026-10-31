// S10 quick review (one question at a time), words vs numbers, the People banner, the album
// "Review N photos" grid and the Remove-from-person sheet.

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, TestEnv env, String location) async {
  await env.pump(
    tester,
    extra: [initialLocationProvider.overrideWithValue(location)],
  );
  await _settle(tester);
}

Future<void> _match(AppDatabase db, int face, int person, double score) => db
    .into(db.reviewMatches)
    .insert(
      ReviewMatchesCompanion.insert(
        faceId: Value(face),
        personId: person,
        score: score,
        margin: 0.1,
        decision: 'suggest',
      ),
      mode: InsertMode.insertOrReplace,
    );

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await _settle(tester);
}

String _question(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quick-question'))).data!;

String _likelihood(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quick-likelihood'))).data!;

String _progress(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('quick-progress'))).data!;

class _Matches {
  late int sara, anna, sure, unsure, other;
}

/// Sara and Anna with one face each, plus three unsorted faces the PC is more or less sure about.
Future<_Matches> _seedMatches(AppDatabase db) async {
  final m = _Matches();
  m.sara = await seedPerson(db, name: 'Sara');
  m.anna = await seedPerson(db, name: 'Anna');
  await seedFace(db, personId: m.sara, seed: 1);
  await seedFace(db, personId: m.anna, seed: 2);
  m.sure = await seedFace(db, seed: 3);
  m.unsure = await seedFace(db, seed: 4);
  m.other = await seedFace(db, seed: 5);
  await _match(db, m.sure, m.sara, 0.45); // very likely
  await _match(db, m.unsure, m.sara, 0.28); // maybe
  await _match(db, m.other, m.anna, 0.35); // likely
  return m;
}

void main() {
  group('Quick review', () {
    appTest(
      'yes, no and not sure, most certain first, each stored as the usual correction',
      (tester, env) async {
        final m = await _seedMatches(env.db);
        await _open(tester, env, '/review');

        expect(find.text('Quick review'), findsOneWidget);
        expect(_progress(tester), '1 of 3');
        expect(_question(tester), 'Is this Sara?');
        expect(_likelihood(tester), 'Very likely');
        expect(find.textContaining('%'), findsNothing);

        await _tap(tester, 'quick-yes');
        expect(
          (await (env.db.select(
            env.db.faces,
          )..where((f) => f.id.equals(m.sure))).getSingle()).personId,
          m.sara,
        );

        expect(_progress(tester), '2 of 3');
        expect(_question(tester), 'Is this Anna?');
        expect(_likelihood(tester), 'Likely');
        await _tap(tester, 'quick-no');
        final rejection =
            (await env.db.select(env.db.faceRejections).get()).single;
        expect((rejection.faceId, rejection.personId), (m.other, m.anna));

        expect(_progress(tester), '3 of 3');
        expect(_likelihood(tester), 'Maybe');
        await _tap(tester, 'quick-unsure');
        final snooze = (await env.db.select(env.db.reviewSnoozes).get()).single;
        expect(snooze.questionKey, 'm:${m.unsure}:${m.sara}');
        expect(
          (await (env.db.select(
            env.db.faces,
          )..where((f) => f.id.equals(m.unsure))).getSingle()).personId,
          isNull,
          reason: '"Not sure" decides nothing',
        );
        expect(find.byKey(const Key('quick-all-done')), findsOneWidget);
        expect(
          find.textContaining("1 answer you weren't sure about"),
          findsOneWidget,
          reason: 'the snoozed question is still in the full lists',
        );
      },
      session: testSession,
    );

    appTest(
      '"Not sure" stays parked until the score rises, then comes back',
      (tester, env) async {
        final m = await _seedMatches(env.db);
        await env.db.delete(env.db.reviewMatches).go();
        await _match(env.db, m.unsure, m.sara, 0.28);
        await _open(tester, env, '/review');
        await _tap(tester, 'quick-unsure');
        expect(find.byKey(const Key('quick-all-done')), findsOneWidget);

        // the next grouping run brings the same evidence: still parked
        await _match(env.db, m.unsure, m.sara, 0.29);
        await _settle(tester);
        expect(find.byKey(const Key('quick-all-done')), findsOneWidget);

        // new photos made the PC surer: asked again
        await _match(env.db, m.unsure, m.sara, 0.42);
        await _settle(tester);
        expect(_question(tester), 'Is this Sara?');
        expect(_likelihood(tester), 'Very likely');
      },
      session: testSession,
    );

    appTest('a parked new group returns once it has more faces', (
      tester,
      env,
    ) async {
      final a = await seedFace(env.db, seed: 11);
      final b = await seedFace(env.db, seed: 12);
      final c = await seedFace(env.db, seed: 13);
      await env.db
          .into(env.db.reviewGroups)
          .insert(
            ReviewGroupsCompanion.insert(
              faceIds: '[$a,$b]',
              cohesion: 0.5,
              quality: 0.7,
            ),
          );
      await _open(tester, env, '/review');
      expect(_question(tester), 'Who is this?');
      await _tap(tester, 'quick-unsure');
      expect(find.byKey(const Key('quick-all-done')), findsOneWidget);

      await env.db.delete(env.db.reviewGroups).go();
      await env.db
          .into(env.db.reviewGroups)
          .insert(
            ReviewGroupsCompanion.insert(
              faceIds: '[$a,$b,$c]',
              cohesion: 0.5,
              quality: 0.7,
            ),
          );
      await _settle(tester);
      expect(_question(tester), 'Who is this?');
      expect(find.text('3 photos of this face'), findsOneWidget);
    }, session: testSession);

    appTest('swiping right says yes, swiping left says no', (
      tester,
      env,
    ) async {
      final m = await _seedMatches(env.db);
      await _open(tester, env, '/review');
      await tester.drag(
        find.byKey(const Key('quick-card')),
        const Offset(400, 0),
      );
      await _settle(tester);
      expect(
        (await (env.db.select(
          env.db.faces,
        )..where((f) => f.id.equals(m.sure))).getSingle()).personId,
        m.sara,
      );
      await tester.drag(
        find.byKey(const Key('quick-card')),
        const Offset(-400, 0),
      );
      await _settle(tester);
      expect(
        (await env.db.select(env.db.faceRejections).get()).single.faceId,
        m.other,
      );
    }, session: testSession);

    appTest(
      '"Who is this?" adds a group to an existing person or names a new one',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        await seedFace(env.db, personId: sara, seed: 1);
        final g1 = await seedFace(env.db, seed: 6, quality: 0.9);
        final g2 = await seedFace(env.db, seed: 7);
        final h1 = await seedFace(env.db, seed: 8);
        final h2 = await seedFace(env.db, seed: 9);
        for (final ids in ['[$g1,$g2]', '[$h1,$h2]']) {
          await env.db
              .into(env.db.reviewGroups)
              .insert(
                ReviewGroupsCompanion.insert(
                  faceIds: ids,
                  cohesion: 0.6,
                  quality: 0.7,
                ),
              );
        }
        await _open(tester, env, '/review');
        expect(_question(tester), 'Who is this?');
        expect(find.byKey(const Key('quick-group-faces')), findsOneWidget);

        await tester.enterText(find.byKey(const Key('quick-group-name')), 'Sa');
        await _settle(tester);
        await tester.tap(find.byKey(Key('quick-group-option-$sara')));
        await _settle(tester);
        expect(find.text('Adds these faces to Sara'), findsOneWidget);
        await _tap(tester, 'quick-yes');
        final faces = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect((faces[g1], faces[g2]), (sara, sara));

        expect(_progress(tester), '2 of 2');
        await tester.enterText(
          find.byKey(const Key('quick-group-name')),
          'sara',
        );
        await _settle(tester);
        expect(
          find.text('Adds these faces to Sara'),
          findsOneWidget,
          reason: 'an exact existing name is the same as picking it',
        );
        await tester.enterText(
          find.byKey(const Key('quick-group-name')),
          'Lina',
        );
        await _settle(tester);
        await _tap(tester, 'quick-yes');
        final lina = (await env.db.select(env.db.persons).get()).singleWhere(
          (p) => p.name == 'Lina',
        );
        final after = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect((after[h1], after[h2]), (lina.id, lina.id));
        expect(await env.db.select(env.db.reviewGroups).get(), isEmpty);
      },
      session: testSession,
    );

    appTest(
      '"Same person?" merges; "Is this Sara? Recognised by clothes" links the body',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final unnamed = await seedPerson(env.db);
        await seedFace(env.db, personId: sara, seed: 1);
        await seedFace(env.db, personId: sara, seed: 2);
        final moved = await seedFace(env.db, personId: unnamed, seed: 3);
        await env.db
            .into(env.db.reviewDuplicates)
            .insert(
              ReviewDuplicatesCompanion.insert(
                personA: sara,
                personB: unnamed,
                score: 0.5,
              ),
            );
        final body = await seedBody(env.db, appearance: outfit(1));
        await env.db
            .into(env.db.reviewBodyLinks)
            .insert(
              ReviewBodyLinksCompanion.insert(
                bodyId: Value(body),
                personId: sara,
                method: 'appearance',
                confidence: 0.81,
              ),
            );
        await _open(tester, env, '/review');

        expect(_question(tester), 'Same person?');
        expect(_likelihood(tester), 'Likely');
        expect(find.byKey(Key('quick-pair-$sara')), findsOneWidget);
        await _tap(tester, 'quick-yes');
        expect((await env.db.select(env.db.persons).get()).single.id, sara);
        expect(
          (await (env.db.select(
            env.db.faces,
          )..where((f) => f.id.equals(moved))).getSingle()).personId,
          sara,
        );

        expect(_question(tester), 'Is this Sara?');
        expect(_likelihood(tester), 'Recognised by clothes · Likely');
        await _tap(tester, 'quick-yes');
        final row = await (env.db.select(
          env.db.bodies,
        )..where((b) => b.id.equals(body))).getSingle();
        expect(row.personId, sara);
        expect(find.byKey(const Key('quick-all-done')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'Advanced details shows percentages and makes the four tabs the default',
      (tester, env) async {
        await _seedMatches(env.db);
        await _open(tester, env, '/review');
        expect(_likelihood(tester), 'Very likely');

        await tester.tap(find.byKey(const Key('quick-menu')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('quick-advanced')));
        await _settle(tester);
        expect(await env.db.setting('review.advanced'), '1');
        expect(
          _likelihood(tester),
          '45% alike',
          reason: 'numbers right away, still on the quick review',
        );
        expect(find.byKey(const Key('quick-question')), findsOneWidget);

        await tester.tap(find.byKey(const Key('quick-see-all')));
        await _settle(tester);
        expect(find.byKey(const Key('review-tab-matches')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'with Advanced details on, /review opens the four tabs',
      (tester, env) async {
        await _seedMatches(env.db);
        await env.db.putSetting('review.advanced', '1');
        await _open(tester, env, '/review');
        expect(find.byKey(const Key('review-tab-matches')), findsOneWidget);
        expect(find.byKey(const Key('quick-question')), findsNothing);
        await tester.tap(find.byKey(const Key('review-open-quick')));
        await _settle(tester);
        expect(find.byKey(const Key('quick-question')), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('Entry points', () {
    appTest(
      'People shows how many questions wait and opens the quick review',
      (tester, env) async {
        await _seedMatches(env.db);
        await _open(tester, env, '/people');
        expect(
          find.text('Help improve your groups · 3 questions'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('people-review-banner')));
        await _settle(tester);
        expect(find.byKey(const Key('quick-question')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'album review: everything starts ticked, untick the strangers, Done decides all',
      (tester, env) async {
        final m = await _seedMatches(env.db);
        final body = await seedBody(env.db, appearance: outfit(2));
        await env.db
            .into(env.db.reviewBodyLinks)
            .insert(
              ReviewBodyLinksCompanion.insert(
                bodyId: Value(body),
                personId: m.sara,
                method: 'appearance',
                confidence: 0.8,
              ),
            );
        await _open(tester, env, '/people/${m.sara}');
        expect(find.text('Review 3 photos'), findsOneWidget);
        await tester.tap(find.byKey(const Key('album-review-banner')));
        await _settle(tester);

        expect(find.byKey(const Key('album-review-grid')), findsOneWidget);
        expect(find.text('3 to add · 0 someone else'), findsOneWidget);
        await tester.tap(find.byKey(Key('album-review-f-${m.unsure}')));
        await _settle(tester);
        expect(find.text('2 to add · 1 someone else'), findsOneWidget);

        await tester.tap(find.byKey(const Key('album-review-done')));
        await _settle(tester);
        final faces = {
          for (final f in await env.db.select(env.db.faces).get())
            f.id: f.personId,
        };
        expect(faces[m.sure], m.sara);
        expect(faces[m.unsure], isNull);
        expect(
          (await env.db.select(env.db.faceRejections).get()).map(
            (r) => (r.faceId, r.personId),
          ),
          [(m.unsure, m.sara)],
        );
        final linked = await (env.db.select(
          env.db.bodies,
        )..where((b) => b.id.equals(body))).getSingle();
        expect(linked.personId, m.sara);
        expect(faces[m.other], isNull, reason: "Anna's suggestion untouched");
        expect(find.byKey(const Key('album-review-banner')), findsNothing);
      },
      session: testSession,
    );

    appTest(
      'Remove from person: "This is someone else" records a rejection',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final face = await seedFace(env.db, personId: sara, seed: 1);
        await seedFace(env.db, personId: sara, seed: 2);
        await _open(tester, env, '/people/$sara');
        await tester.tap(find.byKey(Key('face-menu-$face')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('people-action-remove')));
        await _settle(tester);
        expect(find.byKey(const Key('people-action-notAFace')), findsOneWidget);
        expect(find.byKey(const Key('people-action-moveTo')), findsOneWidget);
        await tester.tap(find.byKey(const Key('people-action-someoneElse')));
        await _settle(tester);
        final row = (await env.db.select(env.db.faceRejections).get()).single;
        expect((row.faceId, row.personId), (face, sara));
        expect(
          (await (env.db.select(
            env.db.faces,
          )..where((f) => f.id.equals(face))).getSingle()).personId,
          isNull,
        );
      },
      session: testSession,
    );

    appTest('Remove from person: "Not a face" hides it', (tester, env) async {
      final sara = await seedPerson(env.db, name: 'Sara');
      final face = await seedFace(env.db, personId: sara, seed: 1);
      await seedFace(env.db, personId: sara, seed: 2);
      await _open(tester, env, '/people/$sara');
      await tester.tap(find.byKey(Key('face-menu-$face')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('people-action-remove')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('people-action-notAFace')));
      await _settle(tester);
      final row = await (env.db.select(
        env.db.faces,
      )..where((f) => f.id.equals(face))).getSingle();
      expect(row.hidden, isTrue);
    }, session: testSession);

    appTest(
      'the photo viewer lists every face with a pencil to reassign it',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final anna = await seedPerson(env.db, name: 'Anna');
        final photo = await seedMedia(env.db, asset: 'a');
        final face = await seedFace(
          env.db,
          mediaId: photo,
          personId: sara,
          seed: 1,
        );
        final stranger = await seedFace(
          env.db,
          mediaId: photo,
          seed: 2,
          x: 0.5,
        );
        await _open(tester, env, '/media/$photo');
        expect(find.byKey(Key('who-edit-$face')), findsOneWidget);
        expect(find.byKey(Key('who-edit-$stranger')), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);

        await tester.tap(find.byKey(Key('who-edit-$face')));
        await _settle(tester);
        await tester.tap(find.byKey(Key('person-picker-$anna')));
        await _settle(tester);
        expect(
          (await (env.db.select(
            env.db.faces,
          )..where((f) => f.id.equals(face))).getSingle()).personId,
          anna,
        );
      },
      session: testSession,
    );
  });
}
