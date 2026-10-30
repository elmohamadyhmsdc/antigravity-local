import 'dart:io';
import 'dart:typed_data';

import 'dtos/jobs.dart';

/// Transport seam for large uploads and ephemeral video jobs.
abstract interface class VideoApi {
  String get serverId;
  Future<({bool exists, int offset})> blobOffset(String sha256);
  Future<int> uploadChunk(
    String sha256,
    Uint8List bytes,
    int offset,
    int total,
  );
  Future<VideoJobStatus> createVideoJob(Map<String, dynamic> request);
  Future<VideoJobStatus> videoJob(String id);
  Future<VideoJobStatus> controlVideoJob(String id, {required bool resume});
  Future<VideoResultFile> videoResult(String id);
  Future<void> downloadVideoResult(String id, File target);
  Future<void> deleteVideoJob(String id);
}

/// Optional extension; older PCs keep using the verified final-result download.
abstract interface class VideoFrameApi {
  Future<VideoFrameBatch> videoFrames(String id, {required int cursor});
}
