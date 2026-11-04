import '../shared/image_preview.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../settings/background_screen.dart';
import '../../data/platform/background_execution.dart';
import 'video_scan_details.dart';

String _eta(AppLocalizations l10n, Duration d) {
  if (d.inSeconds < 90) return l10n.etaSeconds(d.inSeconds.clamp(5, 90));
  if (d.inMinutes < 90) return l10n.etaMinutes(d.inMinutes);
  return l10n.etaHours(d.inHours, d.inMinutes % 60);
}

String pauseReasonText(AppLocalizations l10n, ScanProgress p) =>
    switch (p.pauseReason) {
      PauseReason.user || null => l10n.scanPausedUser,
      PauseReason.noAccess => l10n.scanNoAccess,
      PauseReason.noAlbums => l10n.scanNoAlbums,
      PauseReason.notPaired => l10n.scanNotPaired,
      PauseReason.pcBusy => l10n.scanPcBusy,
      PauseReason.offline => l10n.scanOffline,
      PauseReason.revoked => l10n.scanRevoked,
      PauseReason.modelMismatch => l10n.scanModelMismatch,
      PauseReason.error => l10n.scanError(p.message ?? ''),
    };

/// The scan's live state: progress, faces found, ETA, pause / resume. Used on the Sources screen, in
/// the progress sheet and on Home.
class ScanProgressCard extends ConsumerWidget {
  const ScanProgressCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progress =
        ref.watch(scanProgressProvider).value ?? const ScanProgress();
    final engine = ref.read(scanEngineProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (progress.phase == ScanPhase.idle) return const SizedBox.shrink();

    final processed = progress.done + progress.failed;
    final bgStatus = ref.watch(backgroundStatusProvider).value;
    final showBatteryNotice =
        bgStatus != null &&
        bgStatus.supported &&
        !bgStatus.unrestricted &&
        (progress.phase == ScanPhase.running ||
            progress.phase == ScanPhase.preparing ||
            progress.phase == ScanPhase.waiting ||
            (progress.phase == ScanPhase.paused &&
                progress.pauseReason == PauseReason.offline));
    final video = progress.video;
    final faces = progress.facesFound + (video?.facesFound ?? 0);
    final itemsText = video == null
        ? l10n.scanPhotosOf(processed, progress.total)
        : l10n.scanItemsOf(processed, progress.total);
    final lines = <String>[];
    Widget? action;
    var dismissible = false;
    String headline;
    double? value = progress.fraction;

    switch (progress.phase) {
      case ScanPhase.idle:
        return const SizedBox.shrink();
      case ScanPhase.preparing:
        headline = l10n.scanPreparing;
        if (progress.found > 0) lines.add(l10n.scanFound(progress.found));
        value = null;
        action = TextButton(
          key: const Key('scan-pause'),
          onPressed: progress.pausing ? null : engine.pause,
          child: Text(progress.pausing ? 'Pausing…' : l10n.pause),
        );
      case ScanPhase.running:
        headline = progress.grouping
            ? l10n.scanSorting
            : video != null
            ? videoStageTitle(l10n, video)
            : l10n.scanRunning;
        if (progress.message != null && video == null) {
          lines.add(progress.message!);
        }
        lines.add(itemsText);
        lines.add(l10n.scanFacesFound(faces));
        if (progress.facesLinked > 0) {
          lines.add(l10n.scanFacesLinked(progress.facesLinked));
        }
        if (progress.failed > 0) {
          lines.add(l10n.scanFailedCount(progress.failed));
        }
        if (progress.eta != null && video == null) {
          lines.add(_eta(l10n, progress.eta!));
        }
        action = TextButton(
          key: const Key('scan-pause'),
          onPressed: progress.pausing ? null : engine.pause,
          child: Text(progress.pausing ? 'Pausing…' : l10n.pause),
        );
      case ScanPhase.waiting:
        headline = l10n.scanWaiting;
        lines.add(progress.message ?? l10n.gpuBusyMessage);
        lines.add(itemsText);
        action = TextButton(
          key: const Key('scan-pause'),
          onPressed: progress.pausing ? null : engine.pause,
          child: Text(progress.pausing ? 'Pausing…' : l10n.pause),
        );
      case ScanPhase.paused:
        headline = l10n.scanPaused;
        lines.add(pauseReasonText(l10n, progress));
        if (progress.total > 0) {
          lines.add(itemsText);
        }
        final reason = progress.pauseReason;
        if (reason == PauseReason.noAlbums) {
          action = TextButton(
            onPressed: () => context.push(Routes.sources),
            child: Text(l10n.chooseAlbums),
          );
        } else if (reason == PauseReason.revoked ||
            reason == PauseReason.notPaired) {
          action = TextButton(
            onPressed: () => context.push(Routes.connection),
            child: const Text('Connect PC'),
          );
        } else {
          action = FilledButton(
            key: const Key('scan-resume'),
            onPressed: () => startScan(ref, enumerate: false),
            child: Text(l10n.resume),
          );
        }
      case ScanPhase.completed:
        headline = l10n.scanDone;
        lines.add(l10n.scanSummary(progress.done, progress.facesFound));
        if (progress.failed > 0) {
          lines.add(l10n.scanFailedCount(progress.failed));
        }
        value = 1;
        dismissible = true;
        final review = ref.watch(reviewCountsProvider).value?.total ?? 0;
        if (review > 0) {
          action = FilledButton.tonal(
            key: const Key('scan-open-review'),
            onPressed: () => context.push(Routes.review),
            child: Text(l10n.reviewDecisions(review)),
          );
        }
    }

    if (progress.charactersFound + (video?.charactersFound ?? 0) > 0) {
      lines.add(
        l10n.charactersFound(
          progress.charactersFound + (video?.charactersFound ?? 0),
        ),
      );
    }
    return Card(
      key: const Key('scan-progress-card'),
      margin: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: 8),
      color: progress.phase == ScanPhase.paused
          ? scheme.tertiaryContainer.withValues(alpha: 0.5)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (progress.phase == ScanPhase.running ||
                    progress.phase == ScanPhase.preparing ||
                    progress.phase == ScanPhase.waiting)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Expanded(child: Text(headline, style: text.titleMedium)),
                ?action,
                if (dismissible)
                  IconButton(
                    key: const Key('scan-dismiss'),
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: engine.dismiss,
                  ),
              ],
            ),
            if (progress.currentAssetId != null && !progress.grouping)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: _ScanMediaPreview(
                  key: ValueKey(progress.currentAssetId),
                  progress: progress,
                  height: compact ? 140 : 180,
                ),
              ),
            if (video != null && !progress.grouping)
              VideoScanDetails(
                progress: video,
                active: progress.phase == ScanPhase.running,
              ),
            if (progress.phase != ScanPhase.paused || (progress.total > 0))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(
                  key: const Key('scan-progress-bar'),
                  value: value,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            for (final line in lines) Text(line, style: text.bodyMedium),
            if (showBatteryNotice)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  key: const Key('scan-battery-warning'),
                  onTap: () async {
                    await prepareBackgroundForWork(
                      context,
                      ref,
                      forcePrompt: true,
                    );
                    ref.invalidate(backgroundStatusProvider);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.battery_alert_outlined,
                          color: scheme.error,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.backgroundBatteryWarning,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.backgroundEnable,
                          style: text.labelSmall?.copyWith(
                            color: scheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScanMediaPreview extends ConsumerWidget {
  const _ScanMediaPreview({
    super.key,
    required this.progress,
    required this.height,
  });

  final ScanProgress progress;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final video = progress.currentKind == 'video';
    final milliseconds = progress.previewTimestampMs;
    final timestamp = milliseconds == null
        ? ''
        : ' · ${videoTime(Duration(milliseconds: milliseconds))}';
    final label =
        '${video ? l10n.scanCurrentVideo : l10n.scanCurrentPhoto}$timestamp';
    Widget image(List<int>? bytes) => bytes == null
        ? Center(
            child: Icon(video ? Icons.movie_outlined : Icons.photo_outlined),
          )
        : PreviewImage.memory(
            // Both the phone JPEG and the server frame stay in memory only.
            bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            fit: BoxFit.contain,
            cacheWidth: 480,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                Center(child: Text(l10n.scanPreviewUnavailable)),
          );
    return Semantics(
      label: label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const Key('scan-media-preview'),
              height: height,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: progress.previewBytes != null
                    ? image(progress.previewBytes)
                    : FutureBuilder(
                        future: ref
                            .read(thumbnailServiceProvider)
                            .get(progress.currentAssetId!, size: 480),
                        builder: (context, snapshot) => image(snapshot.data),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The progress as a sheet (Home's "Scanning..." tile opens it).
Future<void> showScanProgressSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ScanProgressCard(compact: true),
          ),
        ),
      ),
    );

/// Starts a scan from anywhere (Home, Library): needs a paired PC, otherwise explains.
Future<void> startScan(
  WidgetRef ref, {
  bool enumerate = true,
  Set<String>? albumIds,
}) async {
  final engine = ref.read(scanEngineProvider);
  if (engine.isRunning) return;
  if (ref.read(mobileApiProvider) == null) {
    if (ref.context.mounted) ref.context.push(Routes.connection);
    return;
  }
  await prepareBackgroundForWork(ref.context, ref);
  if (!ref.context.mounted) return;
  unawaited(engine.start(enumerate: enumerate, albumIds: albumIds));
}

/// A dedicated view of the live analysis, including video stages and controls.
class RunningScanScreen extends ConsumerWidget {
  const RunningScanScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope =
        ref.watch(settingsProvider).value?.scanScopeAlbumIds ??
        const <String>[];
    final albums = ref.watch(albumsProvider).value ?? const [];
    final names = [
      for (final id in scope)
        for (final album in albums)
          if (album.id == id) album.name,
    ];
    final repo = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Library analysis')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ScanProgressCard(compact: true),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Analysis scope'),
            subtitle: Text(names.isEmpty ? 'Current queue' : names.join(', ')),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Scan settings'),
            onTap: () => context.push(Routes.sources),
          ),
          StreamBuilder(
            stream: repo.watchFailedMedia(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const [];
              if (snapshot.hasError) {
                return const Text('Could not load failed items');
              }
              if (rows.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Failed items',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await repo.requeueFailed();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Items queued for analysis.'),
                              ),
                            );
                          }
                        },
                        child: const Text('Retry all'),
                      ),
                    ],
                  ),
                  for (final row in rows)
                    ListTile(
                      leading: Icon(
                        row.kind == 'video'
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                      ),
                      title: Text(row.kind == 'video' ? 'Video' : 'Photo'),
                      subtitle: Text(row.scanError ?? 'Analysis failed'),
                      onTap: () => context.push('${Routes.media}/${row.id}'),
                      trailing: IconButton(
                        tooltip: 'Retry',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await repo.requeueFailed(mediaIds: [row.id]);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Item queued for analysis.'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
