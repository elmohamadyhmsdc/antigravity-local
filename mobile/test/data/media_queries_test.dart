// The Library grid's queries: filters, paging and the boxes of one photo.

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late MediaQueries queries;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    queries = MediaQueries(db);
  });
  tearDown(() => db.close());

  late int sara, withFaces, withoutFaces, pending, failed;

  Future<void> seedLibrary() async {
    sara = await seedPerson(db, name: 'Sara');
    withFaces = await seedMedia(db, asset: 'a', takenAt: 4000);
    withoutFaces = await seedMedia(db, asset: 'b', takenAt: 3000);
    pending = await seedMedia(db, asset: 'c', status: 'pending', takenAt: 2000);
    failed = await seedMedia(db, asset: 'd', status: 'failed', takenAt: 1000);
    await seedMedia(db, asset: 'v', kind: 'video', takenAt: 5000);
    await seedFace(db, mediaId: withFaces, personId: sara, seed: 1);
    await seedFace(db, mediaId: withFaces, seed: 2);
  }

  Future<List<int>> ids(
    MediaFilter f, {
    int offset = 0,
    int limit = 100,
  }) async => (await queries.page(
    f,
    offset: offset,
    limit: limit,
  )).map((m) => m.id).toList();

  test(
    'the library lists photos newest first and leaves videos out (they come in a later phase)',
    () async {
      await seedLibrary();
      expect(await queries.count(const MediaFilter()), 4);
      expect(await ids(const MediaFilter()), [
        withFaces,
        withoutFaces,
        pending,
        failed,
      ]);
      final first = (await queries.page(
        const MediaFilter(),
        offset: 0,
        limit: 1,
      )).single;
      expect(
        (first.assetId, first.faceCount, first.scanStatus),
        ('a', 2, 'done'),
      );
      expect(first.takenAt, DateTime.fromMillisecondsSinceEpoch(4000));
    },
  );

  test('scanned / not scanned / failed', () async {
    await seedLibrary();
    expect(await ids(const MediaFilter(scan: ScanFilter.scanned)), [
      withFaces,
      withoutFaces,
    ]);
    expect(await ids(const MediaFilter(scan: ScanFilter.unscanned)), [pending]);
    expect(await ids(const MediaFilter(scan: ScanFilter.failed)), [failed]);
  });

  test(
    'has faces / has no faces (only photos that were scanned can be said to have none)',
    () async {
      await seedLibrary();
      expect(await ids(const MediaFilter(hasFaces: true)), [withFaces]);
      expect(
        await ids(const MediaFilter(hasFaces: false)),
        [withoutFaces],
        reason: 'a photo waiting to be scanned is not "without faces"',
      );
    },
  );

  test(
    'a person\'s photos: found through the detections, so a linked duplicate counts too',
    () async {
      await seedLibrary();
      expect(await ids(MediaFilter(personId: sara)), [withFaces]);
      // the same face seen in another photo (the duplicate rule linked it instead of storing it again)
      final face = (await db.select(db.faces).get()).firstWhere(
        (f) => f.personId == sara,
      );
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: withoutFaces,
              kind: 'f',
              refId: face.id,
              x: 0.1,
              y: 0.1,
              w: 0.2,
              h: 0.2,
            ),
          );
      expect(await ids(MediaFilter(personId: sara)), [withFaces, withoutFaces]);
      expect(
        await queries.count(
          MediaFilter(personId: sara, scan: ScanFilter.scanned, hasFaces: true),
        ),
        2,
      );
      expect(await queries.count(MediaFilter(personId: sara + 100)), 0);
    },
  );

  test('paging walks the whole list without repeating or skipping', () async {
    await seedLibrary();
    final all = await ids(const MediaFilter());
    final paged = [
      ...await ids(const MediaFilter(), offset: 0, limit: 3),
      ...await ids(const MediaFilter(), offset: 3, limit: 3),
      ...await ids(const MediaFilter(), offset: 6, limit: 3),
    ];
    expect(paged, all);
  });

  test(
    'a photo without a taken date falls back to its modified time',
    () async {
      final a = await seedMedia(db, asset: 'a', modifiedAt: 100, takenAt: 100);
      final b = await seedMedia(db, asset: 'b', modifiedAt: 300, takenAt: 300);
      await db.customStatement(
        'UPDATE media SET taken_at = NULL WHERE id = ?',
        [a],
      );
      expect(await ids(const MediaFilter()), [b, a]);
      expect(
        (await queries.page(
          const MediaFilter(),
          offset: 1,
          limit: 1,
        )).single.takenAt,
        DateTime.fromMillisecondsSinceEpoch(100),
      );
    },
  );

  test('the filter compares by value', () {
    expect(const MediaFilter(personId: 1), const MediaFilter(personId: 1));
    expect(
      const MediaFilter(personId: 1) == const MediaFilter(personId: 2),
      isFalse,
    );
    expect(const MediaFilter().isDefault, isTrue);
    final f = const MediaFilter(
      personId: 3,
      hasFaces: true,
    ).copyWith(clearPerson: true, clearHasFaces: true);
    expect(f.isDefault, isTrue);
  });

  test(
    'the boxes of one photo, with the person of each (a body belongs to its face\'s person)',
    () async {
      await seedLibrary();
      final omar = await seedPerson(db, name: 'Omar');
      final faces = await db.select(db.faces).get();
      final saraFace = faces.firstWhere((f) => f.personId == sara);
      final body = await seedBody(
        db,
        mediaId: withFaces,
        faceId: saraFace.id,
        appearance: outfit(1),
      );
      final linkedBody = await seedBody(
        db,
        mediaId: withFaces,
        personId: omar,
        linkMethod: 'manual',
      );

      final boxes = await queries.watchDetections(withFaces).first;
      expect(boxes.where((b) => b.isFace).length, 2);
      final byRef = {for (final b in boxes) '${b.kind}${b.refId}': b};
      expect(byRef['f${saraFace.id}']!.personId, sara);
      expect(byRef['b$body']!.personId, sara, reason: 'through its face');
      expect(byRef['b$linkedBody']!.personId, omar, reason: 'through the link');
      expect(byRef['b$linkedBody']!.linkMethod, 'manual');
      expect(
        boxes.where((b) => b.isFace && b.personId == null).length,
        1,
        reason: 'the unsorted face',
      );
      expect(await queries.watchDetections(pending).first, isEmpty);
    },
  );

  test('changes() fires when a face is added', () async {
    await seedLibrary();
    final fired = queries.changes().first.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await seedFace(db, mediaId: withoutFaces, seed: 9);
    await fired;
  });
}
