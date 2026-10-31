// The sweeper may only remove what nothing refers to: a crop whose face is gone, a half-finished
// download, scratch copies - and never a file some row still needs (a result, a dataset, a LoRA,
// a paused job's staged input) or anything a running scan/job has just written.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/domain/storage/storage_sweeper.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late FileStore files;
  late Directory cache;
  late File dbFile;
  late StorageSweeper sweeper;
  final now = DateTime(2026, 10, 31, 12);
  final old = now.subtract(const Duration(days: 2));

  Future<String> put(String relative, {int size = 10, DateTime? at}) async {
    await files.write(relative, Uint8List(size));
    files.resolve(relative).setLastModifiedSync(at ?? old);
    return relative;
  }

  File scratch(String name, {int size = 5, DateTime? at}) {
    final file = File('${cache.path}/$name')..writeAsBytesSync(Uint8List(size));
    file.setLastModifiedSync(at ?? old);
    return file;
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('ag_sweeper_');
    files = FileStore(Directory('${dir.path}/crops'));
    cache = Directory('${dir.path}/cache')..createSync();
    dbFile = File('${dir.path}/antigravity.db')
      ..writeAsBytesSync(Uint8List(100));
    File('${dir.path}/antigravity.db-wal').writeAsBytesSync(Uint8List(40));
    sweeper = StorageSweeper(
      db: db,
      files: files,
      databaseFile: dbFile,
      tempDirs: [
        cache,
        cache,
      ], // the same folder twice must not be counted twice
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'removes crops of rows that no longer exist and keeps referenced ones',
    () async {
      final photo = await seedMedia(db, asset: 'a1');
      final kept = await put('faces/1.jpg');
      final faceId = await seedFace(db, mediaId: photo, cropPath: kept);
      final bodyKept = await put('bodies/1.jpg');
      await seedBody(db, mediaId: photo, faceId: faceId, cropPath: bodyKept);
      final orphanFace = await put('faces/99.jpg', size: 30);
      final orphanBody = await put('bodies/99.jpg', size: 20);

      final found = await sweeper.findLeftovers();
      expect(found.orphans, unorderedEquals([orphanFace, orphanBody]));
      expect(found.orphanBytes, 50);
      // looking deletes nothing
      expect(files.resolve(orphanFace).existsSync(), isTrue);

      final result = await sweeper.sweep();
      expect(result.removedFiles, 2);
      expect(result.removedBytes, 50);
      expect(files.resolve(orphanFace).existsSync(), isFalse);
      expect(files.resolve(orphanBody).existsSync(), isFalse);
      expect(files.resolve(kept).existsSync(), isTrue);
      expect(files.resolve(bodyKept).existsSync(), isTrue);
      expect((await sweeper.findLeftovers()).isEmpty, isTrue);
    },
  );

  test(
    'never touches user results, datasets, LoRAs or character samples',
    () async {
      final result = await put('results/j1/out.png');
      final original = await put('results/j1/original.jpg');
      await db
          .into(db.results)
          .insert(
            ResultsCompanion.insert(
              id: 'j1',
              type: 'reface_image',
              path: result,
              originalPath: original,
              mime: 'image/png',
              sizeBytes: 10,
              sha256: 'x',
              createdAt: 1,
            ),
          );
      final item = await put('datasets/d1/a.jpg');
      await db
          .into(db.datasets)
          .insert(
            DatasetsCompanion.insert(id: 'd1', triggerWord: 'w', createdAt: 1),
          );
      await db
          .into(db.datasetItems)
          .insert(
            DatasetItemsCompanion.insert(
              datasetId: 'd1',
              path: item,
              caption: 'c',
            ),
          );
      final lora = await put('loras/l1.safetensors', size: 1000);
      await db
          .into(db.loras)
          .insert(
            LorasCompanion.insert(
              id: 'l1',
              path: lora,
              triggerWord: 'w',
              createdAt: 1,
            ),
          );

      expect((await sweeper.findLeftovers()).isEmpty, isTrue);
      final swept = await sweeper.sweep();
      expect(swept.removedFiles, 0);
      for (final path in [result, original, item, lora]) {
        expect(files.resolve(path).existsSync(), isTrue, reason: path);
      }
    },
  );

  test(
    'keeps the staged inputs of jobs that still exist, sweeps those of removed jobs',
    () async {
      final target = await put('work/j2/target-0.bin');
      final extra = await put('work/j2/refs-0.bin');
      await db
          .into(db.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'j2',
              serverId: 's',
              type: 'reface_image',
              requestJson: '{}',
              targetPath: target,
              targetSha: 'sha',
              targetSize: 10,
              inputFiles: Value(jsonEncode({'sha1': target, 'sha2': extra})),
              status: 'paused',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      final gone = await put('work/j-removed/target-0.bin');
      final export = await put('work/exports/1-2.zip', size: 500);
      final part = await put('results/j3/out.mp4.part', size: 700);

      final found = await sweeper.findLeftovers();
      expect(found.orphans, unorderedEquals([gone, export, part]));
      await sweeper.sweep();
      expect(files.resolve(target).existsSync(), isTrue);
      expect(files.resolve(extra).existsSync(), isTrue);
      expect(files.resolve(gone).existsSync(), isFalse);
      expect(files.resolve(export).existsSync(), isFalse);
      expect(files.resolve(part).existsSync(), isFalse);
      // folders emptied by the sweep are removed too
      expect(Directory('${files.root.path}/results').existsSync(), isFalse);
      expect(Directory('${files.root.path}/work/j2').existsSync(), isTrue);
    },
  );

  test(
    'leaves recent files alone: a scan writing right now is never raced',
    () async {
      final fresh = await put(
        'faces/500.jpg',
        at: now.subtract(const Duration(minutes: 5)),
      );
      final freshScratch = scratch(
        'picked.jpg',
        at: now.subtract(const Duration(minutes: 5)),
      );
      final found = await sweeper.findLeftovers();
      expect(found.isEmpty, isTrue);
      await sweeper.sweep();
      expect(files.resolve(fresh).existsSync(), isTrue);
      expect(freshScratch.existsSync(), isTrue);
    },
  );

  test(
    'sweeps stale scratch entries, but a folder with a recent file stays',
    () async {
      final stale = scratch('reface-1.jpg', size: 7);
      final staleDir = Directory('${cache.path}/backups')..createSync();
      File('${staleDir.path}/library.agbackup')
        ..writeAsBytesSync(Uint8List(300))
        ..setLastModifiedSync(old);
      final activeDir = Directory('${cache.path}/ag_video_x')..createSync();
      File('${activeDir.path}/detections.ndjson')
        ..writeAsBytesSync(Uint8List(50))
        ..setLastModifiedSync(now.subtract(const Duration(minutes: 1)));

      final found = await sweeper.findLeftovers();
      expect(
        found.staleTemp.map(
          (e) => e.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        ),
        unorderedEquals(['reface-1.jpg', 'backups']),
      );
      expect(found.staleTempBytes, 307);

      final result = await sweeper.sweep();
      expect(result.removedFiles, 2);
      expect(result.removedBytes, 307);
      expect(stale.existsSync(), isFalse);
      expect(staleDir.existsSync(), isFalse);
      expect(activeDir.existsSync(), isTrue);
      expect(cache.existsSync(), isTrue);
    },
  );

  test(
    'usage reports folders, database with its journal, and scratch space once',
    () async {
      await put('faces/1.jpg', size: 100);
      await put('bodies/1.jpg', size: 200);
      await put('work/p/1.jpg', size: 400);
      scratch('a.bin', size: 1000);

      final usage = await sweeper.usage();
      expect(usage.folders, {'faces': 100, 'bodies': 200, 'work': 400});
      expect(usage.fileStoreBytes, 700);
      expect(usage.databaseBytes, 140);
      expect(usage.tempBytes, 1000);
      expect(usage.totalBytes, 1840);
    },
  );

  test('an empty library with no folders is a no-op', () async {
    cache.deleteSync();
    final usage = await sweeper.usage();
    expect(usage.totalBytes, 140);
    expect((await sweeper.sweep()).removedFiles, 0);
  });
}
