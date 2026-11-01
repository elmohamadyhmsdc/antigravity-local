// Roadmap section 8.3: the background backfill checks the photos scanned before the feature.

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/sensitive/sensitive_backfill.dart';
import 'package:antigravity_mobile/domain/sensitive/sensitive_policy.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late FakeMobileApi api;
  late FakeMediaLibrary library;
  late SensitiveBackfill backfill;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    api = FakeMobileApi();
    library = FakeMediaLibrary();
    backfill = SensitiveBackfill(
      db: db,
      media: library,
      api: () => api,
      decodeDimensions: (_) async => (1000, 800),
    );
  });
  tearDown(() => db.close());

  Future<int> photo(String asset, {String status = 'done'}) =>
      seedMedia(db, asset: asset, status: status);

  Future<int> body(int media) => db
      .into(db.bodies)
      .insert(
        BodiesCompanion.insert(
          mediaId: Value(media),
          bboxX: 0.1,
          bboxY: 0.1,
          bboxW: 0.5,
          bboxH: 0.8,
          score: 0.9,
          createdAt: 1,
          kpts: const Value(
            '[[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9],[0.1,0.1,0.9]]',
          ),
        ),
      );

  test(
    'checks pending photos, sends the stored bodies in pixels, and marks every photo as checked',
    () async {
      final a = await photo('a');
      final b = await photo('b');
      final bodyId = await body(a);
      api.sensitiveResult = AnalyzeSensitiveResponse(
        modelVersion: sensitiveModelVersion,
        regions: [
          SensitiveRegionDto.fromJson(
            regionJson('BUTTOCKS_EXPOSED', box: [200, 200, 100, 100], body: 0),
          ),
        ],
      );
      expect(await backfill.pending(), 2);

      final done = await backfill.run();
      expect(done, 2);
      expect(await backfill.pending(), 0);

      final first = api.sensitiveCalls.first.single;
      expect(
        (first.bbox.x, first.bbox.w),
        (100.0, 500.0),
        reason: 'normalised box -> 1000 px wide picture',
      );
      expect(first.kpts, hasLength(17));
      expect(first.kpts!.first, [100.0, 80.0, 0.9]);
      expect(api.sensitiveCalls.last, isEmpty, reason: 'photo b has no body');

      final region = (await db.select(db.sensitiveRegions).get()).firstWhere(
        (r) => r.mediaId == a,
      );
      expect(region.bodyId, bodyId);
      final media = {for (final m in await db.select(db.media).get()) m.id: m};
      expect(media[a]!.isSensitive, isTrue);
      expect(media[b]!.sensitiveVersion, sensitiveModelVersion);
    },
  );

  test('a photo without regions is not asked again', () async {
    await photo('a');
    expect(await backfill.run(), 1);
    expect(await backfill.run(), 0);
    expect(api.sensitiveCalls, hasLength(1));
  });

  test('stops when asked, leaving the rest queued', () async {
    await photo('a');
    await photo('b');
    await photo('c');
    var calls = 0;
    final done = await backfill.run(shouldContinue: () => calls++ < 2);
    expect(done, 2);
    expect(await backfill.pending(), 1);
  });

  test(
    'scanning photos, videos and unfinished files are not touched',
    () async {
      await photo('p', status: 'pending');
      await seedMedia(db, asset: 'v', kind: 'video', status: 'done');
      expect(await backfill.run(), 0);
      expect(api.sensitiveCalls, isEmpty);
    },
  );

  test(
    'a PC without the model or a busy GPU stops the run quietly and keeps the queue',
    () async {
      await photo('a');
      await photo('b');
      api.sensitiveError = const ApiException(
        code: 'model_missing',
        message: 'no model',
        statusCode: 409,
      );
      expect(await backfill.run(), 0);
      expect(
        api.sensitiveCalls,
        hasLength(1),
        reason: 'it did not hammer the server',
      );
      expect(await backfill.pending(), 2);

      api.sensitiveError = const ApiException(
        code: 'gpu_busy',
        message: 'busy',
        retryable: true,
        statusCode: 503,
      );
      expect(await backfill.run(), 0);
      expect(await backfill.pending(), 2);
    },
  );

  test(
    'an unreadable photo is skipped for this run and does not block the others',
    () async {
      await photo('gone');
      await photo('ok');
      library.unreadable.add('gone');
      expect(await backfill.run(), 1);
      expect(
        await backfill.pending(),
        1,
        reason: 'the unreadable one stays queued for a later run',
      );
    },
  );
}
