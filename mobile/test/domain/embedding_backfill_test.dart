// Roadmap 7.5 for photos scanned before Phase 8: the pause-aware, one-photo-per-transaction embedding backfill.

import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/sensitive/embedding_backfill.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

Float32List unit(int hot) => Float32List(384)..[hot] = 1;

void main() {
  late AppDatabase db;
  late FakeMobileApi api;
  late EmbeddingBackfill backfill;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeMobileApi();
    backfill = EmbeddingBackfill(
      db: db,
      media: FakeMediaLibrary(),
      api: () => api,
      decodeDimensions: (_) async => (1000, 800),
    );
  });
  tearDown(() => db.close());

  Future<int> photo(
    String asset, {
    int regionsVersion = 1,
    String? label,
    double score = 0.9,
    int bodies = 1,
  }) async {
    final id = await seedMedia(db, asset: asset);
    await (db.update(db.media)..where((m) => m.id.equals(id))).write(
      MediaCompanion(sensitiveVersion: Value(regionsVersion)),
    );
    for (var i = 0; i < bodies; i++) {
      await seedBody(db, mediaId: id);
    }
    if (label != null) {
      await db
          .into(db.sensitiveRegions)
          .insert(
            SensitiveRegionsCompanion.insert(
              mediaId: id,
              label: label,
              exposed: true,
              score: score,
              x: 0.1,
              y: 0.1,
              w: 0.2,
              h: 0.2,
              modelVersion: 1,
              createdAt: 1,
            ),
          );
    }
    return id;
  }

  AnalyzeSensitiveResponse answer(int bodies, {bool chest = true}) =>
      AnalyzeSensitiveResponse(
        modelVersion: 1,
        regions: const [],
        bodies: [
          for (var i = 0; i < bodies; i++)
            BodyEmbeddingsDto(
              chestEmbedding: chest && i == 0 ? unit(5) : null,
              morphology: chest && i == 0 ? {'scale_source': 'kpts'} : null,
            ),
        ],
      );

  test(
    'a photo with an exposed region is embedded in place and marked; others are marked without a request',
    () async {
      final withRegion = await photo('a', label: 'FEMALE_BREAST_EXPOSED');
      final without = await photo('b');
      final covered = await photo('c', label: 'BELLY_COVERED');
      final weak = await photo('d', label: 'BUTTOCKS_EXPOSED', score: 0.3);
      api.sensitiveResult = answer(1);
      expect(await backfill.pending(), 4);

      expect(await backfill.run(), 4);
      expect(await backfill.pending(), 0);
      expect(
        api.sensitiveCalls,
        hasLength(1),
        reason: 'only the photo with a patch-worthy region cost a request',
      );
      expect(api.sensitiveEmbeddingFlags, [true]);

      final body = await (db.select(
        db.bodies,
      )..where((b) => b.mediaId.equals(withRegion))).getSingle();
      expect(vectorFromBlob(body.chestEmbedding!), unit(5));
      expect(body.morphology, contains('scale_source'));
      expect(body.buttocksEmbedding, isNull);
      final versions = {
        for (final m in await db.select(db.media).get())
          m.id: m.bodyEmbeddingVersion,
      };
      expect(versions[withRegion], bodyEmbeddingModelVersion);
      expect(versions[without], bodyEmbeddingModelVersion);
      expect(versions[covered], bodyEmbeddingModelVersion);
      expect(versions[weak], bodyEmbeddingModelVersion);
      expect(await backfill.run(), 0, reason: 'nothing left');
    },
  );

  test(
    'regions must be known first, and videos / unfinished photos are left alone',
    () async {
      await photo('unchecked', regionsVersion: 0, label: 'ANUS_EXPOSED');
      await seedMedia(db, asset: 'v', kind: 'video');
      expect(await backfill.pending(), 0);
      expect(await backfill.run(), 0);
      expect(api.sensitiveCalls, isEmpty);
    },
  );

  test(
    'stops when asked, keeps the queue, and an answer that does not line up with the bodies is not trusted',
    () async {
      await photo('a', label: 'FEMALE_BREAST_EXPOSED', bodies: 2);
      await photo('b', label: 'FEMALE_BREAST_EXPOSED');
      api.sensitiveResult = answer(1); // 2 bodies sent, 1 answered
      var calls = 0;
      expect(await backfill.run(shouldContinue: () => calls++ < 1), 0);
      expect(
        await backfill.pending(),
        2,
        reason: 'the mismatched answer was refused, nothing marked',
      );
      api.sensitiveResult = answer(2);
      expect(await backfill.run(limit: 1), 1);
      expect(await backfill.pending(), 1);
    },
  );

  test(
    'a PC without the model, a busy GPU or the user switch stops it quietly',
    () async {
      await photo('a', label: 'FEMALE_BREAST_EXPOSED');
      api.sensitiveError = const ApiException(
        code: 'model_missing',
        message: 'x',
        statusCode: 409,
      );
      expect(await backfill.run(), 0);
      expect(await backfill.pending(), 1);
      api.sensitiveError = const ApiException(
        code: 'gpu_busy',
        message: 'x',
        retryable: true,
        statusCode: 503,
      );
      expect(await backfill.run(), 0);
      api.sensitiveError = null;
      api.sensitiveResult = answer(1);
      await backfill.setEnabled(false);
      expect(await backfill.run(), 0, reason: 'switched off');
      expect(api.sensitiveCalls, hasLength(2));
      await backfill.setEnabled(true);
      expect(await backfill.run(), 1);
    },
  );
}
