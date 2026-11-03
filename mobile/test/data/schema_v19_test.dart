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
  setUp(() => dir = Directory.systemTemp.createTempSync('ag_v19_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('v18 -> v19 adds tables, columns and preserves existing data', () async {
    final file = File(p.join(dir.path, 'v18.db'));
    final before = AppDatabase(NativeDatabase(file));

    final media = await before
        .into(before.media)
        .insert(
          MediaCompanion.insert(
            assetId: 'm18',
            kind: 'photo',
            scanStatus: const Value('done'),
          ),
        );
    final person = await before
        .into(before.persons)
        .insert(PersonsCompanion.insert(createdAt: 100));

    final face = await before
        .into(before.faces)
        .insert(
          FacesCompanion.insert(
            mediaId: Value(media),
            personId: Value(person),
            modelId: 'test_model',
            embedding: Uint8List(2048),
            qualityScore: 0.95,
            qualityVersion: 1,
            detScore: 0.99,
            facePx: 120,
            sharpness: 50,
            bboxX: 0.2,
            bboxY: 0.2,
            bboxW: 0.3,
            bboxH: 0.3,
            createdAt: 100,
          ),
        );

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
            score: 0.88,
            createdAt: 100,
          ),
        );

    await before.close();

    // Revert file to appear as v18
    final legacy = raw.sqlite3.open(file.path);
    legacy.execute('''
      DROP TABLE IF EXISTS body_overrides;
      DROP TABLE IF EXISTS body_distinct;
      DROP TABLE IF EXISTS face_overrides;
      ALTER TABLE bodies DROP COLUMN ownership;
      ALTER TABLE bodies DROP COLUMN hidden;
      ALTER TABLE faces DROP COLUMN ownership;
      PRAGMA user_version = 18;
    ''');
    legacy.close();

    // Re-open with AppDatabase to trigger upgrade from 18 to 19
    final upgraded = AppDatabase(NativeDatabase(file));
    expect(upgraded.schemaVersion, AppDatabase.currentSchemaVersion);

    // Verify existing rows are intact
    final preservedFace = await (upgraded.select(
      upgraded.faces,
    )..where((f) => f.id.equals(face))).getSingle();
    expect(preservedFace.personId, person);
    expect(preservedFace.ownership, isNull);

    final preservedBody = await (upgraded.select(
      upgraded.bodies,
    )..where((b) => b.id.equals(body))).getSingle();
    expect(preservedBody.personId, person);
    expect(preservedBody.ownership, isNull);
    expect(preservedBody.hidden, isFalse);

    // Verify inserting into new tables
    final fOverrideId = await upgraded
        .into(upgraded.faceOverrides)
        .insert(
          FaceOverridesCompanion.insert(
            assetId: 'm18',
            x: 0.2,
            y: 0.2,
            w: 0.3,
            h: 0.3,
            ownership: const Value('none'),
          ),
        );
    expect(fOverrideId, isPositive);

    final bOverrideId = await upgraded
        .into(upgraded.bodyOverrides)
        .insert(
          BodyOverridesCompanion.insert(
            assetId: 'm18',
            x: 0.1,
            y: 0.1,
            w: 0.5,
            h: 0.8,
            ownership: const Value('none'),
            hidden: const Value(false),
          ),
        );
    expect(bOverrideId, isPositive);

    // Insert second body to test body_distinct
    final body2 = await upgraded
        .into(upgraded.bodies)
        .insert(
          BodiesCompanion.insert(
            mediaId: Value(media),
            bboxX: 0.5,
            bboxY: 0.1,
            bboxW: 0.4,
            bboxH: 0.8,
            score: 0.85,
            createdAt: 101,
          ),
        );

    await upgraded
        .into(upgraded.bodyDistinct)
        .insert(BodyDistinctCompanion.insert(bodyA: body, bodyB: body2));

    final distinctRows = await upgraded.select(upgraded.bodyDistinct).get();
    expect(distinctRows.length, 1);
    expect(distinctRows.first.bodyA, body);
    expect(distinctRows.first.bodyB, body2);

    // Test cascade delete
    await (upgraded.delete(
      upgraded.bodies,
    )..where((b) => b.id.equals(body2))).go();
    final remainingDistinct = await upgraded
        .select(upgraded.bodyDistinct)
        .get();
    expect(remainingDistinct, isEmpty);

    await upgraded.close();
  });
}
