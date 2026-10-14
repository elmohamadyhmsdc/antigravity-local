import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/lora_repository.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:antigravity_mobile/domain/jobs/artifact_store.dart';
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ag_artifacts_');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(Directory('${tmp.path}/files'));
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });
  Future<JobRow> job(String type, {int? person}) async {
    await db
        .into(db.jobs)
        .insert(
          JobsCompanion.insert(
            id: type,
            serverId: 'pc',
            type: type,
            requestJson: jsonEncode({
              'params': {'trigger_word': 'skscharacter', 'repeats': 20},
            }),
            targetPath: 'work/input',
            targetSha: 'a' * 64,
            targetSize: 1,
            status: 'downloading',
            createdAt: 1,
            updatedAt: 1,
          ),
        );
    return (db.select(db.jobs)..where((j) => j.id.equals(type))).getSingle();
  }

  Future<String> bundle(Map<String, List<int>> entries) async {
    final archive = Archive();
    for (final e in entries.entries) {
      archive.addFile(ArchiveFile.bytes(e.key, e.value));
    }
    const path = 'results/bundle.zip';
    await files.write(path, Uint8List.fromList(ZipEncoder().encode(archive)));
    return path;
  }

  test(
    'dataset imports captions, excludes unchecked images on export, and survives backup',
    () async {
      final request = await job('build_lora_dataset');
      final path = await bundle({
        for (var i = 0; i < 5; i++) '20_skscharacter person/$i.png': tinyPng,
        for (var i = 0; i < 5; i++)
          '20_skscharacter person/$i.txt': utf8.encode(
            'skscharacter, photo $i',
          ),
      });
      final commit = await ArtifactStore(db, files).stage(request, path);
      await db.transaction(commit);
      final repository = LoraRepository(db, files);
      final items = await repository.watchItems(request.id).first;
      expect(items.length, 5);
      await repository.updateItem(
        items.first,
        caption: 'skscharacter, edited caption',
        included: false,
      );
      final exported = await repository.exportDataset(request.id);
      final archive = ZipDecoder().decodeBytes(await exported.readAsBytes());
      expect(archive.files.where((e) => e.name.endsWith('.png')).length, 4);
      expect(archive.files.any((e) => e.name.endsWith('/0.png')), isFalse);
      final backup = BackupService(
        db: db,
        files: files,
        settings: AppSettings(db),
      );
      final file = await backup.export(Directory('${tmp.path}/backups'));
      await backup.restore(file);
      expect(
        (await db.select(db.datasets).get()).single.triggerWord,
        'skscharacter',
      );
      expect(
        (await repository.watchItems(request.id).first).first.included,
        isFalse,
      );
    },
  );

  test(
    'malicious archive paths are rejected and never create a dataset',
    () async {
      final request = await job('build_lora_dataset');
      final path = await bundle({'../../escape.png': tinyPng});
      await expectLater(
        ArtifactStore(db, files).stage(request, path),
        throwsFormatException,
      );
      expect(await db.select(db.datasets).get(), isEmpty);
      expect(await File('${tmp.path}/escape.png').exists(), isFalse);
    },
  );

  test(
    'portrait archive creates private image rows without a comparison original',
    () async {
      final request = await job('generate_lora_images');
      final path = await bundle({'one.png': tinyPng, 'two.png': tinyPng});
      final commit = await ArtifactStore(db, files).stage(request, path);
      await db.transaction(commit);
      final images = await db.select(db.results).get();
      expect(images.length, 2);
      expect(images.every((r) => r.path == r.originalPath), isTrue);
    },
  );

  test(
    'a trained model is registered locally and included in a backup',
    () async {
      final request = await job('train_lora');
      await files.write('results/lora.safetensors', tinyPng);
      final commit = await ArtifactStore(
        db,
        files,
      ).stage(request, 'results/lora.safetensors');
      await db.transaction(commit);
      expect(
        (await db.select(db.loras).get()).single.path,
        'results/lora.safetensors',
      );
      final backup = BackupService(
        db: db,
        files: files,
        settings: AppSettings(db),
      );
      final file = await backup.export(Directory('${tmp.path}/backups'));
      await backup.restore(file);
      expect(
        (await db.select(db.loras).get()).single.triggerWord,
        'skscharacter',
      );
      expect(await files.resolve('results/lora.safetensors').exists(), isTrue);
    },
  );

  test('identity anchor is normalized and refuses empty faces', () async {
    final person = await seedPerson(db);
    await seedFace(db, personId: person, seed: 1);
    final faces = await db.select(db.faces).get();
    expect(LoraRepository.anchor(faces).length, 2732);
    expect(() => LoraRepository.anchor([]), throwsFormatException);
  });
}
