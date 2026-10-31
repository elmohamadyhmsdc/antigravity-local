import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/scan/video_scan_progress.dart';
import '../../l10n/app_localizations.dart';

String videoStageTitle(AppLocalizations l10n, VideoScanProgress video) {
  final percent = ((video.fraction ?? 0) * 100).floor().clamp(0, 100);
  return switch (video.stage) {
    VideoScanStage.prepare =>
      video.fraction == null ? l10n.videoOpening : l10n.videoPreparing(percent),
    VideoScanStage.upload => l10n.videoUploading(percent),
    VideoScanStage.queue => l10n.videoWaiting,
    VideoScanStage.analyze => l10n.videoAnalyzing(percent),
    VideoScanStage.download => l10n.videoDownloading,
    VideoScanStage.verify => l10n.videoVerifying,
    VideoScanStage.importing => l10n.videoImporting,
    VideoScanStage.finish => l10n.videoFinishing,
  };
}

String videoTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 40);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600
      ? '${seconds ~/ 3600}:$minutes:$tail'
      : '${seconds ~/ 60}:$tail';
}

String _bytes(num value) {
  if (value >= 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (value >= 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${value.round()} B';
}

/// Always visible, including in the compact progress sheet. A local clock keeps
/// elapsed time and stale-update feedback moving while a network call is pending.
class VideoScanDetails extends StatefulWidget {
  const VideoScanDetails({
    super.key,
    required this.progress,
    required this.active,
  });
  final VideoScanProgress progress;
  final bool active;

  @override
  State<VideoScanDetails> createState() => _VideoScanDetailsState();
}

class _VideoScanDetailsState extends State<VideoScanDetails> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(VideoScanDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _syncTimer();
  }

  void _syncTimer() {
    _timer?.cancel();
    if (widget.active) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.progress;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = widget.active ? DateTime.now() : v.updatedAt;
    final step = switch (v.stage) {
      VideoScanStage.prepare => 0,
      VideoScanStage.upload => 1,
      VideoScanStage.queue || VideoScanStage.analyze => 2,
      _ => 3,
    };
    final explanation = switch (v.stage) {
      VideoScanStage.prepare => l10n.videoPrepareDetail,
      VideoScanStage.upload =>
        v.fraction == 1 ? l10n.videoUploadConfirming : l10n.videoUploadDetail,
      VideoScanStage.queue => l10n.videoQueueDetail,
      VideoScanStage.analyze => switch (v.serverStage) {
        'decode' => l10n.videoDecodeDetail,
        'inference' => l10n.videoInferenceDetail,
        _ => l10n.videoAnalyzeDetail,
      },
      VideoScanStage.download => l10n.videoDownloadDetail,
      VideoScanStage.verify => l10n.videoVerifyDetail,
      VideoScanStage.importing => l10n.videoImportDetail,
      VideoScanStage.finish => l10n.videoFinishDetail,
    };
    final freshness = now.difference(v.updatedAt).inSeconds.clamp(0, 1 << 30);
    final serverAge = v.serverUpdatedAt == null
        ? null
        : now.difference(v.serverUpdatedAt!).inSeconds.clamp(0, 1 << 30);

    Widget metric(String label, String value, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 2,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    return Column(
      key: const Key('video-scan-details'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final (index, label) in [
              l10n.videoStepPrepare,
              l10n.videoStepUpload,
              l10n.videoStepAnalyze,
              l10n.videoStepSave,
            ].indexed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    index < step
                        ? Icons.check_circle
                        : index == step
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: index <= step
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: index == step
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: Text(explanation, style: theme.textTheme.bodyMedium),
        ),
        if (!widget.active)
          Text(l10n.videoLastRecorded, style: theme.textTheme.labelSmall),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          key: const Key('video-stage-progress'),
          value: v.fraction?.clamp(0.0, 1.0) ?? (widget.active ? null : 0),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        if (v.fraction != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.videoStagePercent((v.fraction! * 100).floor().clamp(0, 100)),
              style: theme.textTheme.labelSmall,
            ),
          ),
        if (v.fileName != null) metric(l10n.videoFile, v.fileName!),
        if (v.fileBytes != null || (v.width != null && v.height != null))
          metric(
            l10n.videoSource,
            [
              if (v.fileBytes != null) _bytes(v.fileBytes!),
              if ((v.width ?? 0) > 0 && (v.height ?? 0) > 0)
                '${v.width} × ${v.height}',
            ].join(' · '),
          ),
        metric(l10n.videoElapsed, videoTime(now.difference(v.startedAt))),
        metric(
          l10n.videoStageElapsed,
          videoTime(now.difference(v.stageStartedAt)),
        ),
        if (v.processedBytes != null && v.totalBytes != null)
          metric(
            v.stage == VideoScanStage.prepare
                ? l10n.videoBytesRead
                : v.stage == VideoScanStage.download
                ? l10n.videoBytesReceived
                : l10n.videoBytesSent,
            '${_bytes(v.processedBytes!)} / ${_bytes(v.totalBytes!)}',
          ),
        if (widget.active && v.bytesPerSecond != null && freshness < 5)
          metric(l10n.videoTransferSpeed, '${_bytes(v.bytesPerSecond!)}/s'),
        if (widget.active &&
            (v.stage == VideoScanStage.upload ||
                v.stage == VideoScanStage.download ||
                v.stage == VideoScanStage.analyze))
          metric(
            l10n.videoStageRemaining,
            v.eta == null || freshness >= 15
                ? l10n.videoMeasuring
                : l10n.videoApproximate(videoTime(v.eta!)),
          ),
        if (v.durationMs != null && v.durationMs! > 0)
          metric(
            l10n.videoPosition,
            '${videoTime(Duration(milliseconds: v.analyzedTimestampMs ?? 0))} / ${videoTime(Duration(milliseconds: v.durationMs!))}',
          ),
        if (v.framesDone != null)
          metric(
            l10n.videoSamplesAnalyzed,
            v.totalSamples == null
                ? '${v.framesDone}'
                : '${v.framesDone! + v.skippedSamples} / ${v.totalSamples}',
          ),
        if (v.frameInterval != null)
          metric(
            l10n.videoSampling,
            l10n.videoSamplingSeconds(v.frameInterval!.toStringAsFixed(2)),
          ),
        if (v.incrementalResults || v.framesSaved > 0) ...[
          const SizedBox(height: 10),
          Text(l10n.videoLiveSaving, style: theme.textTheme.bodySmall),
          metric(l10n.videoSavedSamples, '${v.framesSaved}'),
          metric(
            l10n.videoLiveDetections,
            l10n.videoDetectionCounts(
              v.facesFound,
              v.bodiesFound,
              v.charactersFound,
            ),
          ),
        ],
        if (v.skippedSamples > 0)
          metric(l10n.videoSkippedSamples, '${v.skippedSamples}'),
        if (v.serverMessage != null && v.stage == VideoScanStage.queue)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(v.serverMessage!, style: theme.textTheme.bodyMedium),
          ),
        if (v.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              v.warning!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (serverAge != null &&
            (v.stage == VideoScanStage.queue ||
                v.stage == VideoScanStage.analyze ||
                v.stage == VideoScanStage.finish))
          metric(l10n.videoPcUpdate, l10n.videoSecondsAgo(serverAge)),
        if (widget.active && freshness >= 15)
          Padding(
            key: const Key('video-awaiting-update'),
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              l10n.videoAwaitingUpdate(freshness),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 12),
        const Divider(),
        Text(l10n.videoLibraryProgress, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
