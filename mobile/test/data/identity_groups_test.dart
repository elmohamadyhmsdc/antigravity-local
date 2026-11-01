import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/identity_groups.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late IdentityGroupsRepository groups;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    groups = IdentityGroupsRepository(db);
  });
  tearDown(() => db.close());
  test(
    'groups contain people and anime characters without merging identities',
    () async {
      final group = await groups.create(' One  Piece ');
      expect(await groups.create('one piece'), group);
      final luffy = await seedPerson(db, name: 'Luffy'),
          oda = await seedPerson(db, name: 'Oda');
      await (db.update(db.persons)..where((p) => p.id.equals(luffy))).write(
        const PersonsCompanion(kind: Value('character')),
      );
      await groups.assign([luffy, oda], group);
      final row = (await groups.watch().first).single;
      expect((row.name, row.people, row.characters), ('One Piece', 1, 1));
      final people = PeopleRepository(db, FileStore(Directory.systemTemp));
      expect((await people.person(luffy))!.groupName, 'One Piece');
      await groups.rename(group, 'East Blue');
      expect((await people.person(luffy))!.groupName, 'East Blue');
      await groups.delete(group);
      expect(
        (await db.select(db.persons).get()).map((p) => p.groupId),
        everyElement(isNull),
      );
      expect(await db.select(db.persons).get(), hasLength(2));
    },
  );
  test(
    'group media filter includes photos and videos through repeated detection references',
    () async {
      final group = await groups.create('One Piece');
      final person = await seedPerson(db, name: 'Luffy');
      await groups.assign([person], group);
      final first = await seedMedia(db, asset: 'a'),
          second = await seedMedia(db, asset: 'b', kind: 'video');
      final unrelated = await seedMedia(db, asset: 'c');
      final face = await seedFace(db, mediaId: first, personId: person);
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: second,
              kind: 'f',
              refId: face,
              x: 0,
              y: 0,
              w: .5,
              h: .5,
            ),
          );
      final query = MediaQueries(db);
      final rows = await query.page(
        const MediaFilter().copyWith(groupId: group),
        offset: 0,
        limit: 20,
      );
      expect(rows.map((m) => m.id).toSet(), {first, second});
      expect(rows.map((m) => m.id), isNot(contains(unrelated)));
      await groups.assign([person], null);
      expect(
        await query.page(MediaFilter(groupId: group), offset: 0, limit: 20),
        isEmpty,
      );
    },
  );
  test(
    'merging inherits a missing group and retains the target group when both exist',
    () async {
      final a = await groups.create('A'), b = await groups.create('B');
      final source = await seedPerson(db, name: 'Source'),
          target = await seedPerson(db, name: 'Target');
      final repository = PeopleRepository(db, FileStore(Directory.systemTemp));
      await groups.assign([source], a);
      await repository.mergePeople(sourceId: source, targetId: target);
      expect((await repository.person(target))!.groupId, a);
      final another = await seedPerson(db, name: 'Another');
      await groups.assign([another], b);
      await repository.mergePeople(sourceId: another, targetId: target);
      expect((await repository.person(target))!.groupId, a);
    },
  );
}
