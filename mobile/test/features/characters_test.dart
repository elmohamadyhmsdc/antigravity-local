import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/scan/character_descriptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

void main() {
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
        await env.db.select(env.db.characterSamples).get(),
        isEmpty,
        reason: 'testing one photo must never write the user library',
      );
      expect(await env.db.select(env.db.faces).get(), isEmpty);
    },
    session: testSession,
  );

  appTest('character rename and separate controls correct a group', (
    tester,
    env,
  ) async {
    final db = env.db;
    final identity = await db
        .into(db.characterIdentities)
        .insert(CharacterIdentitiesCompanion.insert(createdAt: 1));
    for (var i = 0; i < 2; i++) {
      final media = await db
          .into(db.media)
          .insert(MediaCompanion.insert(assetId: 'art$i', kind: 'photo'));
      await db
          .into(db.characterSamples)
          .insert(
            CharacterSamplesCompanion.insert(
              identityId: identity,
              mediaId: media,
              modelId: characterModelId,
              descriptor: packFloat32(List.filled(160, 0)),
              bboxX: .1,
              bboxY: .1,
              bboxW: .5,
              bboxH: .8,
              score: .95,
              createdAt: 1,
            ),
          );
    }
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/characters')],
    );
    await tester.tap(find.text('Character 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hero');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Hero'), findsOneWidget);
    await tester.tap(find.byTooltip('Separate this character').first);
    await tester.pumpAndSettle();
    expect((await db.select(db.characterIdentities).get()).length, 2);
    expect((await db.select(db.characterSamples).get()).length, 2);
  }, session: testSession);
}
