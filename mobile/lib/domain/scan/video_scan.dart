import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/jobs.dart';
import '../../data/api/video_api.dart';
import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/app_settings.dart';
import '../../data/repositories/library_repository.dart';
import 'photo_result_store.dart';
import 'video_hash.dart';
import 'video_sampling.dart';
import 'video_scan_progress.dart';

class VideoScanPaused implements Exception {
  const VideoScanPaused();
}

Future<String> fileSha256(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

// A top-level wrapper keeps SQLite out of the isolate closure context.
Future<String> isolatedFileSha256(String path) =>
    Isolate.run(() => fileSha256(File(path)));

/// Persistent request IDs prevent duplicate server jobs after a lost response. Only the
/// imported-frame checkpoint travels in backups; PC job IDs stay in private settings.
class VideoScan {
  VideoScan({
    required this.db,
    required this.store,
    required this.settings,
    this.pollInterval = const Duration(seconds: 2),
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  final AppDatabase db;
  final PhotoResultStore store;
  final AppSettings settings;
  final Duration pollInterval;
  final Future<void> Function(Duration) delay;

  Future<StoreOutcome> run(
    MediaRow media, {
    required VideoApi api,
    required VideoMediaLibrary library,
    required SettingsSnapshot prefs,
    required bool Function() paused,
    required void Function(String stage, double progress) report,
    void Function(VideoScanProgress progress)? onProgress,
    void Function(Uint8List bytes, int? timestampMs)? onPreview,
  }) async {
    final startedAt = DateTime.now();
    var stageStartedAt = startedAt;
    VideoScanStage? activeStage;
    final stageWatch = Stopwatch();
    int? processedBytes, totalBytes;
    String? fileName;
    int? fileBytes;
    var byteBaseline = 0;
    int? sampleBaseline;
    var framesSaved = 0;
    VideoJobStatus? currentJob;
    DateTime? serverUpdatedAt;
    var outcome = const StoreOutcome();

    void publish(VideoScanStage stage, [double? fraction]) {
      final now = DateTime.now();
      if (stage != activeStage) {
        activeStage = stage;
        stageStartedAt = now;
        stageWatch.reset();
        stageWatch.start();
        byteBaseline = processedBytes ?? 0;
        sampleBaseline = currentJob?.framesDone == null
            ? null
            : currentJob!.framesDone! + currentJob!.skippedSamples;
      }
      final seconds = stageWatch.elapsedMilliseconds / 1000;
      final transfer =
          stage == VideoScanStage.upload || stage == VideoScanStage.download;
      final speed =
          transfer &&
              seconds >= 1 &&
              processedBytes != null &&
              processedBytes! > byteBaseline
          ? (processedBytes! - byteBaseline) / seconds
          : null;
      double? remaining;
      if (speed != null && totalBytes != null) {
        remaining = (totalBytes - processedBytes!).clamp(0, totalBytes) / speed;
      } else if (stage == VideoScanStage.analyze &&
          seconds >= 2 &&
          sampleBaseline != null &&
          currentJob?.framesDone != null &&
          currentJob?.totalSamples != null) {
        final done = currentJob!.framesDone! + currentJob!.skippedSamples;
        final advanced = done - sampleBaseline!;
        if (advanced >= 2 && done < currentJob!.totalSamples!) {
          remaining = (currentJob!.totalSamples! - done) * seconds / advanced;
        }
      }
      if (stage != VideoScanStage.importing) {
        report(stage.name, fraction ?? 0);
      }
      onProgress?.call(
        VideoScanProgress(
          stage: stage,
          startedAt: startedAt,
          stageStartedAt: stageStartedAt,
          updatedAt: now,
          fraction: fraction,
          durationMs: media.durationMs,
          fileName: fileName,
          fileBytes: fileBytes,
          width: media.width,
          height: media.height,
          processedBytes: transfer || stage == VideoScanStage.prepare
              ? processedBytes
              : null,
          totalBytes: transfer || stage == VideoScanStage.prepare
              ? totalBytes
              : null,
          bytesPerSecond: speed,
          eta:
              remaining != null &&
                  remaining.isFinite &&
                  remaining > 0 &&
                  remaining < 365 * 86400
              ? Duration(seconds: remaining.ceil())
              : null,
          framesDone: currentJob?.framesDone,
          totalSamples: currentJob?.totalSamples,
          analyzedTimestampMs: currentJob?.analyzedTimestampMs,
          frameInterval: currentJob?.frameInterval,
          skippedSamples: currentJob?.skippedSamples ?? 0,
          framesSaved: framesSaved,
          facesFound: outcome.newFaces,
          bodiesFound: outcome.newBodies,
          charactersFound: outcome.newCharacters,
          serverStage: currentJob?.stage,
          serverMessage: currentJob?.message,
          warning: currentJob?.warning,
          serverUpdatedAt: serverUpdatedAt,
          incrementalResults: currentJob?.incrementalResults ?? false,
        ),
      );
    }

    void receiveJob(VideoJobStatus job) {
      currentJob = job;
      serverUpdatedAt = DateTime.now();
      final stage =
          job.status == 'queued' ||
              job.status == 'pending' ||
              job.status == 'paused'
          ? VideoScanStage.queue
          : job.stage == 'finalize'
          ? VideoScanStage.finish
          : VideoScanStage.analyze;
      publish(
        stage,
        stage == VideoScanStage.analyze &&
                (job.status == 'running' || job.status == 'completed')
            ? job.progress
            : null,
      );
    }

    void checkPause() {
      if (paused()) throw const VideoScanPaused();
    }

    final key = 'video.job.${media.id}';
    Map<String, dynamic>? saved;
    final raw = await db.setting(key);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) saved = decoded;
      } on FormatException {
        /* discard invalid checkpoint */
      }
    }
    // A changed source or a different PC must never reuse the previous job.
    if (saved?['server'] != api.serverId ||
        saved?['asset'] != media.assetId ||
        saved?['modified'] != media.modifiedAt ||
        saved?['width'] != media.width ||
        saved?['height'] != media.height ||
        saved?['duration'] != media.durationMs) {
      saved = null;
    }
    if (saved != null) {
      final path = saved['path'] as String?;
      fileName = path == null ? null : File(path).uri.pathSegments.last;
      fileBytes = saved['size'] as int?;
    }

    Future<void> persist() async {
      if (saved == null) {
        await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
      } else {
        await db.putSetting(key, jsonEncode(saved));
      }
    }

    String? warning;
    var workerRetries = 0;
    var nextFrame =
        (await LibraryRepository(db).mediaById(media.id))?.lastScannedFrame ??
        0;
    Future<void> importFrame(Map<String, dynamic> json) async {
      checkPause();
      final frame = json['frame_number'] as int;
      final timestamp = json['timestamp_ms'] as int;
      if (frame < 0 || timestamp < 0) {
        throw ApiException.badResponse('Invalid video frame position.');
      }
      if (frame < nextFrame) return;
      final analysis = AnalyzeImageResponse.fromJson(json);
      final model = (await settings.load()).modelId;
      final characterScan =
          ((saved?['request'] as Map?)?['params']
              as Map?)?['detect_characters'] ==
          true;
      if (!characterScan && model != null && analysis.modelId != model) {
        throw const ApiException(
          code: 'model_mismatch',
          message: 'The video uses a different embedding model.',
        );
      }
      if (!characterScan && model == null) {
        await settings.setModelId(analysis.modelId);
      }
      final stored = await store.store(
        media,
        analysis,
        frameNumber: frame,
        timestampMs: timestamp,
        complete: false,
      );
      outcome = StoreOutcome(
        facesSeen: outcome.facesSeen + stored.facesSeen,
        newFaceIds: [...outcome.newFaceIds, ...stored.newFaceIds],
        linkedFaces: outcome.linkedFaces + stored.linkedFaces,
        newBodies: outcome.newBodies + stored.newBodies,
        newCharacters: outcome.newCharacters + stored.newCharacters,
      );
      nextFrame = frame + 1;
      framesSaved++;
      final liveImport =
          currentJob?.incrementalResults == true &&
          currentJob?.status == 'running' &&
          currentJob?.stage != 'finalize';
      // The legacy callback marks a committed frame, not entry into the stage.
      report('import', 0);
      publish(
        liveImport ? VideoScanStage.analyze : VideoScanStage.importing,
        liveImport ? currentJob?.progress : null,
      );
    }

    for (var restart = 0; restart < 3; restart++) {
      checkPause();
      if (saved == null) {
        currentJob = null;
        serverUpdatedAt = null;
        processedBytes = null;
        totalBytes = null;
        publish(VideoScanStage.prepare);
        final file = await library.videoFile(media.assetId);
        if (file == null || !await file.exists()) {
          throw ApiException.badResponse(
            'The video is no longer available on this phone.',
          );
        }
        final path = file.path;
        totalBytes = await file.length();
        fileBytes = totalBytes;
        fileName = file.uri.pathSegments.last;
        processedBytes = 0;
        publish(VideoScanStage.prepare, 0);
        final String hash;
        try {
          hash = await videoFileHash(
            File(path),
            cancelled: paused,
            onProgress: (progress) {
              processedBytes = (progress * totalBytes!).round();
              publish(VideoScanStage.prepare, progress);
            },
          );
        } on VideoHashCancelled {
          throw const VideoScanPaused();
        }
        checkPause();
        final current = await LibraryRepository(db).mediaById(media.id);
        if (current == null) throw const VideoScanPaused();
        saved = {
          'server': api.serverId,
          'asset': media.assetId,
          'modified': media.modifiedAt,
          'width': media.width,
          'height': media.height,
          'duration': media.durationMs,
          'size': fileBytes,
          'sha': hash,
          'path': path,
          'request': {
            'type': 'analyze_video',
            'client_job_id':
                '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
            'inputs': {'video': hash},
            'params': {
              'frame_interval': prefs.adaptiveVideoSampling
                  ? adaptiveVideoInterval(media.durationMs)
                  : prefs.frameInterval,
              'sampling_mode': prefs.adaptiveVideoSampling
                  ? 'adaptive'
                  : 'fixed',
              'min_quality': prefs.qualityGate,
              'detect_bodies': prefs.scanBodies,
              'detect_characters': prefs.scanCharacters,
              'model_id': prefs.modelId,
              'start_frame': current.lastScannedFrame,
            },
          },
        };
        await persist(); // before POST: an app kill cannot lose its idempotency key
      }
      try {
        var id = saved['id'] as String?;
        if (id == null) {
          final hash = saved['sha'] as String;
          final file = await library.videoFile(media.assetId);
          if (file == null) {
            throw ApiException.badResponse('The video could not be read.');
          }
          final total = await file.length();
          fileBytes = total;
          fileName = file.uri.pathSegments.last;
          if (total <= 0) throw ApiException.badResponse('The video is empty.');
          var head = await api.blobOffset(hash);
          var offset = head.offset;
          if (offset > total || (head.exists && offset != total)) {
            throw ApiException.badResponse(
              'The PC returned an invalid upload size.',
            );
          }
          totalBytes = total;
          processedBytes = offset;
          publish(VideoScanStage.upload, offset / total);
          final source = await file.open();
          try {
            var stalled = 0;
            while (!head.exists && offset < total) {
              checkPause();
              await source.setPosition(offset);
              final bytes = await source.read(
                min(4 * 1024 * 1024, total - offset),
              );
              if (bytes.isEmpty) {
                throw ApiException.badResponse(
                  'The video changed during upload.',
                );
              }
              final telemetry = Stopwatch()..start();
              final next = api is VideoTransferProgressApi
                  ? await (api as VideoTransferProgressApi).uploadVideoChunk(
                      hash,
                      bytes,
                      offset,
                      total,
                      onProgress: (sent) {
                        if (telemetry.elapsedMilliseconds < 200) return;
                        telemetry.reset();
                        processedBytes = offset + sent.clamp(0, bytes.length);
                        publish(VideoScanStage.upload, processedBytes! / total);
                      },
                    )
                  : await api.uploadChunk(hash, bytes, offset, total);
              if (next == offset && ++stalled > 3) {
                throw ApiException.badResponse('The upload is not advancing.');
              }
              if (next != offset) stalled = 0;
              offset = next;
              processedBytes = offset;
              publish(VideoScanStage.upload, offset / total);
            }
          } finally {
            await source.close();
          }
          checkPause();
          publish(VideoScanStage.queue);
          final job = await api.createVideoJob(
            Map<String, dynamic>.from(saved['request'] as Map),
          );
          id = job.id;
          saved['id'] = id;
          await persist();
        }
        publish(VideoScanStage.queue);
        var streamed = false;
        while (true) {
          if (paused()) {
            try {
              await api.controlVideoJob(id, resume: false);
            } on ApiException {
              /* reconnect later */
            }
            throw const VideoScanPaused();
          }
          var job = await api.videoJob(id);
          receiveJob(job);
          if (job.previewBytes case final bytes?) {
            onPreview?.call(bytes, job.previewTimestampMs);
          }
          warning = job.warning;
          if (job.incrementalResults && api is VideoFrameApi) {
            streamed = true;
            final state = saved!;
            var more = true;
            var complete = false;
            while (more) {
              final batch = await (api as VideoFrameApi).videoFrames(
                id,
                cursor: state['cursor'] as int? ?? 0,
              );
              var previous = -1;
              for (final frame in batch.frames) {
                final number = frame['frame_number'] as int;
                if (number <= previous) {
                  throw ApiException.badResponse(
                    'Video frames are out of order.',
                  );
                }
                previous = number;
                await importFrame(frame);
              }
              // Cursor follows committed frame writes. A kill before this setting
              // is saved safely replays the batch against lastScannedFrame.
              state['cursor'] = batch.nextCursor;
              await persist();
              more = batch.hasMore;
              complete = batch.completed;
            }
            if (complete) {
              job = await api.videoJob(id);
              receiveJob(job);
              warning = job.warning;
              break;
            }
          }
          if (job.status == 'paused') {
            if (job.error != null && ++workerRetries > 2) {
              throw ApiException(
                code: 'engine_unavailable',
                message:
                    'The PC analysis worker stopped repeatedly. Resume the scan to retry.',
              );
            }
            job = await api.controlVideoJob(id, resume: true);
            receiveJob(job);
            if (job.status == 'paused') {
              throw ApiException(
                code: 'resource_pressure',
                message: job.message ?? 'The PC paused video analysis.',
                retryable: true,
                retryAfter: pollInterval,
              );
            }
          }
          if (job.status == 'failed') {
            try {
              await api.deleteVideoJob(id);
            } on ApiException {
              // The next scan gets a fresh request even if this PC disconnects now.
            }
            saved = null;
            await persist();
            throw ApiException(
              code: 'bad_video',
              message: job.error ?? 'Video analysis failed on the PC.',
            );
          }
          if (job.status == 'completed') break;
          await delay(pollInterval);
        }
        checkPause();
        if (!streamed) {
          processedBytes = 0;
          totalBytes = null;
          publish(VideoScanStage.download);
          final manifest = await api.videoResult(id);
          final temp = await Directory.systemTemp.createTemp('ag_video_');
          try {
            final result = File('${temp.path}/detections.ndjson');
            totalBytes = manifest.size;
            processedBytes = 0;
            publish(VideoScanStage.download, 0);
            final telemetry = Stopwatch()..start();
            if (api is VideoTransferProgressApi) {
              await (api as VideoTransferProgressApi).downloadVideoWithProgress(
                id,
                result,
                onProgress: (received) {
                  if (telemetry.elapsedMilliseconds < 200) return;
                  telemetry.reset();
                  processedBytes = received;
                  publish(
                    VideoScanStage.download,
                    manifest.size > 0 ? received / manifest.size : null,
                  );
                },
              );
            } else {
              await api.downloadVideoResult(id, result);
            }
            processedBytes = await result.length();
            publish(
              VideoScanStage.download,
              manifest.size > 0
                  ? (processedBytes! / manifest.size).clamp(0.0, 1.0)
                  : 1,
            );
            publish(VideoScanStage.verify);
            final path = result.path;
            if (await result.length() != manifest.size ||
                await isolatedFileSha256(path) != manifest.sha256) {
              throw ApiException.badResponse(
                'The downloaded video result failed its integrity check.',
              );
            }
            var previous = -1;
            publish(VideoScanStage.importing);
            await for (final line
                in result
                    .openRead()
                    .transform(utf8.decoder)
                    .transform(const LineSplitter())) {
              checkPause();
              if (line.trim().isEmpty) continue;
              final json = jsonDecode(line) as Map<String, dynamic>;
              final frame = json['frame_number'] as int;
              final timestamp = json['timestamp_ms'] as int;
              if (frame <= previous || frame < 0 || timestamp < 0) {
                throw ApiException.badResponse(
                  'Video frames are out of order.',
                );
              }
              previous = frame;
              await importFrame(json);
            }
          } finally {
            await temp.delete(recursive: true);
          }
        }
        publish(VideoScanStage.finish);
        await (db.update(db.media)..where((m) => m.id.equals(media.id))).write(
          MediaCompanion(
            scanStatus: const Value('done'),
            scanVersion: const Value(scanVersion),
            scannedAt: Value(DateTime.now().millisecondsSinceEpoch),
            scanError: Value(warning),
          ),
        );
        // ACK only after every frame committed locally. A failed ACK is safe to retry later.
        try {
          await api.deleteVideoJob(id);
        } on ApiException {
          /* TTL cleans up unreachable PCs */
        }
        await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
        return outcome;
      } on VideoScanPaused {
        final id = saved?['id'] as String?;
        if (id != null) {
          try {
            await api.controlVideoJob(id, resume: false);
          } on ApiException {
            /* resume later */
          }
        }
        rethrow;
      } on ApiException catch (e) {
        if (e.statusCode == 404 || e.code == 'missing_blobs') {
          saved = null;
          await persist();
          continue;
        }
        rethrow;
      }
    }
    throw ApiException.network(
      'The PC restarted or evicted the upload repeatedly. Resume to try again.',
    );
  }
}
