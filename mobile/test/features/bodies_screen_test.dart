// Roadmap Phase 4: the Bodies screen - Tier-A and colour chips, find similar, naming a pose from an example
// with remove-before-save, the saved groups, and the entries from People and a person's page.

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/pose_index.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

const standing = <List<double>>[
  [500, 300],
  [530, 280],
  [470, 280],
  [560, 290],
  [440, 290],
  [650, 400],
  [350, 400],
  [670, 550],
  [330, 550],
  [680, 700],
  [320, 700],
  [560, 800],
  [440, 800],
  [560, 1050],
  [440, 1050],
  [560, 1300],
  [440, 1300],
];

List<List<double>> withWrist(double y) => [
  for (var i = 0; i < 17; i++) i == 9 ? [680, y] : standing[i],
];

List<List<double>> rotated(List<List<double>> pts) => [
  for (final p in pts) [1500 - p[1], p[0]],
];

String kpts(List<List<double>> pts) => jsonEncode([
  for (final p in pts) [p[0] / 1000, p[1] / 1500, 0.9],
]);

Future<int> _body(
  AppDatabase db,
  int media,
  List<List<double>> pts, {
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
    BodiesCompanion(kpts: Value(kpts(pts)), extent: const Value('full')),
  );
  return id;
}

/// Real isolates need real time: a widget test runs in fake time, so the work goes through runAsync.
Future<void> _settleReal(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 2000)),
  );
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'chips filter by pose and colour; find similar ranks the same pose first',
    (tester, env) async {
      final media = await seedMedia(
        env.db,
        asset: 'm',
        width: 1000,
        height: 1500,
      );
      final a = await _body(env.db, media, standing);
      final b = await _body(env.db, media, withWrist(250));
      final c = await _body(env.db, media, rotated(standing));
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );

      expect(find.text('Bodies'), findsWidgets);
      for (final id in [a, b, c]) {
        expect(
          find.byKey(Key('body-$id')),
          findsOneWidget,
          reason: 'all bodies show first',
        );
      }
      expect(find.byKey(const Key('pose-chip-standing')), findsOneWidget);
      expect(find.byKey(const Key('pose-chip-lying')), findsOneWidget);
      expect(find.text('Standing · 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pose-chip-lying')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('body-$c')), findsOneWidget);
      expect(find.byKey(Key('body-$a')), findsNothing);

      await tester.tap(find.byKey(const Key('pose-chip-lying')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('color-chip-blue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('color-chip-blue')));
      await _settleReal(tester);
      expect(
        find.text('Nothing matches this filter.'),
        findsOneWidget,
        reason: 'no outfit colours stored',
      );
      await tester.ensureVisible(find.byKey(const Key('color-chip-blue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('color-chip-blue')));
      await _settleReal(tester);

      await tester.tap(find.byKey(Key('body-$b')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-similar')));
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-similar-chip')), findsOneWidget);
      expect(find.byKey(Key('body-$b')), findsNothing, reason: 'never itself');
      expect(find.byKey(Key('body-$a')), findsOneWidget);
      tester
          .widget<InputChip>(find.byKey(const Key('bodies-similar-chip')))
          .onDeleted!();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bodies-similar-chip')), findsNothing);
    },
    session: testSession,
  );

  appTest(
    'naming a pose previews the matches, lets the user remove one, and saves a group',
    (tester, env) async {
      final media = await seedMedia(
        env.db,
        asset: 'm',
        width: 1000,
        height: 1500,
      );
      final ex = await _body(env.db, media, withWrist(250));
      final alike = await _body(env.db, media, withWrist(255));
      final odd = await _body(env.db, media, withWrist(245));
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );

      await tester.tap(find.byKey(Key('body-$ex')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-name-pose')));
      await _settleReal(tester);
      await tester.enterText(find.byKey(const Key('category-name')), 'Hand up');
      await tester.pump();
      await tester.tap(find.byKey(const Key('category-name-ok')));
      await _settleReal(tester);

      expect(find.textContaining('3 matches'), findsOneWidget);
      await tester.tap(find.byKey(Key('preview-$odd')));
      await tester.pump();
      expect(find.textContaining('2 matches'), findsOneWidget);
      await tester.tap(find.byKey(const Key('category-save')));
      await _settleReal(tester);

      final category = await env.db.select(env.db.poseCategories).getSingle();
      expect(category.name, 'Hand up');
      final states = {
        for (final m in await env.db.select(env.db.bodyPoseMatches).get())
          m.bodyId: m.state,
      };
      expect(
        (states[ex], states[alike], states[odd]),
        ('manual', 'auto', 'rejected'),
      );

      await tester.tap(find.byKey(const Key('bodies-tab-poses')));
      await tester.pumpAndSettle();
      expect(find.text('Hand up'), findsOneWidget);
      expect(find.text('2 bodies'), findsOneWidget);
      await tester.tap(find.byKey(Key('category-pose-${category.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('category-body-$alike')), findsOneWidget);
      expect(find.byKey(Key('category-body-$odd')), findsNothing);
      await tester.longPress(find.byKey(Key('category-body-$alike')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('category-body-$alike')),
        findsNothing,
        reason: 'long-press takes a body out',
      );
      await tester.tap(find.byKey(const Key('category-delete')));
      await tester.pumpAndSettle();
      expect(await env.db.select(env.db.poseCategories).get(), isEmpty);
    },
    session: testSession,
  );

  appTest(
    'a body whose pose cannot be measured says so instead of opening an empty preview',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'm');
      final id = await seedBody(
        env.db,
        mediaId: media,
        cropPath: 'bodies/x.jpg',
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      expect(find.byKey(Key('body-$id')), findsOneWidget);
      await tester.tap(find.byKey(Key('body-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-name-pose')));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot be measured'), findsOneWidget);
      expect(await env.db.select(env.db.poseCategories).get(), isEmpty);
    },
    session: testSession,
  );

  appTest(
    'People and a person page open the screen; a person scopes it to their bodies',
    (tester, env) async {
      final lina = await seedPerson(env.db, name: 'Lina');
      final media = await seedMedia(
        env.db,
        asset: 'm',
        width: 1000,
        height: 1500,
      );
      final mine = await _body(env.db, media, standing, person: lina);
      final theirs = await _body(env.db, media, standing);
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people')],
      );
      await tester.tap(find.byKey(const Key('open-bodies')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('body-$mine')), findsOneWidget);
      expect(find.byKey(Key('body-$theirs')), findsOneWidget);
    },
    session: testSession,
  );

  appTest('a person scopes the screen to their bodies', (tester, env) async {
    final lina = await seedPerson(env.db, name: 'Lina');
    final media = await seedMedia(
      env.db,
      asset: 'm',
      width: 1000,
      height: 1500,
    );
    final mine = await _body(env.db, media, standing, person: lina);
    final theirs = await _body(env.db, media, standing);
    await tester.runAsync(() => PoseIndex(env.db).rebuild());
    await env.pump(
      tester,
      extra: [
        initialLocationProvider.overrideWithValue('/bodies?personId=$lina'),
      ],
    );
    expect(find.byKey(Key('body-$mine')), findsOneWidget);
    expect(find.byKey(Key('body-$theirs')), findsNothing);
  }, session: testSession);

  appTest(
    'a body with an exposed-region embedding can search for similar photos of that area',
    (tester, env) async {
      final media = await seedMedia(env.db, asset: 'm');
      Uint8List vec(double lean) {
        final v = Float32List(384)
          ..[0] = 1 - lean
          ..[1] = lean;
        return packFloat32(v);
      }

      Future<int> withChest(Uint8List? chest) async {
        final id = await seedBody(
          env.db,
          mediaId: media,
          cropPath: 'bodies/x.jpg',
        );
        await (env.db.update(env.db.bodies)..where((b) => b.id.equals(id)))
            .write(BodiesCompanion(chestEmbedding: Value(chest)));
        return id;
      }

      final query = await withChest(vec(0.1));
      final close = await withChest(vec(0.12));
      final far = await withChest(vec(0.9));
      final none = await withChest(null);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/bodies')],
      );
      await tester.tap(find.byKey(Key('body-$none')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('action-similar-chest')),
        findsNothing,
        reason: 'no embedding, no action',
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('body-$query')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-similar-buttocks')), findsNothing);
      await tester.tap(find.byKey(const Key('action-similar-chest')));
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-similar-chip')), findsOneWidget);
      expect(find.byKey(Key('body-$close')), findsOneWidget);
      expect(find.byKey(Key('body-$far')), findsOneWidget);
      expect(
        find.byKey(Key('body-$query')),
        findsNothing,
        reason: 'never itself',
      );
      expect(find.byKey(Key('body-$none')), findsNothing);
    },
    session: testSession,
  );

  appTest(
    'the photo viewer offers pose and colour actions on a body and opens the Bodies screen on it',
    (tester, env) async {
      final media = await seedMedia(
        env.db,
        asset: 'viewer',
        width: 1000,
        height: 1500,
      );
      env.library.bytes['viewer'] = _validPng();
      final a = await _body(env.db, media, standing);
      final b = await _body(env.db, media, withWrist(250));
      await tester.runAsync(() => PoseIndex(env.db).rebuild());
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/media/$media')],
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('toggle-bodies')));

      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(Key('box-b-$b')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      for (final key in [
        'box-similar-pose',
        'box-similar-colours',
        'box-name-pose',
        'box-name-outfit',
        'box-mark-tattoo',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      await tester.tap(find.byKey(const Key('box-similar-pose')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('bodies-similar-chip')),
        findsOneWidget,
        reason: 'opened on the similar-pose search',
      );
      expect(find.byKey(Key('body-$a')), findsOneWidget);
      expect(find.byKey(Key('body-$b')), findsNothing, reason: 'never itself');
    },
    session: testSession,
  );

  appTest(
    'similar colours ranks by outfit and a deep link starts there',
    (tester, env) async {
      final media = await seedMedia(
        env.db,
        asset: 'c',
        width: 1000,
        height: 1500,
      );
      final base = outfit(1);
      final q = await seedBody(
        env.db,
        mediaId: media,
        appearance: base,
        cropPath: 'bodies/x.jpg',
      );
      final twin = await seedBody(
        env.db,
        mediaId: media,
        appearance: base,
        cropPath: 'bodies/x.jpg',
      );
      final other = await seedBody(
        env.db,
        mediaId: media,
        appearance: outfit(9),
        cropPath: 'bodies/x.jpg',
      );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/bodies?colours=$q'),
        ],
        settle: false,
      );
      await _settleReal(tester);
      expect(find.byKey(const Key('bodies-similar-chip')), findsOneWidget);
      expect(find.text('Similar colours'), findsOneWidget);
      expect(find.byKey(Key('body-$twin')), findsOneWidget);
      expect(find.byKey(Key('body-$other')), findsNothing);
      expect(find.byKey(Key('body-$q')), findsNothing);
    },
    session: testSession,
  );

  appTest('group photo chips list photos with several people', (
    tester,
    env,
  ) async {
    final trio = await seedMedia(
      env.db,
      asset: 'trio',
      width: 1000,
      height: 1500,
    );
    final ids = [
      for (final x in [200.0, 500.0, 800.0])
        await _body(env.db, trio, [
          for (final p in standing) [p[0] - 500 + x, p[1]],
        ]),
    ];
    await tester.runAsync(() => PoseIndex(env.db).rebuild());
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/bodies')],
    );
    await _settleReal(tester);
    expect(find.byKey(const Key('group-chip-group')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('group-chip-group')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-chip-group')));
    await _settleReal(tester);
    expect(
      find.byKey(Key('body-${ids.first}')),
      findsOneWidget,
      reason: 'one body stands for the photo',
    );
    expect(find.byKey(Key('body-${ids.last}')), findsNothing);
    expect(find.text('Group photos'), findsWidgets);
  }, session: testSession);
}

/// A real 4x4 grey PNG (the shared tiny fixture is not decodable by the engine's codec).
Uint8List _validPng() {
  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    final length = ByteData(4)..setUint32(0, data.length);
    final sum = ByteData(4)..setUint32(0, crc(body));
    return [
      ...length.buffer.asUint8List(),
      ...body,
      ...sum.buffer.asUint8List(),
    ];
  }

  final header = ByteData(13)
    ..setUint32(0, 4)
    ..setUint32(4, 4)
    ..setUint8(8, 8)
    ..setUint8(9, 0);
  final raw = <int>[
    for (var y = 0; y < 4; y++) ...[0, 128, 128, 128, 128],
  ];
  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', header.buffer.asUint8List()),
    ...chunk('IDAT', ZLibEncoder().convert(raw)),
    ...chunk('IEND', const []),
  ]);
}
