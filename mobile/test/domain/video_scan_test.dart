import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/jobs.dart';
import 'package:antigravity_mobile/data/api/video_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/insights_repository.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/scan/video_scan.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

class VideoLibrary extends FakeMediaLibrary implements VideoMediaLibrary {
  VideoLibrary(this.file);
  final File file;
  @override
  Future<File?> videoFile(String assetId) async => file;
}

class VideoPc implements VideoApi {
  @override
  String get serverId => 'pc';
  final uploaded = <int>[];
  final requests = <Map<String, dynamic>>[];
  List<int> result = [];
  bool corrupt = false;
  bool loseCreateResponse = false;
  bool missingJob = false;
  int uploadedOffset = 0;
  int deleted = 0;
  void Function()? afterDownload;
  @override
  Future<({bool exists, int offset})> blobOffset(String sha256) async =>
      (exists: uploadedOffset == 10, offset: uploadedOffset);
  @override
  Future<int> uploadChunk(
    String sha256,
    Uint8List bytes,
    int offset,
    int total,
  ) async {
    uploaded.add(offset);
    uploadedOffset = offset + bytes.length;
    return uploadedOffset;
  }

  @override
  Future<VideoJobStatus> createVideoJob(Map<String, dynamic> request) async {
    requests.add(request);
    if (loseCreateResponse) {
      loseCreateResponse = false;
      throw ApiException.network('Lost response');
    }
    return const VideoJobStatus(
      id: 'video-1',
      status: 'completed',
      progress: 1,
    );
  }

  @override
  Future<VideoJobStatus> videoJob(String id) async {
    if (missingJob) {
      missingJob = false;
      throw const ApiException(
        code: 'not_found',
        message: 'PC restarted',
        statusCode: 404,
      );
    }
    return VideoJobStatus(id: id, status: 'completed', progress: 1);
  }

  @override
  Future<VideoJobStatus> controlVideoJob(String id, {required bool resume}) =>
      videoJob(id);
  @override
  Future<VideoResultFile> videoResult(String id) async =>
      VideoResultFile.fromJson({
        'name': 'detections.ndjson',
        'size': result.length,
        'sha256': sha256.convert(result).toString(),
      });
  @override
  Future<void> downloadVideoResult(String id, File target) async {
    await target.writeAsBytes(corrupt ? [0, 1] : result);
    afterDownload?.call();
  }

