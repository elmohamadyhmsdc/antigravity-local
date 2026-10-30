// Every manual correction the user can make, and that none of them is ever undone by auto-grouping.

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late InMemoryEmbeddingIndex index;
  late PeopleRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_people_');
    files = FileStore(Directory('${tmp.path}/crops'));
    index = InMemoryEmbeddingIndex();
    repo = PeopleRepository(db, files, index: index);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<FaceRow> face(int id) =>
      (db.select(db.faces)..where((f) => f.id.equals(id))).getSingle();
  Future<BodyRow> body(int id) =>
      (db.select(db.bodies)..where((b) => b.id.equals(id))).getSingle();
  Future<PersonRow?> person(int id) =>
      (db.select(db.persons)..where((p) => p.id.equals(id))).getSingleOrNull();

  group('people', () {
    test(
      'the list is ordered by face count, with the chosen cover or else the best face',
      () async {
        final few = await seedPerson(db, name: 'Few');
        final many = await seedPerson(db, name: 'Many');
        await seedFace(
          db,
          personId: few,
          seed: 1,
          cropPath: 'faces/a.jpg',
          quality: 0.9,
        );
        await seedFace(
          db,
          personId: many,
          seed: 2,
          cropPath: 'faces/low.jpg',
          quality: 0.3,
        );
        final best = await seedFace(
          db,
          personId: many,
          seed: 3,
          cropPath: 'faces/best.jpg',
          quality: 0.9,
        );
        final chosen = await seedFace(
          db,
          personId: many,
          seed: 4,
          cropPath: 'faces/chosen.jpg',
          quality: 0.5,
        );

        var people = await repo.people();
        expect(people.map((p) => (p.name, p.faceCount)), [
          ('Many', 3),
          ('Few', 1),
        ]);
        expect(
          people.first.avatarCropPath,
          'faces/best.jpg',
          reason: 'no cover chosen: the best-quality face',
        );

        await repo.setAvatar(many, chosen);
        people = await repo.people();
        expect(people.first.avatarCropPath, 'faces/chosen.jpg');
        expect(best, isNonZero);

        await repo.assignFaces([
          chosen,
        ], few); // the cover face leaves: back to the best remaining one
        people = await repo.people();
        expect(
          people.firstWhere((p) => p.id == many).avatarCropPath,
          'faces/best.jpg',
        );
      },
    );

    test('a cover can only be one of the person\'s own faces', () async {
      final a = await seedPerson(db), b = await seedPerson(db);
      final theirs = await seedFace(db, personId: b, seed: 1);
      await repo.setAvatar(a, theirs);
      expect((await person(a))!.avatarFaceId, isNull);
    });

    test(
      'createPerson: trims the name, a blank name means "unnamed", the best face becomes the cover',
      () async {
        final f1 = await seedFace(db, seed: 1, quality: 0.4);
        final f2 = await seedFace(db, seed: 2, quality: 0.8);
        final named = await repo.createPerson(
          name: '  Sara  ',
          faceIds: [f1, f2],
        );
        expect((await person(named))!.name, 'Sara');
        expect((await person(named))!.avatarFaceId, f2);
        expect((await face(f1)).personId, named);

        final blank = await repo.createPerson(name: '   ');
        expect((await person(blank))!.name, isNull);
        await repo.renamePerson(blank, ' Omar ');
        expect((await person(blank))!.name, 'Omar');
        await repo.renamePerson(blank, '');
        expect((await person(blank))!.name, isNull);
      },
    );

    test(
      'deleting a person sets their faces free, clears outfit links to them and forgets the pairs',
      () async {
        final sara = await seedPerson(db, name: 'Sara');
        final omar = await seedPerson(db, name: 'Omar');
        final f = await seedFace(db, personId: sara, seed: 1);
        final linked = await seedBody(
          db,
          personId: sara,
          linkMethod: 'appearance',
          linkConfidence: 0.9,
        );
        await repo.markDistinct(sara, omar);
        await repo.rejectFaces([
          await seedFace(db, seed: 2),
        ], fromPersonId: sara);

        await repo.deletePerson(sara);

        expect(await person(sara), isNull);
        expect(
          (await face(f)).personId,
          isNull,
          reason: 'the face is not deleted',
        );
        final b = await body(linked);
        expect(
          (b.personId, b.linkMethod, b.linkConfidence),
          (null, null, null),
        );
        expect(await db.select(db.personDistinct).get(), isEmpty);
        expect(await db.select(db.faceRejections).get(), isEmpty);
        expect(await person(omar), isNotNull);
      },
    );
  });

  group('faces', () {
    test(
      'assigning moves faces, forgets a "not them" about that very person and clears their suggestion',
      () async {
        final sara = await seedPerson(db), omar = await seedPerson(db);
        final f = await seedFace(db, personId: omar, seed: 1);
        final g = await seedFace(db, seed: 2);
        await db
            .into(db.faceRejections)
            .insert(FaceRejectionsCompanion.insert(faceId: g, personId: sara));
        await db
            .into(db.faceRejections)
            .insert(FaceRejectionsCompanion.insert(faceId: g, personId: omar));
        await db
            .into(db.reviewMatches)
            .insert(
              ReviewMatchesCompanion.insert(
                faceId: Value(g),
                personId: sara,
                score: 0.4,
                margin: 0.1,
                decision: 'suggest',
              ),
            );

        await repo.assignFaces([f, g], sara);

        expect((await face(f)).personId, sara);
        expect((await face(g)).personId, sara);
        final rejections = await db.select(db.faceRejections).get();
        expect(
          rejections.map((r) => (r.faceId, r.personId)),
          [(g, omar)],
          reason: '"not Omar" still holds, "not Sara" was wrong',
        );
        expect(await db.select(db.reviewMatches).get(), isEmpty);
      },
    );

    test(
      '"not this person" unassigns the face and auto-grouping is told never to put it back',
      () async {
        final sara = await seedPerson(db);
        final f = await seedFace(db, personId: sara, seed: 1);
        final suggested = await seedFace(
          db,
          seed: 2,
        ); // not assigned yet: a rejected suggestion
        await repo.rejectFaces([f]);
        await repo.rejectFaces([suggested], fromPersonId: sara);

        expect((await face(f)).personId, isNull);
        expect((await face(suggested)).personId, isNull);
        final rejections = await db.select(db.faceRejections).get();
        expect(rejections.map((r) => (r.faceId, r.personId)).toSet(), {
          (f, sara),
          (suggested, sara),
        });
      },
    );

    test(
      'rejecting a face that has no person and no person given does nothing',
      () async {
        final f = await seedFace(db, seed: 1);
        await repo.rejectFaces([f]);
        expect(await db.select(db.faceRejections).get(), isEmpty);
      },
    );

    test(
      'deleting faces removes their crops, detections, cover role and index entries - and never the photo',
      () async {
        final sara = await seedPerson(db);
        final media = await seedMedia(db);
        final f = await seedFace(db, mediaId: media, personId: sara, seed: 1);
        final path = await files.writeFaceCrop(
          f,
          Uint8List.fromList([1, 2, 3]),
        );
        await (db.update(db.faces)..where((x) => x.id.equals(f))).write(
          FacesCompanion(cropPath: Value(path)),
        );
        await repo.setAvatar(sara, f);
        final withFace = await seedBody(db, mediaId: media, faceId: f);
        await index.addAll([(f, unitVec(1))]);

        await repo.deleteFaces([f]);

        expect(await db.select(db.faces).get(), isEmpty);
        expect(files.resolve(path).existsSync(), isFalse);
        expect(
          await db
              .select(db.mediaDetections)
              .get()
              .then((d) => d.where((x) => x.kind == 'f')),
          isEmpty,
        );
        expect((await person(sara))!.avatarFaceId, isNull);
        expect(
          (await body(withFace)).faceId,
          isNull,
          reason: 'the body stays, it just has no face now',
        );
        expect(await index.size(), 0);
        expect(await db.select(db.media).get(), hasLength(1));
      },
    );

    test('unsorted faces and their count follow what is assigned', () async {
      final sara = await seedPerson(db);
      final a = await seedFace(db, seed: 1, quality: 0.4);
      final b = await seedFace(db, seed: 2, quality: 0.9);
      await seedFace(db, personId: sara, seed: 3);
      final unsorted = await repo.watchFaces(null).first;
      expect(unsorted.map((f) => f.id), [b, a], reason: 'best quality first');
      expect(await repo.watchUnsortedCount().first, 2);
      await repo.assignFaces([a], sara);
      expect(await repo.watchUnsortedCount().first, 1);
      expect((await repo.watchFaces(sara).first).length, 2);
    });

    test(
      'dismissing hides faces from group suggestions without sorting them',
      () async {
        final a = await seedFace(db, seed: 1);
        await repo.dismissFaces([a]);
        final f = await face(a);
        expect((f.reviewDismissed, f.personId), (true, null));
      },
    );
  });

  group('merging', () {
    test(
      'everything of the source moves to the target, and the source is gone',
      () async {
        final target = await seedPerson(db, name: null);
        final source = await seedPerson(db, name: 'Sara');
        final third = await seedPerson(db, name: 'Third');
        final fa = await seedFace(db, personId: source, seed: 1);
        final fb = await seedFace(db, personId: target, seed: 2);
        final stray = await seedFace(
          db,
          seed: 3,
        ); // was rejected from the source
        await repo.setAvatar(source, fa);
        final linked = await seedBody(
          db,
          personId: source,
          linkMethod: 'manual',
        );
        await db
            .into(db.faceRejections)
            .insert(
              FaceRejectionsCompanion.insert(faceId: stray, personId: source),
            );
        await db
            .into(db.bodyRejections)
            .insert(
              BodyRejectionsCompanion.insert(bodyId: linked, personId: source),
            );
        await db
            .into(db.reviewMatches)
            .insert(
              ReviewMatchesCompanion.insert(
                faceId: Value(stray),
                personId: source,
                score: 0.5,
                margin: 0.1,
                decision: 'suggest',
              ),
            );
        await repo.markDistinct(
          source,
          third,
        ); // "Sara is not Third" must still hold for the merged person

        await repo.mergePeople(sourceId: source, targetId: target);

        expect(await person(source), isNull);
        final merged = (await person(target))!;
        expect(
          merged.name,
          'Sara',
          reason: 'an unnamed target takes the source name',
        );
        expect(merged.avatarFaceId, fa, reason: 'and its cover');
        expect((await face(fa)).personId, target);
        expect((await face(fb)).personId, target);
        expect((await body(linked)).personId, target);
        expect(
          (await db.select(db.faceRejections).get()).map(
            (r) => (r.faceId, r.personId),
          ),
          [(stray, target)],
          reason: '"not Sara" is now "not this person"',
        );
        expect(
          (await db.select(db.bodyRejections).get()).map((r) => r.personId),
          isEmpty,
          reason: 'the merged body is explicitly assigned to the kept person',
        );
        expect(
          (await db.select(db.reviewMatches).get()).map((m) => m.personId),
          isEmpty,
          reason:
              'a rejected match must not return after merging its suggested person',
        );
        final distinct = await db.select(db.personDistinct).get();
        expect(distinct.map((d) => (d.personA, d.personB)), [(target, third)]);
      },
    );

    test(
      'the target keeps its own name and cover; merging a person into itself does nothing',
      () async {
        final target = await seedPerson(db, name: 'Keep');
        final source = await seedPerson(db, name: 'Drop');
        final mine = await seedFace(db, personId: target, seed: 1);
        await repo.setAvatar(target, mine);
        await seedFace(db, personId: source, seed: 2);
        await repo.mergePeople(sourceId: target, targetId: target);
        expect(await person(target), isNotNull);
        await repo.mergePeople(sourceId: source, targetId: target);
        final merged = (await person(target))!;
        expect((merged.name, merged.avatarFaceId), ('Keep', mine));
        expect(
          (await db.select(db.faces).get()).every((f) => f.personId == target),
          isTrue,
        );
      },
    );

    test('merging with a person that does not exist changes nothing', () async {
      final a = await seedPerson(db, name: 'A');
      await repo.mergePeople(sourceId: a, targetId: 999);
      expect(await person(a), isNotNull);
    });

    test(
      'a pair marked different is remembered in either order and removed from the duplicate suggestions',
      () async {
        final a = await seedPerson(db), b = await seedPerson(db);
        await db
            .into(db.reviewDuplicates)
            .insert(
              ReviewDuplicatesCompanion.insert(
                personA: a,
                personB: b,
                score: 0.6,
              ),
            );
        await repo.markDistinct(b, a);
        expect(await repo.areDistinct(a, b), isTrue);
        expect(await repo.areDistinct(b, a), isTrue);
        expect(await db.select(db.reviewDuplicates).get(), isEmpty);
        await repo.markDistinct(a, b); // twice is fine
        expect((await db.select(db.personDistinct).get()).length, 1);
        await repo.markDistinct(a, a);
        expect((await db.select(db.personDistinct).get()).length, 1);
      },
    );
  });

  group('bodies', () {
    test(
      'a body belongs to its face\'s person, else to the person it was linked to',
      () async {
        final sara = await seedPerson(db), omar = await seedPerson(db);
        final faceId = await seedFace(db, personId: sara, seed: 1);
        final viaFace = await seedBody(
          db,
          faceId: faceId,
          personId: omar,
          linkMethod: 'manual',
        ); // the face wins
        final viaLink = await seedBody(
          db,
          personId: sara,
          linkMethod: 'appearance',
          linkConfidence: 0.9,
        );
        final nobody = await seedBody(db);
        final bodies = await repo.watchBodies(sara).first;
        expect(bodies.map((b) => b.id).toSet(), {viaFace, viaLink});
        expect(bodies.firstWhere((b) => b.id == viaFace).personId, sara);
        expect(nobody, isNonZero);
        expect(
          await repo.watchBodies(omar).first,
          isEmpty,
          reason: 'its face says it is Sara',
        );
      },
    );

    test(
      'linking by hand is a manual link that outfit matching never overwrites',
      () async {
        final sara = await seedPerson(db);
        final b = await seedBody(db);
        await db
            .into(db.reviewBodyLinks)
            .insert(
              ReviewBodyLinksCompanion.insert(
                bodyId: Value(b),
                personId: sara,
                method: 'appearance',
                confidence: 0.8,
              ),
            );
        await repo.linkBody(b, sara);
        final row = await body(b);
        expect(
          (row.personId, row.linkMethod, row.linkConfidence),
          (sara, 'manual', null),
        );
        expect(await db.select(db.reviewBodyLinks).get(), isEmpty);
      },
    );

    test(
      '"not this person" on a linked body unlinks it for good; on a body with a face it detaches the face',
      () async {
        final sara = await seedPerson(db);
        final faceId = await seedFace(db, personId: sara, seed: 1);
        final linked = await seedBody(
          db,
          personId: sara,
          linkMethod: 'appearance',
          linkConfidence: 0.9,
        );
        final withFace = await seedBody(db, faceId: faceId);

        await repo.rejectBody(linked, personId: sara);
        await repo.rejectBody(withFace);

        final l = await body(linked);
        expect(
          (l.personId, l.linkMethod, l.linkConfidence),
          (null, null, null),
        );
        expect(
          (await body(withFace)).faceId,
          isNull,
          reason: 'the face stays, it just is not this body\'s face',
        );
        expect((await face(faceId)).personId, sara);
        final rejected = await db.select(db.bodyRejections).get();
        expect(rejected.map((r) => (r.bodyId, r.personId)).toSet(), {
          (linked, sara),
          (withFace, sara),
        });
      },
    );
  });
}
