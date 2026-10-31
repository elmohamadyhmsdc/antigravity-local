import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/data/platform/video_frames.dart';
import 'package:antigravity_mobile/data/repositories/app_settings.dart';
import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/scan/video_scan.dart';
import 'package:antigravity_mobile/domain/scan/video_scan_progress.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';
import 'video_scan_test.dart' show VideoLibrary, VideoPc;

/// A PC that analyses single frames (the phone-side path) and still accepts uploads (fallback).
class FramePc extends VideoPc implements MobileApi {
  final analyzed = <int>[];

  @override
  Future<AnalyzeImageResponse> analyzeImage(
    Uint8List jpegBytes, {
    String filename = 'photo.jpg',
    AnalyzeOptions options = const AnalyzeOptions(),
  }) async {
    final frame = jpegBytes.first;
    analyzed.add(frame);
    return AnalyzeImageResponse.fromJson({
      'model_id': 'buffalo_l@1',
      'image_w': 1000,
      'image_h': 800,
      'faces': [faceJson(unitVec(100 + frame))],
      'bodies': [],
      'pairs': [],
    });
  }

  @override
  Future<Capabilities> capabilities() => throw UnimplementedError();
  @override
  Future<Health> health() => throw UnimplementedError();
  @override
  Future<GroupingPlanResponse> groupingPlan(GroupingPlanRequest request) =>
      throw UnimplementedError();
}

/// The phone decoder: frame k of a 30 fps video is a one-byte "JPEG" holding k ~/ 15.
class FakeFrames implements LocalVideoFrames {
  FakeFrames({this.durationMs = 3000, this.readable = true});
  final int durationMs;
  bool readable;
  final requested = <int>[];
  var closed = 0;

  @override
  Future<VideoProbe?> probe(String assetId) async => VideoProbe(
    durationMs: durationMs,
    fps: 30,
    frameCount: durationMs * 30 ~/ 1000,
  );

  @override
  Future<List<Uint8List?>> frames(
    String assetId,
    List<int> timesMs, {
    int maxSide = 2048,
  }) async {
    requested.addAll(timesMs);
    return [
      for (final t in timesMs)
        readable ? Uint8List.fromList([t * 30 ~/ 1000 ~/ 15]) : null,
    ];
  }

  @override
  Future<void> close() async => closed++;
}

void main() {
  late AppDatabase db;
  late Directory temp;
  late InMemoryEmbeddingIndex index;
  late FramePc pc;
  late FakeFrames frames;
  late MediaRow row;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('ag_video_local_');
    index = InMemoryEmbeddingIndex();
    pc = FramePc();
    frames = FakeFrames();
    await LibraryRepository(db).syncAssets([
      const AssetInfo(
        id: '41',
        width: 640,
        height: 480,
        modifiedAt: 1,
        takenAt: 1,
        kind: 'video',
        durationMs: 3000,
      ),
    ]);
    row = (await db.select(db.media).get()).single;
  });
  tearDown(() async {
    await index.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<StoreOutcome> run({
    void Function(VideoScanProgress)? onProgress,
  }) async {
    final library = VideoLibrary(
      await File('${temp.path}/original.mp4').writeAsBytes(List.filled(10, 42)),
    );
    return VideoScan(
      db: db,
      store: PhotoResultStore(
        db: db,
        files: FileStore(Directory('${temp.path}/crops')),
        index: index,
      ),
      settings: AppSettings(db),
      localFrames: frames,
      delay: (_) async {},
    ).run(
      row,
      api: pc,
      library: library,
      prefs: const SettingsSnapshot(),
      paused: () => false,
      report: (_, _) {},
      onProgress: onProgress,
    );
  }

  test(
    'the phone decodes the sampled frames and never uploads the video',
    () async {
      final updates = <VideoScanProgress>[];
      final outcome = await run(onProgress: updates.add);
      // 3 s adaptive = every 0.5 s at 30 fps: frames 0, 15, ... 75.
      expect(frames.requested, [0, 500, 1000, 1500, 2000, 2500]);
      expect(pc.analyzed, [0, 1, 2, 3, 4, 5]);
      expect(pc.uploaded, isEmpty);
      expect(pc.requests, isEmpty);
      expect(outcome.facesSeen, 6);
      final media = (await db.select(db.media).get()).single;
      expect(media.scanStatus, 'done');
      expect(media.lastScannedFrame, 76);
      expect(await db.setting('video.local.${row.id}'), isNull);
      expect(frames.closed, 1);
      final analyze = updates.where((p) => p.stage == VideoScanStage.analyze);
      expect(analyze.last.totalSamples, 6);
      expect(analyze.last.framesDone, 6);
      expect(updates.any((p) => p.stage == VideoScanStage.upload), isFalse);
    },
  );

  test(
    'a resumed scan continues on the pinned grid after the last committed frame',
    () async {
      await (db.update(db.media)..where((m) => m.id.equals(row.id))).write(
        const MediaCompanion(lastScannedFrame: Value(31)),
      );
      await run();
      expect(frames.requested, [1500, 2000, 2500]);
      expect(pc.analyzed, [3, 4, 5]);
    },
  );

  test(
    'a video the phone cannot decode falls back to the upload path',
    () async {
      frames = FakeFrames(durationMs: 10000, readable: false);
      await run();
      expect(pc.analyzed, isEmpty);
      expect(pc.requests, hasLength(1));
      expect(pc.uploaded, isNotEmpty);
    },
  );

  test('the queue takes photos first, then videos shortest first', () async {
    final repo = LibraryRepository(db);
    await repo.syncAssets([
      const AssetInfo(
        id: '41',
        width: 640,
        height: 480,
        modifiedAt: 1,
        takenAt: 1,
        kind: 'video',
        durationMs: 3000,
      ),
      const AssetInfo(
        id: '50',
        width: 640,
        height: 480,
        modifiedAt: 1,
        takenAt: 1,
        kind: 'video',
        durationMs: 1000,
      ),
      const AssetInfo(
        id: '60',
        width: 10,
        height: 10,
        modifiedAt: 1,
        takenAt: 1,
      ),
    ]);
    final order = [
      for (var i = 0; i < 3; i++) (await repo.claimNext())!.assetId,
    ];
    expect(order, ['60', '50', '41']);
  });
}
