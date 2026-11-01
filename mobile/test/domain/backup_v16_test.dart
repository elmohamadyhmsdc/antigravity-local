// Schema v16 tables travel in a backup in foreign-key order: body_clusters BEFORE bodies (bodies point at
// them), categories before their matches, regions after media and bodies. body_pose_features is a cache.

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _Phone {
  _Phone(String name) {
    db = AppDatabase(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('ag_bk16_${name}_');
    backup = BackupService(
      db: db,
      files: FileStore(Directory('${dir.path}/crops')),
      settings: AppSettings(db),
      clock: () => DateTime(2026, 11, 2, 1, 0, 0),
    );
  }

  late final AppDatabase db;
  late final Directory dir;
  late final BackupService backup;

  Future<void> dispose() async {
    await db.close();
    dir.deleteSync(recursive: true);
  }

  Future<List<Map<String, Object?>>> dump(String table) async => [
    for (final row
        in await db.customSelect('SELECT * FROM $table ORDER BY 1').get())
      row.data,
  ];
}

void main() {
  test('backupTables are in foreign-key order for the v16 tables', () {
    final names = [for (final t in backupTables) t.name];
    int at(String n) => names.indexOf(n);
    expect(at('body_clusters'), isNonNegative);
    expect(at('body_clusters'), lessThan(at('bodies')));
    expect(at('persons'), lessThan(at('body_clusters')));
    for (final child in [
      'sensitive_regions',
      'body_marks',
      'pose_categories',
      'outfit_categories',
    ]) {
      expect(at(child), greaterThan(at('bodies')), reason: child);
    }
    expect(at('pose_categories'), lessThan(at('body_pose_matches')));
    expect(at('outfit_categories'), lessThan(at('body_outfit_matches')));
    expect(at('sensitive_regions'), greaterThan(at('media')));
    expect(names, isNot(contains('body_pose_features')), reason: 'a cache');
  });

  test(
    'a v16 library round-trips: clusters, regions, categories, matches, flags',
    () async {
      final a = _Phone('a');
      final b = _Phone('b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      final db = a.db;

      final person = await db
          .into(db.persons)
          .insert(PersonsCompanion.insert(createdAt: 1));
      final media = await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              assetId: 'x1',
              kind: 'photo',
              scanStatus: const Value('done'),
              isSensitive: const Value(true),
              sensitiveVersion: const Value(1),
              sensitiveOverride: const Value('sensitive'),
            ),
          );
      final cluster = await db
          .into(db.bodyClusters)
          .insert(
            BodyClustersCompanion.insert(
              clusterType: 'chest',
              centroidEmbedding: Uint8List.fromList(List.filled(384 * 4, 7)),
              personId: Value(person),
              bodyCount: const Value(1),
              createdAt: 5,
            ),
          );
      final body = await db
          .into(db.bodies)
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
              chestClusterId: Value(cluster),
              chestEmbedding: Value(
                Uint8List.fromList(List.filled(384 * 4, 3)),
              ),
              morphology: const Value('{"scale_source":"kpts"}'),
            ),
          );
      await db
          .into(db.sensitiveRegions)
          .insert(
            SensitiveRegionsCompanion.insert(
              mediaId: media,
              bodyId: Value(body),
              label: 'FEMALE_BREAST_EXPOSED',
              exposed: true,
              score: 0.93,
              x: 0.2,
              y: 0.2,
              w: 0.1,
              h: 0.1,
              modelVersion: 1,
              userState: const Value('confirmed'),
              createdAt: 2,
            ),
          );
      final pose = await db
          .into(db.poseCategories)
          .insert(
            PoseCategoriesCompanion.insert(
              name: 'Arms up',
              exemplarBodyId: Value(body),
              exemplarFeature: Uint8List(136),
              exemplarMask: 0x1ffff,
              exemplarScaleSource: 'torso',
              threshold: 0.8,
              createdAt: 3,
            ),
          );
      final outfit = await db
          .into(db.outfitCategories)
          .insert(
            OutfitCategoriesCompanion.insert(
              name: 'Blue',
              personId: Value(person),
              exemplarAppearance: Uint8List(320),
              threshold: 0.9,
              createdAt: 4,
            ),
          );
      await db
          .into(db.bodyPoseMatches)
          .insert(
            BodyPoseMatchesCompanion.insert(
              bodyId: body,
              categoryId: pose,
              similarity: 0.9,
              state: 'manual',
            ),
          );
      await db
          .into(db.bodyOutfitMatches)
          .insert(
            BodyOutfitMatchesCompanion.insert(
              bodyId: body,
              categoryId: outfit,
              similarity: 0.95,
              state: 'rejected',
            ),
          );
      await db
          .into(db.bodyPoseFeatures)
          .insert(
            BodyPoseFeaturesCompanion.insert(
              bodyId: Value(body),
              version: 1,
              feature: Uint8List(136),
              visibleMask: 3,
              scaleSource: 'torso',
            ),
          );

      await db
          .into(db.equipmentObjects)
          .insert(
            EquipmentObjectsCompanion.insert(
              mediaId: media,
              bodyId: Value(body),
              objectKey: 'test-racket',
              label: 'tennis racket',
              x: .1,
              y: .1,
              w: .2,
              h: .2,
              state: const Value('confirmed'),
            ),
          );
      await db
          .into(db.equipmentPhotos)
          .insert(
            EquipmentPhotosCompanion.insert(mediaId: Value(media), version: 1),
          );
      final file = await a.backup.export(Directory('${a.dir.path}/out'));
      await b.backup.restore(file);

      for (final table in [
        'persons',
        'media',
        'body_clusters',
        'bodies',
        'sensitive_regions',
        'equipment_objects',
        'equipment_photos',
        'pose_categories',
        'outfit_categories',
        'body_pose_matches',
        'body_outfit_matches',
      ]) {
        expect(await b.dump(table), await a.dump(table), reason: table);
      }
      expect(
        await b.dump('body_pose_features'),
        isEmpty,
        reason: 'a cache, rebuilt after a restore',
      );
      final restored = await b.db.select(b.db.media).getSingle();
      expect(
        (restored.isSensitive, restored.sensitiveOverride),
        (true, 'sensitive'),
      );
      expect(
        (await b.db.select(b.db.bodies).getSingle()).chestClusterId,
        cluster,
      );
      expect(
        await b.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}
