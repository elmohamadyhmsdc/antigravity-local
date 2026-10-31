// S04 Library (grid + filters) and S06 Media viewer (who is in this photo, photos that are gone).

import 'package:antigravity_mobile/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(
    const Duration(milliseconds: 500),
  ); // the grid refreshes 400 ms after a change
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, TestEnv env, String location) async {
  await env.pump(
    tester,
    extra: [initialLocationProvider.overrideWithValue(location)],
  );
  await _settle(tester);
}

void main() {
  group('S04 Library', () {
    appTest('an empty library points to Sources', (tester, env) async {
      await _open(tester, env, '/library');
      expect(find.text('No photos yet'), findsOneWidget);
      await tester.tap(find.text('Choose albums'));
      await _settle(tester);
      expect(find.text('Albums to scan'), findsOneWidget);
    }, session: testSession);

    appTest(
      'photos appear as tiles with their face count; filters narrow the grid',
      (tester, env) async {
        final scanned = await seedMedia(env.db, asset: 'a', takenAt: 3000);
        final empty = await seedMedia(env.db, asset: 'b', takenAt: 2000);
        final waiting = await seedMedia(
          env.db,
          asset: 'c',
          status: 'pending',
          takenAt: 1000,
        );
        await seedFace(env.db, mediaId: scanned, seed: 1);
        await seedFace(env.db, mediaId: scanned, seed: 2);
        await _open(tester, env, '/library');

        for (final id in [scanned, empty, waiting]) {
          expect(find.byKey(Key('media-$id')), findsOneWidget);
        }
        expect(
          find.text('2'),
          findsOneWidget,
          reason: 'the face count badge of the first photo',
        );

        await tester.ensureVisible(find.byKey(const Key('filter-unscanned')));
        await tester.tap(find.byKey(const Key('filter-unscanned')));
        await _settle(tester);
        expect(find.byKey(Key('media-$waiting')), findsOneWidget);
        expect(find.byKey(Key('media-$scanned')), findsNothing);

        await tester.ensureVisible(find.byKey(const Key('filter-all')));
        await tester.tap(find.byKey(const Key('filter-all')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('filter-has-faces')));
        await tester.tap(find.byKey(const Key('filter-has-faces')));
        await _settle(tester);
        expect(find.byKey(Key('media-$scanned')), findsOneWidget);
        expect(find.byKey(Key('media-$empty')), findsNothing);

        await tester.ensureVisible(find.byKey(const Key('filter-failed')));
        await tester.tap(find.byKey(const Key('filter-failed')));
        await _settle(tester);
        expect(find.text('No photos match these filters'), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'filter by person shows their photos and can be cleared',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final withSara = await seedMedia(env.db, asset: 'a', takenAt: 2000);
        final without = await seedMedia(env.db, asset: 'b', takenAt: 1000);
        await seedFace(env.db, mediaId: withSara, personId: sara, seed: 1);
        await _open(tester, env, '/library');

        await tester.ensureVisible(find.byKey(const Key('filter-pick-person')));
        await tester.tap(find.byKey(const Key('filter-pick-person')));
        await _settle(tester);
        await tester.tap(find.byKey(Key('person-picker-$sara')));
        await _settle(tester);
        expect(find.byKey(const Key('filter-person')), findsOneWidget);
        expect(find.byKey(Key('media-$withSara')), findsOneWidget);
        expect(find.byKey(Key('media-$without')), findsNothing);

        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('filter-person')),
            matching: find.byIcon(Icons.cancel),
          ),
        );
        await _settle(tester);
        expect(find.byKey(Key('media-$without')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'the grid follows the database while a scan adds photos',
      (tester, env) async {
        await seedMedia(env.db, asset: 'a');
        await _open(tester, env, '/library');
        final later = await seedMedia(env.db, asset: 'b', takenAt: 5000);
        await _settle(tester);
        expect(find.byKey(Key('media-$later')), findsOneWidget);
      },
      session: testSession,
    );
  });

  group('S06 Media viewer', () {
    appTest(
      'who is in this photo: people as chips, the rest as "unsorted"',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final photo = await seedMedia(env.db, asset: 'a');
        await seedFace(env.db, mediaId: photo, personId: sara, seed: 1);
        await seedFace(env.db, mediaId: photo, seed: 2, x: 0.5);
        await _open(tester, env, '/media/$photo');
        expect(find.text('Who is here'), findsOneWidget);
        expect(find.byKey(Key('who-$sara')), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
        // the original is not available in this test: the viewer says so instead of crashing
        expect(find.text('Photo not found'), findsOneWidget);

        await tester.tap(find.byKey(Key('who-$sara')));
        await _settle(tester);
        expect(
          find.byKey(const Key('person-title')),
          findsOneWidget,
          reason: 'a chip opens the person',
        );
      },
      session: testSession,
    );

    appTest('a photo that was not scanned yet says so', (tester, env) async {
      final photo = await seedMedia(env.db, asset: 'a', status: 'pending');
      await _open(tester, env, '/media/$photo');
      expect(find.text('This photo has not been scanned yet.'), findsOneWidget);
    }, session: testSession);

    appTest('a scanned photo with no faces says so', (tester, env) async {
      final photo = await seedMedia(env.db, asset: 'a');
      await _open(tester, env, '/media/$photo');
      expect(find.text('No faces were found in this photo.'), findsOneWidget);
    }, session: testSession);

    appTest(
      'a photo that is no longer in the library does not crash',
      (tester, env) async {
        await _open(tester, env, '/media/404');
        expect(find.text('Photo not found'), findsOneWidget);
      },
      session: testSession,
    );
  });
}
