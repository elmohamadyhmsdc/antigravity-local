// Cleanup of what the scan no longer stores: tiny faces and the small faces of a crowd photo.

import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/cleanup/background_faces.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late BackgroundFaces cleaner;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    cleaner = BackgroundFaces(db);
  });
  tearDown(() => db.close());

  Future<void> px(int face, double value) =>
      (db.update(db.faces)..where((f) => f.id.equals(face))).write(
        FacesCompanion(facePx: Value(value)),
      );

  test('tiny faces are found, normal ones are not', () async {
    final big = await seedFace(db, seed: 1);
    final tiny = await seedFace(db, seed: 2);
    await px(tiny, 30);

    expect(await cleaner.find(), [tiny]);
    expect(big, isNonZero);
  });

  test(
    'in a crowd, faces far smaller than the biggest are background; a couple is never a crowd',
    () async {
      final crowd = await seedMedia(db, asset: 'crowd');
      final main = await seedFace(db, mediaId: crowd, seed: 1);
      final other = await seedFace(db, mediaId: crowd, seed: 2);
      final small = await seedFace(db, mediaId: crowd, seed: 3);
      await px(main, 300);
      await px(other, 200);
      await px(small, 90); // 30% of the biggest, in a frame of three

      final couple = await seedMedia(db, asset: 'couple');
      final a = await seedFace(db, mediaId: couple, seed: 4);
      final b = await seedFace(db, mediaId: couple, seed: 5);
      await px(a, 300);
      await px(b, 90);

      expect(await cleaner.find(), [small]);
    },
  );

  test(
    'a face the user vouched for is never listed; hide and restore are reversible',
    () async {
      final people = PeopleRepository(
        db,
        FileStore(Directory.systemTemp.createTempSync('ag_bg_')),
        index: InMemoryEmbeddingIndex(),
      );
      final sara = await seedPerson(db, name: 'Sara');
      final kept = await seedFace(db, seed: 1);
      final tiny = await seedFace(db, seed: 2);
      await px(kept, 30);
      await px(tiny, 30);
      await people.assignFaces([kept], sara); // by hand: vouched for

      final found = await cleaner.find();
      expect(found, [tiny]);

      await cleaner.hide(found);
      expect(
        (await (db.select(
          db.faces,
        )..where((f) => f.id.equals(tiny))).getSingle()).hidden,
        isTrue,
      );
      expect(
        await cleaner.find(),
        isEmpty,
        reason: 'hidden faces are not listed again',
      );

      await cleaner.restore(found);
      expect(
        (await (db.select(
          db.faces,
        )..where((f) => f.id.equals(tiny))).getSingle()).hidden,
        isFalse,
      );
    },
  );
}
