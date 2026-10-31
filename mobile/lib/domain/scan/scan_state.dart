import 'dart:typed_data';

import 'video_scan_progress.dart';

enum ScanPhase {
  idle, // nothing running
  preparing, // listing the photos of the chosen albums
  running, // analysing photos
  waiting, // the PC is busy / unreachable: retrying
  paused, // stopped - [PauseReason] says why
  completed, // the queue is empty
}

enum PauseReason {
  user,
  noAccess, // photo permission missing
  noAlbums, // no album chosen
  notPaired,
  pcBusy, // the GPU stayed busy for minutes
  offline, // the PC could not be reached
  revoked, // the PC no longer accepts this phone
  modelMismatch, // the PC embeds with another model than this library
  error,
}

/// What the Sources screen, the progress sheet, Home and the notification show.
class ScanProgress {
  const ScanProgress({
    this.phase = ScanPhase.idle,
    this.pauseReason,
    this.message,
    this.found = 0,
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.facesFound = 0,
    this.facesLinked = 0,
    this.bodiesFound = 0,
    this.charactersFound = 0,
    this.eta,
    this.startedAt,
    this.grouping = false,
    this.currentAssetId,
    this.currentKind,
    this.previewBytes,
    this.previewTimestampMs,
    this.video,
  });

  final ScanPhase phase;
  final PauseReason? pauseReason;
  final String? message; // detail for errors / waiting
  final int found; // photos seen in the chosen albums while preparing
  final int total; // photos queued for this run
  final int done;
  final int failed;
  final int facesFound; // new faces stored during this run
  final int facesLinked; // faces recognised as ones the library already had
  final int bodiesFound;
  final int charactersFound;
  final Duration? eta;
  final DateTime? startedAt;
  final bool grouping; // the PC is sorting faces into people right now
  final String? currentAssetId;
  final String? currentKind;
  final Uint8List? previewBytes;
  final int? previewTimestampMs;
  final VideoScanProgress? video;

  bool get isActive =>
      phase == ScanPhase.preparing ||
      phase == ScanPhase.running ||
      phase == ScanPhase.waiting;

  double? get fraction =>
      total <= 0 ? null : ((done + failed) / total).clamp(0.0, 1.0);

  ScanProgress copyWith({
    ScanPhase? phase,
    PauseReason? pauseReason,
    bool clearPauseReason = false,
    String? message,
    bool clearMessage = false,
    int? found,
    int? total,
    int? done,
    int? failed,
    int? facesFound,
    int? facesLinked,
    int? bodiesFound,
    int? charactersFound,
    Duration? eta,
    bool clearEta = false,
    DateTime? startedAt,
    bool? grouping,
    String? currentAssetId,
    String? currentKind,
    Uint8List? previewBytes,
    int? previewTimestampMs,
    bool clearPreview = false,
    VideoScanProgress? video,
    bool clearVideo = false,
  }) => ScanProgress(
    phase: phase ?? this.phase,
    pauseReason: clearPauseReason ? null : (pauseReason ?? this.pauseReason),
    message: clearMessage ? null : (message ?? this.message),
    found: found ?? this.found,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    facesFound: facesFound ?? this.facesFound,
    facesLinked: facesLinked ?? this.facesLinked,
    bodiesFound: bodiesFound ?? this.bodiesFound,
    charactersFound: charactersFound ?? this.charactersFound,
    eta: clearEta ? null : (eta ?? this.eta),
    startedAt: startedAt ?? this.startedAt,
    grouping: grouping ?? this.grouping,
    currentAssetId: clearPreview
        ? null
        : (currentAssetId ?? this.currentAssetId),
    currentKind: clearPreview ? null : (currentKind ?? this.currentKind),
    previewBytes: clearPreview ? null : (previewBytes ?? this.previewBytes),
    previewTimestampMs: clearPreview
        ? null
        : (previewTimestampMs ?? this.previewTimestampMs),
    video: clearVideo ? null : (video ?? this.video),
  );
}

/// Keeps the app process alive while a scan runs with the screen off (an Android foreground
/// service with a progress notification). The scan itself runs in the app's own isolate.
abstract interface class ScanKeepAlive {
  Future<void> start({required String title, required String text});
  Future<void> update(String text);
  Future<void> stop();
}

class NoKeepAlive implements ScanKeepAlive {
  const NoKeepAlive();

  @override
  Future<void> start({required String title, required String text}) async {}

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> stop() async {}
}
