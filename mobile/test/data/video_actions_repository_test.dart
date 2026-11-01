import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/api/action_api.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/repositories/action_frames.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/video_actions_repository.dart';
import 'package:antigravity_mobile/domain/pose/action_matcher.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

Pose actor(double x, {double angle = 0}) {
  const points = [
    [50, 10],
    [54, 8],
    [46, 8],
    [58, 10],
    [42, 10],
    [65, 25],
    [35, 25],
    [72, 43],
    [28, 43],
    [74, 60],
    [26, 60],
    [59, 55],
    [41, 55],
    [61, 75],
    [39, 75],
    [65, 95],
    [35, 95],
  ];
  return Pose([
    for (final p in points)
      Pt(
        x + 50 + (p[0] - 50) * math.cos(angle) - (p[1] - 55) * math.sin(angle),
        55 + (p[0] - 50) * math.sin(angle) + (p[1] - 55) * math.cos(angle),
        .9,
      ),
  ], extent: 'full');
}

List<List<double>> points(Pose p) => [
  for (final k in p.points) [k.x / 500, k.y / 300, k.score],
];

class _RemoteMatcher implements ActionMatchApi {
  var calls = 0;
  var offline = false;
  @override
  Future<Map<String, double?>> compareActions({
    required String kind,
    required List<Map<String, dynamic>> query,
    required List<({String id, List<Map<String, dynamic>> frames})> candidates,
    bool allowMirror = false,
  }) async {
    calls++;
    if (offline) throw ApiException.network('fixture offline');
    expect(candidates.length, lessThanOrEqualTo(64));
    expect(query.length, lessThanOrEqualTo(20));
    final q = [for (final f in query) ActionPoseFrame.fromJson(f)];
    return {
      for (final c in candidates)
        c.id: compareActionSequences(q, [
          for (final f in c.frames) ActionPoseFrame.fromJson(f),
        ], allowMirror: allowMirror),
    };
  }
}

