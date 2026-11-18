import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/face_refresh.dart';
import 'package:antigravity_mobile/data/repositories/identity_rescan.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:antigravity_mobile/domain/identity/doubt_audit.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late InMemoryEmbeddingIndex index;
  late PhotoResultStore store;
  late PeopleRepository people;
  late IdentityRescan rescan;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_identity_rescan_');
    final files = FileStore(tmp);
    index = InMemoryEmbeddingIndex();
    store = PhotoResultStore(db: db, files: files, index: index);
    people = PeopleRepository(db, files, index: index);
    rescan = IdentityRescan(db);
  });
  tearDown(() async {
    await index.dispose();
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  test('face refresh updates the existing measurement and keeps manual face and body data', () async {
    final mediaId = await seedMedia(db);
    final personId = await seedPerson(db, name: 'Sara');
    final faceId = await seedFace(
      db, personId: personId, mediaId: mediaId, x: .1, y: .125, w: .2, h: .3,
    );
    await people.confirmFaces([faceId], personId);
    final bodyId = await seedBody(
      db, mediaId: mediaId, personId: personId, faceId: faceId, linkMethod: 'manual',
    );
    await (db.update(db.mediaDetections)..where(
      (d) => d.kind.equals('f') & d.refId.equals(faceId),
    )).write(const MediaDetectionsCompanion(outline: Value('existing outline')));
    await index.addAll([(faceId, unitVec(1))]);
    final media = (await LibraryRepository(db).mediaById(mediaId))!;
    final bodyQuery = db.select(db.bodies)..where((b) => b.id.equals(bodyId));
    final body = await bodyQuery.getSingle();
    final refresh = FaceRefresh(db);
    await refresh.request();
    await refresh.activate();
    final grouping = GroupingInputs(db);
    expect(dot((await grouping.models()).single.proto, unitVec(1)), closeTo(1, .001));
    await store.store(
      media,
      analysis(faces: [faceJson(unitVec(57), quality: .65)], bodies: [bodyJson()]),
      facesOnly: true,
    );
    final row = await db.select(db.faces).getSingle();
    expect(row.id, faceId);
    expect(row.personId, personId);
    expect(row.embedding, embeddingToBlob(unitVec(57)));
    expect(dot((await grouping.models()).single.proto, unitVec(57)), closeTo(1, .001));
    expect(await index.size(), 1);
    expect((await db.select(db.faceConfirmations).getSingle()).faceId, faceId);
    expect(await bodyQuery.getSingle(), body);
    expect(await db.select(db.bodies).get(), hasLength(1));
    expect(await LibraryRepository(db).mediaById(mediaId), media);
    final detection = await (db.select(db.mediaDetections)..where(
      (d) => d.kind.equals('f') & d.refId.equals(faceId),
    )).getSingle();
    expect(detection.outline, 'existing outline');
    expect(await refresh.finished(mediaId), isTrue);
    expect(await db.setting('${FaceRefresh.evidencePrefix}$faceId'), isNotNull);
  });

  test('face refresh stores character faces and honors deletion decisions', () async {
    final mediaId = await seedMedia(db);
    final media = (await LibraryRepository(db).mediaById(mediaId))!;
    final result = AnalyzeImageResponse.fromJson(
      fixture('AnalyzeImageResponse.character_face_body'),
    );
    await store.store(media, result, facesOnly: true);
    final row = await db.select(db.faces).getSingle();
    expect(row.kind, 'character');
    expect(await db.select(db.bodies).get(), isEmpty);
    final chars = PeopleRepository(db, FileStore(tmp), kind: 'character');
    await chars.deleteFaces([row.id]);
    await store.store(media, result, facesOnly: true);
    expect(await db.select(db.faces).get(), isEmpty);
  });

  test(
    'scope includes aliases, linked bodies and videos without consuming unrelated work',
    () async {
      final p = await seedPerson(db, name: 'Sara');
      final photo = await seedMedia(db);
      final alias = await seedMedia(db, asset: 'copy');
      final video = await seedMedia(db, asset: 'video', kind: 'video');
      final bodyOnly = await seedMedia(db, asset: 'body');
      final unrelated = await seedMedia(
        db,
        asset: 'unrelated',
        status: 'pending',
      );
      final f = await seedFace(db, personId: p, mediaId: photo);
      await seedFace(db, personId: p, mediaId: video);
      await seedBody(db, faceId: f, mediaId: bodyOnly);
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: alias,
              kind: 'f',
              refId: f,
              x: .1,
              y: .1,
              w: .2,
              h: .2,
            ),
          );
      await db.putSetting('video.job.$video', 'old job');
      await db.putSetting('video.local.$video', 'old cursor');
      await (db.update(db.media)..where((m) => m.id.equals(video))).write(
        const MediaCompanion(lastScannedFrame: Value(900)),
      );
      expect(await rescan.enqueue(p), 4);
      final repo = LibraryRepository(db);
      expect(await rescan.personId(), p);
      expect((await repo.scanCounts(identityRescanOnly: true)).pending, 4);
      expect(await rescan.pending(unrelated), isFalse);
      expect((await repo.mediaById(video))!.lastScannedFrame, 0);
      expect(await db.setting('video.job.$video'), isNull);
      expect(await db.setting('video.local.$video'), isNull);
      for (var i = 0; i < 4; i++) {
        final row = (await repo.claimNext(identityRescanOnly: true))!;
        expect(row.id, isNot(unrelated));
        await rescan.finish(row.id);
      }
      expect(await repo.claimNext(identityRescanOnly: true), isNull);
      expect((await repo.mediaById(unrelated))!.scanStatus, 'pending');
    },
  );

  test(
    'library scope is the union of identity media and retains video checkpoints on resume',
    () async {
      final human = await seedPerson(db);
      final character = await seedPerson(db);
      await (db.update(db.persons)..where((p) => p.id.equals(character))).write(
        const PersonsCompanion(kind: Value('character')),
      );
      final shared = await seedMedia(db);
      final alias = await seedMedia(db, asset: 'alias');
      final video = await seedMedia(db, asset: 'video', kind: 'video');
      final unrelated = await seedMedia(
        db,
        asset: 'unrelated',
        status: 'pending',
      );
      final face = await seedFace(db, personId: human, mediaId: shared);
      await seedFace(db, personId: character, mediaId: shared, seed: 2);
      await seedBody(db, faceId: face, mediaId: video);
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: alias,
              kind: 'f',
              refId: face,
              x: .1,
              y: .1,
              w: .2,
              h: .2,
            ),
          );
      final videoRow = db.update(db.media)..where((m) => m.id.equals(video));
      await videoRow.write(const MediaCompanion(lastScannedFrame: Value(900)));
      await db.putSetting('video.job.$video', 'old');
      await rescan.queueLibrary();
      await rescan.queueLibrary();
      expect(await rescan.hasQueued(), isTrue);
      expect(await db.setting('video.job.$video'), 'old');
      await rescan.activateNext();
      final repo = LibraryRepository(db);
      expect(await rescan.libraryActive(), isTrue);
      expect((await repo.scanCounts(identityRescanOnly: true)).pending, 3);
      expect(await rescan.pending(alias), isTrue);
      expect(await rescan.pending(unrelated), isFalse);
      expect((await repo.mediaById(video))!.lastScannedFrame, 0);
      expect(await db.setting('video.job.$video'), isNull);

      await rescan.finish(shared);
      await videoRow.write(
        const MediaCompanion(
          scanStatus: Value('failed'),
          lastScannedFrame: Value(240),
        ),
      );
      await db.putSetting('video.job.$video', 'repair checkpoint');
      final resumed = IdentityRescan(db);
      await resumed.queueLibrary();
      await resumed.activateNext();
      await resumed.retryIncomplete();
      expect(await resumed.hasQueued(), isFalse);
      expect(await resumed.libraryCompletedCount(), 1);
      expect(await resumed.pending(shared), isFalse);
      expect(await resumed.pending(video), isTrue);
      expect((await repo.mediaById(video))!.lastScannedFrame, 240);
      expect(await db.setting('video.job.$video'), 'repair checkpoint');
    },
  );

  test(
    'waiting identities survive restart, keep FIFO snapshots and leave the active video alone',
    () async {
      final first = await seedPerson(db);
      final second = await seedPerson(db);
      final third = await seedPerson(db);
      final video = await seedMedia(db, kind: 'video');
      final photo = await seedMedia(db, asset: 'second');
      final last = await seedMedia(db, asset: 'third');
      await seedFace(db, mediaId: video, personId: first);
      final face = await seedFace(db, mediaId: photo, personId: second);
      await seedFace(db, mediaId: last, personId: third);
      await rescan.enqueue(first);
      await (db.update(db.media)..where((m) => m.id.equals(video))).write(
        const MediaCompanion(
          scanStatus: Value('scanning'),
          lastScannedFrame: Value(240),
        ),
      );
      await db.putSetting('video.job.$video', 'running job');
      await db.putSetting('video.local.$video', 'running cursor');
      await rescan.queue(second);
      await rescan.queue(first);
      await rescan.queue(second);
      await rescan.queue(third);
      expect(await rescan.watchQueuedCount().first, 2);
      final repo = LibraryRepository(db);
      expect((await repo.mediaById(video))!.scanStatus, 'scanning');
      expect((await repo.mediaById(video))!.lastScannedFrame, 240);
      expect(await db.setting('video.job.$video'), 'running job');
      expect(await db.setting('video.local.$video'), 'running cursor');
      expect(await rescan.pending(video), isTrue);
      expect((await repo.mediaById(photo))!.scanStatus, 'done');

      // Later ownership changes must not replace the scope saved by the tap.
      await (db.update(db.faces)..where((f) => f.id.equals(face))).write(
        const FacesCompanion(personId: Value(null)),
      );
      final reopened = IdentityRescan(db);
      await reopened.activateNext();
      expect(await reopened.personId(), first);
      await reopened.endSession();
      await reopened.activateNext();
      expect(await reopened.personId(), second);
      expect(await reopened.pending(photo), isTrue);
      expect((await repo.mediaById(photo))!.scanStatus, 'pending');
      expect(await reopened.watchQueuedCount().first, 1);
      await reopened.endSession();
      await reopened.activateNext();
      expect(await reopened.personId(), third);
      expect(await reopened.pending(last), isTrue);
      expect(await reopened.hasQueued(), isFalse);
    },
  );

  test('merging waiting identities retains both saved media scopes', () async {
    final source = await seedPerson(db), target = await seedPerson(db);
    final first = await seedMedia(db);
    final second = await seedMedia(db, asset: 'second');
    await seedFace(db, mediaId: first, personId: source);
    await seedFace(db, mediaId: second, personId: target);
    await rescan.queue(source);
    await rescan.queue(target);
    await people.mergePeople(
      sourceId: source,
      targetId: target,
      allowSharedFrames: true,
    );
    expect(await rescan.watchQueuedCount().first, 1);
    await rescan.activateNext();
    expect(await rescan.personId(), target);
    expect(await rescan.pending(first), isTrue);
    expect(await rescan.pending(second), isTrue);
  });

  test(
    'retry keeps failed video checkpoint; explicit new scan restarts it',
    () async {
      final p = await seedPerson(db);
      final v = await seedMedia(db, kind: 'video');
      await seedFace(db, personId: p, mediaId: v);
      await rescan.enqueue(p);
      await (db.update(db.media)..where((m) => m.id.equals(v))).write(
        const MediaCompanion(
          scanStatus: Value('failed'),
          lastScannedFrame: Value(240),
        ),
      );
      await db.putSetting('video.job.$v', 'resume');
      await rescan.retryIncomplete();
      expect((await LibraryRepository(db).mediaById(v))!.lastScannedFrame, 240);
      expect(await db.setting('video.job.$v'), 'resume');
      await rescan.enqueue(p);
      expect((await LibraryRepository(db).mediaById(v))!.lastScannedFrame, 0);
      expect(await db.setting('video.job.$v'), isNull);
    },
  );

  test(
    'a manual merge retargets an interrupted rescan without losing its file scope',
    () async {
      final source = await seedPerson(db), target = await seedPerson(db);
      final m = await seedMedia(db);
      await seedFace(db, mediaId: m, personId: source);
      await rescan.enqueue(source);
      await people.mergePeople(
        sourceId: source,
        targetId: target,
        allowSharedFrames: true,
      );
      expect(await rescan.personId(), target);
      expect(await rescan.pending(m), isTrue);
    },
  );

  test(
    'cover anchors a two-person mix and clear outliers cannot return to the old identity',
    () async {
      final p = await seedPerson(db, name: 'Sara');
      final cover = await seedFace(db, personId: p, seed: 1);
      final wrong = await seedFace(db, personId: p, seed: 2);
      final body = await seedBody(
        db,
        faceId: wrong,
        personId: p,
        linkMethod: 'weak_face',
      );
      await (db.update(db.persons)..where((row) => row.id.equals(p))).write(
        PersonsCompanion(avatarFaceId: Value(cover)),
      );
      expect((await DoubtAudit(db).run(anchorPersonId: p)).faces, 1);
      expect(await people.regroupDoubtfulFaces(p), 1);
      final rows = await db.select(db.faces).get();
      expect(rows.singleWhere((f) => f.id == cover).personId, p);
      expect(rows.singleWhere((f) => f.id == wrong).personId, isNull);
      expect((await db.select(db.faceRejections).get()).single.personId, p);
      expect(
        (await db.select(db.bodies).get())
            .singleWhere((b) => b.id == body)
            .personId,
        isNull,
      );
      expect((await db.select(db.persons).get()).single.name, 'Sara');
      expect(await people.regroupDoubtfulFaces(p), 0);
    },
  );

  test(
    'confirmed assignments and locked identities survive regrouping',
    () async {
      final p = await seedPerson(db);
      final a = await seedFace(db, personId: p, seed: 1);
      final b = await seedFace(db, personId: p, seed: 2);
      await people.confirmFaces([a, b], p);
      await DoubtAudit(db).run(anchorPersonId: p);
      expect(await people.regroupDoubtfulFaces(p), 0);
      await people.setPersonFlags([p], groupingLocked: true);
      await DoubtAudit(db).run(anchorPersonId: p);
      expect(await people.regroupDoubtfulFaces(p), 0);
      expect(
        (await db.select(db.faces).get()).every((f) => f.personId == p),
        isTrue,
      );
    },
  );

  test(
    'CCIP character faces with zero sharpness are audited and separated',
    () async {
      final p = await seedPerson(db, name: 'Hero');
      await (db.update(db.persons)..where((row) => row.id.equals(p))).write(
        const PersonsCompanion(kind: Value('character')),
      );
      final a = await seedFace(db, personId: p);
      final b = await seedFace(db, personId: p);
      for (final (id, axis) in [(a, 0), (b, 1)]) {
        final vector = Float32List(characterEmbeddingDim)..[axis] = 1;
        await (db.update(db.faces)..where((f) => f.id.equals(id))).write(
          FacesCompanion(
            kind: const Value('character'),
            modelId: const Value(characterEmbeddingModelId),
            embedding: Value(embeddingToBlob(vector)),
            sharpness: const Value(0),
          ),
        );
      }
      await (db.update(db.persons)..where((row) => row.id.equals(p))).write(
        PersonsCompanion(avatarFaceId: Value(a)),
      );
      expect(
        (await DoubtAudit(db, kind: 'character').run(anchorPersonId: p)).faces,
        1,
      );
      expect(
        await PeopleRepository(
          db,
          FileStore(tmp),
          kind: 'character',
        ).regroupDoubtfulFaces(p),
        1,
      );
    },
  );

  for (final protect in [false, true]) {
    test(
      'corrects People to Characters; manual confirmation protected=$protect',
      () async {
        final p = await seedPerson(db, name: 'Old identity');
        final m = await seedMedia(db);
        final json = fixture('AnalyzeImageResponse.character_face_body');
        final char = (json['characters'] as List).single as Map;
        char['score'] = .95;
        final face = char['face'] as Map;
        face['score'] = .95;
        final box = face['bbox'] as Map;
        final w = json['image_w'] as num;
        final h = json['image_h'] as num;
        final old = await seedFace(
          db,
          personId: p,
          mediaId: m,
          x: (box['x'] as num) / w,
          y: (box['y'] as num) / h,
          w: (box['w'] as num) / w,
          h: (box['h'] as num) / h,
        );
        await index.addAll([(old, unitVec(1))]);
        if (protect) await people.confirmFaces([old], p);
        await rescan.enqueue(p);
        await store.store(
          (await LibraryRepository(db).mediaById(m))!,
          AnalyzeImageResponse.fromJson(json),
          repairCharacters: true,
        );
        final faces = await db.select(db.faces).get();
        expect(faces.where((f) => f.kind == 'character'), hasLength(1));
        expect(
          faces.where((f) => f.id == old),
          protect ? hasLength(1) : isEmpty,
        );
        expect(await index.size(), protect ? 1 : 0);
        expect(await rescan.pending(m), isFalse);
      },
    );
  }
}
