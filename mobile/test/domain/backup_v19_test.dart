import 'dart:io';

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
    dir = Directory.systemTemp.createTempSync('ag_bk19_${name}_');
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
}

void main() {
  test('backupTables includes v19 tables in foreign-key order', () {
    final names = [for (final t in backupTables) t.name];
    int at(String n) => names.indexOf(n);

    expect(at('face_overrides'), isNonNegative);
    expect(at('body_overrides'), isNonNegative);
    expect(at('body_distinct'), isNonNegative);

    // body_distinct points at bodies: must come after bodies
    expect(at('bodies'), lessThan(at('body_distinct')));
  });

  test(
    'backup and restore round trip preserves v19 tables and columns',
    () async {
      final phoneA = _Phone('a');
      final phoneB = _Phone('b');

      try {
        final mediaId = await phoneA.db
            .into(phoneA.db.media)
            .insert(
              MediaCompanion.insert(
                assetId: 'backup_v19_media',
                kind: 'photo',
                scanStatus: const Value('done'),
              ),
            );

        final personId = await phoneA.db
            .into(phoneA.db.persons)
            .insert(PersonsCompanion.insert(createdAt: 100));

        final b1 = await phoneA.db
            .into(phoneA.db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(mediaId),
                personId: Value(personId),
                ownership: const Value('none'),
                hidden: const Value(false),
                bboxX: 0.1,
                bboxY: 0.1,
                bboxW: 0.3,
                bboxH: 0.6,
                score: 0.9,
                createdAt: 100,
              ),
            );

        final b2 = await phoneA.db
            .into(phoneA.db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(mediaId),
                ownership: const Value(null),
                hidden: const Value(true),
                bboxX: 0.5,
                bboxY: 0.1,
                bboxW: 0.3,
                bboxH: 0.6,
                score: 0.85,
                createdAt: 101,
              ),
            );

        await phoneA.db
            .into(phoneA.db.bodyDistinct)
            .insert(BodyDistinctCompanion.insert(bodyA: b1, bodyB: b2));

        await phoneA.db
            .into(phoneA.db.bodyOverrides)
            .insert(
              BodyOverridesCompanion.insert(
                assetId: 'backup_v19_media',
                x: 0.1,
                y: 0.1,
                w: 0.3,
                h: 0.6,
                ownership: const Value('none'),
                hidden: const Value(false),
                scope: const Value('single'),
              ),
            );

        await phoneA.db
            .into(phoneA.db.faceOverrides)
            .insert(
              FaceOverridesCompanion.insert(
                assetId: 'backup_v19_media',
                x: 0.2,
                y: 0.2,
                w: 0.2,
                h: 0.2,
                ownership: const Value('none'),
                scope: const Value('track'),
              ),
            );

        // Export from phone A
        final archive = await phoneA.backup.export(
          Directory('${phoneA.dir.path}/out'),
        );
        expect(archive.existsSync(), isTrue);

        // Restore to phone B
        await phoneB.backup.restore(archive);

        // Verify on phone B
        final bodiesB = await phoneB.db.select(phoneB.db.bodies).get();
        expect(bodiesB.length, 2);
        expect(bodiesB.first.ownership, 'none');
        expect(bodiesB.last.hidden, isTrue);

        final distinctB = await phoneB.db.select(phoneB.db.bodyDistinct).get();
        expect(distinctB.length, 1);

        final bOverridesB = await phoneB.db
            .select(phoneB.db.bodyOverrides)
            .get();
        expect(bOverridesB.length, 1);
        expect(bOverridesB.first.ownership, 'none');

        final fOverridesB = await phoneB.db
            .select(phoneB.db.faceOverrides)
            .get();
        expect(fOverridesB.length, 1);
        expect(fOverridesB.first.scope, 'track');
      } finally {
        await phoneA.dispose();
        await phoneB.dispose();
      }
    },
  );
}
