import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import '../support/seed.dart';

void main() {
  test('v17 to v18 keeps names, scan state and detection links', () async {
    final dir = await Directory.systemTemp.createTemp(
      'identity_group_upgrade_',
    );
    final file = File('${dir.path}/phone.db');
    final before = AppDatabase(NativeDatabase(file));
    final person = await seedPerson(before, name: 'Luffy');
    final media = await seedMedia(before, asset: 'existing');
    await seedFace(before, mediaId: media, personId: person);
    await before.close();
    final legacy = raw.sqlite3.open(file.path);
    legacy.execute(
      'DROP TABLE person_media_moves; ALTER TABLE persons DROP COLUMN group_id; DROP TABLE identity_groups; PRAGMA user_version=17;',
    );
    legacy.close();
    final after = AppDatabase(NativeDatabase(file));
    try {
      expect((await after.select(after.persons).get()).single.name, 'Luffy');
      expect((await after.select(after.persons).get()).single.groupId, isNull);
      expect((await after.select(after.media).get()).single.scanStatus, 'done');
      expect((await after.select(after.faces).get()).single.personId, person);
      expect(await after.select(after.identityGroups).get(), isEmpty);
      expect(await after.select(after.personMediaMoves).get(), isEmpty);
      expect(
        await after.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    } finally {
      await after.close();
      await dir.delete(recursive: true);
    }
  });
}
