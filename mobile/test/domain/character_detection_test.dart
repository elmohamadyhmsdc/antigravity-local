import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/action_frames.dart';
import 'package:antigravity_mobile/data/repositories/video_actions_repository.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:antigravity_mobile/domain/scan/character_descriptor.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixtureNamed(String name) =>
    jsonDecode(
          File(
            '../the app/mobile_api/contract/fixtures/AnalyzeImageResponse.$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

Map<String, dynamic> fixture() => fixtureNamed('character_no_face');

/// The old PC answer: one whole-figure box, no face and no body of its own.
AnalyzeImageResponse result({double x = 0, bool two = false}) {
  final json = fixture();
  json['image_w'] = 512;
  final first = Map<String, dynamic>.from(
    (json['characters'] as List).single as Map,
  );
  first['bbox'] = {'x': x, 'y': 0, 'w': 128, 'h': 256};
  json['characters'] = [
    first,
    if (two)
      {
        ...first,
        'bbox': {'x': 256, 'y': 0, 'w': 128, 'h': 256},
      },
  ];
  return AnalyzeImageResponse.fromJson(json);
}

/// The current PC answer: a drawn face with its CCIP embedding, and the body around it.
AnalyzeImageResponse faceAndBody() =>
    AnalyzeImageResponse.fromJson(fixtureNamed('character_face_body'));

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late PhotoResultStore store;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('gallery_character_test_');
    files = FileStore(Directory('${tmp.path}/crops'));
    store = PhotoResultStore(
      db: db,
      files: files,
      index: InMemoryEmbeddingIndex(),
    );
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });
  Future<MediaRow> media(String asset) async {
    final id = await db
        .into(db.media)
        .insert(MediaCompanion.insert(assetId: asset, kind: 'photo'));
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  test(
    'character videos share stable body tracks and real action frame evidence',
    () async {
      final id = await db
          .into(db.media)
          .insert(MediaCompanion.insert(assetId: 'anime-video', kind: 'video'));
      final m = await (db.select(
        db.media,
      )..where((m) => m.id.equals(id))).getSingle();
      for (var i = 0; i < 3; i++) {
        final json = fixtureNamed('character_face_body');
        final body =
            ((json['characters'] as List).single as Map)['body'] as Map;
        body['appearance'] = List.filled(80, 1 / math.sqrt(40));
        body['kpts'] = [
          for (var k = 0; k < 17; k++)
            [100.0 + k * 3, 50.0 + k * 5 + (k == 9 ? i * 20 : 0), .9],
        ];
        await store.store(
          m,
          AnalyzeImageResponse.fromJson(json),
          frameNumber: i,
          timestampMs: i * 1000,
          complete: i == 2,
        );
      }
      final bodies = await (db.select(
        db.bodies,
      )..where((b) => b.mediaId.equals(id))).get();
      expect(bodies, hasLength(1));
      expect(bodies.single.kind, 'character');
      expect(bodies.single.trackId, bodies.single.id);
      final frames = await ActionFrameStore(db).load(m);
      expect(frames.map((f) => f['time']), [0, 1000, 2000]);
      expect(
        frames.every(
          (f) => (f['bodies'] as List).single['body'] == bodies.single.id,
        ),
        isTrue,
      );
      expect(
        frames.first['bodies'][0]['kpts'][9][1],
        isNot(frames.last['bodies'][0]['kpts'][9][1]),
      );
      final actions = VideoActionsRepository(db);
      final action = await actions.saveAction('Wave');
      await actions.addExample(
        actionId: action,
        mediaId: id,
        startMs: 0,
        endMs: 2000,
      );
      expect((await actions.action(action))!.examples.single.frameCount, 3);
      final face = (await db.select(db.faces).get()).single;
      final characters = PeopleRepository(db, files, kind: 'character');
      final identity = await characters.createPerson(
        name: 'Hero',
        faceIds: [face.id],
      );
      final person = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(createdAt: 1, name: const Value('Alex')),
          );
      expect((await characters.identities()).map((p) => p.id).toSet(), {
        identity,
        person,
      });
      expect((await actions.participants(id, 0, 2000)).single.id, identity);
    },
  );

  test(
    'explicit rescan upgrades older character body rows to the shared track',
    () async {
      final id = await db
          .into(db.media)
          .insert(MediaCompanion.insert(assetId: 'old-anime', kind: 'video'));
      final m = await (db.select(
        db.media,
      )..where((m) => m.id.equals(id))).getSingle();
      for (var i = 0; i < 3; i++) {
        await store.store(
          m,
          faceAndBody(),
          frameNumber: i,
          timestampMs: i * 1000,
        );
        await (db.update(db.bodies)..where((b) => b.mediaId.equals(id))).write(
          const BodiesCompanion(trackId: Value(null)),
        );
      }
      expect(
        await (db.select(db.bodies)..where((b) => b.mediaId.equals(id))).get(),
        hasLength(3),
      );
      for (var i = 0; i < 3; i++) {
        await store.store(
          m,
          faceAndBody(),
          frameNumber: i,
          timestampMs: i * 1000,
        );
      }
      final bodies = await (db.select(
        db.bodies,
      )..where((b) => b.mediaId.equals(id))).get();
      expect(bodies.map((b) => b.trackId).toSet(), {bodies.first.id});
      expect(await ActionFrameStore(db).load(m), hasLength(3));
    },
  );

  test(
    'Python character fixture decodes without a face and scores identically',
    () {
      final c = result().characters.single;
      expect(c.descriptor.length, characterDescriptorDim);
      expect(c.modelId, characterModelId);
      expect(c.face, isNull);
      expect(c.body, isNull);
      expect(characterSimilarity(c.descriptor, c.descriptor), closeTo(1, 1e-6));
      final differentHair = [...c.descriptor];
      for (var i = 0; i < 32; i++) {
        differentHair[i] = 0;
      }
      differentHair[14] = 1;
      expect(
        characterSimilarity(c.descriptor, differentHair),
        lessThan(characterAutoMatch),
      );
      expect(result().faces, isEmpty);
    },
  );

  test('a character can carry a face with a CCIP embedding and a body', () {
    final c = faceAndBody().characters.single;
    expect(c.face!.embedding!.length, characterEmbeddingDim);
    expect(c.face!.bbox.w, 48);
    expect(c.body!.appearance!.length, 80);
  });

  test('unknown models and invalid descriptors are refused', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (c) => c['descriptor'] = List.filled(159, .1),
      (c) => c['descriptor'] = List.filled(160, double.nan),
      (c) => c['model_id'] = 'buffalo_l@1',
    ]) {
      final json = fixture();
      mutate((json['characters'] as List).single as Map<String, dynamic>);
      expect(() => AnalyzeImageResponse.fromJson(json), throwsFormatException);
    }
    final wrongEmbedding = fixtureNamed('character_face_body');
    final face =
        ((wrongEmbedding['characters'] as List).single as Map)['face']
            as Map<String, dynamic>;
    face['embedding_model_id'] = 'buffalo_l@1';
    expect(
      () => AnalyzeImageResponse.fromJson(wrongEmbedding),
      throwsFormatException,
    );
    final old = fixture()..remove('characters');
    expect(AnalyzeImageResponse.fromJson(old).characters, isEmpty);
  });

  test(
    'an old whole-figure answer is kept as a body of kind character, rescans change nothing',
    () async {
      final first = await media('first');
      expect((await store.store(first, result())).newCharacters, 1);
      expect((await store.store(first, result())).newCharacters, 0);
      final bodies = await db.select(db.bodies).get();
      expect(bodies, hasLength(1));
      expect(bodies.single.kind, 'character');
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.persons).get(), isEmpty);
    },
  );

  test(
    'a drawn face is stored like a person face: 768-d CCIP, its body linked, detections for both',
    () async {
      await store.store(await media('art'), faceAndBody());
      final face = (await db.select(db.faces).get()).single;
      expect(face.kind, 'character');
      expect(face.modelId, characterEmbeddingModelId);
      expect(face.embedding.length, characterEmbeddingDim * 4);
      expect(face.personId, isNull);
      final body = (await db.select(db.bodies).get()).single;
      expect(body.kind, 'character');
      expect(body.faceId, face.id);
      expect(body.appearance, isNotNull);
      final detections = await db.select(db.mediaDetections).get();
      expect(detections.map((d) => d.kind).toSet(), {'f', 'b'});
    },
  );

  test('rescans and neighbouring frames do not duplicate a drawn face', () async {
    final m = await media('art');
    await store.store(m, faceAndBody());
    await store.store(m, faceAndBody());
    expect(await db.select(db.faces).get(), hasLength(1));
    expect(await db.select(db.bodies).get(), hasLength(1));
    // the same drawing in another photo is a new sighting; another frame of this one is not
    await store.store(await media('other'), faceAndBody());
    expect(await db.select(db.faces).get(), hasLength(2));
    final video = await media('clip');
    await store.store(video, faceAndBody(), frameNumber: 1);
    await store.store(video, faceAndBody(), frameNumber: 40);
    expect(
      await (db.select(
        db.faces,
      )..where((f) => f.mediaId.equals(video.id))).get(),
      hasLength(1),
    );
    expect(
      await (db.select(
        db.mediaDetections,
      )..where((d) => d.mediaId.equals(video.id) & d.kind.equals('f'))).get(),
      hasLength(2),
    );
  });

  test(
    'people and characters never see each other: pools, lists and grouping inputs',
    () async {
      await store.store(await media('art'), faceAndBody());
      final people = PeopleRepository(db, files);
      final characters = PeopleRepository(db, files, kind: 'character');
      expect(await people.watchUnsortedCount().first, 0);
      expect(await characters.watchUnsortedCount().first, 1);
      expect(await GroupingInputs(db).pending(), isEmpty);
      final pending = await GroupingInputs(db, kind: 'character').pending();
      expect(pending.single.embedding.length, characterEmbeddingDim);

      final id = await characters.createPerson(
        name: 'Hero',
        faceIds: [pending.single.id],
      );
      expect(await people.people(), isEmpty);
      final listed = await characters.people();
      expect((listed.single.id, listed.single.kind), (id, 'character'));
      expect(await characters.watchUnsortedCount().first, 0);
      final models = await GroupingInputs(db, kind: 'character').models();
      expect(models.single.proto.length, characterEmbeddingDim);
      expect(await GroupingInputs(db).models(), isEmpty);
    },
  );

  test(
    'the grouping plan creates a character, not a person, for characters',
    () async {
      final m = await media('art');
      await store.store(m, faceAndBody());
      await store.store(await media('other'), faceAndBody());
      final ids = [for (final f in await db.select(db.faces).get()) f.id];
      final plan = GroupingPlanResponse.fromJson({
        'mode': 'apply',
        'assignments': <Object>[],
        'groups': [
          {'face_ids': ids, 'cohesion': .9, 'quality': .9, 'auto_create': true},
        ],
        'duplicates': <Object>[],
        'body_links': <Object>[],
        'unsorted_face_ids': <Object>[],
      });
      final made = await PlanApplier(db, kind: 'character').applyFacePlan(plan);
      expect(made.newPeople, 1);
      final persons = await db.select(db.persons).get();
      expect(persons.single.kind, 'character');
      final request = await GroupingInputs(
        db,
        kind: 'character',
      ).request(mode: 'apply', stages: ['match'], strictness: 'character');
      expect(request.models.single.pid, persons.single.id);
      expect(request.toJson()['strictness'], 'character');
    },
  );

  test(
    'unmarking an anime album drops its characters and rescans it for people',
    () async {
      const asset = AssetInfo(
        id: 'art',
        width: 512,
        height: 512,
        modifiedAt: 1,
        takenAt: 1,
        illustrated: true,
      );
      final repo = LibraryRepository(db);
      await repo.syncAssets([asset]);
      var row = (await db.select(db.media).get()).single;
      expect(row.illustrated, isTrue);
      await store.store(row, faceAndBody());
      expect(await db.select(db.faces).get(), hasLength(1));

      final sync = await repo.syncAssets([asset.withIllustrated(false)]);
      expect(sync.changed, 1);
      row = (await db.select(db.media).get()).single;
      expect(row.illustrated, isFalse);
      expect(row.scanStatus, 'pending');
      expect(row.scanVersion, 0);
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.bodies).get(), isEmpty);
      expect(await db.select(db.mediaDetections).get(), isEmpty);

      // Marking it again only requeues: nothing about people is deleted.
      expect((await repo.syncAssets([asset])).changed, 1);
      expect((await db.select(db.media).get()).single.illustrated, isTrue);
      expect((await repo.syncAssets([asset])).changed, 0);
    },
  );

  test('marked anime albums are saved per album', () async {
    await AppSettings(db).setCharacterAlbumIds(['b', 'a', 'a']);
    expect((await AppSettings(db).load()).characterAlbumIds, ['a', 'b']);
    expect((await AppSettings(db).load()).scanActive, isFalse);
  });

  test(
    'backup roundtrip preserves characters, their names, faces, bodies and crops',
    () async {
      final parsed = fixtureNamed('character_face_body');
      final c = (parsed['characters'] as List).single as Map<String, dynamic>;
      (c['face'] as Map)['crop_jpeg'] = base64Encode(
        Uint8List.fromList([1, 2, 3]),
      );
      await store.store(
        await media('art'),
        AnalyzeImageResponse.fromJson(parsed),
      );
      final face = (await db.select(db.faces).get()).single;
      await PeopleRepository(
        db,
        files,
        kind: 'character',
      ).createPerson(name: 'Hero', faceIds: [face.id]);
      await AppSettings(db).setCharacterAlbumIds(['anime']);
      final backup = BackupService(
        db: db,
        files: files,
        settings: AppSettings(db),
      );
      final archive = await backup.export(Directory('${tmp.path}/backup'));
      final restored = AppDatabase(NativeDatabase.memory());
      final restoredFiles = FileStore(Directory('${tmp.path}/restored'));
      try {
        await BackupService(
          db: restored,
          files: restoredFiles,
          settings: AppSettings(restored),
        ).restore(archive);
        final copy = (await restored.select(restored.faces).get()).single;
        expect(copy.kind, 'character');
        expect(copy.embedding, face.embedding);
        final person = (await restored.select(restored.persons).get()).single;
        expect((person.kind, person.name), ('character', 'Hero'));
        expect(
          (await restored.select(restored.bodies).get()).single.kind,
          'character',
        );
        expect(await restoredFiles.resolve(copy.cropPath!).readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect((await AppSettings(restored).load()).characterAlbumIds, [
          'anime',
        ]);
      } finally {
        await restored.close();
      }
    },
  );
}
