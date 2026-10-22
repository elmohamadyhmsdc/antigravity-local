import 'dart:io';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:antigravity_mobile/domain/jobs/job_progress.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ETA needs a measured speed, running status and valid remaining steps',
    () {
      final progress = JobProgress(
        '{"step":10,"total_steps":100,"seconds_per_step":2.5}',
      );
      expect(progress.remaining('running'), const Duration(seconds: 225));
      for (final status in [
        'paused',
        'queued',
        'uploading',
        'downloading',
        'completed',
        'failed',
      ]) {
        expect(progress.remaining(status), isNull);
      }
      for (final details in [
        'not json',
        '[]',
        '{"step":3,"total_steps":10}',
        '{"step":10,"total_steps":10,"seconds_per_step":2}',
        '{"step":0,"total_steps":10,"seconds_per_step":2}',
        '{"step":3,"total_steps":10,"seconds_per_step":-2}',
      ]) {
        expect(JobProgress(details).remaining('running'), isNull);
      }
    },
  );

  test(
    'job history deduplicates polls, caps storage and cascades on removal',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final dir = Directory.systemTemp.createTempSync('ag_history_');
      addTearDown(() => dir.delete(recursive: true));
      final repo = StudioRepository(db, FileStore(dir));
      await db
          .into(db.jobs)
          .insert(
            JobsCompanion.insert(
              id: 'one',
              serverId: 'pc',
              type: 'train_lora',
              requestJson: '{}',
              targetPath: 'work/input',
              targetSha: 'a' * 64,
              targetSize: 1,
              status: 'queued',
              createdAt: 1,
              updatedAt: 1,
            ),
          );
      for (var i = 0; i < 120; i++) {
        await repo.update(
          'one',
          JobsCompanion(
            status: const Value('running'),
            message: Value('Epoch $i'),
          ),
        );
        await repo.update(
          'one',
          JobsCompanion(
            status: const Value('running'),
            message: Value('Epoch $i'),
          ),
        );
      }
      final events = await repo.watchEvents('one').first;
      expect(events, hasLength(100));
      expect(events.first.message, 'Epoch 119');
      expect(events.last.message, 'Epoch 20');
      await (db.delete(db.jobs)..where((j) => j.id.equals('one'))).go();
      expect(await db.select(db.jobEvents).get(), isEmpty);
    },
  );
}
