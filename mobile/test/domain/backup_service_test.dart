// The phone holds the only copy of the library: a backup must round-trip LOSSLESSLY - every row of every
// table, every crop byte, the settings that describe the library - and a damaged backup must never
// touch the library it was meant to replace.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

class Phone {
  Phone(String name) {
    db = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('ag_backup_${name}_');
    files = FileStore(Directory('${dir.path}/crops'));
    settings = AppSettings(db);
    backup = BackupService(
      db: db,
      files: files,
      settings: settings,
      clock: () => DateTime(2026, 10, 11, 21, 30, 5),
    );
  }

  late final AppDatabase db;
  late final Directory dir;
  late final FileStore files;
  late final AppSettings settings;
  late final BackupService backup;

  Future<void> dispose() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }

  Future<int> face({
    int? media,
    int? person,
    int seed = 1,
    double quality = 0.7,
    bool crop = true,
    List<int> cropBytes = const [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9],
  }) async {
    final id = await seedFace(
      db,
      mediaId: media,
      personId: person,
      seed: seed,
      quality: quality,
    );
    if (crop) {
      final path = await files.writeFaceCrop(
        id,
        Uint8List.fromList([...cropBytes, id]),
      );
      await (db.update(db.faces)..where((f) => f.id.equals(id))).write(
        FacesCompanion(cropPath: Value(path)),
      );
    }
    return id;
  }

  /// A library that uses every table and every kind of column (blobs, nulls, reals, JSON text).
  Future<void> populate() async {
    final sara = await seedPerson(db, name: 'Sara', createdAt: 1700000000000);
    final omar = await seedPerson(db, name: null, createdAt: 1700000001000);
    final lina = await seedPerson(
      db,
      name: 'Lina ✨ ليلى',
      createdAt: 1700000002000,
    ); // non-ASCII survives

    final photo1 = await seedMedia(
      db,
      asset: 'content://media/1',
      takenAt: 1690000000000,
      modifiedAt: 1690000000500,
    );
    final photo2 = await seedMedia(
      db,
      asset: 'content://media/2',
      status: 'failed',
    );
    await seedMedia(db, asset: 'content://media/3', status: 'pending');
    await (db.update(db.media)..where((m) => m.id.equals(photo2))).write(
      const MediaCompanion(
        scanError: Value('not a picture'),
        scanAttempts: Value(3),
        scanVersion: Value(1),
      ),
    );

    final f1 = await face(media: photo1, person: sara, seed: 1, quality: 0.91);
    final f2 = await face(media: photo1, person: omar, seed: 2, quality: 0.5);
    final f3 = await face(media: photo2, seed: 3, crop: false); // no crop
    await face(seed: 4, person: lina); // no photo
    await (db.update(db.persons)..where((p) => p.id.equals(sara))).write(
      PersonsCompanion(avatarFaceId: Value(f1)),
    );
    await (db.update(db.faces)..where((f) => f.id.equals(f3))).write(
      const FacesCompanion(
        reviewDismissed: Value(true),
        kps: Value('[[0.1,0.2],[0.3,0.4]]'),
        yaw: Value(-12.5),
      ),
    );

    final b1 = await seedBody(
      db,
      mediaId: photo1,
      faceId: f1,
      appearance: outfit(1),
      frameNumber: 0,
    );
    final b2 = await seedBody(
      db,
      mediaId: photo1,
      personId: sara,
      linkMethod: 'appearance',
      linkConfidence: 0.8765,
      appearance: outfit(2),
      weakFace: unitVec(77),
    );
    final path = await files.writeBodyCrop(
      b2,
      Uint8List.fromList([9, 8, 7, b2]),
    );
    await (db.update(db.bodies)..where((b) => b.id.equals(b2))).write(
      BodiesCompanion(cropPath: Value(path)),
    );
    await seedBody(db, mediaId: photo2, linkMethod: null);

    await db
        .into(db.faceRejections)
        .insert(FaceRejectionsCompanion.insert(faceId: f2, personId: sara));
    await db
        .into(db.bodyRejections)
        .insert(BodyRejectionsCompanion.insert(bodyId: b1, personId: omar));
    await db
        .into(db.personDistinct)
        .insert(PersonDistinctCompanion.insert(personA: sara, personB: omar));
    await db
        .into(db.reviewMatches)
        .insert(
          ReviewMatchesCompanion.insert(
            faceId: Value(f3),
            personId: sara,
            score: 0.41,
            margin: 0.12,
            decision: 'suggest',
          ),
        );
    await db
        .into(db.reviewGroups)
        .insert(
          ReviewGroupsCompanion.insert(
            faceIds: '[$f3]',
            cohesion: 0.5,
            quality: 0.6,
            autoCreate: const Value(true),
          ),
        );
    await db
        .into(db.reviewDuplicates)
        .insert(
          ReviewDuplicatesCompanion.insert(
            personA: sara,
            personB: omar,
            score: 0.55,
          ),
        );
    await db
        .into(db.reviewBodyLinks)
        .insert(
          ReviewBodyLinksCompanion.insert(
            bodyId: Value(b2),
            personId: sara,
            method: 'appearance',
            confidence: 0.7,
          ),
        );

    await settings.setStrictness('strict');
    await settings.setQualityGate(0.55);
    await settings.setAlbumIds(['b-1', 'b-2']);
    await settings.setModelId('buffalo_l@1');
    // things that must NOT travel: this phone's pairing, its running-scan flag, upload bookkeeping
    await settings.setScanActive(true);
    await db.upsertServer(
      ServersCompanion.insert(
        id: 'srv_x',
        name: 'PC',
        host: '10.0.0.2',
        port: 8443,
        fingerprint: 'ab' * 32,
        pairedAt: 5,
      ),
    );
    await db
        .into(db.uploadQueue)
        .insert(
          UploadQueueCompanion.insert(
            sha256: 'a' * 64,
            localPath: '/x',
            sizeBytes: 1,
            createdAt: 1,
          ),
        );
  }

  /// Every backed-up table as plain data (blobs as base64), for exact comparison.
  Future<Map<String, List<Map<String, Object?>>>> dump() async {
    final out = <String, List<Map<String, Object?>>>{};
    for (final table in backupTables) {
      final rows = await db
          .customSelect('SELECT * FROM ${table.name} ORDER BY rowid')
          .get();
      out[table.name] = [
        for (final r in rows)
          {
            for (final e in r.data.entries)
              e.key: e.value is Uint8List
                  ? base64Encode(e.value as Uint8List)
                  : e.value,
          },
      ];
    }
    return out;
  }

  Future<Map<String, String>> crops() async => {
    for (final (relative, file) in await files.allFiles())
      relative: base64Encode(await file.readAsBytes()),
  };
}

