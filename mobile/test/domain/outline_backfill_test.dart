import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/domain/geometry/outline.dart';
import 'package:antigravity_mobile/domain/scan/outline_backfill.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

class FakeMediaLibrary implements MediaLibrary {
  Uint8List? jpegBytes = Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<Uint8List?> downscaledJpeg(
    String assetId, {
    required int width,
    required int height,
    required int maxSide,
  }) async => jpegBytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMobileApi implements MobileApi {
  int calls = 0;
  List<OutlineTargetDto> lastTargets = [];
  List<List<Offset>?> returnOutlines = [];
  bool shouldThrow = false;

  @override
  Future<List<List<Offset>?>> analyzeOutlines(
    Uint8List jpegBytes,
    List<OutlineTargetDto> targets, {
    String filename = 'photo.jpg',
  }) async {
    calls++;
    lastTargets = targets;
    if (shouldThrow) throw Exception('Server error');
    return returnOutlines;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late FakeMediaLibrary media;
  late FakeMobileApi api;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    media = FakeMediaLibrary();
    api = FakeMobileApi();
  });

  tearDown(() async {
    await db.close();
  });

  OutlineBackfill createBackfill({bool isServerReady = true}) {
    return OutlineBackfill(
      db: db,
      media: media,
      api: () => api,
      isServerReady: () => isServerReady,
      decodeDimensions: (_) async => (1000, 1000),
    );
  }

  Future<int> missingDetection(int mediaId, {int refId = 99}) => db
      .into(db.mediaDetections)
      .insert(
        MediaDetectionsCompanion.insert(
          mediaId: mediaId,
          kind: 'b',
          refId: refId,
          x: 0.1,
          y: 0.1,
          w: 0.2,
          h: 0.2,
        ),
      );

  const triangle = [Offset(100, 100), Offset(300, 100), Offset(200, 300)];

