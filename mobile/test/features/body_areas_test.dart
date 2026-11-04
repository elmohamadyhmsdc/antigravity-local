// Roadmap 7.5 UI: the experimental "Areas" tab. OFF by default (no tab), switched on from the Bodies menu,
// one tap gives a whole group to a person, and a bridge photo only offers the other group.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Float32List _vec(int seed, {Float32List? near}) {
  final r = math.Random(seed);
  final v = Float32List(384);
  for (var i = 0; i < 384; i++) {
    v[i] = near == null
        ? r.nextDouble() - 0.5
        : near[i] + (r.nextDouble() - 0.5) * 0.01;
  }
  final n = math.sqrt(v.fold<double>(0, (a, b) => a + b * b));
  for (var i = 0; i < 384; i++) {
    v[i] /= n;
  }
  return v;
}

Future<int> _body(
  AppDatabase db,
  int media, {
  Float32List? chest,
  Float32List? lower,
  int? person,
}) async {
  final id = await seedBody(
    db,
    mediaId: media,
    personId: person,
    linkMethod: person == null ? null : 'manual',
    cropPath: 'bodies/x.jpg',
  );
  await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
    BodiesCompanion(
      chestEmbedding: Value(chest == null ? null : packFloat32(chest)),
      buttocksEmbedding: Value(lower == null ? null : packFloat32(lower)),
    ),
  );
  return id;
}

Future<void> _settleReal(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 4000)),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  appTest(
    'the Areas destination stays visible while grouping is OFF',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'm');
      final base = _vec(1);
      await _body(env.db, media, chest: base);
      await _body(env.db, media, chest: _vec(2, near: base));
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-tab-areas')), findsOneWidget);
      expect(await env.db.select(env.db.bodyClusters).get(), isEmpty);
    },
    session: testSession,
  );

  appTest(
    'switching it on builds the groups; one tap gives a group to a person; a bridge only offers the other group',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'm');
      final lina = await seedPerson(env.db, name: 'Lina');
      final chestBase = _vec(10), lowerBase = _vec(11);
      // two photos that show both areas (the bridges), plus one more of each area
      final b1 = await _body(
        env.db,
        media,
        chest: _vec(12, near: chestBase),
        lower: _vec(13, near: lowerBase),
      );
      final secondMedia = await seedMedia(env.db, asset: 'independent-bridge');
      final b2 = await _body(
        env.db,
        secondMedia,
        chest: _vec(14, near: chestBase),
        lower: _vec(15, near: lowerBase),
      );
      final chestOnly = await _body(
        env.db,
        media,
        chest: _vec(16, near: chestBase),
      );
      final lowerOnly = await _body(
        env.db,
        media,
        lower: _vec(17, near: lowerBase),
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-tab-areas')), findsOneWidget);

      await tester.tap(find.byKey(const Key('bodies-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clusters-toggle')));
      await _settleReal(tester);
      expect(await env.db.setting('body_clusters_enabled'), 'true');
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-tab-areas')), findsOneWidget);
      expect(
        await env.db.select(env.db.bodyClusters).get(),
        hasLength(2),
        reason: 'one chest group and one lower-body group',
      );

      await tester.ensureVisible(find.byKey(const Key('bodies-tab-areas')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('bodies-tab-areas')));
      await _settleReal(tester);
      final chest = await (env.db.select(
        env.db.bodyClusters,
      )..where((c) => c.clusterType.equals('chest'))).getSingle();
      final lower = await (env.db.select(
        env.db.bodyClusters,
      )..where((c) => c.clusterType.equals('buttocks'))).getSingle();
      expect(find.byKey(Key('cluster-${chest.id}')), findsOneWidget);
      expect(find.text('Chest area · group ${chest.id}'), findsOneWidget);

      await tester.ensureVisible(find.byKey(Key('cluster-assign-${chest.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('cluster-assign-${chest.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('person-picker-$lina')));
      await _settleReal(tester);

      var rows = {
        for (final b in await env.db.select(env.db.bodies).get()) b.id: b,
      };
      expect(rows[b1]!.personId, lina);
      expect(rows[chestOnly]!.personId, lina);
      expect(
        rows[lowerOnly]!.personId,
        isNull,
        reason: 'the other group is only offered',
      );
      expect(find.text('Belongs to Lina'), findsOneWidget);

      final bridge = find.byKey(Key('bridge-${chest.id}-${lower.id}'));
      await tester.scrollUntilVisible(
        bridge,
        -180,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('area-groups')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(bridge, findsOneWidget);
      expect(
        (await env.db.select(env.db.bodyClusters).get())
            .firstWhere((c) => c.id == lower.id)
            .personId,
        isNull,
      );
      await tester.ensureVisible(bridge);
      await tester.pumpAndSettle();
      await tester.tap(bridge);
      await _settleReal(tester);
      rows = {
        for (final b in await env.db.select(env.db.bodies).get()) b.id: b,
      };
      expect(rows[lowerOnly]!.personId, lina);
      expect(rows[b2]!.personId, lina);
    },
    session: testSession,
  );
}
