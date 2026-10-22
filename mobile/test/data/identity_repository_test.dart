import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/identity_repository.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late IdentityRepository identities;
  late Directory dir;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    identities = IdentityRepository(db);
    dir = Directory.systemTemp.createTempSync('ag_identity_');
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test(
    'saved selections round-trip with backups and survive a person merge',
    () async {
      final first = await seedPerson(db, name: 'First');
      final second = await seedPerson(db, name: 'Second');
      final face = await seedFace(db, personId: first);
      final id = await identities.save(
        name: 'Side view',
        personId: first,
        faceIds: [face],
      );
      await PeopleRepository(
        db,
        FileStore(dir),
      ).mergePeople(sourceId: first, targetId: second);
      expect((await identities.watch().first).single.personId, second);
      expect((await identities.faces(id)).single.id, face);
      final service = BackupService(
        db: db,
        files: FileStore(Directory('${dir.path}/files')),
        settings: AppSettings(db),
      );
      final archive = await service.export(Directory('${dir.path}/out'));
      await identities.delete(id);
      await service.restore(archive);
      expect((await identities.faces(id)).single.id, face);
    },
  );

  test(
    'moved faces and mixed embedding models cannot be used silently',
    () async {
      final person = await seedPerson(db);
      final other = await seedPerson(db);
      final face = await seedFace(db, personId: person);
      final id = await identities.save(
        name: 'Portrait',
        personId: person,
        faceIds: [face],
      );
      await (db.update(db.faces)..where((f) => f.id.equals(face))).write(
        FacesCompanion(personId: Value(other)),
      );
      await expectLater(identities.faces(id), throwsFormatException);
      await expectLater(
        identities.save(name: 'Invalid', personId: person, faceIds: [face]),
        throwsFormatException,
      );
      final next = await seedFace(db, personId: other);
      await (db.update(db.faces)..where((f) => f.id.equals(next))).write(
        const FacesCompanion(modelId: Value('new-model')),
      );
      await expectLater(
        identities.save(name: 'Mixed', personId: other, faceIds: [face, next]),
        throwsFormatException,
      );
    },
  );

  test(
    'deleting faces and people cascades without dangling references',
    () async {
      final person = await seedPerson(db);
      final face = await seedFace(db, personId: person);
      final id = await identities.save(
        name: 'Portrait',
        personId: person,
        faceIds: [face],
      );
      await (db.delete(db.faces)..where((f) => f.id.equals(face))).go();
      expect(await db.select(db.identitySetFaces).get(), isEmpty);
      await expectLater(identities.faces(id), throwsFormatException);
      await (db.delete(db.persons)..where((p) => p.id.equals(person))).go();
      expect(await identities.watch().first, isEmpty);
    },
  );
}
