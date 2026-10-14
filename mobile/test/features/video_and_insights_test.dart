import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest('Insights reads local data even when the PC is offline', (
    tester,
    env,
  ) async {
    env.api.capabilitiesError = ApiException.network('Offline');
    await seedPerson(env.db, name: 'Sara');
    await seedMedia(env.db, asset: 'video', kind: 'video', status: 'done');
    await seedMedia(env.db, asset: 'photo', status: 'pending');
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/insights')],
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Library insights'), findsOneWidget);
    expect(find.text('1 of 2 items scanned'), findsOneWidget);
    expect(find.text('Photos: 1 · Videos: 1'), findsOneWidget);
    expect(env.api.analyzeCalls, isEmpty);
  }, session: testSession);

  appTest(
    'Library separates photos and videos and marks video duration',
    (tester, env) async {
      final photo = await seedMedia(env.db, asset: 'photo');
      final video = await seedMedia(env.db, asset: 'video', kind: 'video');
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/library')],
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('media-$photo')), findsOneWidget);
      expect(find.byKey(Key('media-$video')), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('media-$photo')), findsNothing);
      expect(find.byKey(Key('media-$video')), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'A missing video shows a readable state instead of crashing',
    (tester, env) async {
      final video = await seedMedia(env.db, asset: 'gone', kind: 'video');
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/media/$video')],
      );
      await tester.pumpAndSettle();
      expect(find.text('Video unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    session: testSession,
  );
}
