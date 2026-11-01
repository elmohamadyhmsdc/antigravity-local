import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/kind_corrections.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../the app/mobile_api/contract/fixtures/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

/// Two real faces (the first passes the gate, with its body) - a person photo.
AnalyzeImageResponse people() => AnalyzeImageResponse.fromJson(
  fixture('AnalyzeImageResponse.two_faces_one_body'),
);

/// A drawn face (CCIP) with its body, 128 x 256.
AnalyzeImageResponse character() => AnalyzeImageResponse.fromJson(
  fixture('AnalyzeImageResponse.character_face_body'),
);

void main() {
  late AppDatabase db;
  late Directory tmp;
  late PhotoResultStore store;
  late KindCorrections corrections;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('gallery_kind_test_');
    final files = FileStore(Directory('${tmp.path}/crops'));
    final index = InMemoryEmbeddingIndex();
    store = PhotoResultStore(db: db, files: files, index: index);
    corrections = KindCorrections(db, files, index: index);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<MediaRow> media(String asset, {String kind = 'photo'}) async {
    final id = await db
        .into(db.media)
        .insert(MediaCompanion.insert(assetId: asset, kind: kind));
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  Future<MediaRow> reload(MediaRow m) =>
      (db.select(db.media)..where((r) => r.id.equals(m.id))).getSingle();

  Future<List<FaceRow>> faces([String? kind]) =>
      (db.select(db.faces)..where(
            (f) => kind == null ? const Constant(true) : f.kind.equals(kind),
          ))
          .get();

  Future<List<BodyRow>> bodies([String? kind]) =>
      (db.select(db.bodies)..where(
            (b) => kind == null ? const Constant(true) : b.kind.equals(kind),
          ))
          .get();

  test('options carry the corrections exactly as the contract fixture', () {
    expect(
      const AnalyzeOptions(
        detectCharacters: true,
        returnOutlines: false,
        facelessCharacters: false,
        forceKind: 'person',
        kindOverrides: [
          KindOverrideDto(
            kind: 'character',
            part: 'face',
            box: (x: 0.25, y: 0.1, w: 0.2, h: 0.15),
          ),
          KindOverrideDto(
            kind: 'person',
            part: 'body',
            box: (x: 0.0, y: 0.0, w: 0.5, h: 1.0),
            timestampMs: 2000,
          ),
        ],
      ).toJson(),
      fixture('AnalyzeImageOptions.kind_corrections'),
    );
    final json = fixture('AnalyzeImageResponse.two_faces_one_body');
    (json['faces'] as List).first['forced'] = true;
    final parsed = AnalyzeImageResponse.fromJson(json);
    expect(parsed.faces.first.forced, isTrue);
    expect(parsed.faces.last.forced, isFalse);
  });

  test(
    'a person face moved to Characters takes its body, is remembered and rescanned',
    () async {
      final m = await media('a');
      await store.store(m, people());
      final face = (await faces(
        'person',
      )).firstWhere((f) => f.cropPath != null || f.qualityScore > 0);
      expect(await bodies('person'), hasLength(1));

      final files = await corrections.moveDetections(
        faceIds: [face.id],
        toKind: 'character',
      );
      expect(files, 1);
      expect(await faces('person'), isEmpty);
      expect(await bodies('person'), isEmpty);
      expect(
        await (db.select(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(m.id))).get(),
        isEmpty,
      );
      final row = await reload(m);
      expect(row.scanStatus, 'pending');
      expect(row.scanVersion, 0);

      final set = await KindOverrideStore(db).forAsset('a');
      expect(set.forceKind, isNull);
      final sent = set.dtos();
      expect({for (final o in sent) o.part}, {'face', 'body'});
      expect(sent.every((o) => o.kind == 'character'), isTrue);
      final faceBox = sent.firstWhere((o) => o.part == 'face').box;
      expect(faceBox.x, closeTo(412.5 / 1280, 1e-6));
      expect(faceBox.w, closeTo(176 / 1280, 1e-6));

      // Correcting the same detection again replaces its correction, it does not pile up.
      await store.store(await reload(m), people());
      final again = (await faces('person')).single;
      await corrections.moveDetections(faceIds: [again.id], toKind: 'person');
      final rows = await db.select(db.kindOverrides).get();
      expect(rows.where((o) => o.part == 'face'), hasLength(1));
      expect(rows.where((o) => o.part == 'body'), hasLength(1));
      expect(rows.every((o) => o.kind == 'person'), isTrue);
      // A different face gets its own.
      await store.store(await reload(m), character());
      final drawn = (await faces('character')).single;
      await corrections.moveDetections(faceIds: [drawn.id], toKind: 'person');
      expect(
        (await db.select(db.kindOverrides).get()).where(
          (o) => o.part == 'face',
        ),
        hasLength(2),
      );
    },
  );

  test('a whole person becomes a character with the same name', () async {
    final m = await media('b');
    await store.store(m, people());
    final ali = await db
        .into(db.persons)
        .insert(
          PersonsCompanion.insert(
            name: const Value('Ali'),
            favorite: const Value(true),
            createdAt: 1,
          ),
        );
    await db.customUpdate(
      'UPDATE faces SET person_id = ?',
      variables: [Variable.withInt(ali)],
    );

    final moved = await corrections.movePerson(ali);
    expect(moved.files, 1);
    final target = await (db.select(
      db.persons,
    )..where((p) => p.id.equals(moved.id!))).getSingle();
    expect(target.kind, 'character');
    expect(target.name, 'Ali');
    expect(target.favorite, isTrue);
    expect(
      await (db.select(db.persons)..where((p) => p.id.equals(ali))).get(),
      isEmpty,
    );
    final overrides = await db.select(db.kindOverrides).get();
    expect(overrides, isNotEmpty);
    expect(overrides.every((o) => o.targetPersonId == moved.id), isTrue);
  });

  test(
    'what a rescan finds at a moved detection joins its target, only once',
    () async {
      final m = await media('c');
      final target = await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(
              name: const Value('Rei'),
              kind: const Value('character'),
              createdAt: 1,
            ),
          );
      // The character fixture's face is at (40, 10, 48, 62) in a 128 x 256 picture.
      await db
          .into(db.kindOverrides)
          .insert(
            KindOverridesCompanion.insert(
              assetId: 'c',
              kind: 'character',
              part: const Value('face'),
              x: const Value(40 / 128),
              y: const Value(10 / 256),
              w: const Value(48 / 128),
              h: const Value(62 / 256),
              targetPersonId: Value(target),
              createdAt: 1,
            ),
          );
      await store.store(m, character());
      final face = (await faces('character')).single;
      expect(face.personId, target);
      final o = (await db.select(db.kindOverrides).get()).single;
      expect(o.targetPersonId, isNull);
      expect(o.kind, 'character'); // the correction itself stays

      // The user later takes the face out by hand: a rescan does not put it back.
      await db.customUpdate('UPDATE faces SET person_id = NULL');
      await store.store(await reload(m), character());
      expect((await faces('character')).single.personId, isNull);
    },
  );

  test('a video correction is sent for frames near its time only', () async {
    final m = await media('v', kind: 'video');
    await db
        .into(db.kindOverrides)
        .insert(
          KindOverridesCompanion.insert(
            assetId: m.assetId,
            kind: 'person',
            part: const Value('body'),
            x: const Value(0),
            y: const Value(0),
            w: const Value(.5),
            h: const Value(1),
            timestampMs: const Value(4000),
            createdAt: 1,
          ),
        );
    final set = await KindOverrideStore(db).forAsset('v');
    expect(set.dtos(timestampMs: 4400), hasLength(1));
    expect(set.dtos(timestampMs: 5000), isEmpty);
    expect(set.dtos(), hasLength(1)); // the PC job filters per frame itself
  });

  test('a whole file can be people, characters, or automatic again', () async {
    final m = await media('d');
    await store.store(m, people());
    await store.store(await reload(m), character());
    expect(await faces('character'), hasLength(1));

    await corrections.setMediaKind(m.id, 'person');
    expect(await corrections.mediaKind(m.id), 'person');
    expect(await faces('character'), isEmpty);
    expect(await bodies('character'), isEmpty);
    expect(await faces('person'), isNotEmpty); // the right kind stays
    expect((await reload(m)).scanStatus, 'pending');
    expect((await KindOverrideStore(db).forAsset('d')).forceKind, 'person');

    await corrections.setMediaKind(m.id, 'character');
    expect(await corrections.mediaKind(m.id), 'character');
    expect(await faces('person'), isEmpty);
    expect(
      (await db.select(db.kindOverrides).get()).where((o) => o.part == null),
      hasLength(1),
    );

    await store.store(await reload(m), character());
    await corrections.setMediaKind(m.id, null);
    expect(await corrections.mediaKind(m.id), isNull);
    expect(await faces(), isEmpty);
    expect(await db.select(db.kindOverrides).get(), isEmpty);
  });

  test('a character body keeps its extent like a person body', () async {
    final m = await media('e');
    await store.store(m, character());
    expect((await bodies('character')).single.extent, 'upper');
  });
}
