import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/identity_groups.dart';
import 'package:antigravity_mobile/features/people/organize_media_screen.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_media_organizer.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<int> _character(AppDatabase db, String name) async {
  final id = await seedPerson(db, name: name);
  await (db.update(db.persons)..where((p) => p.id.equals(id))).write(
    const PersonsCompanion(kind: Value('character')),
  );
  return id;
}

void main() {
  appTest('choosing a shared-file owner preserves excluded files', (
    tester,
    env,
  ) async {
    final a = await seedPerson(env.db, name: 'Luffy'),
        b = await seedPerson(env.db, name: 'Zoro');
    final shared = await seedMedia(env.db, asset: '42'),
        excluded = await seedMedia(env.db, asset: '43');
    await seedFace(env.db, mediaId: shared, personId: a);
    await seedFace(env.db, mediaId: shared, personId: b);
    await seedFace(env.db, mediaId: excluded, personId: a);
    final bridge = FakeMediaOrganizer()
      ..seed('42')
      ..seed('43');
    await env.pump(
      tester,
      extra: [
        mediaOrganizerBridgeProvider.overrideWithValue(bridge),
        initialLocationProvider.overrideWithValue('/people'),
      ],
    );
    Navigator.of(tester.element(find.byKey(Key('person-$a')))).push(
      MaterialPageRoute<void>(
        builder: (_) => OrganizePersonMediaScreen(personIds: {a, b}),
      ),
    );
    await tester.pumpAndSettle();
    final check = find.byKey(Key('organize-check-$excluded'));
    await tester.scrollUntilVisible(
      check,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, 600));
    await tester.pumpAndSettle();
    final owner = find.byKey(ValueKey('organize-owner-$shared-null'));
    await tester.scrollUntilVisible(
      owner,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(owner);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luffy').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      check,
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check).value, isFalse);
    await tester.tap(find.byKey(const Key('organize-apply')));
    await tester.pumpAndSettle();
    expect(bridge.moves.single.map((m) => m.asset.assetId), ['42']);
    expect(bridge.originals['43']!.path, 'DCIM/Camera/');
  }, session: testSession);

  appTest(
    'anime identities can be filtered by series and assigned to a new group',
    (tester, env) async {
      final repository = IdentityGroupsRepository(env.db);
      final onePiece = await repository.create('One Piece');
      final luffy = await _character(env.db, 'Luffy'),
          naruto = await _character(env.db, 'Naruto');
      await repository.assign([luffy], onePiece);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/characters')],
      );
      final filter = find.byKey(const ValueKey('people-group-filter-null'));
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('One Piece').last);
      await tester.pumpAndSettle();
      expect(find.byKey(Key('person-$luffy')), findsOneWidget);
      expect(find.byKey(Key('person-$naruto')), findsNothing);
      await tester.longPress(find.byKey(Key('person-$luffy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('people-action-setGroup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('identity-group-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('identity-group-name')),
        'East Blue',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('identity-group-save')));
      await tester.pumpAndSettle();
      final assigned = (await env.db.select(env.db.persons).get())
          .firstWhere((p) => p.id == luffy)
          .groupId;
      final group = (await env.db.select(env.db.identityGroups).get())
          .firstWhere((g) => g.id == assigned);
      expect(group.name, 'East Blue');
      expect(await env.db.select(env.db.persons).get(), hasLength(2));
    },
    session: testSession,
  );

  appTest(
    'preview and owner choice never move files until Apply is tapped',
    (tester, env) async {
      final luffy = await seedPerson(env.db, name: 'Luffy'),
          zoro = await seedPerson(env.db, name: 'Zoro');
      final group = await IdentityGroupsRepository(env.db).create('One Piece');
      await IdentityGroupsRepository(env.db).assign([luffy, zoro], group);
      final media = await seedMedia(env.db, asset: '42');
      await seedFace(env.db, mediaId: media, personId: luffy);
      await seedFace(env.db, mediaId: media, personId: zoro);
      final bridge = FakeMediaOrganizer()..seed('42');
      await env.pump(
        tester,
        extra: [
          mediaOrganizerBridgeProvider.overrideWithValue(bridge),
          initialLocationProvider.overrideWithValue('/people'),
        ],
      );
      final context = tester.element(find.byKey(Key('person-$luffy')));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrganizePersonMediaScreen(personIds: {luffy, zoro}),
        ),
      );
      await tester.pumpAndSettle();
      expect(bridge.moves, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('organize-apply')))
            .onPressed,
        isNull,
      );
      final owner = find.byKey(ValueKey('organize-owner-$media-null'));
      await tester.scrollUntilVisible(
        owner,
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(owner);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Luffy').last);
      await tester.pumpAndSettle();
      expect(find.text('Luffy_image_0001.jpg'), findsOneWidget);
      expect(bridge.moves, isEmpty);
      await tester.tap(find.byKey(const Key('organize-apply')));
      await tester.pumpAndSettle();
      expect(bridge.moves.single, hasLength(1));
      expect(
        bridge.originals['42']!.path,
        'DCIM/Your Gallery/One Piece/Luffy/',
      );
      expect(find.text('1 file organized · 0 files not moved'), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'group controls and move preview fit a small phone with large text',
    (tester, env) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final group = await IdentityGroupsRepository(
        env.db,
      ).create('One Piece — Straw Hat Pirates');
      final person = await seedPerson(env.db, name: 'Monkey D. Luffy');
      await IdentityGroupsRepository(env.db).assign([person], group);
      final media = await seedMedia(env.db, asset: '42');
      await seedFace(env.db, mediaId: media, personId: person);
      final bridge = FakeMediaOrganizer()..seed('42');
      await env.pump(
        tester,
        extra: [
          mediaOrganizerBridgeProvider.overrideWithValue(bridge),
          initialLocationProvider.overrideWithValue('/people'),
        ],
      );
      final filter = find.byKey(const ValueKey('people-group-filter-null'));
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final context = tester.element(find.byKey(Key('person-$person')));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrganizePersonMediaScreen(personIds: {person}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('organize-apply')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(bridge.moves, isEmpty);
    },
    session: testSession,
  );
}
