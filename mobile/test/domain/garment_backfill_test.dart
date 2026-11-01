// Roadmap Phase 7: raw garment tags per body, asked from the PC in the background and stored as evidence.
// Off by default; no tag is a filter.

import 'dart:io';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/garments/garment_backfill.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late FakeMobileApi api;
  late GarmentBackfill backfill;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeMobileApi();
    backfill = GarmentBackfill(
      db: db,
      media: FakeMediaLibrary(),
      api: () => api,
      decodeDimensions: (_) async => (1000, 800),
    );
  });
  tearDown(() => db.close());

  Future<int> photo(String asset, {String status = 'done'}) =>
      seedMedia(db, asset: asset, status: status);

  Future<int> body(int media, {double x = 0.1}) => db
      .into(db.bodies)
      .insert(
        BodiesCompanion.insert(
          mediaId: Value(media),
          bboxX: x,
          bboxY: 0.1,
          bboxW: 0.5,
          bboxH: 0.8,
          score: 0.9,
          createdAt: 1,
        ),
      );

  const shirt = GarmentTagDto(tag: 't-shirt', category: 'upper', score: 0.81);
  const jeans = GarmentTagDto(tag: 'jeans', category: 'lower', score: 0.44);

  test('the switch defaults to OFF and nothing is asked while off', () async {
    final a = await photo('a');
    await body(a);
    expect(await backfill.enabled, isFalse);
    expect(await backfill.run(), 0);
    expect(api.garmentCalls, isEmpty);
    expect(await backfill.pending(), 1);
  });

  test(
    'tags each body in order, sends boxes in pixels, and marks every photo as done',
    () async {
      await backfill.setEnabled(true);
      final a = await photo('a');
      final b = await photo('b');
      final first = await body(a);
      final second = await body(a, x: 0.3);
      api.garmentsHandler = (n) => AnalyzeGarmentsResponse(
        modelVersion: garmentModelVersion,
        bodies: <List<GarmentTagDto>>[
          [shirt, jeans],
          [],
        ].sublist(0, n),
      );

      expect(await backfill.run(), 2);
      expect(await backfill.pending(), 0);

      final sent = api.garmentCalls.first;
      expect(sent, hasLength(2));
      expect((sent.first.bbox.x, sent.first.bbox.w), (100.0, 500.0));
      expect(sent.first.kpts, isNull, reason: 'garments need only the box');
      expect(
        api.garmentCalls,
        hasLength(1),
        reason: 'photo b has no body: no call',
      );

      final tags = await garmentTagsOf(db, first);
      expect(tags.map((t) => (t.tag, t.category)), [
        ('t-shirt', 'upper'),
        ('jeans', 'lower'),
      ]);
      expect(await garmentTagsOf(db, second), isEmpty);
      final media = {for (final m in await db.select(db.media).get()) m.id: m};
      expect(media[a]!.garmentVersion, garmentModelVersion);
      expect(media[b]!.garmentVersion, garmentModelVersion);
      expect(await backfill.run(), 0, reason: 'not asked again');
    },
  );

  test('a new answer replaces the old tags of a body', () async {
    await backfill.setEnabled(true);
    final a = await photo('a');
    final one = await body(a);
    api.garmentsHandler = (n) => const AnalyzeGarmentsResponse(
      modelVersion: garmentModelVersion,
      bodies: <List<GarmentTagDto>>[
        [shirt],
      ],
    );
    await backfill.run();
    await (db.update(db.media)..where((m) => m.id.equals(a))).write(
      const MediaCompanion(garmentVersion: Value(0)),
    );
    api.garmentsHandler = (n) => const AnalyzeGarmentsResponse(
      modelVersion: garmentModelVersion,
      bodies: <List<GarmentTagDto>>[
        [jeans],
      ],
    );
    await backfill.run();
    expect((await garmentTagsOf(db, one)).map((t) => t.tag), ['jeans']);
  });

  test(
    'stops when asked, keeps the queue, and skips videos and unfinished files',
    () async {
      await backfill.setEnabled(true);
      for (final id in ['a', 'b', 'c']) {
        await body(await photo(id));
      }
      await seedMedia(db, asset: 'v', kind: 'video', status: 'done');
      await photo('p', status: 'pending');
      api.garmentsHandler = (n) => AnalyzeGarmentsResponse(
        modelVersion: garmentModelVersion,
        bodies: [for (var i = 0; i < n; i++) const []],
      );
      var calls = 0;
      expect(await backfill.run(shouldContinue: () => calls++ < 2), 2);
      expect(await backfill.pending(), 1);
    },
  );

  test(
    'a PC without the tagger or a busy GPU stops quietly and keeps the queue',
    () async {
      await backfill.setEnabled(true);
      await body(await photo('a'));
      await body(await photo('b'));
      api.garmentsHandler = (_) => throw const ApiException(
        code: 'model_missing',
        message: 'no tagger',
        statusCode: 409,
      );
      expect(await backfill.run(), 0);
      expect(
        api.garmentCalls,
        hasLength(1),
        reason: 'did not hammer the server',
      );
      expect(await backfill.pending(), 2);
    },
  );

  test('the response and the capability parse from the contract fixtures', () {
    final response = AnalyzeGarmentsResponse.fromJson(
      fixture('AnalyzeGarmentsResponse.two_bodies'),
    );
    expect(response.modelVersion, 1);
    expect(response.bodies.first.map((t) => t.tag), ['t-shirt', 'jeans']);
    expect(response.bodies.last, isEmpty);
    // the sensitive response now also carries the per-body embeddings it was asked for
    final sensitive = AnalyzeSensitiveResponse.fromJson(
      fixture('AnalyzeSensitiveResponse.with_embeddings'),
    );
    expect(sensitive.bodies, hasLength(2));
    expect(sensitive.bodies!.first.chestEmbedding, isNotNull);
    expect(sensitive.bodies!.last.chestEmbedding, isNull);
    expect(File('pubspec.yaml').existsSync(), isTrue);
  });
}