void main() {
  late Phone a;
  late Phone b;
  setUp(() {
    a = Phone('a');
    b = Phone('b');
  });
  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test(
    'export -> restore on another phone gives back every row and every crop byte',
    () async {
      await a.populate();
      final beforeDump = await a.dump();
      final beforeCrops = await a.crops();
      expect(beforeDump['faces']!.length, 4);
      expect(beforeCrops.length, 4, reason: '3 face crops + 1 body crop');

      final progress = <String>[];
      final file = await a.backup.export(
        Directory('${a.dir.path}/out'),
        onProgress: (p) => progress.add(p.stage),
      );
      expect(file.path, endsWith('antigravity-20261011-213005.agbackup'));
      expect(progress, containsAll(['database', 'crops']));

      final info = await b.backup.inspect(file);
      expect(
        (info.people, info.faces, info.photos, info.cropCount),
        (3, 4, 3, 4),
      );
      expect(info.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(info.createdAt, isNotNull);

      final restored = await b.backup.restore(file);
      expect(restored.faces, 4);

      expect(
        await b.dump(),
        beforeDump,
        reason: 'lossless: every row of every table',
      );
      expect(
        await b.crops(),
        beforeCrops,
        reason: 'lossless: every crop byte, at the same relative path',
      );

      final settings = await b.settings.load();
      expect(
        (settings.strictness, settings.qualityGate, settings.modelId),
        ('strict', 0.55, 'buffalo_l@1'),
      );
      expect(settings.albumIds, ['b-1', 'b-2']);
      expect(
        settings.scanActive,
        isFalse,
        reason: 'a running-scan flag is about this phone, not the library',
      );
    },
  );

  test(
    'a backup never carries this phone\'s pairing or upload bookkeeping, and restoring never removes them',
    () async {
      await a.populate();
      final file = await a.backup.export(Directory('${a.dir.path}/out'));
      final names = ZipDecoder()
          .decodeBytes(await file.readAsBytes())
          .files
          .map((f) => f.name)
          .toList();
      expect(
        names.where(
          (n) =>
              n.contains('servers') ||
              n.contains('upload') ||
              n.contains('blob'),
        ),
        isEmpty,
      );
      expect(names, contains('manifest.json'));
      expect(
        names
            .where((n) => n.startsWith('db/'))
            .every((n) => n.endsWith('.jsonl')),
        isTrue,
      );

      await b.db.upsertServer(
        ServersCompanion.insert(
          id: 'srv_b',
          name: 'My PC',
          host: '10.0.0.9',
          port: 8443,
          fingerprint: 'cd' * 32,
          pairedAt: 9,
        ),
      );
      await b.backup.restore(file);
      expect(
        (await b.db.latestServer())!.id,
        'srv_b',
        reason: 'the new phone stays paired with its own PC',
      );
    },
  );

  test('restoring replaces whatever the phone had, crops included', () async {
    await a.populate();
    final file = await a.backup.export(Directory('${a.dir.path}/out'));

    final stranger = await seedPerson(b.db, name: 'Only on phone B');
    final strangerFace = await b.face(person: stranger, seed: 900);
    expect(strangerFace, isNonZero);

    await b.backup.restore(file);
    final names = (await b.db.select(b.db.persons).get())
        .map((p) => p.name)
        .toSet();
    expect(names, {'Sara', null, 'Lina ✨ ليلى'});
    expect((await b.db.select(b.db.faces).get()).length, 4);
    expect(
      await b.crops(),
      await a.crops(),
      reason: 'the old crops are gone, the restored ones are in place',
    );
  });

  test(
    'ids keep counting upward after a restore, so new rows never reuse a restored id',
    () async {
      await a.populate();
      final file = await a.backup.export(Directory('${a.dir.path}/out'));
      await b.backup.restore(file);
      final maxFace =
          (await b.db
                  .customSelect('SELECT MAX(id) AS m FROM faces')
                  .getSingle())
              .read<int>('m');
      final next = await seedFace(b.db, seed: 5000);
      expect(next, greaterThan(maxFace));
    },
  );

  test('backup -> restore -> backup -> restore is stable', () async {
    await a.populate();
    final first = await a.backup.export(Directory('${a.dir.path}/one'));
    await b.backup.restore(first);
    final second = await b.backup.export(Directory('${b.dir.path}/two'));
    final c = Phone('c');
    addTearDown(c.dispose);
    await c.backup.restore(second);
    expect(await c.dump(), await a.dump());
    expect(await c.crops(), await a.crops());
  });

  test('an empty library backs up and restores', () async {
    final file = await a.backup.export(Directory('${a.dir.path}/out'));
    await b.populate();
    await b.backup.restore(file);
    expect((await b.db.select(b.db.persons).get()), isEmpty);
    expect((await b.db.select(b.db.faces).get()), isEmpty);
    expect(await b.crops(), isEmpty);
  });

  group('a damaged backup never touches the library', () {
    late File good;
    late Map<String, List<Map<String, Object?>>> libraryBefore;
    late Map<String, String> cropsBefore;

    setUp(() async {
      await a.populate();
      good = await a.backup.export(Directory('${a.dir.path}/out'));
      await b.populate();
      await seedPerson(
        b.db,
        name: 'Only on phone B',
      ); // so "unchanged" cannot be mistaken for "restored"
      libraryBefore = await b.dump();
      cropsBefore = await b.crops();
    });

    Future<File> tampered(
      String name, {
      Uint8List Function(String entry, Uint8List content)? change,
      bool Function(String)? drop,
    }) async {
      final source = ZipDecoder().decodeBytes(await good.readAsBytes());
      final out = Archive();
      for (final f in source.files) {
        if (drop != null && drop(f.name)) continue;
        final content = f.content;
        out.addFile(
          ArchiveFile.bytes(
            f.name,
            change == null ? content : change(f.name, content),
          ),
        );
      }
      final file = File('${a.dir.path}/$name.agbackup');
      await file.writeAsBytes(ZipEncoder().encode(out));
      return file;
    }

    Future<void> expectRefused(File file, Matcher message) async {
      await expectLater(
        b.backup.restore(file),
        throwsA(
          isA<BackupException>().having((e) => e.message, 'message', message),
        ),
      );
      expect(
        await b.dump(),
        libraryBefore,
        reason: 'the library on the phone is exactly as it was',
      );
      expect(await b.crops(), cropsBefore, reason: 'and so are its crops');
      expect(
        Directory('${b.files.root.path}.restoring').existsSync(),
        isFalse,
        reason: 'no half-extracted leftovers',
      );
    }

    test('a file that is not a backup', () async {
      final junk = File('${a.dir.path}/junk.agbackup')
        ..writeAsStringSync('this is not a zip');
      await expectLater(
        b.backup.inspect(junk),
        throwsA(isA<BackupException>()),
      );
      await expectRefused(junk, contains('not an Antigravity backup'));
    });

    test('a zip without a manifest', () async {
      final file = await tampered(
        'nomanifest',
        drop: (n) => n == 'manifest.json',
      );
      await expectRefused(file, contains('not an Antigravity backup'));
    });

    test(
      'a database file that was altered after the backup was made (checksum)',
      () async {
        final file = await tampered(
          'altered',
          change: (name, content) => name.startsWith('db/faces.')
              ? Uint8List.fromList(
                  utf8.encode(
                    utf8.decode(content).replaceFirst('0.91', '0.99'),
                  ),
                )
              : content,
        );
        await expectRefused(file, contains('checksum'));
      },
    );

    test(
      'a backup that lost a database file (the row counts no longer add up)',
      () async {
        final manifestFix = await tampered(
          'incomplete',
          drop: (n) => n.startsWith('db/bodies.'),
          change: (name, content) {
            if (name != 'manifest.json') return content;
            final m = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
            (m['db_files'] as Map<String, dynamic>).removeWhere(
              (k, _) => k.startsWith('db/bodies.'),
            );
            return Uint8List.fromList(utf8.encode(jsonEncode(m)));
          },
        );
        await expectRefused(manifestFix, contains('incomplete'));
      },
    );

    test('a backup from a newer version of the app', () async {
      final file = await tampered(
        'newer',
        change: (name, content) {
          if (name != 'manifest.json') return content;
          final m = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
          m['format_version'] = backupFormatVersion + 1;
          return Uint8List.fromList(utf8.encode(jsonEncode(m)));
        },
      );
      await expectRefused(file, contains('newer version'));
    });

    test('a crop with a path that tries to leave the folder', () async {
      final source = ZipDecoder().decodeBytes(await good.readAsBytes());
      final evil = Archive()
        ..addFile(ArchiveFile.bytes('crops/../evil.jpg', [1, 2, 3]));
      for (final f in source.files) {
        evil.addFile(ArchiveFile.bytes(f.name, f.content));
      }
      final file = File('${a.dir.path}/evil.agbackup')
        ..writeAsBytesSync(ZipEncoder().encode(evil));
      await expectRefused(file, contains('unsafe'));
    });
  });

  test('the last backup time is remembered for the reminder on Home', () async {
    await a.populate();
    expect((await a.settings.load()).lastBackupAt, isNull);
    await a.backup.export(Directory('${a.dir.path}/out'));
    expect(
      (await a.settings.load()).lastBackupAt,
      DateTime(2026, 10, 11, 21, 30, 5),
    );
  });

  test('the settings keys that travel are exactly the library ones', () {
    expect(
      SettingKeys.backedUp,
      containsAll([
        SettingKeys.strictness,
        SettingKeys.qualityGate,
        SettingKeys.albumIds,
        SettingKeys.modelId,
      ]),
    );
    expect(SettingKeys.backedUp, isNot(contains(SettingKeys.scanActive)));
    expect(SettingKeys.backedUp, isNot(contains(SettingKeys.lastBackupAt)));
  });

  test(
    'restore preserves video checkpoints and discards stale PC job references',
    () async {
      final id = await seedMedia(
        a.db,
        asset: 'video',
        kind: 'video',
        status: 'scanning',
      );
      await (a.db.update(a.db.media)..where((m) => m.id.equals(id))).write(
        const MediaCompanion(lastScannedFrame: Value(31)),
      );
      await a.settings.setScanVideos(false);
      await a.settings.setFrameInterval(2);
      await a.db.putSetting('video.job.$id', '{"id":"source-pc-job"}');
      final file = await a.backup.export(Directory('${a.dir.path}/out'));
      await b.db.putSetting('video.job.$id', '{"id":"newer-pc-job"}');
      await b.settings.setScanActive(true);
      await b.backup.restore(file);
      expect((await b.db.select(b.db.media).get()).single.lastScannedFrame, 31);
      expect(await b.db.setting('video.job.$id'), isNull);
      final prefs = await b.settings.load();
      expect(
        (prefs.scanVideos, prefs.frameInterval, prefs.scanActive),
        (false, 2.0, false),
      );
    },
  );
}
