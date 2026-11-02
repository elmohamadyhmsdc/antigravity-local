import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scan/scan_state.dart';
import '../../library_providers.dart';
import '../../studio_providers.dart';
import '../../data/db/app_database.dart';

sealed class ActivityState {
  const ActivityState();

  bool get isIdle => this is ActivityIdle;
  bool get isBusy => !isIdle;
}

class ActivityIdle extends ActivityState {
  const ActivityIdle();
}

class ActivityScanning extends ActivityState {
  const ActivityScanning({
    required this.done,
    required this.total,
    this.phase = ScanPhase.running,
  });

  final int done;
  final int total;
  final ScanPhase phase;

  double get progress => total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
}

class ActivityJob extends ActivityState {
  const ActivityJob({
    required this.id,
    required this.type,
    required this.progress,
    this.status = 'running',
  });

  final String id;
  final String type;
  final double progress;
  final String status;
}

class ActivityMultiple extends ActivityState {
  const ActivityMultiple({
    required this.primaryDescription,
    required this.extraCount,
  });

  final String primaryDescription;
  final int extraCount;
}

class ActivityFailed extends ActivityState {
  const ActivityFailed({required this.message, this.jobId});

  final String message;
  final String? jobId;
}

final activityStateProvider = Provider<ActivityState>((ref) {
  final scanAsync = ref.watch(scanProgressProvider);
  final jobsAsync = ref.watch(jobsProvider);

  final scan = scanAsync.value;
  final jobs = jobsAsync.value ?? const <JobRow>[];

  // 1. Check active scan
  final isScanActive = scan != null && scan.isActive;

  // 2. Active jobs (uploading, queued, running, downloading)
  final activeJobs = jobs.where((j) {
    return j.status == 'uploading' ||
        j.status == 'queued' ||
        j.status == 'running' ||
        j.status == 'downloading';
  }).toList();

  // 3. Unacknowledged failures
  final unacknowledgedFailedJobs = jobs.where((j) {
    return (j.status == 'failed' || j.status == 'lost') && !j.acknowledged;
  }).toList();

  final int scanCount = isScanActive ? 1 : 0;
  final int activeJobCount = activeJobs.length;
  final int totalActiveCount = scanCount + activeJobCount;

  if (totalActiveCount > 1) {
    String primary;
    if (isScanActive) {
      primary = 'Scanning (${scan.done}/${scan.total})';
    } else {
      final first = activeJobs.first;
      primary = '${first.type} ${(first.progress * 100).toInt()}%';
    }
    return ActivityMultiple(
      primaryDescription: primary,
      extraCount: totalActiveCount - 1,
    );
  }

  if (isScanActive) {
    return ActivityScanning(
      done: scan.done,
      total: scan.total,
      phase: scan.phase,
    );
  }

  if (activeJobs.isNotEmpty) {
    final job = activeJobs.first;
    return ActivityJob(
      id: job.id,
      type: job.type,
      progress: job.progress,
      status: job.status,
    );
  }

  if (unacknowledgedFailedJobs.isNotEmpty) {
    final failed = unacknowledgedFailedJobs.first;
    return ActivityFailed(
      message: failed.error ?? 'Job failed',
      jobId: failed.id,
    );
  }

  return const ActivityIdle();
});
