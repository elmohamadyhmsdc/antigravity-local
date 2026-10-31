/// Measurements for the current video. Percentages belong to one stage only;
/// waiting and verification deliberately have no invented percentage or ETA.
enum VideoScanStage {
  prepare,
  upload,
  queue,
  analyze,
  download,
  verify,
  importing,
  finish,
}

class VideoScanProgress {
  const VideoScanProgress({
    required this.stage,
    required this.startedAt,
    required this.stageStartedAt,
    required this.updatedAt,
    this.fraction,
    this.durationMs,
    this.fileName,
    this.fileBytes,
    this.width,
    this.height,
    this.processedBytes,
    this.totalBytes,
    this.bytesPerSecond,
    this.eta,
    this.framesDone,
    this.totalSamples,
    this.analyzedTimestampMs,
    this.frameInterval,
    this.skippedSamples = 0,
    this.framesSaved = 0,
    this.facesFound = 0,
    this.bodiesFound = 0,
    this.charactersFound = 0,
    this.serverStage,
    this.serverMessage,
    this.warning,
    this.serverUpdatedAt,
    this.incrementalResults = false,
  });

  final VideoScanStage stage;
  final DateTime startedAt;
  final DateTime stageStartedAt;
  final DateTime updatedAt;
  final double? fraction;
  final int? durationMs;
  final String? fileName;
  final int? fileBytes;
  final int? width;
  final int? height;
  final int? processedBytes;
  final int? totalBytes;
  final double? bytesPerSecond;
  final Duration? eta;
  final int? framesDone;
  final int? totalSamples;
  final int? analyzedTimestampMs;
  final double? frameInterval;
  final int skippedSamples;
  final int framesSaved;
  final int facesFound;
  final int bodiesFound;
  final int charactersFound;
  final String? serverStage;
  final String? serverMessage;
  final String? warning;
  final DateTime? serverUpdatedAt;
  final bool incrementalResults;
}
