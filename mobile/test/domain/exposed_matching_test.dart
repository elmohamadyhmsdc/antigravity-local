// Roadmap Phase 8 on the phone: embeddings stored in place by the scan, the ranked "similar photos" search,
// DBSCAN, and the persistent clusters that stay OFF until the gate has passed.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/domain/pose/exposed_matching.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

Float32List unit384(int seed, {Float32List? near, double noise = 0.0}) {
  final r = math.Random(seed);
  final v = Float32List(384);
  for (var i = 0; i < 384; i++) {
    v[i] = near == null
        ? r.nextDouble() - 0.5
        : near[i] + (r.nextDouble() - 0.5) * noise * 0.1;
  }
  final n = math.sqrt(v.fold<double>(0, (a, b) => a + b * b));
  for (var i = 0; i < 384; i++) {
    v[i] /= n;
  }
  return v;
}

void main() {
  late AppDatabase db;
  late int media;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    media = await seedMedia(db, asset: 'x');
  });
  tearDown(() => db.close());

  Future<int> body(
    Float32List? chest, {
    Float32List? buttocks,
    int? person,
    String? link,
  }) async {
    final id = await seedBody(
      db,
      mediaId: media,
      personId: person,
      linkMethod: link,
    );
    await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
      BodiesCompanion(
        chestEmbedding: Value(chest == null ? null : packFloat32(chest)),
        buttocksEmbedding: Value(
          buttocks == null ? null : packFloat32(buttocks),
        ),
      ),
    );
    return id;
  }

  group('dbscan', () {
    test('two tight groups and a loner', () {
      final a = unit384(1), b = unit384(2);
      final vs = [
        a,
        unit384(3, near: a, noise: 0.1),
        unit384(4, near: a, noise: 0.1),
        b,
        unit384(5, near: b, noise: 0.1),
        unit384(6),
      ];
      final labels = dbscan(vs, eps: 0.25, minPoints: 2);
      expect(labels[0], labels[1]);
      expect(labels[1], labels[2]);
      expect(labels[3], labels[4]);
      expect(labels[0], isNot(labels[3]));
      expect(labels[5], -1, reason: 'noise');
      expect(dbscan(const [], eps: 0.25), isEmpty);
    });
  });

  group('similar photos', () {
    test('ranked by cosine, never itself, per half', () async {
      final base = unit384(10);
      final q = await body(base);
      final close = await body(unit384(11, near: base, noise: 0.1));
      final far = await body(unit384(12));
      await body(null, buttocks: unit384(13));
      final matcher = ExposedMatcher(db);
      final r = await matcher.findSimilar(q, ExposedKind.chest);
      expect(r.map((x) => x.bodyId), [close, far]);
      expect(r.first.similarity, greaterThan(r.last.similarity));
      expect(
        await matcher.findSimilar(q, ExposedKind.buttocks),
        isEmpty,
        reason: 'the query has no lower-body embedding',
      );
      expect(
        await matcher.findSimilar(q, ExposedKind.chest, minimum: 0.9),
        hasLength(1),
      );
      expect(await matcher.kindsOf(q), {ExposedKind.chest});
    });
  });

  group('clusters are off until switched on', () {
    test(
      'rebuild does nothing while off; on, it groups and remembers a person',
      () async {
        final base = unit384(20);
        final a1 = await body(base),
            a2 = await body(unit384(21, near: base, noise: 0.1)),
            a3 = await body(unit384(22, near: base, noise: 0.1));
        final loner = await body(unit384(23));
        final clusters = ExposedClusters(db);
        expect(await clusters.enabled, isFalse);
        expect(await clusters.rebuild(ExposedKind.chest), isNull);
        expect(await db.select(db.bodyClusters).get(), isEmpty);

        await clusters.setEnabled(true);
        expect(await clusters.rebuild(ExposedKind.chest), 1);
        final c = await db.select(db.bodyClusters).getSingle();
        expect(
          (c.clusterType, c.bodyCount, c.centroidEmbedding.length),
          ('chest', 3, 384 * 4),
        );
        final rows = {
          for (final b in await db.select(db.bodies).get()) b.id: b,
        };
        expect(
          {
            rows[a1]!.chestClusterId,
            rows[a2]!.chestClusterId,
            rows[a3]!.chestClusterId,
          },
          {c.id},
        );
        expect(rows[loner]!.chestClusterId, isNull);

        expect(
          await clusters.rebuild(ExposedKind.chest),
          1,
          reason: 'idempotent: same clusters again',
        );
        expect(await db.select(db.bodyClusters).get(), hasLength(1));
      },
    );

    test(
      'one tap assigns only what nobody claimed and never against a rejection',
      () async {
        final base = unit384(30);
        final lina = await seedPerson(db, name: 'Lina');
        final omar = await seedPerson(db, name: 'Omar');
        final free = await body(base);
        final taken = await body(
          unit384(31, near: base, noise: 0.1),
          person: omar,
          link: 'manual',
        );
        final rejected = await body(unit384(32, near: base, noise: 0.1));
        await db
            .into(db.bodyRejections)
            .insert(
              BodyRejectionsCompanion.insert(bodyId: rejected, personId: lina),
            );
        final clusters = ExposedClusters(db);
        await clusters.setEnabled(true);
        await clusters.rebuild(ExposedKind.chest);
        final cluster = (await db.select(db.bodyClusters).getSingle()).id;

        expect(await clusters.assign(cluster, lina), 1);
        final rows = {
          for (final b in await db.select(db.bodies).get()) b.id: b,
        };
        expect(
          (rows[free]!.personId, rows[free]!.linkMethod),
          (lina, 'manual'),
        );
        expect(
          rows[taken]!.personId,
          omar,
          reason: "somebody else's link stays",
        );
        expect(
          rows[rejected]!.personId,
          isNull,
          reason: 'the user said not her',
        );
        expect((await db.select(db.bodyClusters).getSingle()).personId, lina);
      },
    );

    test(
      'a bridge photo only SUGGESTS the other cluster, and needs two of them',
      () async {
        final chestBase = unit384(40), lowerBase = unit384(41);
        Future<int> bridge(int s) => body(
          unit384(s, near: chestBase, noise: 0.1),
          buttocks: unit384(s + 100, near: lowerBase, noise: 0.1),
        );
        final lina = await seedPerson(db);
        await bridge(42);
        await bridge(43);
        await body(unit384(44, near: chestBase, noise: 0.1));
        await body(null, buttocks: unit384(45, near: lowerBase, noise: 0.1));
        final clusters = ExposedClusters(db);
        await clusters.setEnabled(true);
        await clusters.rebuild(ExposedKind.chest);
        await clusters.rebuild(ExposedKind.buttocks);
        final chest = (await (db.select(
          db.bodyClusters,
        )..where((c) => c.clusterType.equals('chest'))).getSingle()).id;
        final lower = (await (db.select(
          db.bodyClusters,
        )..where((c) => c.clusterType.equals('buttocks'))).getSingle()).id;
        expect(
          await clusters.bridgeSuggestions(),
          isEmpty,
          reason: 'neither cluster has a person yet',
        );
        await clusters.assign(chest, lina);
        final suggestions = await clusters.bridgeSuggestions();
        expect(suggestions.single.fromCluster, chest);
        expect(suggestions.single.toCluster, lower);
        expect(suggestions.single.bridges, 2);
        expect(
          (await db.select(db.bodyClusters).get())
              .firstWhere((c) => c.id == lower)
              .personId,
          isNull,
          reason: 'never propagated automatically',
        );
        expect(await clusters.bridgeSuggestions(minBridges: 3), isEmpty);
      },
    );
  });

  group('cluster UI support', () {
    test(
      'clusters() lists members; a rebuilt cluster keeps the majority person; suggestions are queued only while on',
      () async {
        final base = unit384(50);
        final lina = await seedPerson(db, name: 'Lina');
        await body(base, person: lina, link: 'manual');
        await body(
          unit384(51, near: base, noise: 0.1),
          person: lina,
          link: 'manual',
        );
        final free = await body(unit384(52, near: base, noise: 0.1));
        final claimed = await body(unit384(53, near: base, noise: 0.1));
        await db
            .into(db.bodyRejections)
            .insert(
              BodyRejectionsCompanion.insert(bodyId: claimed, personId: lina),
            );
        final clusters = ExposedClusters(db);
        expect(
          await clusters.publishSuggestions(),
          0,
          reason: 'off: nothing is queued',
        );
        await clusters.setEnabled(true);
        await clusters.rebuild(ExposedKind.chest);

        final listed = await clusters.clusters();
        expect(listed, hasLength(1));
        expect(listed.single.bodyIds, hasLength(4));
        expect(listed.single.cluster.personId, lina);

        final queued = await db.select(db.reviewBodyLinks).get();
        expect(queued.map((q) => q.bodyId), [free]);
        expect(
          (queued.single.method, queued.single.personId),
          ('cluster', lina),
        );
        expect(queued.single.confidence, closeTo(0.85, 1e-9));
        expect(
          (await db.select(db.bodies).get())
              .firstWhere((b) => b.id == free)
              .personId,
          isNull,
          reason: 'a suggestion, never a link',
        );
      },
    );

    test('the switch defaults to OFF', () async {
      expect(await ExposedClusters(db).enabled, isFalse);
    });
  });

  group('the scan stores the embeddings', () {
    test(
      'in place, without wiping them when a later scan does not return any',
      () async {
        final tmp = Directory.systemTemp.createTempSync('ag_p8_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final scan = PhotoResultStore(
          db: db,
          files: FileStore(Directory('${tmp.path}/c')),
          index: InMemoryEmbeddingIndex(),
        );
        final m = await seedMedia(db, asset: 'scan', status: 'scanning');
        final row = await (db.select(
          db.media,
        )..where((x) => x.id.equals(m))).getSingle();
        final e = unit384(50);
        final json = bodyJson();
        json['chest_embedding'] = encodeVector(e);
        json['morphology'] = {
          'scale_source': 'kpts',
          'breast_span_ratio': 0.3,
          'micro_marks': <Object>[],
        };
        await scan.store(row, analysis(bodies: [json]));
        var stored = (await db.select(db.bodies).get()).firstWhere(
          (b) => b.mediaId == m,
        );
        expect(vectorFromBlob(stored.chestEmbedding!), e);
        expect(stored.buttocksEmbedding, isNull);
        expect(stored.morphology, contains('breast_span_ratio'));

        await scan.store(row, analysis(bodies: [bodyJson()]));
        stored = (await db.select(db.bodies).get()).firstWhere(
          (b) => b.mediaId == m,
        );
        expect(stored.id, isNotNull);
        expect(
          vectorFromBlob(stored.chestEmbedding!),
          e,
          reason: 'a rescan without the flag keeps the embedding',
        );
      },
    );
  });

  test('the DTO parses embeddings and morphology, absent means null', () {
    final json = bodyJson();
    expect(DetectedBody.fromJson(json).chestEmbedding, isNull);
    json['chest_embedding'] = encodeVector(unit384(60));
    json['morphology'] = {'scale_source': 'bbox'};
    final parsed = DetectedBody.fromJson(json);
    expect(parsed.chestEmbedding!.length, 384);
    expect(parsed.morphology!['scale_source'], 'bbox');
    expect(parsed.buttocksEmbedding, isNull);
    json['chest_embedding'] = 'AAAA';
    expect(
      () => DetectedBody.fromJson(json),
      throwsA(anything),
      reason: 'wrong size is refused',
    );
  });
}
