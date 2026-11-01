// Schema v16 (roadmap sections 6.4 / 7.5 / 8.3): the v15 -> v16 upgrade is purely additive and
// idempotent, and the new tables behave (cascade / set null).

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ag_v16_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('v15 -> v16 adds the tables and columns and keeps every row', () async {
    final file = File(p.join(dir.path, 'v15.db'));
    final before = AppDatabase(NativeDatabase(file));
    final media = await before
        .into(before.media)
        .insert(
          MediaCompanion.insert(
            assetId: 'm15',
            kind: 'photo',
            scanStatus: const Value('done'),
          ),
        );
    final person = await before
        .into(before.persons)
        .insert(PersonsCompanion.insert(createdAt: 1));
    final body = await before
        .into(before.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(media),
            personId: Value(person),
            bboxX: 0.1,
            bboxY: 0.1,
            bboxW: 0.5,
            bboxH: 0.8,
            score: 0.9,
            createdAt: 1,
          ),
        );
    await before.close();

    // Make it look like a v15 file. (SQLite cannot drop a column that is a foreign key, so the two
    // *_cluster_id columns stay: the upgrade must tolerate columns that already exist.)
    final legacy = raw.sqlite3.open(file.path);
    legacy.execute('''
      DROP TABLE sensitive_regions; DROP TABLE body_outfit_matches; DROP TABLE body_pose_matches;
      DROP TABLE outfit_categories; DROP TABLE pose_categories; DROP TABLE body_pose_features;
      DROP TABLE body_marks;
      ALTER TABLE media DROP COLUMN sensitive_override;
      ALTER TABLE media DROP COLUMN is_sensitive;
      ALTER TABLE media DROP COLUMN sensitive_version;
      ALTER TABLE media DROP COLUMN body_embedding_version;
      ALTER TABLE bodies DROP COLUMN chest_embedding;
      ALTER TABLE bodies DROP COLUMN buttocks_embedding;
      ALTER TABLE bodies DROP COLUMN morphology;
      PRAGMA user_version = 15;
    ''');
    legacy.close();

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
        'body_clusters',
        'body_marks',
        'body_pose_features',
        'pose_categories',
        'outfit_categories',
        'body_pose_matches',
        'body_outfit_matches',
        'sensitive_regions',
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
    expect(
      indexes,
      containsAll([
        'body_clusters_person',
        'body_marks_person',
        'body_pose_matches_cat',
        'body_outfit_matches_cat',
        'sensitive_regions_media',
        'sensitive_regions_body',
      ]),
    );

    final m = await db.select(db.media).getSingle();
    expect((m.assetId, m.scanStatus), ('m15', 'done'));
    expect(
      (m.isSensitive, m.sensitiveOverride, m.sensitiveVersion),
      (false, null, 0),
      reason: 'new columns take their defaults; no rescan is queued',
    );
    final b = await db.select(db.bodies).getSingle();
    expect((b.id, b.personId, b.mediaId), (body, person, media));
    expect(
      (b.chestEmbedding, b.buttocksEmbedding, b.morphology, b.chestClusterId),
      (null, null, null, null),
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      AppDatabase.currentSchemaVersion,
    );
    expect(AppDatabase.currentSchemaVersion, 16);

    // the new tables work with their cascades / set-nulls
    final cluster = await db
        .into(db.bodyClusters)
        .insert(
          BodyClustersCompanion.insert(
            clusterType: 'chest',
            centroidEmbedding: Uint8List(384 * 4),
            personId: Value(person),
            createdAt: 1,
          ),
        );
    await (db.update(db.bodies)..where((x) => x.id.equals(body))).write(
      BodiesCompanion(chestClusterId: Value(cluster)),
    );
    await (db.delete(db.persons)..where((x) => x.id.equals(person))).go();
    expect(
      (await db.select(db.bodyClusters).getSingle()).personId,
      isNull,
      reason: 'deleting a person keeps the clustering work',
    );
    await (db.delete(db.bodyClusters)..where((x) => x.id.equals(cluster))).go();
    expect(
      (await db.select(db.bodies).getSingle()).chestClusterId,
      isNull,
      reason: 'a deleted cluster leaves its bodies',
    );
    await (db.delete(db.bodies)..where((x) => x.id.equals(body))).go();
    expect(await db.select(db.bodyPoseFeatures).get(), isEmpty);
  });

  test('opening an already-v16 file again changes nothing', () async {
    final file = File(p.join(dir.path, 'v16.db'));
    var db = AppDatabase(NativeDatabase(file));
    await db
        .into(db.media)
        .insert(MediaCompanion.insert(assetId: 'x', kind: 'photo'));
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.select(db.media).get(), hasLength(1));
  });
}
