import 'dart:io';

import 'dtos/jobs.dart';
import 'video_api.dart';

/// Uses the same pinned transport and resumable blob protocol as video scanning.
abstract interface class StudioApi implements VideoApi {
  Future<StudioJobStatus> createStudioJob(Map<String, dynamic> request);
  Future<StudioJobStatus> studioJob(String id);
  Future<StudioJobStatus> controlStudioJob(String id, {required bool resume});
  Stream<StudioJobStatus> studioEvents(String id);
  Future<StudioResultFile> studioResult(String id);
  Future<void> downloadStudioResult(String id, String name, File target);
}
