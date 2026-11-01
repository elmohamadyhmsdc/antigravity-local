import 'dart:io';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/identity_groups.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_media_organizer.dart';
import '../support/seed.dart';

void main() {
  test(
    'group memberships and interrupted original-file moves survive backup restore',
    () async {
      final dir = await Directory.systemTemp.createTemp('group_backup_');
      final a = AppDatabase(NativeDatabase.memory()),
          b = AppDatabase(NativeDatabase.memory());
      try {
        final group = await IdentityGroupsRepository(a).create('One Piece');
        final person = await seedPerson(a, name: 'Luffy');
        await IdentityGroupsRepository(a).assign([person], group);
        final media = await seedMedia(a, asset: '42');
        await seedFace(a, mediaId: media, personId: person);
        final bridge = FakeMediaOrganizer()
          ..seed('42')
          ..crashAfter = 1;
        final organizer = PersonMediaOrganizer(db: a, bridge: bridge);
        await expectLater(
          organizer.apply(await organizer.plan({person})),
          throwsStateError,
        );
        BackupService service(AppDatabase db, String sub) => BackupService(
          db: db,
          files: FileStore(Directory('${dir.path}/$sub')),
          settings: AppSettings(db),
        );
        final archive = await service(
          a,
          'source',
        ).export(Directory('${dir.path}/export'));
        await service(b, 'restored').restore(archive);
        expect(
          (await b.select(b.identityGroups).get()).single.name,
          'One Piece',
        );
        expect((await b.select(b.persons).get()).single.groupId, group);
        expect(
          (await b.select(b.personMediaMoves).get()).single.state,
          'pending',
        );
        bridge.crashAfter = null;
        final restored = PersonMediaOrganizer(db: b, bridge: bridge);
        await restored.apply(await restored.pending());
        expect(
          (await b.select(b.personMediaMoves).get()).single.state,
          'moved',
        );
        expect((await b.select(b.media).get()).single.assetId, '42');
        expect(await b.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
        await IdentityGroupsRepository(b).delete(group);
        expect((await b.select(b.persons).get()).single.groupId, isNull);
        expect(await b.select(b.media).get(), hasLength(1));
      } finally {
        await a.close();
        await b.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
