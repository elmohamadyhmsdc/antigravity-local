import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  test(
    'v16 to v17 adds equipment without rewriting library or queuing rescans',
    () async {
      final dir = await Directory.systemTemp.createTemp('equipment_migration_');
      final file = File('${dir.path}/phone.db');
      final before = AppDatabase(NativeDatabase(file));
      await before
          .into(before.media)
          .insert(MediaCompanion.insert(assetId: 'existing', kind: 'photo'));
      await before.close();
      final legacy = raw.sqlite3.open(file.path);
      legacy.execute(
        'DROP TABLE equipment_objects; DROP TABLE equipment_photos; PRAGMA user_version=16;',
      );
      legacy.close();
      final after = AppDatabase(NativeDatabase(file));
      try {
        expect(
          (await after.select(after.media).get()).single.assetId,
          'existing',
        );
        expect(await after.select(after.equipmentObjects).get(), isEmpty);
        expect(await after.select(after.equipmentPhotos).get(), isEmpty);
        expect(
          await after.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await after.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