  test(
    'failed work survives closing and reopening the database on disk',
    () async {
      final directory = await Directory.systemTemp.createTemp('outline_queue_');
      try {
        await db.close();
        final file = File('${directory.path}/library.sqlite');
        db = AppDatabase(NativeDatabase(file));
        final mediaId = await seedMedia(db);
        await missingDetection(mediaId);
        api.shouldThrow = true;
        expect(await createBackfill().backfillPhoto(mediaId), isFalse);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        final restored = createBackfill();
        expect(await restored.watchPending().first, 1);
        api.shouldThrow = false;
        api.returnOutlines = [triangle];
        expect(await restored.retryPending(), 1);
        expect(await restored.watchPending().first, 0);
      } finally {
        await db.close();
        db = AppDatabase(NativeDatabase.memory());
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'partial failure stays queued across backfill instances; retry sends only missing targets',
    () async {
      final mediaId = await seedMedia(db);
      final first = await missingDetection(mediaId, refId: 1);
      final second = await missingDetection(mediaId, refId: 2);
      api.returnOutlines = [triangle, null];
      final original = createBackfill();
      expect(await original.backfillPhoto(mediaId), isTrue);
      expect(await original.watchPending().first, 1);
      final saved = await (db.select(
        db.mediaDetections,
      )..where((d) => d.id.equals(first))).getSingle();
      expect(saved.outline, isNotNull);

      // No in-memory list is needed to reconstruct the queue after app restart.
      final restored = createBackfill();
      expect(await restored.watchPending().first, 1);
      api.returnOutlines = [triangle];
      expect(await restored.retryPending(), 1);
      expect(api.lastTargets, hasLength(1));
      expect(await restored.watchPending().first, 0);
      expect(
        (await (db.select(
          db.mediaDetections,
        )..where((d) => d.id.equals(second))).getSingle()).outline,
        isNotNull,
      );
      expect(
        (await (db.select(
          db.mediaDetections,
        )..where((d) => d.id.equals(first))).getSingle()).outline,
        saved.outline,
      );
      expect(await restored.retryPending(), 0);
      expect(api.calls, 2);
    },
  );

  test(
    'explicit retry can recover a failure in the same app session',
    () async {
      final mediaId = await seedMedia(db);
      await missingDetection(mediaId);
      final backfill = createBackfill();
      api.shouldThrow = true;
      expect(await backfill.backfillPhoto(mediaId), isFalse);
      expect(await backfill.watchPending().first, 1);
      expect(await backfill.backfillPhoto(mediaId), isFalse);
      expect(
        api.calls,
        1,
        reason: 'A rebuilding viewer must not hammer the full PC',
      );
      api.shouldThrow = false;
      api.returnOutlines = [triangle];
      expect(await backfill.retryPending(), 1);
      expect(api.calls, 2);
      expect(await backfill.watchPending().first, 0);
    },
  );

  test(
    'a memory failure stops the retry pass without losing any pending photos',
    () async {
      final first = await seedMedia(db, asset: 'first');
      final second = await seedMedia(db, asset: 'second');
      await missingDetection(first);
      await missingDetection(second);
      api.returnOutlines = [null];
      final backfill = createBackfill();
      expect(await backfill.retryPending(), 0);
      expect(api.calls, 1);
      expect(await backfill.watchPending().first, 2);
      api.returnOutlines = [triangle];
      expect(await backfill.retryPending(), 2);
      expect(await backfill.watchPending().first, 0);
    },
  );

  test(
    'retry stops between photos when paused and resumes the remaining queue',
    () async {
      final first = await seedMedia(db, asset: 'first');
      final second = await seedMedia(db, asset: 'second');
      await missingDetection(first);
      await missingDetection(second);
      api.returnOutlines = [triangle];
      final backfill = createBackfill();
      expect(
        await backfill.retryPending(shouldContinue: () => api.calls == 0),
        1,
      );
      expect(await backfill.watchPending().first, 1);
      expect(await backfill.retryPending(), 1);
      expect(await backfill.watchPending().first, 0);
    },
  );

  test(
    'a busy server can be retried after becoming ready without recreating the service',
    () async {
      final mediaId = await seedMedia(db);
      await missingDetection(mediaId);
      var ready = false;
      final backfill = OutlineBackfill(
        db: db,
        media: media,
        api: () => api,
        isServerReady: () => ready,
        decodeDimensions: (_) async => (1000, 1000),
      );
      expect(await backfill.backfillPhoto(mediaId), isFalse);
      expect(await backfill.retryPending(), 0);
      expect(api.calls, 0);
      ready = true;
      api.returnOutlines = [triangle];
      expect(await backfill.backfillPhoto(mediaId), isTrue);
      expect(api.calls, 1);
    },
  );

  test(
    'pending queue excludes videos, active scans and finished outlines',
    () async {
      final video = await seedMedia(db, asset: 'video', kind: 'video');
      final active = await seedMedia(db, asset: 'active', status: 'scanning');
      final photo = await seedMedia(db, asset: 'photo');
      await missingDetection(video);
      await missingDetection(active);
      await missingDetection(photo);
      final backfill = createBackfill();
      expect(await backfill.watchPending().first, 1);
      api.returnOutlines = [triangle];
      expect(await backfill.retryPending(), 1);
      expect(await backfill.watchPending().first, 0);
    },
  );

  test(
    'opening a photo with NULL outlines triggers one call and stores results',
    () async {
      final mediaId = await seedMedia(
        db,
        asset: 'photo_1',
        width: 2000,
        height: 2000,
      );
      final faceId = await seedFace(db);

      // Insert face detection with outline = NULL
      final fDetId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: mediaId,
              kind: 'f',
              refId: faceId,
              x: 0.1,
              y: 0.1,
              w: 0.2,
              h: 0.2,
            ),
          );

      // Insert body detection with outline = NULL
      final bDetId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: mediaId,
              kind: 'b',
              refId: 99,
              x: 0.2,
              y: 0.2,
              w: 0.4,
              h: 0.6,
            ),
          );

