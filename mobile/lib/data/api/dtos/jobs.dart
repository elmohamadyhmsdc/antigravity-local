import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'json_util.dart';

class VideoJobStatus {
  const VideoJobStatus({
    required this.id,
    required this.status,
    required this.progress,
    this.error,
    this.previewBytes,
    this.previewTimestampMs,
    this.warning,
    this.message,
    this.incrementalResults = false,
    this.framesDone,
    this.totalSamples,
    this.analyzedTimestampMs,
    this.frameInterval,
    this.skippedSamples = 0,
    this.stage,
  });

  factory VideoJobStatus.fromJson(Map<String, dynamic> json) {
    final progress = number(json, 'progress');
    final status = field<String>(json, 'status');
    final preview = json['preview_jpeg'] as String?;
    final timestamp = json['preview_timestamp_ms'] == null
        ? null
        : integer(json, 'preview_timestamp_ms');
    if ((preview != null && preview.length > 256 * 1024) ||
        (timestamp != null && timestamp < 0)) {
      throw const FormatException('Invalid video preview');
    }
    final details = json['details'] as Map? ?? const {};
    final skipped = details['skipped_frames'] as int? ?? 0;
    int? count(Object? value) => value is int && value >= 0 ? value : null;
    double? positive(Object? value) =>
        value is num && value.isFinite && value > 0 ? value.toDouble() : null;
    final fps = positive(details['fps']);
    final lastFrame = count(json['last_frame']);
    if (!progress.isFinite ||
        progress < 0 ||
        progress > 1 ||
        !const [
          'pending',
          'queued',
          'running',
          'paused',
          'completed',
          'failed',
        ].contains(status)) {
      throw const FormatException('Invalid video job status');
    }
    return VideoJobStatus(
      id: field<String>(json, 'job_id'),
      status: status,
      progress: progress,
      error: json['error'] as String?,
      message: json['message'] as String?,
      incrementalResults: json['incremental_results'] == true,
      previewBytes: preview == null ? null : base64Decode(preview),
      previewTimestampMs: timestamp,
      framesDone: count(json['frames_done']),
      totalSamples: count(details['total_samples']),
      analyzedTimestampMs: fps == null || lastFrame == null
          ? null
          : (lastFrame * 1000 / fps).round(),
      frameInterval: positive(details['frame_interval']),
      skippedSamples: skipped < 0 ? 0 : skipped,
      stage: details['stage'] as String?,
      warning:
          details['warning'] as String? ??
          (skipped > 0
              ? '$skipped unreadable video samples were skipped.'
              : null),
    );
  }

  final String id;
  final String status;
  final double progress;
  final String? error;
  final String? message;
  final Uint8List? previewBytes;
  final int? previewTimestampMs;
  final String? warning;
  final bool incrementalResults;
  final int? framesDone;
  final int? totalSamples;
  final int? analyzedTimestampMs;
  final double? frameInterval;
  final int skippedSamples;
  final String? stage;
}

class VideoFrameBatch {
  VideoFrameBatch.fromJson(Map<String, dynamic> json, {required int cursor})
    : nextCursor = integer(json, 'next_cursor'),
      hasMore = field<bool>(json, 'has_more'),
      completed = field<bool>(json, 'completed') {
    final raw = field<String>(json, 'ndjson');
    if (raw.length > 16 * 1024 * 1024) {
      throw const FormatException('Video frame batch is too large');
    }
    final bytes = utf8.encode(raw);
    if (nextCursor < cursor ||
        nextCursor - cursor != bytes.length ||
        sha256.convert(bytes).toString() != field<String>(json, 'sha256') ||
        (hasMore && nextCursor == cursor) ||
        (completed && hasMore) ||
        (raw.isNotEmpty && !raw.endsWith('\n'))) {
      throw const FormatException(
        'Invalid video frame batch integrity or cursor',
      );
    }
    frames = [
      for (final line in const LineSplitter().convert(raw))
        if (line.isNotEmpty) map(jsonDecode(line), 'video frame'),
    ];
    if (frames.length > 8) throw const FormatException('Too many video frames');
  }

  final int nextCursor;
  final bool hasMore;
  final bool completed;
  late final List<Map<String, dynamic>> frames;
}

class VideoResultFile {
  VideoResultFile.fromJson(Map<String, dynamic> json)
    : name = field<String>(json, 'name'),
      size = integer(json, 'size'),
      sha256 = field<String>(json, 'sha256') {
    if (name != 'detections.ndjson' ||
        size < 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid video result manifest');
    }
  }

  final String name;
  final int size;
  final String sha256;
}

class StudioJobStatus {
  StudioJobStatus.fromJson(Map<String, dynamic> json)
    : id = field<String>(json, 'job_id'),
      status = field<String>(json, 'status'),
      progress = number(json, 'progress'),
      message = json['message'] as String?,
      error = json['error'] as String?,
      details = Map<String, dynamic>.from(json['details'] as Map? ?? const {}) {
    if (id.isEmpty ||
        !progress.isFinite ||
        progress < 0 ||
        progress > 1 ||
        !const [
          'queued',
          'running',
          'paused',
          'completed',
          'failed',
        ].contains(status)) {
      throw const FormatException('Invalid Studio job status');
    }
  }
  final String id;
  final String status;
  final double progress;
  final String? message;
  final String? error;
  final Map<String, dynamic> details;
}

class StudioResultFile {
  StudioResultFile.fromJson(Map<String, dynamic> json)
    : name = field<String>(json, 'name'),
      size = integer(json, 'size'),
      sha256 = field<String>(json, 'sha256'),
      mime = field<String>(json, 'mime') {
    if (!const {
          'result.png': 'image/png',
          'result.mp4': 'video/mp4',
          'dataset.zip': 'application/zip',
          'portraits.zip': 'application/zip',
          'lora.safetensors': 'application/octet-stream',
        }.entries.any((entry) => entry.key == name && entry.value == mime) ||
        size <= 0 ||
        size > 2 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid Studio result manifest');
    }
  }
  final String name;
  final int size;
  final String sha256;
  final String mime;
}
