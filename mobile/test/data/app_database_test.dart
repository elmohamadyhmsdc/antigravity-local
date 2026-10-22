import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/db/open_database.dart';
import 'package:antigravity_mobile/data/secrets/secret_store.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

const _keyA =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const _keyB =
    'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210';

Future<void> _addFace(
  AppDatabase db, {
  int? mediaId,
  int? personId,
  double quality = 0.7,
}) {
  return db
      .into(db.faces)
      .insert(
        FacesCompanion.insert(
          mediaId: Value(mediaId),
          personId: Value(personId),
          modelId: 'buffalo_l@1',
          embedding: Uint8List(2048),
          qualityScore: quality,
          qualityVersion: 2,
          detScore: 0.9,
          facePx: 120,
          sharpness: 300,
          bboxX: 0.1,
          bboxY: 0.1,
          bboxW: 0.2,
          bboxH: 0.3,
          createdAt: 1,
        ),
      );
}

Future<int> _addMedia(AppDatabase db, String asset, String kind) {
  return db
      .into(db.media)
      .insert(MediaCompanion.insert(assetId: asset, kind: kind));
}

const _v3Indexes = [
  'media_scan_status',
  'faces_person_id',
  'faces_media_id',
  'bodies_media_id',
  'bodies_person_id',
  'bodies_face_id',
  'face_rejections_person_id',
  'media_detections_media_id',
  'media_detections_ref',
];

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('ag_db_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('encryption', () {
    test(
      'this build is SQLCipher, and the file on disk is not readable as SQLite',
      () async {
        final file = File(p.join(dir.path, 'enc.db'));
        final db = openEncryptedDatabase(file, _keyA);
        await db
            .into(db.persons)
            .insert(
              PersonsCompanion.insert(name: const Value('Sara'), createdAt: 1),
            );
        expect((await db.select(db.persons).get()).single.name, 'Sara');
        await db.close();

        final header = file.readAsBytesSync().take(16).toList();
        expect(
          String.fromCharCodes(header),
          isNot(startsWith('SQLite format 3')),
          reason: 'an unencrypted database starts with the SQLite magic string',
        );
        expect(file.readAsBytesSync().length, greaterThan(0));
        expect(
          String.fromCharCodes(file.readAsBytesSync()).contains('Sara'),
          isFalse,
          reason: 'row contents must not appear in plaintext',
        );
      },
    );

    test('the right key reopens it, a wrong key is refused', () async {
      final file = File(p.join(dir.path, 'enc.db'));
      final db = openEncryptedDatabase(file, _keyA);
      await db
          .into(db.persons)
          .insert(
            PersonsCompanion.insert(name: const Value('Omar'), createdAt: 1),
          );
      await db.close();

      final again = openEncryptedDatabase(file, _keyA);
      expect((await again.select(again.persons).get()).single.name, 'Omar');
      await again.close();

      final wrong = openEncryptedDatabase(file, _keyB);
      await expectLater(wrong.select(wrong.persons).get(), throwsA(anything));
      await wrong.close().catchError((_) {});
    });

    test(
      'a build without SQLCipher is refused instead of storing data unencrypted',
      () {
        expect(
          () => requireSqlCipher(null),
          throwsA(isA<DatabaseEncryptionException>()),
        );
        expect(
          () => requireSqlCipher(''),
          throwsA(isA<DatabaseEncryptionException>()),
        );
        requireSqlCipher('4.6.1 community'); // does not throw

        final db = raw.sqlite3.openInMemory();
        addTearDown(db.close);
        final version = db.select('PRAGMA cipher_version');
        expect(
          version,
          isNotEmpty,
          reason:
              'the bundled SQLite must be the SQLCipher build (pubspec hooks)',
        );
        applyDatabaseKey(db, _keyA); // the real connection passes the check
      },
    );

    test(
      'the database key is created once, is 256-bit hex and is reused',
      () async {
        final secrets = MemorySecretStore();
        final first = await readOrCreateDatabaseKey(secrets);
        expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(await readOrCreateDatabaseKey(secrets), first);
        expect(generateDatabaseKey(), isNot(generateDatabaseKey()));
        secrets.values['db.key'] = 'garbage';
        expect(
          await readOrCreateDatabaseKey(secrets),
          isNot('garbage'),
          reason: 'a corrupt key entry is replaced',
        );
      },
    );
  });

  group('schema', () {
    test(
      'creates every table of schema v${AppDatabase.currentSchemaVersion}',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final names =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'table'",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toSet();
        expect(
          names,
          containsAll([
            'persons',
            'media',
            'faces',
            'bodies',
            'face_rejections',
            'body_rejections',
            'person_distinct',
            'servers',
            'settings',
            'upload_queue',
            'blob_hints',
            'media_detections',
            'review_matches',
            'review_groups',
            'review_duplicates',
            'review_body_links',
          ]),
        );
        final indexes =
            (await db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE type = 'index'",
                    )
                    .get())
                .map((r) => r.read<String>('name'))
                .toSet();
        expect(indexes, containsAll(_v3Indexes));
        final version =
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version');
        expect(version, AppDatabase.currentSchemaVersion);
      },
    );

    test('foreign keys are enforced and cascades work', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await expectLater(
        _addFace(db, mediaId: 999),
        throwsA(anything),
        reason: 'faces.media_id must reference media',
      );

      final media = await _addMedia(db, 'asset-1', 'photo');
      await _addFace(db, mediaId: media);
      expect((await db.select(db.faces).get()).length, 1);
      await (db.delete(db.media)..where((m) => m.id.equals(media))).go();
      expect(
        await db.select(db.faces).get(),
        isEmpty,
        reason: 'deleting a media row deletes its faces',
      );
    });

    test(
      'deleting a person un-assigns their faces instead of deleting them',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final person = await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(createdAt: 1));
        await _addFace(db, personId: person);
        await (db.delete(db.persons)..where((x) => x.id.equals(person))).go();
        final face = (await db.select(db.faces).get()).single;
        expect(face.personId, isNull);
      },
    );

    test('media.asset_id is unique', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _addMedia(db, 'same', 'photo');
      await expectLater(_addMedia(db, 'same', 'video'), throwsA(anything));
    });
  });

  group('library stats', () {
    test(
      'count people, faces, photos, videos and unsorted faces - and update live',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        expect(await db.libraryStats(), const LibraryStats());
        expect((await db.libraryStats()).isEmpty, isTrue);

        final seen = <LibraryStats>[];
        final sub = db.watchLibraryStats().listen(seen.add);
        addTearDown(sub.cancel);

        final photo = await _addMedia(db, 'p1', 'photo');
        await _addMedia(db, 'p2', 'photo');
        await _addMedia(db, 'v1', 'video');
        final sara = await db
            .into(db.persons)
            .insert(PersonsCompanion.insert(createdAt: 1));
        await _addFace(db, mediaId: photo, personId: sara);
        await _addFace(db, mediaId: photo);
        await _addFace(db, mediaId: photo);
        await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                modelId: 'buffalo_l@1',
                embedding: Uint8List(2048),
                qualityScore: 0.5,
                qualityVersion: 2,
                detScore: 0.9,
                facePx: 80,
                sharpness: 100,
                bboxX: 0,
                bboxY: 0,
                bboxW: 0.1,
                bboxH: 0.1,
                reviewDismissed: const Value(true),
                createdAt: 1,
              ),
            );

        final stats = await db.libraryStats();
        expect(
          stats,
          const LibraryStats(
            people: 1,
            faces: 4,
            photos: 2,
            videos: 1,
            unsorted: 2,
          ),
          reason:
              'a dismissed face is not "unsorted"; a face with a person is sorted',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(seen.last, stats, reason: 'the stream follows writes');
      },
    );
  });

  group('servers + settings', () {
    test('the latest paired server wins; settings upsert', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await db.latestServer(), isNull);
      await db.upsertServer(
        ServersCompanion.insert(
          id: 'srv_a',
          name: 'Old PC',
          host: '10.0.0.1',
          port: 8443,
          fingerprint: 'aa' * 32,
          pairedAt: 100,
        ),
      );
      await db.upsertServer(
        ServersCompanion.insert(
          id: 'srv_b',
          name: 'New PC',
          host: '10.0.0.2',
          port: 8443,
          fingerprint: 'bb' * 32,
          pairedAt: 200,
        ),
      );
      expect((await db.latestServer())!.id, 'srv_b');
      await db.deleteServer('srv_b');
      expect((await db.latestServer())!.id, 'srv_a');

      await db.putSetting('strictness', 'balanced');
      await db.putSetting('strictness', 'strict');
      expect(await db.setting('strictness'), 'strict');
      expect(await db.setting('missing'), isNull);
    });
  });

  group('migrations', () {
    // A database exactly as an older build left it: the current schema with everything newer
    // than [version] taken away again (DROP COLUMN needs SQLite 3.35+, which SQLCipher 4 is).
    Future<File> legacyDatabase(int version) async {
      final file = File(p.join(dir.path, 'legacy_v$version.db'));
      final fresh = AppDatabase(NativeDatabase(file));
      await fresh
          .customSelect('SELECT 1')
          .get(); // creates the file with the current schema
      await fresh.close();
      final legacy = raw.sqlite3.open(file.path);
      legacy.execute(
        'DROP TABLE job_events; DROP TABLE identity_set_faces; DROP TABLE identity_sets; DROP TABLE dataset_items; DROP TABLE datasets; DROP TABLE loras; DROP TABLE jobs; DROP TABLE results;',
      );
      legacy.execute('''
        DROP TABLE review_body_links; DROP TABLE review_duplicates; DROP TABLE review_groups;
        DROP TABLE review_matches; DROP TABLE media_detections;
        DROP INDEX media_scan_status; DROP INDEX faces_person_id; DROP INDEX faces_media_id;
        DROP INDEX bodies_media_id; DROP INDEX bodies_person_id; DROP INDEX bodies_face_id;
        DROP INDEX face_rejections_person_id;
        ALTER TABLE media DROP COLUMN taken_at;
        ALTER TABLE media DROP COLUMN scan_attempts;
        ALTER TABLE media DROP COLUMN scan_error;
      ''');
      if (version < 2) {
        legacy.execute('DROP TABLE upload_queue; DROP TABLE blob_hints;');
      }
      legacy.execute('''
        INSERT INTO persons (name, created_at) VALUES ('Lina', 42);
        INSERT INTO settings ("key", value) VALUES ('strictness', 'loose');
        INSERT INTO media (asset_id, kind, modified_at, width, height, scan_status)
          VALUES ('asset-1', 'photo', 7, 1200, 800, 'done');
        INSERT INTO faces (media_id, person_id, model_id, embedding, quality_score, quality_version,
                           det_score, face_px, sharpness, bbox_x, bbox_y, bbox_w, bbox_h, created_at)
          VALUES (1, 1, 'buffalo_l@1', zeroblob(2048), 0.7, 2, 0.9, 100, 200, 0.1, 0.1, 0.2, 0.2, 5);
        PRAGMA user_version = $version;
      ''');
      legacy.close();
      return file;
    }

    for (final from in [1, 2]) {
      test(
        'v$from -> v${AppDatabase.currentSchemaVersion} adds the scan, detection and review tables and keeps every row',
        () async {
          final file = await legacyDatabase(from);
          final db = AppDatabase(NativeDatabase(file));
          addTearDown(db.close);

          final tables =
              (await db
                      .customSelect(
                        "SELECT name FROM sqlite_master WHERE type = 'table'",
                      )
                      .get())
                  .map((r) => r.read<String>('name'))
                  .toSet();
          expect(
            tables,
            containsAll([
              'upload_queue', // v2 step (only runs when coming from v1)
              'blob_hints',
              'media_detections',
              'review_matches',
              'review_groups',
              'review_duplicates',
              'review_body_links',
            ]),
          );
          final indexes =
              (await db
                      .customSelect(
                        "SELECT name FROM sqlite_master WHERE type = 'index'",
                      )
                      .get())
                  .map((r) => r.read<String>('name'))
                  .toSet();
          expect(indexes, containsAll(_v3Indexes));

          // nothing was lost
          expect((await db.select(db.persons).get()).single.name, 'Lina');
          expect(await db.setting('strictness'), 'loose');
          final media = (await db.select(db.media).get()).single;
          expect(
            (media.assetId, media.modifiedAt, media.scanStatus),
            ('asset-1', 7, 'done'),
          );
          expect(
            media.scanAttempts,
            0,
            reason: 'new columns take their defaults',
          );
          expect(media.takenAt, isNull);
          expect(media.scanError, isNull);
          final face = (await db.select(db.faces).get()).single;
          expect((face.mediaId, face.personId), (1, 1));
          expect(
            (await db.customSelect('PRAGMA foreign_key_check').get()),
            isEmpty,
            reason: 'the upgrade leaves no dangling reference',
          );
          expect(
            (await db.customSelect('PRAGMA user_version').getSingle())
                .read<int>('user_version'),
            AppDatabase.currentSchemaVersion,
          );

          // and the new tables work, with their cascades
          await db
              .into(db.mediaDetections)
              .insert(
                MediaDetectionsCompanion.insert(
                  mediaId: 1,
                  kind: 'f',
                  refId: face.id,
                  x: 0.1,
                  y: 0.1,
                  w: 0.2,
                  h: 0.2,
                ),
              );
          await db
              .into(db.reviewMatches)
              .insert(
                ReviewMatchesCompanion.insert(
                  faceId: Value(face.id),
                  personId: 1,
                  score: 0.6,
                  margin: 0.2,
                  decision: 'suggest',
                ),
              );
          await (db.delete(db.media)..where((m) => m.id.equals(1))).go();
          expect(
            await db.select(db.mediaDetections).get(),
            isEmpty,
            reason: 'detections go with their photo',
          );
          expect(
            await db.select(db.reviewMatches).get(),
            isEmpty,
            reason: 'and so does a match of a deleted face',
          );
        },
      );
    }

    test('re-opening an up-to-date database changes nothing', () async {
      final file = File(p.join(dir.path, 'current.db'));
      final first = AppDatabase(NativeDatabase(file));
      await first.putSetting('a', 'b');
      await first.close();
      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      expect(await second.setting('a'), 'b');
    });
    test('v3 -> v4 keeps the library and adds empty Studio tables', () async {
      final file = File(p.join(dir.path, 'v3.db'));
      final before = AppDatabase(NativeDatabase(file));
      await before
          .into(before.persons)
          .insert(
            PersonsCompanion.insert(name: const Value('Sara'), createdAt: 1),
          );
      await before.close();
      final legacy = raw.sqlite3.open(file.path);
      legacy.execute(
        'DROP TABLE job_events; DROP TABLE identity_set_faces; DROP TABLE identity_sets; DROP TABLE dataset_items; DROP TABLE datasets; DROP TABLE loras; DROP TABLE jobs; DROP TABLE results; PRAGMA user_version = 3;',
      );
      legacy.close();
      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      expect((await after.select(after.persons).get()).single.name, 'Sara');
      expect(await after.select(after.jobs).get(), isEmpty);
      expect(await after.select(after.results).get(), isEmpty);
      expect(
        await after.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });
    test(
      'v5 upgrade keeps the library and adds identity sets and local job history',
      () async {
        final file = File(p.join(dir.path, 'v5.db'));
        final before = AppDatabase(NativeDatabase(file));
        final person = await before
            .into(before.persons)
            .insert(
              PersonsCompanion.insert(name: const Value('Sara'), createdAt: 1),
            );
        await _addFace(before, personId: person);
        await before.close();
        final legacy = raw.sqlite3.open(file.path);
        legacy.execute(
          'DROP TABLE job_events; DROP TABLE identity_set_faces; DROP TABLE identity_sets; PRAGMA user_version = 5;',
        );
        legacy.close();
        final after = AppDatabase(NativeDatabase(file));
        addTearDown(after.close);
        expect((await after.select(after.persons).get()).single.name, 'Sara');
        expect((await after.select(after.faces).get()).single.personId, person);
        expect(await after.select(after.identitySets).get(), isEmpty);
        expect(await after.select(after.identitySetFaces).get(), isEmpty);
        expect(await after.select(after.jobEvents).get(), isEmpty);
        expect(
          await after.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
    test('v4 upgrade preserves Studio jobs and adds artifact tables', () async {
      final file = File(p.join(dir.path, 'v4.db'));
      final before = AppDatabase(NativeDatabase(file));
      await before
          .into(before.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'saved-job',
              serverId: 'pc',
              type: 'reface_image_v3',
              requestJson: '{}',
              targetPath: 'work/target.jpg',
              targetSha: 'a' * 64,
              targetSize: 1,
              status: 'paused',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      await before.close();
      final legacy = raw.sqlite3.open(file.path);
      legacy.execute(
        'DROP TABLE job_events; DROP TABLE identity_set_faces; DROP TABLE identity_sets; DROP TABLE dataset_items; DROP TABLE datasets; DROP TABLE loras; ALTER TABLE jobs DROP COLUMN input_files; ALTER TABLE jobs DROP COLUMN details_json; PRAGMA user_version = 4;',
      );
      legacy.close();
      final after = AppDatabase(NativeDatabase(file));
      addTearDown(after.close);
      final job = (await after.select(after.jobs).get()).single;
      expect(job.id, 'saved-job');
      expect(job.inputFiles, '{}');
      expect(job.detailsJson, '{}');
      expect(await after.select(after.datasets).get(), isEmpty);
      expect(await after.select(after.loras).get(), isEmpty);
    });
  });
}
