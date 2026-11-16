import 'package:antigravity_mobile/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  group('PersonMediaActionSheet & Long-press UX', () {
    appTest(
      'Long-press on a photo opens PersonMediaActionSheet showing Face & Body badge',
      (tester, env) async {
        final sara = await seedPerson(env.db, name: 'Sara', createdAt: 1);
        final mediaId = await seedMedia(env.db, asset: 'asset-sara-1');
        final faceId = await seedFace(
          env.db,
          mediaId: mediaId,
          personId: sara,
          seed: 1,
        );
        await seedBody(
          env.db,
          mediaId: mediaId,
          faceId: faceId,
          personId: sara,
        );

        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/$sara')],
        );
        await _settle(tester);

        // Tap/ensure in Media tab
        expect(find.byKey(Key('media-$mediaId')), findsOneWidget);

        // Long press on the media item
        await tester.longPress(find.byKey(Key('media-$mediaId')));
        await _settle(tester);
        await expandActionSections(tester);

        // Verify PersonMediaActionSheet is open with Hero Card and badges
        expect(find.text('Sara'), findsWidgets);
        expect(find.text('Linked by face & body'), findsWidgets);
        expect(find.byKey(const Key('action-not-this-person')), findsOneWidget);
        expect(find.byKey(const Key('action-not-this-body')), findsOneWidget);
        expect(find.byKey(const Key('action-another-person')), findsOneWidget);
        expect(find.byKey(const Key('action-set-cover')), findsOneWidget);
        expect(find.byKey(const Key('action-view-full')), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'Hero Card shows "Linked by face only" when photo only has a face',
      (tester, env) async {
        final omar = await seedPerson(env.db, name: 'Omar', createdAt: 2);
        final mediaId = await seedMedia(env.db, asset: 'asset-omar-face');
        await seedFace(env.db, mediaId: mediaId, personId: omar, seed: 2);

        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/$omar')],
        );
        await _settle(tester);

        await tester.longPress(find.byKey(Key('media-$mediaId')));
        await _settle(tester);
        await expandActionSections(tester);

        expect(find.text('Linked by face only'), findsWidgets);
        expect(find.byKey(const Key('action-not-this-person')), findsOneWidget);
        expect(find.byKey(const Key('action-not-this-body')), findsNothing);
      },
      session: testSession,
    );

    appTest(
      'Hero Card shows "Linked by body only" when photo only has a linked body',
      (tester, env) async {
        final lina = await seedPerson(env.db, name: 'Lina', createdAt: 3);
        final mediaId = await seedMedia(env.db, asset: 'asset-lina-body');
        await seedBody(
          env.db,
          mediaId: mediaId,
          personId: lina,
          linkMethod: 'outfit',
        );

        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/people/$lina')],
        );
        await _settle(tester);

        await tester.longPress(find.byKey(Key('media-$mediaId')));
        await _settle(tester);
        await expandActionSections(tester);

        expect(find.text('Linked by body only'), findsWidgets);
        expect(find.byKey(const Key('action-not-this-person')), findsNothing);
        expect(find.byKey(const Key('action-not-this-body')), findsOneWidget);
      },
      session: testSession,
    );

    appTest('Tapping "Not this person" unlinks and rejects face', (
      tester,
      env,
    ) async {
      final adam = await seedPerson(env.db, name: 'Adam', createdAt: 4);
      final mediaId = await seedMedia(env.db, asset: 'asset-adam-1');
      final faceId = await seedFace(
        env.db,
        mediaId: mediaId,
        personId: adam,
        seed: 4,
      );

      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$adam')],
      );
      await _settle(tester);

      await tester.longPress(find.byKey(Key('media-$mediaId')));
      await _settle(tester);
      await expandActionSections(tester);

      await tester.ensureVisible(
        find.byKey(const Key('action-not-this-person')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-not-this-person')));
      await _settle(tester);

      // Verify face is rejected from Adam
      final rejections = await env.db.select(env.db.faceRejections).get();
      expect(
        rejections.any((r) => r.faceId == faceId && r.personId == adam),
        isTrue,
      );
    }, session: testSession);

    appTest('Tapping "Not this body" rejects body link', (tester, env) async {
      final noor = await seedPerson(env.db, name: 'Noor', createdAt: 5);
      final mediaId = await seedMedia(env.db, asset: 'asset-noor-1');
      final bodyId = await seedBody(
        env.db,
        mediaId: mediaId,
        personId: noor,
        linkMethod: 'outfit',
      );

      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$noor')],
      );
      await _settle(tester);

      await tester.longPress(find.byKey(Key('media-$mediaId')));
      await _settle(tester);
      await expandActionSections(tester);

      await tester.ensureVisible(find.byKey(const Key('action-not-this-body')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-not-this-body')));
      await _settle(tester);

      // Verify body link is cleared/rejected for Noor
      final body = (await env.db.select(env.db.bodies).get()).firstWhere(
        (b) => b.id == bodyId,
      );
      expect(body.personId, isNull);
    }, session: testSession);

    appTest('Tapping "Set as cover photo" sets avatarFaceId for person', (
      tester,
      env,
    ) async {
      final maya = await seedPerson(env.db, name: 'Maya', createdAt: 6);
      final mediaId = await seedMedia(env.db, asset: 'asset-maya-1');
      final faceId = await seedFace(
        env.db,
        mediaId: mediaId,
        personId: maya,
        seed: 6,
      );

      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$maya')],
      );
      await _settle(tester);

      await tester.longPress(find.byKey(Key('media-$mediaId')));
      await _settle(tester);
      await expandActionSections(tester);

      await tester.ensureVisible(find.byKey(const Key('action-set-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-set-cover')));
      await _settle(tester);

      final updated = (await env.db.select(env.db.persons).get()).firstWhere(
        (p) => p.id == maya,
      );
      expect(updated.avatarFaceId, faceId);
    }, session: testSession);
  });
}