  @override
  Future<void> deleteVideoJob(String id) async {
    deleted++;
  }
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late VideoLibrary library;
  late AppSettings settings;
  late VideoScan scanner;
  late VideoPc pc;
  late MediaRow row;
  late InMemoryEmbeddingIndex index;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('ag_video_test_');
    library = VideoLibrary(
      await File('${temp.path}/original.mp4').writeAsBytes(List.filled(10, 42)),
    );
    settings = AppSettings(db);
    index = InMemoryEmbeddingIndex();
    scanner = VideoScan(
      db: db,
      store: PhotoResultStore(
        db: db,
        files: FileStore(Directory('${temp.path}/crops')),
        index: index,
      ),
      settings: settings,
      delay: (_) async {},
    );
    await LibraryRepository(db).syncAssets([
      const AssetInfo(
        id: 'video',
        width: 640,
        height: 480,
        modifiedAt: 1,
        takenAt: 1,
        kind: 'video',
        durationMs: 3000,
      ),
    ]);
    row = (await db.select(db.media).get()).single;
    pc = VideoPc();
    pc.result = utf8.encode(
      [
        for (final frame in [0, 30, 60])
          jsonEncode({
            'model_id': 'buffalo_l@1',
            'image_w': 1000,
            'image_h': 800,
            'faces': [faceJson(unitVec(100 + frame))],
            'bodies': [],
            'pairs': [],
            'frame_number': frame,
            'timestamp_ms': frame * 1000 ~/ 30,
          }),
      ].join('\n'),
    );
  });
  tearDown(() async {
    await index.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StoreOutcome> run({
    bool Function()? paused,
    void Function(String, double)? report,
  }) => scanner.run(
    row,
    api: pc,
    library: library,
    prefs: const SettingsSnapshot(),
    paused: paused ?? () => false,
    report: report ?? (_, _) {},
  );

  test(
    'resumes a partial upload and stores timestamped frame detections',
    () async {
      pc.uploadedOffset = 4;
      final outcome = await run();
      expect(pc.uploaded, [4]);
      expect(outcome.newFaces, 3);
      final faces = await db.select(db.faces).get();
      expect(faces.map((f) => f.frameNumber), [0, 30, 60]);
      expect(faces.map((f) => f.timestampMs), [0, 1000, 2000]);
      final current = (await db.select(db.media).get()).single;
      expect((current.scanStatus, current.lastScannedFrame), ('done', 61));
      expect(pc.deleted, 1);
      expect(await db.setting('video.job.${row.id}'), isNull);
    },
  );

  test('lost POST response reuses the persisted client job id', () async {
    pc.loseCreateResponse = true;
    await expectLater(run(), throwsA(isA<ApiException>()));
    await run();
    expect(pc.requests.length, 2);
    expect(pc.requests[0]['client_job_id'], pc.requests[1]['client_job_id']);
    expect(pc.uploaded, [0]);
  });

  test(
    'an interrupted import resumes without repeating committed frames',
    () async {
      var paused = false;
      await expectLater(
        run(
          paused: () => paused,
          report: (stage, _) {
            if (stage == 'import') paused = true;
          },
        ),
        throwsA(isA<VideoScanPaused>()),
      );
      expect((await db.select(db.faces).get()).length, 1);
      expect(pc.deleted, 0);
      await run();
      expect((await db.select(db.faces).get()).length, 3);
      expect((await db.select(db.mediaDetections).get()).length, 3);
      expect(pc.requests.length, 1);
    },
  );

  test(
    'a PC restart creates a new job from the imported frame checkpoint',
    () async {
      var paused = false;
      await expectLater(
        run(
          paused: () => paused,
          report: (stage, _) {
            if (stage == 'import') paused = true;
          },
        ),
        throwsA(isA<VideoScanPaused>()),
      );
      pc.missingJob = true;
      await run();
      expect((pc.requests.last['params'] as Map)['start_frame'], 1);
      expect(
        pc.requests.first['client_job_id'],
        isNot(pc.requests.last['client_job_id']),
      );
      expect((await db.select(db.faces).get()).length, 3);
    },
  );

  test(
    'a corrupt download cannot import any rows or acknowledge the PC',
    () async {
      pc.corrupt = true;
      await expectLater(run(), throwsA(isA<ApiException>()));
      expect(await db.select(db.faces).get(), isEmpty);
      expect((await db.select(db.media).get()).single.lastScannedFrame, 0);
      expect(pc.deleted, 0);
    },
  );

  test(
    'a different embedding model is refused before importing a frame',
    () async {
      await settings.setModelId('another-model');
      await expectLater(
        run(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'model_mismatch'),
        ),
      );
      expect(await db.select(db.faces).get(), isEmpty);
      expect(pc.deleted, 0);
    },
  );

  test(
    'video filters include body-only sightings and insights deduplicate frames',
    () async {
      await run();
      final person = await seedPerson(db, name: 'Sara');
      final body = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(row.id),
              personId: Value(person),
              bboxX: 0,
              bboxY: 0,
              bboxW: 1,
              bboxH: 1,
              score: 0.9,
              createdAt: 1,
            ),
          );
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: row.id,
              kind: 'b',
              refId: body,
              x: 0,
              y: 0,
              w: 1,
              h: 1,
            ),
          );
      final queries = MediaQueries(db);
      expect(
        await queries.count(MediaFilter(personId: person, kind: 'video')),
        1,
      );
      expect(await queries.count(const MediaFilter(kind: 'photo')), 0);
      final data = await InsightsRepository(db).watch().first;
      expect(data.identifiedBodies, 1);
      expect(data.topPeople.single.mediaCount, 1);
    },
  );
}
