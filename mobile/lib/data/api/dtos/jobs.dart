import 'json_util.dart';

class VideoJobStatus {
  const VideoJobStatus({
    required this.id,
    required this.status,
    required this.progress,
    this.error,
  });

  factory VideoJobStatus.fromJson(Map<String, dynamic> json) {
    final progress = number(json, 'progress');
    final status = field<String>(json, 'status');
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
    );
  }

  final String id;
  final String status;
  final double progress;
  final String? error;
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