void main() {
  late AppDatabase db;
  late VideoActionsRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = VideoActionsRepository(db);
  });
  tearDown(() => db.close());

  Future<int> photo(
    String asset, {
    double distance = 70,
    List<int> people = const [],
  }) async {
    final id = await seedMedia(db, asset: asset, width: 500, height: 300);
    for (var i = 0; i < 2; i++) {
      final body = await seedBody(
        db,
        mediaId: id,
        personId: people.isEmpty ? null : people[i],
      );
      await (db.update(db.bodies)..where((b) => b.id.equals(body))).write(
        BodiesCompanion(
          kpts: Value(jsonEncode(points(actor(i * distance)))),
          extent: const Value('full'),
        ),
      );
    }
    return id;
  }

  Future<int> video(
    String asset, {
    bool reversed = false,
    bool gap = false,
    bool snapshots = true,
  }) async {
    final id = await seedMedia(
      db,
      asset: asset,
      kind: 'video',
      width: 500,
      height: 300,
    );
    final media = await (db.select(
      db.media,
    )..where((m) => m.id.equals(id))).getSingle();
    final body = await seedBody(db, mediaId: id, frameNumber: 0);
    await (db.update(db.bodies)..where((b) => b.id.equals(body))).write(
      BodiesCompanion(trackId: Value(body)),
    );
    if (snapshots) {
      for (var i = 0; i < 3; i++) {
        final time = i == 2 && gap ? 30000 : i * 1000;
        await ActionFrameStore(db).put(
          media,
          frameNumber: i,
          timeMs: time,
          width: 500,
          height: 300,
          bodies: [
            {
              'body': body,
              'kpts': points(
                actor(0, angle: (reversed ? 2 - i : i) * math.pi / 4),
              ),
              'extent': 'full',
            },
          ],
        );
      }
    }
    return id;
  }

  test(
    'photo examples match whole group geometry across identities and preserve reviewed decisions',
    () async {
      final a = await seedPerson(db, name: 'A'),
          b = await seedPerson(db, name: 'B');
      final c = await seedPerson(db, name: 'C'),
          d = await seedPerson(db, name: 'D');
      final source = await photo('source', people: [a, b]);
      final alike = await photo('alike', people: [c, d]);
      final apart = await photo('apart', distance: 210);
      final id = await repo.saveAction('Greeting');
      await repo.addPhotoExample(actionId: id, mediaId: source);
      expect((await repo.action(id))!.examples.single.participantIds.toSet(), {
        a,
        b,
      });
      expect(
        (await repo.participants(source, 0, 0)).map((p) => p.name).toSet(),
        {'A', 'B'},
      );
      var results = await repo.search(id);
      expect(results.map((m) => m.mediaId), contains(alike));
      expect(results.map((m) => m.mediaId), isNot(contains(apart)));
      expect(results.map((m) => m.mediaId), isNot(contains(source)));
      final match = results.single;
      expect(match.participantIds.toSet(), {c, d});
      expect(match.state, 'suggested');
      await repo.reviewMatch(id, match.id, accepted: false);
      expect(await repo.search(id), isEmpty);
      expect((await repo.watchMatches(id).first).single.state, 'rejected');
      await repo.reviewMatch(id, match.id, accepted: true);
      results = await repo.search(id);
      expect(results.single.state, 'confirmed');
      await (db.update(db.media)..where((m) => m.id.equals(alike))).write(
        const MediaCompanion(modifiedAt: Value(999)),
      );
      await expectLater(
        repo.reviewMatch(id, match.id, accepted: true),
        throwsFormatException,
      );
      expect(await repo.watchMatches(id).first, isEmpty);
    },
  );

  test(
    'photo actions compare people and anime characters through the same catalog',
    () async {
      final source = await photo('human');
      final character = await photo('anime');
      await (db.update(db.bodies)..where((b) => b.mediaId.equals(character)))
          .write(const BodiesCompanion(kind: Value('character')));
      final id = await repo.saveAction('Partner stretch');
      await repo.addPhotoExample(actionId: id, mediaId: character);
      final matches = await repo.search(id);
      expect(matches.single.mediaId, source);
      await repo.reviewMatch(id, matches.single.id, accepted: true);
      expect((await repo.watchMatches(id).first).single.state, 'confirmed');
    },
  );

  test(
    'paired CPU matcher and offline fallback preserve the same action results',
    () async {
      final remote = _RemoteMatcher();
      repo = VideoActionsRepository(db, remoteMatcher: () => remote);
      final source = await photo('source');
      final alike = await photo('candidate');
      final id = await repo.saveAction('Greeting');
      await repo.addPhotoExample(actionId: id, mediaId: source);
      final online = await repo.search(id);
      expect(online.single.mediaId, alike);
      expect(remote.calls, greaterThan(0));
      remote.offline = true;
      final offline = await repo.search(id);
      expect(offline.single.mediaId, alike);
      expect(
        offline.single.similarity,
        closeTo(online.single.similarity, 1e-6),
      );
    },
  );

  test(
    'one catalog holds photo and motion examples, keeps stable IDs on rename and backs up evidence',
    () async {
      final p = await photo('photo');
      final v = await video('video');
      final id = await repo.saveAction('Stretch');
      await repo.addPhotoExample(actionId: id, mediaId: p);
      await repo.addExample(actionId: id, mediaId: v, startMs: 0, endMs: 2000);
      expect((await repo.action(id))!.examples.map((e) => e.kind).toSet(), {
        'photo',
        'video',
      });
      expect(await repo.saveAction('Partner stretch', id: id), id);
      await expectLater(
        repo.saveAction(' partner stretch '),
        throwsFormatException,
      );
      final backup = await AppSettings(db).rawBackedUp();
      expect(backup.keys, contains('$actionCatalogPrefix$id'));
      expect(backup.keys.any((k) => k.startsWith(actionFramePrefix)), isTrue);
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await AppSettings(restored).putRaw(backup);
      expect(
        (await VideoActionsRepository(restored).action(id))!.examples.length,
        2,
      );
      await (db.delete(db.media)..where((m) => m.id.equals(p))).go();
      expect(
        (await repo.action(id))!.examples.first.frames,
        isNotEmpty,
        reason: 'explicit exemplar snapshot outlives its source',
      );
    },
  );

  test(
    'temporal matching respects direction, actual pose samples, gaps and explicit scope',
    () async {
      final source = await video('source');
      final same = await video('same');
      final reverse = await video('reverse', reversed: true);
      final gap = await video('gap', gap: true);
      final old = await video('old', snapshots: false);
      final id = await repo.saveAction('Bend sideways');
      await repo.addExample(
        actionId: id,
        mediaId: source,
        startMs: 0,
        endMs: 2000,
      );
      final results = await repo.search(id);
      expect(results.map((m) => m.mediaId), contains(same));
      expect(
        results.map((m) => m.mediaId),
        isNot(anyOf(contains(reverse), contains(gap), contains(old))),
      );
      expect(await repo.search(id, mediaIds: {}), isEmpty);
      await expectLater(
        repo.addExample(actionId: id, mediaId: old, startMs: 0, endMs: 2000),
        throwsFormatException,
      );
      await expectLater(
        repo.addExample(actionId: id, mediaId: gap, startMs: 0, endMs: 30000),
        throwsFormatException,
      );
      await expectLater(
        repo.addExample(
          actionId: id,
          mediaId: source,
          startMs: -1,
          endMs: 2000,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'identity merges remap only participant references without changing labels or motion',
    () async {
      final a = await seedPerson(db),
          b = await seedPerson(db),
          target = await seedPerson(db);
      final source = await photo('source', people: [a, b]);
      final id = await repo.saveAction('High five');
      await repo.addPhotoExample(actionId: id, mediaId: source);
      final before = (await repo.action(
        id,
      ))!.examples.single.frames.first.members.first.data.toList();
      await db.transaction(() => mergeActionPersonReferences(db, a, target));
      final action = (await repo.action(id))!;
      expect(action.name, 'High five');
      expect(action.examples.single.participantIds.toSet(), {target, b});
      expect(
        action.examples.single.frames.first.members.first.data.toList(),
        before,
      );
    },
  );

  test(
    'catalog stream reacts to changes and removing examples/deleting actions is durable',
    () async {
      final stream = StreamIterator(repo.watchActions());
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      final id = await repo.saveAction('Wave');
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.single.id, id);
      final p = await photo('photo');
      final example = await repo.addPhotoExample(actionId: id, mediaId: p);
      await repo.removeExample(id, example);
      expect((await repo.action(id))!.examples, isEmpty);
      await repo.deleteAction(id);
      expect(await repo.action(id), isNull);
      await stream.cancel();
    },
  );

  test(
    'motion descriptor tolerates sample timing, preserves order, count and mirror choice',
    () {
      final q = [
        for (var i = 0; i < 3; i++)
          actionPoseFrame(i * 1000, [actor(0, angle: i * math.pi / 4)])!,
      ];
      final stretched = [
        for (var i = 0; i < 5; i++)
          actionPoseFrame(i * 600, [actor(100, angle: i * math.pi / 8)])!,
      ];
      expect(compareActionSequences(q, stretched), greaterThan(.82));
      expect(compareActionSequences(q, q.reversed.toList()), lessThan(.82));
      expect(
        compareActionSequences(q, [
          actionPoseFrame(0, [actor(0), actor(70)])!,
        ]),
        isNull,
      );
      final encoded = q.first.toJson();
      expect(
        compareActionSequences([q.first], [ActionPoseFrame.fromJson(encoded)]),
        closeTo(1, 1e-6),
      );
    },
  );
}
