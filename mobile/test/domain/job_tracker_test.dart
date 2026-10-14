import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/jobs.dart';
import 'package:antigravity_mobile/data/api/studio_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:antigravity_mobile/domain/backup/backup_service.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class FakeStudioApi extends FakeMobileApi implements StudioApi {
  @override
  String get serverId => 'test-pc';
  int offset = 0;
  bool losePost = false, corrupt = false, loseAck = false;
  int creates = 0, deletes = 0;
  String status = 'completed';
  final requests = <String, String>{};
  Future<void> Function()? beforeDelete;
  Future<void> Function()? duringPost;

  StudioJobStatus state(String id) => StudioJobStatus.fromJson({
    'job_id': id,
    'status': status,
    'progress': status == 'completed' ? 1.0 : .4,
    'message': 'Rendering',
  });
  @override
  Future<({bool exists, int offset})> blobOffset(String sha256) async =>
      (exists: offset > 0, offset: offset);
  @override
  Future<int> uploadChunk(
    String sha256,
    Uint8List bytes,
    int start,
    int total,
  ) async => offset = total;
  @override
  Future<StudioJobStatus> createStudioJob(Map<String, dynamic> request) async {
    creates++;
    final id = requests.putIfAbsent(
      request['client_job_id'] as String,
      () => 'studio_${requests.length}',
    );
    await duringPost?.call();
    if (losePost) {
      losePost = false;
      throw ApiException.network('POST response lost');
    }
    return state(id);
  }

  @override
  Future<StudioJobStatus> studioJob(String id) async => state(id);
  @override
  Future<StudioJobStatus> controlStudioJob(
    String id, {
    required bool resume,
  }) async {
    status = resume ? 'running' : 'paused';
    return state(id);
  }

  @override
  Stream<StudioJobStatus> studioEvents(String id) => const Stream.empty();
  @override
  Future<StudioResultFile> studioResult(String id) async =>
      StudioResultFile.fromJson({
        'name': 'result.png',
        'mime': 'image/png',
        'size': tinyPng.length,
        'sha256': sha256.convert(tinyPng).toString(),
      });
  @override
  Future<void> downloadStudioResult(String id, String name, File target) async {
    await target.writeAsBytes(corrupt ? [1, 2, 3] : tinyPng);
  }

  @override
  Future<void> deleteVideoJob(String id) async {
    await beforeDelete?.call();
    deletes++;
    if (loseAck) {
      loseAck = false;
      throw ApiException.network('ACK response lost');
    }
    requests.removeWhere((key, value) => value == id);
  }

  @override
  Future<VideoJobStatus> createVideoJob(Map<String, dynamic> request) =>
      throw UnimplementedError();
  @override
  Future<VideoJobStatus> videoJob(String id) => throw UnimplementedError();
  @override
  Future<VideoJobStatus> controlVideoJob(String id, {required bool resume}) =>
      throw UnimplementedError();
  @override
  Future<VideoResultFile> videoResult(String id) => throw UnimplementedError();
  @override
  Future<void> downloadVideoResult(String id, File target) =>
      throw UnimplementedError();
}

void main() {
  late Directory tmp;
  late AppDatabase db;
  late FileStore files;
  late StudioRepository repository;
  late FakeStudioApi api;
  late JobTracker tracker;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ag_jobs_test_');
    db = AppDatabase(NativeDatabase.memory());
    files = FileStore(Directory('${tmp.path}/private'));
    repository = StudioRepository(db, files);
    api = FakeStudioApi();
    tracker = JobTracker(
      repository: repository,
      api: () => api,
      keepAlive: const NoKeepAlive(),
      interval: const Duration(days: 1),
    );
  });
  tearDown(() async {
    tracker.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<String> enqueue() async {
    final target = File('${tmp.path}/photo.jpg');
    await target.writeAsBytes(tinyPng);
    return repository.enqueue(
      serverId: api.serverId,
      type: 'reface_image_v3',
      params: {'source_faces': []},
      target: target,
      video: false,
    );
  }

  test(
    'lost POST response and app restart reuse the same request; verified result precedes ACK',
    () async {
      final id = await enqueue();
      api.losePost = true;
      await tracker.synchronizeOnce();
      expect((await repository.job(id))!.remoteId, isNull);
      expect(api.requests.length, 1);
      tracker.dispose();
      tracker = JobTracker(
        repository: repository,
        api: () => api,
        keepAlive: const NoKeepAlive(),
      );
      api.beforeDelete = () async {
        expect((await db.select(db.results).get()).single.id, id);
        expect(
          await files
              .resolve((await db.select(db.results).get()).single.path)
              .exists(),
          isTrue,
        );
      };
      await tracker.synchronizeOnce();
      expect(api.creates, 2);
      expect((await repository.job(id))!.acknowledged, isTrue);
      expect((await repository.job(id))!.status, 'completed');
      expect(api.requests, isEmpty);
    },
  );

  test(
    'corrupt result is never ACKed or committed and download can be retried',
    () async {
      final id = await enqueue();
      api.corrupt = true;
      await tracker.synchronizeOnce();
      expect(await db.select(db.results).get(), isEmpty);
      expect(api.deletes, 0);
      expect((await repository.job(id))!.status, 'downloading');
      api.corrupt = false;
      await tracker.synchronizeOnce();
      expect(api.deletes, 1);
      expect((await db.select(db.results).get()).length, 1);
    },
  );

  test(
    'lost ACK response retries cleanup without importing the result twice',
    () async {
      final id = await enqueue();
      api.loseAck = true;
      await tracker.synchronizeOnce();
      expect((await repository.job(id))!.status, 'completed');
      expect((await repository.job(id))!.acknowledged, isFalse);
      await tracker.synchronizeOnce();
      expect(api.deletes, 2);
      expect(api.creates, 1);
      expect((await db.select(db.results).get()).length, 1);
    },
  );

  test(
    'pause while POST is in flight leaves both phone and PC paused',
    () async {
      final id = await enqueue();
      api.status = 'queued';
      api.duringPost = () async {
        await tracker.pause((await repository.job(id))!);
      };
      await tracker.synchronizeOnce();
      expect((await repository.job(id))!.status, 'paused');
      expect(api.status, 'paused');
      expect((await repository.job(id))!.remoteId, isNotNull);
      expect(api.deletes, 0);
    },
  );

  test(
    'backup carries private outputs and originals, excludes live jobs and work inputs',
    () async {
      final id = await enqueue();
      await tracker.synchronizeOnce();
      await enqueue();
      final service = BackupService(
        db: db,
        files: files,
        settings: AppSettings(db),
      );
      final backup = await service.export(Directory('${tmp.path}/backups'));
      expect((await service.inspect(backup)).rows['results'], 1);
      await service.restore(backup);
      expect(await db.select(db.jobs).get(), isEmpty);
      final restored = (await db.select(db.results).get()).single;
      expect(restored.id, id);
      expect(await files.resolve(restored.path).readAsBytes(), tinyPng);
      expect(await files.resolve(restored.originalPath).readAsBytes(), tinyPng);
      expect(
        (await files.allFiles()).any((e) => e.$1.startsWith('work/')),
        isFalse,
      );
    },
  );

  test('unsafe result names and private paths are rejected', () {
    expect(
      () => StudioResultFile.fromJson({
        'name': '../../x',
        'mime': 'image/png',
        'size': 1,
        'sha256': 'a' * 64,
      }),
      throwsFormatException,
    );
    for (final path in [
      '../outside',
      '/outside',
      'C:/outside',
      'faces\\..\\outside',
    ]) {
      expect(() => files.resolve(path), throwsFormatException);
    }
  });
}
