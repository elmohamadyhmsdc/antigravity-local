// Roadmap section 8 on the phone: the policy, the region store (user decisions survive a rescan),
// the scan store hook (body ids), and the backfill.

import 'dart:io';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/sensitive_store.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/sensitive/sensitive_policy.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  group('policy', () {
    test('only the exposed sensitive labels above their threshold count', () {
      bool counts(String label, double score, [String? state]) =>
          regionCounts((label: label, score: score, userState: state));
      expect(counts('FEMALE_BREAST_EXPOSED', 0.9), isTrue);
      expect(counts('FEMALE_BREAST_EXPOSED', 0.3), isFalse, reason: 'below');
      expect(counts('BELLY_EXPOSED', 0.99), isFalse, reason: 'not a label');
      expect(counts('BUTTOCKS_COVERED', 0.99), isFalse, reason: 'covered');
      expect(counts('ANUS_EXPOSED', 0.9, 'dismissed'), isFalse);
      expect(counts('ANUS_EXPOSED', 0.1, 'confirmed'), isTrue);
    });

    test(
      'the override wins; any counting region of any frame flags the file',
      () {
        const hit = (label: 'BUTTOCKS_EXPOSED', score: 0.8, userState: null);
        const weak = (label: 'BUTTOCKS_EXPOSED', score: 0.2, userState: null);
        expect(mediaIsSensitive([hit]), isTrue);
        expect(mediaIsSensitive([weak, hit]), isTrue);
        expect(mediaIsSensitive([weak]), isFalse);
        expect(mediaIsSensitive([hit], override: 'none'), isFalse);
        expect(mediaIsSensitive([], override: 'sensitive'), isTrue);
      },
    );
  });

  group('store', () {
    late AppDatabase db;
    late SensitiveStore store;
    late int media;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = SensitiveStore(db);
      media = await seedMedia(db, asset: 's1');
    });
    tearDown(() => db.close());

    Future<void> put(
      List<Map<String, dynamic>> regions, {
      int? frame,
      Map<int, int> bodies = const {},
    }) => store.replaceRegions(
      media,
      [for (final r in regions) SensitiveRegionDto.fromJson(r)],
      imageW: 1000,
      imageH: 800,
      bodyIds: bodies,
      modelVersion: sensitiveModelVersion,
      frameNumber: frame,
    );

    Future<MediaRow> row() =>
        (db.select(db.media)..where((m) => m.id.equals(media))).getSingle();

    test('regions are stored normalised and flag the file', () async {
      await put([
        regionJson('FEMALE_BREAST_EXPOSED', box: [100, 80, 200, 160]),
      ]);
      final r = (await db.select(db.sensitiveRegions).get()).single;
      expect((r.x, r.y, r.w, r.h), (0.1, 0.1, 0.2, 0.2));
      expect(r.exposed, isTrue);
      final m = await row();
      expect(
        (m.isSensitive, m.sensitiveVersion),
        (true, sensitiveModelVersion),
      );
    });

    test('a file with no regions is still marked as checked', () async {
      await put([]);
      final m = await row();
      expect(
        (m.isSensitive, m.sensitiveVersion),
        (false, sensitiveModelVersion),
      );
    });

    test('a rescan keeps the user decision on the same region', () async {
      await put([
        regionJson('ANUS_EXPOSED', score: 0.4, box: [10, 10, 100, 100]),
      ]);
      final id = (await db.select(db.sensitiveRegions).get()).single.id;
      expect((await row()).isSensitive, isFalse, reason: 'below the threshold');
      await store.setRegionState(id, 'confirmed');
      expect((await row()).isSensitive, isTrue, reason: 'the user said yes');

      await put([
        regionJson('ANUS_EXPOSED', score: 0.5, box: [15, 12, 100, 100]),
      ]);
      final after = (await db.select(db.sensitiveRegions).get()).single;
      expect(after.userState, 'confirmed');
      expect((await row()).isSensitive, isTrue);

      // the model no longer sees it: a confirmed region is the user's word and stays
      await put([]);
      expect(await db.select(db.sensitiveRegions).get(), hasLength(1));
      await store.setRegionState(after.id, 'dismissed');
      await put([]);
      expect(await db.select(db.sensitiveRegions).get(), isEmpty);
      expect((await row()).isSensitive, isFalse);
    });

    test(
      'frames of a video are replaced one by one and any frame flags the file',
      () async {
        await put([regionJson('BUTTOCKS_EXPOSED')], frame: 0);
        await put([], frame: 1);
        await put([], frame: 0);
        expect(await db.select(db.sensitiveRegions).get(), isEmpty);
        await put([regionJson('BUTTOCKS_EXPOSED')], frame: 4);
        await put([], frame: 5);
        expect((await row()).isSensitive, isTrue);
        expect(await db.select(db.sensitiveRegions).get(), hasLength(1));
      },
    );

    test('the override and a policy recompute', () async {
      await put([regionJson('FEMALE_GENITALIA_EXPOSED')]);
      await store.setOverride(media, 'none');
      expect((await row()).isSensitive, isFalse);
      await store.setOverride(media, null);
      expect((await row()).isSensitive, isTrue);
      await db.customStatement('UPDATE media SET is_sensitive = 0');
      await store.recomputeAll();
      expect(
        (await row()).isSensitive,
        isTrue,
        reason: 'derived from the rows',
      );
    });

    test(
      'deleting the body keeps the region (set null); the media cascades',
      () async {
        final bodyId = await db
            .into(db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(media),
                bboxX: 0,
                bboxY: 0,
                bboxW: 1,
                bboxH: 1,
                score: 0.9,
                createdAt: 1,
              ),
            );
        await put([regionJson('ANUS_EXPOSED', body: 0)], bodies: {0: bodyId});
        expect(
          (await db.select(db.sensitiveRegions).get()).single.bodyId,
          bodyId,
        );
        await (db.delete(db.bodies)..where((b) => b.id.equals(bodyId))).go();
        expect(
          (await db.select(db.sensitiveRegions).get()).single.bodyId,
          isNull,
        );
        await (db.delete(db.media)..where((m) => m.id.equals(media))).go();
        expect(await db.select(db.sensitiveRegions).get(), isEmpty);
      },
    );
  });

  group('scan store hook', () {
    late AppDatabase db;
    late Directory tmp;
    late PhotoResultStore scan;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      tmp = Directory.systemTemp.createTempSync('ag_sens_');
      scan = PhotoResultStore(
        db: db,
        files: FileStore(Directory('${tmp.path}/crops')),
        index: InMemoryEmbeddingIndex(),
      );
    });
    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test(
      'regions are tied to the stored body and a plain response adds none',
      () async {
        final id = await seedMedia(db, asset: 'h1', status: 'scanning');
        final media = await (db.select(
          db.media,
        )..where((m) => m.id.equals(id))).getSingle();
        await scan.store(media, analysis(bodies: [bodyJson()]));
        expect(await db.select(db.sensitiveRegions).get(), isEmpty);
        expect(
          (await db.select(db.media).getSingle()).sensitiveVersion,
          0,
          reason: 'not asked for',
        );

        await scan.store(
          media,
          analysis(
            bodies: [bodyJson()],
            sensitive: [
              regionJson(
                'FEMALE_BREAST_EXPOSED',
                box: [200, 200, 80, 60],
                body: 0,
              ),
              regionJson('BELLY_COVERED', box: [600, 500, 50, 50], body: null),
            ],
          ),
        );
        final body = (await db.select(db.bodies).get()).single;
        final regions = await db.select(db.sensitiveRegions).get();
        expect(
          regions,
          hasLength(2),
          reason: 'the same body was updated in place, regions stored once',
        );
        expect(
          regions.firstWhere((r) => r.label == 'FEMALE_BREAST_EXPOSED').bodyId,
          body.id,
        );
        expect(
          regions.firstWhere((r) => r.label == 'BELLY_COVERED').bodyId,
          isNull,
        );
        final m = await db.select(db.media).getSingle();
        expect(
          (m.isSensitive, m.sensitiveVersion),
          (true, sensitiveModelVersion),
        );

        // scanning the same photo again does not duplicate regions
        await scan.store(
          media,
          analysis(
            bodies: [bodyJson()],
            sensitive: [
              regionJson(
                'FEMALE_BREAST_EXPOSED',
                box: [200, 200, 80, 60],
                body: 0,
              ),
            ],
          ),
        );
        expect(await db.select(db.sensitiveRegions).get(), hasLength(1));
      },
    );
  });

  group('attribution (S3) and videos (S4)', () {
    late AppDatabase db;
    late SensitiveStore store;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = SensitiveStore(db);
    });
    tearDown(() => db.close());

    Future<void> region(
      int media,
      int? bodyId, {
      String label = 'BUTTOCKS_EXPOSED',
      int? frame,
    }) => store.replaceRegions(
      media,
      [
        SensitiveRegionDto.fromJson(
          regionJson(label, body: bodyId == null ? null : 0),
        ),
      ],
      imageW: 1000,
      imageH: 800,
      bodyIds: {0: ?bodyId},
      modelVersion: sensitiveModelVersion,
      frameNumber: frame,
    );

    test(
      'regions follow the body to its person: by face, by an event link, by hand',
      () async {
        final lina = await seedPerson(db, name: 'Lina');
        final omar = await seedPerson(db, name: 'Omar');
        final m1 = await seedMedia(db, asset: 'a', takenAt: 3000);
        final m2 = await seedMedia(db, asset: 'b', takenAt: 2000);
        final m3 = await seedMedia(db, asset: 'c', takenAt: 1000);
        final m4 = await seedMedia(db, asset: 'd', takenAt: 500);
        final face = await seedFace(db, mediaId: m1, personId: lina);
        final byFace = await seedBody(db, mediaId: m1, faceId: face);
        final byEvent = await seedBody(
          db,
          mediaId: m2,
          personId: lina,
          linkMethod: 'event_outfit',
          linkConfidence: 0.93,
        );
        final byHand = await seedBody(
          db,
          mediaId: m3,
          personId: lina,
          linkMethod: 'manual',
        );
        final other = await seedBody(
          db,
          mediaId: m4,
          personId: omar,
          linkMethod: 'manual',
        );
        for (final (m, b) in [
          (m1, byFace),
          (m2, byEvent),
          (m3, byHand),
          (m4, other),
        ]) {
          await region(m, b);
        }
        expect(await store.mediaOfPerson(lina), [
          m1,
          m2,
          m3,
        ], reason: 'newest first, Omar excluded');
        expect(await store.mediaOfPerson(omar), [m4]);
        expect(await store.peopleOfMedia(m2), {lina});
      },
    );

    test(
      'a region that does not count, or one the user dismissed, attributes nothing',
      () async {
        final lina = await seedPerson(db);
        final m = await seedMedia(db, asset: 'x');
        final body = await seedBody(
          db,
          mediaId: m,
          personId: lina,
          linkMethod: 'manual',
        );
        await region(m, body, label: 'BELLY_EXPOSED');
        expect(
          await store.mediaOfPerson(lina),
          isEmpty,
          reason: 'not a sensitive label',
        );
        await region(m, body);
        expect(await store.mediaOfPerson(lina), [m]);
        final id = (await db.select(db.sensitiveRegions).get()).single.id;
        await store.setRegionState(id, 'dismissed');
        expect(await store.mediaOfPerson(lina), isEmpty);
        expect(await store.peopleOfMedia(m), isEmpty);
      },
    );

    test(
      'an unattributed region belongs to nobody until the body is linked',
      () async {
        final lina = await seedPerson(db);
        final m = await seedMedia(db, asset: 'y');
        final body = await seedBody(db, mediaId: m);
        await region(m, body);
        expect(await store.mediaOfPerson(lina), isEmpty);
        await (db.update(db.bodies)..where((b) => b.id.equals(body))).write(
          BodiesCompanion(
            personId: Value(lina),
            linkMethod: const Value('manual'),
          ),
        );
        expect(await store.mediaOfPerson(lina), [m]);
      },
    );

    test(
      'one sampled frame with a region flags the whole clip; clearing it unflags',
      () async {
        final video = await seedMedia(db, asset: 'v', kind: 'video');
        for (var frame = 0; frame < 5; frame++) {
          await store.replaceRegions(
            video,
            frame == 3
                ? [
                    SensitiveRegionDto.fromJson(
                      regionJson('ANUS_EXPOSED', box: [10, 10, 50, 50]),
                    ),
                  ]
                : [],
            imageW: 1000,
            imageH: 800,
            bodyIds: const {},
            modelVersion: sensitiveModelVersion,
            frameNumber: frame,
          );
        }
        final row = await (db.select(
          db.media,
        )..where((m) => m.id.equals(video))).getSingle();
        expect(row.isSensitive, isTrue);
        expect(await db.select(db.sensitiveRegions).get(), hasLength(1));
        await store.replaceRegions(
          video,
          const [],
          imageW: 1000,
          imageH: 800,
          bodyIds: const {},
          modelVersion: sensitiveModelVersion,
          frameNumber: 3,
        );
        expect(
          (await (db.select(
            db.media,
          )..where((m) => m.id.equals(video))).getSingle()).isSensitive,
          isFalse,
        );
      },
    );
  });
}
