import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest('mixed types share bulk flags without cross-kind merge', (
    tester,
    env,
  ) async {
    final person = await seedPerson(env.db, name: 'Alice');
    final character = await seedPerson(env.db, name: 'Hero');
    await (env.db.update(env.db.persons)..where((p) => p.id.equals(character)))
        .write(const PersonsCompanion(kind: Value('character')));
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/people')],
    );
    expect(find.byKey(Key('person-$person')), findsOneWidget);
    expect(find.byKey(Key('person-$character')), findsOneWidget);
    await tester.tap(find.byKey(const Key('people-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('person-$person')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('person-$character')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('people-selection-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('people-action-merge')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('people-more-actions')));
    await tester.tap(find.byKey(const Key('people-more-actions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('people-action-pin')), findsOneWidget);
    expect(find.byKey(const Key('people-action-export')), findsOneWidget);
  }, session: testSession);
  appTest(
    'character Reface entry requires a source face reference',
    (tester, env) async {
      final hero = await seedPerson(env.db, name: 'Hero');
      await (env.db.update(env.db.persons)..where((p) => p.id.equals(hero)))
          .write(const PersonsCompanion(kind: Value('character')));
      final face = await seedFace(env.db, personId: hero);
      await (env.db.update(
        env.db.faces,
      )..where((f) => f.id.equals(face))).write(
        const FacesCompanion(
          kind: Value('character'),
          modelId: Value(characterEmbeddingModelId),
        ),
      );
      env.picker.photo = tinyPng;
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/reface?person=$hero'),
        ],
      );
      await pickRefaceTarget(tester);
      await tester.ensureVisible(find.byKey(const Key('target-face-0')));
      await tester.tap(find.byKey(const Key('target-face-0')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('reface-next')));
      await tester.tap(find.byKey(const Key('reface-next')));
      await tester.pumpAndSettle();
      expect(find.text('Hero'), findsOneWidget);
      expect(find.byKey(const Key('reference-source-face')), findsOneWidget);
    },
    session: testSession,
  );
  appTest(
    'characters are reachable from People and offer an isolated photo test',
    (tester, env) async {
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await tester.tap(find.byKey(const Key('open-characters')));
      await tester.pumpAndSettle();
      expect(find.text('No characters yet'), findsOneWidget);
      await tester.tap(find.byKey(const Key('people-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-character-photo')));
      await tester.pumpAndSettle();
      expect(find.text('Test a character photo'), findsOneWidget);
      env.picker.photo = tinyPng;
      env.api.analyzeResult = AnalyzeImageResponse.fromJson(
        fixture('AnalyzeImageResponse.character_no_face'),
      );
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();
      expect(env.api.analyzeOptions.single.detectCharacters, isTrue);
      await tester.scrollUntilVisible(
        find.byKey(const Key('analyze-summary')),
        180,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 character appearances found'), findsOneWidget);
      expect(find.text('Character 1'), findsOneWidget);
      expect(
        await env.db.select(env.db.persons).get(),
        isEmpty,
        reason: 'testing one photo must never write the user library',
      );
      expect(await env.db.select(env.db.faces).get(), isEmpty);
    },
    session: testSession,
  );

  appTest(
    'characters are listed like people, apart from people, and open the same detail page',
    (tester, env) async {
      final db = env.db;
      Future<int> person(String kind, String name) => db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              name: Value(name),
              kind: Value(kind),
              createdAt: 1,
            ),
          );
      final hero = await person('character', 'Hero');
      final human = await person('person', 'Alice');
      for (final (kind, owner, n) in [
        ('character', hero, 2),
        ('person', human, 1),
      ]) {
        for (var i = 0; i < n; i++) {
          await db
              .into(db.faces)
              .insert(
                FacesCompanion.insert(
                  personId: Value(owner),
                  modelId: kind == 'character'
                      ? characterEmbeddingModelId
                      : 'buffalo_l@1',
                  embedding: packFloat32(
                    List.filled(kind == 'character' ? 768 : 512, 0),
                  ),
                  qualityScore: .9,
                  qualityVersion: 2,
                  detScore: .9,
                  facePx: 80,
                  sharpness: 1,
                  bboxX: 0,
                  bboxY: 0,
                  bboxW: .2,
                  bboxH: .2,
                  kind: Value(kind),
                  createdAt: 1,
                ),
              );
        }
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/characters')],
      );
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('2 faces'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-all-types')));
      await tester.pumpAndSettle();
      expect(find.text('Hero'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-people')));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Hero'), findsNothing);
      await tester.tap(find.byKey(const Key('open-characters')));
      await tester.pumpAndSettle();
      expect(find.text('Hero'), findsOneWidget);
      await tester.tap(find.byKey(Key('person-$hero')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('person-title')), findsOneWidget);
      expect(find.byKey(const Key('person-use-studio')), findsOneWidget);
      expect(find.byTooltip('Actions in media'), findsOneWidget);
    },
    session: testSession,
  );
}
