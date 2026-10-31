import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/character_repository.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:antigravity_mobile/domain/scan/character_descriptor.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(
          File(
            '../the app/mobile_api/contract/fixtures/AnalyzeImageResponse.character_no_face.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

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

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late PhotoResultStore store;
  late CharacterRepository characters;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('gallery_character_test_');
    files = FileStore(Directory('${tmp.path}/crops'));
    store = PhotoResultStore(
      db: db,
      files: files,
      index: InMemoryEmbeddingIndex(),
    );
    characters = CharacterRepository(db, files);
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
    'Python character fixture decodes without a face and scores identically',
    () {
      final c = result().characters.single;
      expect(c.descriptor.length, characterDescriptorDim);
      expect(c.modelId, characterModelId);
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
    final old = fixture()..remove('characters');
    expect(AnalyzeImageResponse.fromJson(old).characters, isEmpty);
  });

  test(
    'face-free results persist atomically, rescan is idempotent, photos match',
    () async {
      final first = await media('first');
      expect((await store.store(first, result())).newCharacters, 1);
      expect((await store.store(first, result())).newCharacters, 0);
      expect(
        (await store.store(await media('second'), result())).newCharacters,
        1,
      );
      final samples = await db.select(db.characterSamples).get();
      expect(samples.length, 2);
      expect(samples.map((s) => s.identityId).toSet().length, 1);
      expect(samples.first.descriptor.length, 640);
      expect(await db.select(db.faces).get(), isEmpty);
      expect(await db.select(db.bodies).get(), isEmpty);
      expect((await characters.watch().first).single.samples, 2);
    },
  );

  test(
    'two characters in one frame cannot share an identity even with identical clothes',
    () async {
      final m = await media('twins');
      await store.store(m, result(two: true), frameNumber: 10);
      await store.store(m, result(two: true), frameNumber: 10);
      final samples = await db.select(db.characterSamples).get();
      expect(samples.length, 2);
      expect(samples.map((s) => s.identityId).toSet().length, 2);
    },
  );

  test(
    'separating and naming survive a rescan and ambiguity does not pick a twin',
    () async {
      final a = await media('a'), b = await media('b');
      await store.store(a, result());
      await store.store(b, result());
      final samples = await db.select(db.characterSamples).get();
      await characters.rename(samples.first.identityId, '  Hero  ');
      await characters.separate(samples.last.id);
      await store.store(b, result());
      final after = await db.select(db.characterSamples).get();
      expect(after[0].identityId, isNot(after[1].identityId));
      expect(
        (await db.select(db.characterIdentities).get()).first.name,
        'Hero',
      );
      await store.store(await media('ambiguous'), result());
      expect((await db.select(db.characterIdentities).get()).length, 3);
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
      await store.store(row, result());
      expect(await db.select(db.characterSamples).get(), hasLength(1));

      final sync = await repo.syncAssets([asset.withIllustrated(false)]);
      expect(sync.changed, 1);
      row = (await db.select(db.media).get()).single;
      expect(row.illustrated, isFalse);
      expect(row.scanStatus, 'pending');
      expect(row.scanVersion, 0);
      expect(await db.select(db.characterSamples).get(), isEmpty);
      expect(await db.select(db.characterIdentities).get(), isEmpty);

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
    'backup roundtrip preserves characters, names, descriptors, crops and mode',
    () async {
      final m = await media('art');
      final parsed = fixture();
      (parsed['characters'] as List).single['crop_jpeg'] = base64Encode(
        Uint8List.fromList([1, 2, 3]),
      );
      await store.store(m, AnalyzeImageResponse.fromJson(parsed));
      final sample = (await db.select(db.characterSamples).get()).single;
      await characters.rename(sample.identityId, 'Hero');
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
        final copy =
            (await restored.select(restored.characterSamples).get()).single;
        expect(copy.descriptor, sample.descriptor);
        expect(
          (await restored.select(restored.characterIdentities).get())
              .single
              .name,
          'Hero',
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
