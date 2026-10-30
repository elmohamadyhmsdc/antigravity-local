// S03 Home: PC status chip (connected / busy / offline / revoked), library stats read from the
// local database, forgetting the PC.

import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

Finder _chip(String label) => find.descendant(
  of: find.byKey(const Key('status-chip')),
  matching: find.text(label),
);

Future<void> _addFace(TestEnv env, {int? personId, int? mediaId}) => env.db
    .into(env.db.faces)
    .insert(
      FacesCompanion.insert(
        mediaId: Value(mediaId),
        personId: Value(personId),
        modelId: 'buffalo_l@1',
        embedding: Uint8List(2048),
        qualityScore: 0.7,
        qualityVersion: 2,
        detScore: 0.9,
        facePx: 100,
        sharpness: 200,
        bboxX: 0.1,
        bboxY: 0.1,
        bboxW: 0.2,
        bboxH: 0.2,
        createdAt: 1,
      ),
    );

void main() {
  group('status chip', () {
    appTest('connected: shows the PC name, no banner', (tester, env) async {
      await env.pump(tester);
      expect(_chip('RTX-PC'), findsOneWidget);
      expect(find.byKey(const Key('status-banner')), findsNothing);
    }, session: testSession);

    appTest('busy: shows the GPU job that holds the PC', (tester, env) async {
      env.api.capabilities_ = Capabilities.fromJson(
        fixture('Capabilities.busy_with_dashboard_job'),
      );
      await env.pump(tester);
      expect(_chip('RTX-PC - busy'), findsOneWidget);
      expect(textContaining('busy with a reface_video_v3 job'), findsOneWidget);
    }, session: testSession);

    appTest('offline: says so and tapping the chip checks again', (
      tester,
      env,
    ) async {
      env.api.capabilitiesError = ApiException.network('refused');
      await env.pump(tester);
      expect(_chip('PC offline'), findsOneWidget);
      expect(textContaining('Cannot reach your PC'), findsOneWidget);

      env.api.capabilitiesError = null; // the server came back
      await tester.tap(find.byKey(const Key('status-chip')));
      await tester.pumpAndSettle();
      expect(_chip('RTX-PC'), findsOneWidget);
      expect(find.byKey(const Key('status-banner')), findsNothing);
    }, session: testSession);

    appTest(
      'revoked: the PC no longer accepts this phone; "Pair again" returns to Welcome',
      (tester, env) async {
        env.api.capabilitiesError = const ApiException(
          code: 'unauthorized',
          message: 'Missing or invalid device token.',
          statusCode: 401,
        );
        await env.pump(tester);
        expect(_chip('Pairing revoked'), findsOneWidget);
        await tester.tap(find.text('Pair again'));
        await tester.pumpAndSettle();
        expect(find.text('Connect to your PC'), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('library stats (from the local database)', () {
    appTest(
      'an empty library shows zeros and the empty-state card',
      (tester, env) async {
        await env.pump(tester);
        for (final label in ['People', 'Faces', 'Photos', 'Videos']) {
          expect(
            tester.widget<Text>(find.byKey(Key('stat-$label'))).data,
            '0',
            reason: label,
          );
        }
        expect(find.text('Your library is empty'), findsOneWidget);
        await revealForTap(tester, find.text('No unsorted faces'));
        expect(find.text('No unsorted faces'), findsOneWidget);
      },
      session: testSession,
    );

    appTest('counts follow what is stored, live', (tester, env) async {
      await env.pump(tester);
      // Written from the test's own zone (not tester.runAsync): the stream queries behind the
      // tiles share the database lock, which only advances inside this zone.
      final photo = await env.db
          .into(env.db.media)
          .insert(MediaCompanion.insert(assetId: 'a', kind: 'photo'));
      await env.db
          .into(env.db.media)
          .insert(MediaCompanion.insert(assetId: 'b', kind: 'photo'));
      await env.db
          .into(env.db.media)
          .insert(MediaCompanion.insert(assetId: 'c', kind: 'video'));
      final sara = await env.db
          .into(env.db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));
      await _addFace(env, personId: sara, mediaId: photo);
      await _addFace(env, mediaId: photo);
      await _addFace(env, mediaId: photo);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      String stat(String label) =>
          tester.widget<Text>(find.byKey(Key('stat-$label'))).data!;
      expect(
        (stat('People'), stat('Faces'), stat('Photos'), stat('Videos')),
        ('1', '3', '2', '1'),
      );
      expect(find.text('2 unsorted faces'), findsOneWidget);
      expect(find.text('Your library is empty'), findsNothing);
    }, session: testSession);
  });

  group('forget this PC', () {
    appTest(
      'asks first, then unpairs and returns to Welcome - the library stays',
      (tester, env) async {
        await env.secrets.write('token.srv_7f3a91c2', 'agm_x');
        await env.db.putSetting('strictness', 'balanced');
        await env.pump(tester);

        await tester.tap(find.byKey(const Key('home-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forget this PC'));
        await tester.pumpAndSettle();
        expect(find.text('Forget RTX-PC?'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          env.secrets.values.containsKey('token.srv_7f3a91c2'),
          isTrue,
          reason: 'cancel changes nothing',
        );

        await tester.tap(find.byKey(const Key('home-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forget this PC'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Forget'));
        await tester.pumpAndSettle();

        expect(find.text('Connect to your PC'), findsOneWidget);
        expect(
          env.secrets.values.containsKey('token.srv_7f3a91c2'),
          isFalse,
          reason: 'the token is deleted',
        );
        expect(
          await env.db.setting('strictness'),
          'balanced',
          reason: 'user data is untouched',
        );
      },
      session: testSession,
    );
  });

  appTest('"Detect faces in a photo" opens the analysis screen', (
    tester,
    env,
  ) async {
    await env.pump(tester);
    await revealForTap(
      tester,
      find.byKey(const Key('try-detection')),
      scrollable: find
          .descendant(
            of: find.byKey(const Key('home-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const Key('try-detection')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a photo'), findsOneWidget);
  }, session: testSession);
}