      api.returnOutlines = [
        [
          const Offset(100, 100),
          const Offset(300, 100),
          const Offset(200, 300),
        ],
        [
          const Offset(200, 200),
          const Offset(600, 200),
          const Offset(400, 800),
        ],
      ];

      final backfill = createBackfill();
      final ok = await backfill.backfillPhoto(mediaId);
      expect(ok, isTrue);
      expect(api.calls, 1);
      expect(api.lastTargets, hasLength(2));
      expect(api.lastTargets[0].kind, 'f');
      expect(api.lastTargets[0].bbox.x, 100.0);
      expect(api.lastTargets[1].kind, 'b');
      expect(api.lastTargets[1].bbox.x, 200.0);

      // Verify stored outlines in DB
      final fRow = await (db.select(
        db.mediaDetections,
      )..where((t) => t.id.equals(fDetId))).getSingle();
      expect(fRow.outline, isNotNull);
      final fPoints = decodeOutline(fRow.outline);
      expect(fPoints, isNotNull);
      expect(fPoints!, hasLength(3));

      final bRow = await (db.select(
        db.mediaDetections,
      )..where((t) => t.id.equals(bDetId))).getSingle();
      expect(bRow.outline, isNotNull);
      final bPoints = decodeOutline(bRow.outline);
      expect(bPoints, isNotNull);
      expect(bPoints!, hasLength(3));

      // Debounce: calling again for same photo does nothing
      final secondRun = await backfill.backfillPhoto(mediaId);
      expect(secondRun, isFalse);
      expect(api.calls, 1);
    },
  );

  test('a failure leaves NULL and fails silently', () async {
    final mediaId = await seedMedia(
      db,
      asset: 'photo_err',
      width: 1000,
      height: 1000,
    );
    final faceId = await seedFace(db);
    final detId = await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            kind: 'f',
            refId: faceId,
            x: 0.1,
            y: 0.1,
            w: 0.2,
            h: 0.2,
          ),
        );

    api.shouldThrow = true;
    final backfill = createBackfill();
    final ok = await backfill.backfillPhoto(mediaId);
    expect(ok, isFalse);

    final row = await (db.select(
      db.mediaDetections,
    )..where((t) => t.id.equals(detId))).getSingle();
    expect(row.outline, isNull);
  });

  test('a connected-but-busy server is skipped', () async {
    final mediaId = await seedMedia(
      db,
      asset: 'photo_busy',
      width: 1000,
      height: 1000,
    );
    final faceId = await seedFace(db);
    await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: mediaId,
            kind: 'f',
            refId: faceId,
            x: 0.1,
            y: 0.1,
            w: 0.2,
            h: 0.2,
          ),
        );

    final backfill = createBackfill(isServerReady: false);
    final ok = await backfill.backfillPhoto(mediaId);
    expect(ok, isFalse);
    expect(api.calls, 0);
  });

  test('videos and photos without missing outlines are skipped', () async {
    final videoId = await seedMedia(db, asset: 'video_1', kind: 'video');
    final backfill = createBackfill();
    final okVideo = await backfill.backfillPhoto(videoId);
    expect(okVideo, isFalse);
    expect(api.calls, 0);

    final photoId = await seedMedia(db, asset: 'photo_full');
    final faceId = await seedFace(db);
    await db
        .into(db.mediaDetections)
        .insert(
          MediaDetectionsCompanion.insert(
            mediaId: photoId,
            kind: 'f',
            refId: faceId,
            x: 0.1,
            y: 0.1,
            w: 0.2,
            h: 0.2,
            outline: Value(
              jsonEncode([
                [0.5, 0.5],
                [0.6, 0.6],
                [0.4, 0.6],
              ]),
            ),
          ),
        );

    final okPhoto = await backfill.backfillPhoto(photoId);
    expect(okPhoto, isFalse);
    expect(api.calls, 0);
  });
}
