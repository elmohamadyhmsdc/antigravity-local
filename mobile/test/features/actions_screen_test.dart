import 'dart:convert';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/action_frames.dart';
import 'package:antigravity_mobile/data/repositories/video_actions_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest(
    'suggestion is explicitly accepted and filters are available',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'match-photo');
      final person = await seedPerson(env.db, name: 'Mira');
      final repo = VideoActionsRepository(env.db);
      final actionId = await repo.saveAction('Greeting');
      final row = (await env.db.select(env.db.settings).get()).singleWhere(
        (s) => s.key == '$actionCatalogPrefix$actionId',
      );
      final doc = jsonDecode(row.value) as Map<String, dynamic>;
      doc['matches'] = [
        {
          'id': 'candidate',
          'action': actionId,
          'example': 'sample',
          'media': media,
          'start': 0,
          'end': 0,
          'people': [person],
          'similarity': .91,
          'state': 'suggested',
          'kind': 'photo',
          'asset': 'match-photo',
          'modified': 1000,
        },
      ];
      await env.db.putSetting(row.key, jsonEncode(doc));
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/discover')],
        settle: false,
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await revealForTap(tester, find.text('Actions'));
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Greeting'));
      await tester.pumpAndSettle();
      await revealForTap(tester, find.text('Accept'));
      expect(
        find.textContaining('91% configuration similarity'),
        findsOneWidget,
      );
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.textContaining('confirmed'), findsOneWidget);
      expect(find.text('Review status'), findsOneWidget);
      expect(find.text('Media type'), findsOneWidget);
      expect(find.text('Participant'), findsOneWidget);
    },
    session: testSession,
  );
  appTest(
    'photo action is named from the original and remains in the shared catalog',
    (tester, env) async {
      final media = await seedMedia(
        env.db,
        asset: 'action-photo',
        width: 1000,
        height: 1500,
      );
      final person = await seedPerson(env.db, name: 'Mira');
      final body = await seedBody(env.db, mediaId: media, personId: person);
      final points = [
        [.5, .2],
        [.53, .19],
        [.47, .19],
        [.56, .2],
        [.44, .2],
        [.65, .27],
        [.35, .27],
        [.67, .37],
        [.33, .37],
        [.68, .47],
        [.32, .47],
        [.56, .53],
        [.44, .53],
        [.56, .70],
        [.44, .70],
        [.56, .87],
        [.44, .87],
      ];
      await (env.db.update(
        env.db.bodies,
      )..where((b) => b.id.equals(body))).write(
        BodiesCompanion(
          kpts: Value(
            jsonEncode([
              for (final p in points) [...p, .9],
            ]),
          ),
          extent: const Value('full'),
        ),
      );
      env.library.bytes['action-photo'] = tinyPng;
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/media/$media')],
        settle: false,
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Tools').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name an action'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find participants'));
      await tester.pumpAndSettle();
      expect(find.text('Mira'), findsOneWidget);
      await tester.tap(find.text('Mira'));
      await tester.enterText(
        find.widgetWithText(TextField, 'New action name'),
        'Greeting',
      );
      await revealForTap(tester, find.text('Save example'));
      await tester.tap(find.text('Save example'));
      await tester.pumpAndSettle();
      final rows = (await env.db.select(env.db.settings).get())
          .where((s) => s.key.startsWith(actionCatalogPrefix))
          .toList();
      final action = jsonDecode(rows.single.value) as Map<String, dynamic>;
      expect(action['name'], 'Greeting');
      final example = (action['examples'] as List).single;
      expect(example['kind'], 'photo');
      expect(example['people'], [person]);
    },
    session: testSession,
  );
}
