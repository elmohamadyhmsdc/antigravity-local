// Face/body thumbnails are a cache: cut again from the original when missing, trimmed to a size
// limit with the least recently shown first, and people's covers always kept.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/crop_cache.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late List<(String, bool, int?)> loads;
  late List<({double x, double y, double w, double h})> cuts;
  Completer<void>? gate;

  CropCache cache({int cap = defaultCropCacheBytes}) => CropCache(
    db: db,
    files: files,
    capBytes: cap,
    loadOriginal: (asset, video, time) async {
      loads.add((asset, video, time));
      await gate?.future;
      return Uint8List.fromList([1, 2, 3]);
    },
    cut: (source, kind, box) async {
      cuts.add(box);
      return Uint8List.fromList([0xFF, 0xD8, kind.index, 0xFF, 0xD9]);
    },
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_crop_cache_');
    files = FileStore(Directory('${tmp.path}/crops'));
    loads = [];
    cuts = [];
    gate = null;
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  group('framing matches the PC', () {
    test('a face gets 20% of its longer side all round, at most 256 px', () {
      final r = cropPixels(
        CropKind.face,
        (x: 0.4, y: 0.4, w: 0.1, h: 0.2),
        1000,
        1000,
      );
      // box 400..500 x 400..600, pad 40
      expect((r.left, r.top, r.width, r.height), (360, 360, 180, 280));
      expect((r.outWidth, r.outHeight), (165, 256));
    });

    test('a face at the edge is clamped to the picture', () {
      final r = cropPixels(
        CropKind.face,
        (x: 0, y: 0, w: 0.05, h: 0.05),
        2000,
        1000,
      );
      expect((r.left, r.top), (0, 0));
      expect(r.width, lessThanOrEqualTo(2000));
    });

    test('a body gets 6% / 4% padding and at most 384 px height', () {
      final r = cropPixels(
        CropKind.body,
        (x: 0.25, y: 0.1, w: 0.5, h: 0.8),
        1000,
        1000,
      );
      expect((r.left, r.top, r.width, r.height), (220, 68, 560, 864));
      expect(r.outHeight, 384);
      expect(r.outWidth, (560 * 384 / 864).round());
    });
  });

  group('cutting again from the original', () {
    test(
      'a missing video face crop is cut from its frame and then reused',
      () async {
        final media = await seedMedia(db, asset: '77', kind: 'video');
        final face = await seedFace(
          db,
          mediaId: media,
          x: 0.3,
          y: 0.2,
          w: 0.1,
          h: 0.15,
        );
        await (db.update(db.faces)..where((f) => f.id.equals(face))).write(
          const FacesCompanion(timestampMs: Value(4500)),
        );
        final c = cache();
        final file = await c.ensure('faces/$face.jpg');
        expect(file, isNotNull);
        expect(file!.readAsBytesSync(), [0xFF, 0xD8, 0, 0xFF, 0xD9]);
        expect(loads, [('77', true, 4500)]);
        expect(cuts.single, (x: 0.3, y: 0.2, w: 0.1, h: 0.15));

        await c.ensure('faces/$face.jpg');
        expect(loads.length, 1, reason: 'the file exists now');
      },
    );

    test('a body crop of a photo uses the photo', () async {
      final media = await seedMedia(db, asset: '12');
      final body = await seedBody(db, mediaId: media);
      expect(await cache().ensure('bodies/$body.jpg'), isNotNull);
      expect(loads, [('12', false, null)]);
    });

    test(
      'two tiles asking for the same crop decode the original once',
      () async {
        final media = await seedMedia(db, asset: '5');
        final face = await seedFace(db, mediaId: media);
        final c = cache();
        gate = Completer<void>();
        final a = c.ensure('faces/$face.jpg');
        final b = c.ensure('faces/$face.jpg');
        gate!.complete();
        expect((await a)!.path, (await b)!.path);
        expect(loads.length, 1);
      },
    );

    test(
      'nothing to cut from: other files, deleted rows, unsafe paths',
      () async {
        final c = cache();
        expect(await c.ensure('characters/3.jpg'), isNull);
        expect(await c.ensure('faces/999.jpg'), isNull);
        expect(await c.ensure('faces/999.jpg'), isNull);
        expect(await c.ensure(null), isNull);
        expect(loads, isEmpty);
      },
    );
  });

  group('the size limit', () {
    Future<void> crop(String relative, int bytes, int ageMinutes) async {
      await files.write(relative, Uint8List(bytes));
      files
          .resolve(relative)
          .setLastModifiedSync(
            DateTime.now().subtract(Duration(minutes: ageMinutes)),
          );
    }

    test(
      'the least recently shown go first; covers and characters stay',
      () async {
        final media = await seedMedia(db);
        final cover = await seedFace(db, mediaId: media);
        await seedPerson(db, name: 'Sara', avatarFaceId: cover);
        await crop('faces/$cover.jpg', 1000, 100); // oldest, but a cover
        await crop('faces/2.jpg', 1000, 90);
        await crop('bodies/3.jpg', 1000, 80);
        await crop('faces/4.jpg', 1000, 10);
        await crop('characters/5.jpg', 5000, 200);

        final c = cache(cap: 2500);
        expect(await c.size(), 4000);
        expect(await c.evict(), 2000);
        expect(files.resolve('faces/$cover.jpg').existsSync(), isTrue);
        expect(files.resolve('faces/2.jpg').existsSync(), isFalse);
        expect(files.resolve('bodies/3.jpg').existsSync(), isFalse);
        expect(files.resolve('faces/4.jpg').existsSync(), isTrue);
        expect(files.resolve('characters/5.jpg').existsSync(), isTrue);
        expect(await c.evict(), 0, reason: 'already under the limit');
      },
    );

    test('showing a crop protects it from the next trim', () async {
      final media = await seedMedia(db);
      final a = await seedFace(db, mediaId: media);
      final b = await seedFace(db, mediaId: media);
      await crop('faces/$a.jpg', 1000, 60);
      await crop('faces/$b.jpg', 1000, 30);
      final c = cache(cap: 1500);
      await c.ensure('faces/$a.jpg');
      await c.evict();
      expect(files.resolve('faces/$a.jpg').existsSync(), isTrue);
      expect(files.resolve('faces/$b.jpg').existsSync(), isFalse);
    });
  });
}
