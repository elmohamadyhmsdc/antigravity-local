// S04 Library (grid + filters) and S06 Media viewer (who is in this photo, photos that are gone).

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
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
  if (location == '/library') {
    final rows = await env.db.select(env.db.media).get();
    env.library.addAlbum(
      AlbumInfo(id: 'all', name: 'All', count: rows.length, isAll: true),
      [
        for (final row in rows)
          AssetInfo(
            id: row.assetId,
            width: row.width ?? 1,
            height: row.height ?? 1,
            modifiedAt: row.modifiedAt,
            takenAt: row.takenAt ?? 0,
            kind: row.kind,
            durationMs: row.durationMs,
          ),
      ],
    );
  }
  await env.pump(
    tester,
    extra: [initialLocationProvider.overrideWithValue(location)],
  );
  await _settle(tester);
}

void main() {
  group('S04 Library', () {
    appTest(
      'an empty library shows empty state and settings navigation',
      (tester, env) async {
        await _open(tester, env, '/library');
        expect(find.text('No photos or videos available'), findsOneWidget);
        expect(find.byKey(const Key('tab-root-settings')), findsOneWidget);
        await tester.tap(find.byKey(const Key('tab-root-settings')));
        await _settle(tester);
        expect(find.text('Settings'), findsWidgets);
      },
      session: testSession,
    );

    appTest(
      'gallery provides tabs and filter toggle in TabRootScaffold',
      (tester, env) async {
        await _open(tester, env, '/library');
        expect(find.byKey(const Key('library-tabs')), findsOneWidget);
        expect(find.byKey(const Key('library-filters-toggle')), findsOneWidget);
        expect(find.byKey(const Key('tab-root-settings')), findsOneWidget);
      },
      session: testSession,
    );

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

        for (final asset in ['a', 'b', 'c']) {
          expect(find.byKey(ValueKey('asset-$asset')), findsOneWidget);
        }
        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);

        await tester.ensureVisible(find.byKey(const Key('filter-unscanned')));
        await tester.tap(find.byKey(const Key('filter-unscanned')));
        await tester.tap(find.text('Show media'));
        await _settle(tester);
        expect(find.byKey(Key('media-$waiting')), findsOneWidget);
        expect(find.byKey(Key('media-$scanned')), findsNothing);

        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('filter-all')));
        await tester.tap(find.byKey(const Key('filter-all')));
        await tester.tap(find.text('Show media'));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('filter-has-faces')));
        await tester.tap(find.byKey(const Key('filter-has-faces')));
        await tester.tap(find.text('Show media'));
        await _settle(tester);
        expect(find.byKey(Key('media-$scanned')), findsOneWidget);
        expect(find.byKey(Key('media-$empty')), findsNothing);

        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('filter-failed')));
        await tester.tap(find.byKey(const Key('filter-failed')));
        await tester.tap(find.text('Show media'));
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

        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);
        await tester.ensureVisible(find.byKey(const Key('filter-pick-person')));
        await tester.tap(find.byKey(const Key('filter-pick-person')));
        await _settle(tester);
        await tester.tap(find.byKey(Key('person-picker-$sara')));
        await _settle(tester);
        expect(find.byKey(const Key('filter-person')), findsOneWidget);
        await tester.tap(find.text('Show media'));
        await _settle(tester);
        expect(find.byKey(Key('media-$withSara')), findsOneWidget);
        expect(find.byKey(Key('media-$without')), findsNothing);

        await tester.tap(find.byKey(const Key('library-clear-filters')));
        await _settle(tester);
        expect(find.byKey(const ValueKey('asset-b')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'the grid follows the database while a scan adds photos',
      (tester, env) async {
        await seedMedia(env.db, asset: 'a');
        await _open(tester, env, '/library');
        await tester.tap(find.byKey(const Key('library-filters-toggle')));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('filter-unscanned')));
        await tester.tap(find.text('Show media'));
        await _settle(tester);
        final later = await seedMedia(
          env.db,
          asset: 'b',
          status: 'pending',
          takenAt: 5000,
        );
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
        await tester.tap(find.text('Details'));
        await _settle(tester);
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
      await tester.tap(find.text('Details'));
      await _settle(tester);
      expect(find.text('This photo has not been scanned yet.'), findsOneWidget);
    }, session: testSession);

    appTest('a scanned photo with no faces says so', (tester, env) async {
      final photo = await seedMedia(env.db, asset: 'a');
      await _open(tester, env, '/media/$photo');
      await tester.tap(find.text('Details'));
      await _settle(tester);
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

    appTest(
      'media viewer provides face box toggle, Google Lens search, and swipe navigation',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara');
        final photo1 = await seedMedia(env.db, asset: 'a', takenAt: 2000);
        final photo2 = await seedMedia(env.db, asset: 'b', takenAt: 1000);
        await seedFace(env.db, mediaId: photo1, personId: sara, seed: 1);
        await seedFace(env.db, mediaId: photo2, seed: 2);

        await _open(tester, env, '/media/$photo1');
        expect(find.byKey(const Key('media-page-view')), findsOneWidget);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await _settle(tester);
        expect(find.byKey(const Key('toggle-faces')), findsOneWidget);
        expect(find.byKey(const Key('google-lens')), findsOneWidget);

        // Toggle faces
        await tester.tap(find.byKey(const Key('toggle-faces')));
        await _settle(tester);

        // Swipe left to photo2
        await tester.drag(
          find.byKey(const Key('media-page-view')),
          const Offset(-400, 0),
        );
        await _settle(tester);
      },
      session: testSession,
    );
  });
}
