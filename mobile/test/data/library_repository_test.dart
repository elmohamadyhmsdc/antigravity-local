// The scan queue: the `media` table is the queue. Diffing MediaStore against it, claiming work,
// and what a restart or a failure does to the queue.

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

AssetInfo _asset(String id, {int modified = 1000, int w = 1200, int h = 800}) =>
    AssetInfo(
      id: id,
      width: w,
      height: h,
      modifiedAt: modified,
      takenAt: modified,
    );

void main() {
  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });
  tearDown(() => db.close());

  Future<MediaRow> row(String assetId) => (db.select(
    db.media,
  )..where((m) => m.assetId.equals(assetId))).getSingle();

  group('syncAssets', () {
    test(
      'new photos are queued, an unchanged library queues nothing, running it twice is harmless',
      () async {
        final first = await repo.syncAssets(syntheticAssets(5));
        expect(
          (first.added, first.changed, first.requeued, first.unchanged),
          (5, 0, 0, 0),
        );
        expect(await repo.scanCounts(), const ScanCounts(pending: 5));

        final second = await repo.syncAssets(syntheticAssets(5));
        expect((second.added, second.queued, second.unchanged), (0, 0, 5));
        expect(
          (await db.select(db.media).get()).length,
          5,
          reason: 'no duplicate rows (asset_id is unique)',
        );
      },
    );

    test(
      'a scanned photo that was edited (modified time or size) is queued again',
      () async {
        await repo.syncAssets([_asset('a'), _asset('b'), _asset('c')]);
        await db
            .update(db.media)
            .write(
              const MediaCompanion(
                scanStatus: Value('done'),
                scanAttempts: Value(2),
              ),
            );

        final result = await repo.syncAssets([
          _asset('a'), // untouched
          _asset('b', modified: 2000), // edited
          _asset('c', w: 600, h: 400), // resized
        ]);
        expect((result.changed, result.unchanged), (2, 1));
        expect((await row('a')).scanStatus, 'done');
        final b = await row('b');
        expect(
          (b.scanStatus, b.scanAttempts, b.modifiedAt),
          ('pending', 0, 2000),
        );
        expect((await row('c')).width, 600);
      },
    );

    test(
      'failed and skipped photos get another chance; a done one scanned by an older algorithm too',
      () async {
        await repo.syncAssets([
          _asset('failed'),
          _asset('skipped'),
          _asset('old'),
          _asset('fresh'),
        ]);
        await (db.update(
          db.media,
        )..where((m) => m.assetId.equals('failed'))).write(
          const MediaCompanion(
            scanStatus: Value('failed'),
            scanError: Value('boom'),
            scanAttempts: Value(3),
          ),
        );
        await (db.update(db.media)..where((m) => m.assetId.equals('skipped')))
            .write(const MediaCompanion(scanStatus: Value('skipped')));
        await (db.update(
          db.media,
        )..where((m) => m.assetId.equals('old'))).write(
          const MediaCompanion(
            scanStatus: Value('done'),
            scanVersion: Value(scanVersion - 1),
          ),
        );
        await (db.update(
          db.media,
        )..where((m) => m.assetId.equals('fresh'))).write(
          const MediaCompanion(
            scanStatus: Value('done'),
            scanVersion: Value(scanVersion),
          ),
        );

        final result = await repo.syncAssets([
          _asset('failed'),
          _asset('skipped'),
          _asset('old'),
          _asset('fresh'),
        ]);
        expect((result.requeued, result.unchanged), (3, 1));
        final failed = await row('failed');
        expect(
          (failed.scanStatus, failed.scanError, failed.scanAttempts),
          ('pending', isNull, 0),
        );
        expect((await row('fresh')).scanStatus, 'done');
      },
    );

    test('the same photo twice in one page (two albums) is one row', () async {
      final r = await repo.syncAssets([_asset('x'), _asset('x'), _asset('y')]);
      expect(r.added, 2);
      expect((await db.select(db.media).get()).length, 2);
    });

    test(
      'more than one chunk of photos (the SQL variable limit) works',
      () async {
        final r = await repo.syncAssets(syntheticAssets(950));
        expect(r.added, 950);
        expect((await repo.syncAssets(syntheticAssets(950))).unchanged, 950);
      },
    );

    test(
      'skipPending takes photos that left the chosen albums out of the queue, a new sync revives the rest',
      () async {
        await repo.syncAssets([_asset('keep'), _asset('drop')]);
        await repo.skipPending();
        expect((await repo.scanCounts()).skipped, 2);
        await repo.syncAssets([
          _asset('keep'),
        ]); // 'drop' is no longer in the albums
        final counts = await repo.scanCounts();
        expect((counts.pending, counts.skipped), (1, 1));
      },
    );
  });

  group('the work queue', () {
    test(
      'claimNext hands out the oldest waiting photo once and counts the attempt',
      () async {
        await repo.syncAssets([_asset('first'), _asset('second')]);
        final a = await repo.claimNext();
        expect(a!.assetId, 'first');
        expect((await row('first')).scanStatus, 'scanning');
        expect((await row('first')).scanAttempts, 1);
        final b = await repo.claimNext();
        expect(b!.assetId, 'second');
        expect(
          await repo.claimNext(),
          isNull,
          reason: 'nothing waiting, both are being scanned',
        );
        expect((await repo.scanCounts()).scanning, 2);
      },
    );

    test(
      'a photo handed back (the PC was busy) is waiting again and the attempt is not held against it',
      () async {
        await repo.syncAssets([_asset('a')]);
        final claimed = (await repo.claimNext())!;
        await repo.requeue(claimed.id);
        final back = await row('a');
        expect((back.scanStatus, back.scanAttempts), ('pending', 0));
      },
    );

    test(
      'markFailed keeps the reason; a restart (resetScanning) puts half-done photos back',
      () async {
        await repo.syncAssets([_asset('a'), _asset('b')]);
        final a = (await repo.claimNext())!;
        await repo.markFailed(a.id, 'not a picture');
        await repo.claimNext(); // b is being scanned when the app dies
        expect(await repo.resetScanning(), 1);
        final counts = await repo.scanCounts();
        expect((counts.failed, counts.pending, counts.scanning), (1, 1, 0));
        expect((await row('a')).scanError, 'not a picture');
      },
    );

    test('counts follow the table live', () async {
      final seen = <ScanCounts>[];
      final sub = repo.watchScanCounts().listen(seen.add);
      addTearDown(sub.cancel);
      await repo.syncAssets(syntheticAssets(3));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen.last.pending, 3);
      final m = (await repo.claimNext())!;
      await db
          .update(db.media)
          .write(const MediaCompanion(scanStatus: Value('done')));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(seen.last, const ScanCounts(done: 3));
      expect(m.assetId, 'asset-1');
    });
  });

  test(
    'deleting photos removes their faces and detections with them',
    () async {
      final m = await seedMedia(db, asset: 'x');
      await seedFace(db, mediaId: m, seed: 1);
      await repo.deleteMedia([m]);
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.mediaDetections).get(), isEmpty);
    },
  );
}
