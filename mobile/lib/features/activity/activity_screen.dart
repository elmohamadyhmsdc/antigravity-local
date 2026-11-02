import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../ui/collection/segmented_bar.dart';
import '../../ui/scaffolds/sheet_scaffold.dart';
import '../../ui/sheets/confirm_sheet.dart';
import '../../ui/states/empty_state.dart';
import '../../ui/states/progress_card.dart';
import '../jobs/jobs_screen.dart' show jobStatusLabel, jobTypeLabel;
import '../shared/empty_state.dart' show LoadingBox, RetryState;

/// A1 — Unified Activity Screen (Now || History).
/// The single home for observing library scans and background AI jobs.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.initialTab = 0});

  final int initialTab; // 0 = Now, 1 = History

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late int _selectedTab;
  int _historyFilter = 0; // 0 = All, 1 = Completed, 2 = Failed

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  Future<void> _clearFinished(WidgetRef ref) async {
    final confirmed = await ConfirmSheet.show(
      context: context,
      title: 'Clear finished tasks',
      message: 'Remove all completed and failed tasks from the history?',
      confirmLabel: 'Clear',
      isDanger: false,
    );
    if (confirmed != true || !mounted) return;

    final jobs = ref.read(jobsProvider).value ?? const [];
    final tracker = ref.read(jobTrackerProvider);
    for (final job in jobs) {
      if (['completed', 'failed', 'lost'].contains(job.status)) {
        await tracker.remove(job);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scan = ref.watch(scanProgressProvider).value;
    final jobsAsync = ref.watch(jobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeActivity),
        actions: [
          if (_selectedTab == 1)
            IconButton(
              tooltip: 'Clear finished tasks',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _clearFinished(ref),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedBar<int>(
              segments: const [
                SegmentItem(
                  value: 0,
                  label: 'Now',
                  icon: Icons.pending_actions,
                ),
                SegmentItem(value: 1, label: 'History', icon: Icons.history),
              ],
              selected: _selectedTab,
              onSelected: (i) => setState(() => _selectedTab = i),
            ),
          ),
          Expanded(
            child: jobsAsync.when(
              loading: () => const LoadingBox(),
              error: (_, _) => RetryState(
                onRetry: () {
                  ref.invalidate(jobsProvider);
                  ref.invalidate(scanProgressProvider);
                },
              ),
              data: (jobs) => _selectedTab == 0
                  ? _buildNowTab(context, scan, jobs)
                  : _buildHistoryTab(context, jobs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowTab(
    BuildContext context,
    ScanProgress? scan,
    List<JobRow> jobs,
  ) {
    final l10n = AppLocalizations.of(context);
    final activeJobs = jobs.where((j) {
      return const [
        'uploading',
        'running',
        'queued',
        'downloading',
      ].contains(j.status);
    }).toList();

    final isScanActive = scan != null && scan.phase != ScanPhase.idle;

    if (!isScanActive && activeJobs.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.check_circle_outline,
          title: 'No active activity',
          subtitle:
              'Library scans and background AI tasks will show progress here.',
        ),
      );
    }

    final theme = Theme.of(context);
    final engine = ref.read(scanEngineProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 1. Library scan progress card
        if (isScanActive) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Library Scan',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          ProgressCard(
            data: ProgressCardData(
              type: ProgressCardType.scan,
              title: scan.grouping
                  ? l10n.scanSorting
                  : 'Library Face & Pose Analysis',
              subtitle:
                  '${scan.done + scan.failed} of ${scan.total} items scanned (${scan.facesFound} faces, ${scan.bodiesFound} bodies)',
              progress: scan.fraction,
              isPaused: scan.phase == ScanPhase.paused,
              onPause: scan.phase == ScanPhase.running ? engine.pause : null,
              onResume: scan.phase == ScanPhase.paused
                  ? () => engine.start(enumerate: false)
                  : null,
              onTap: () => context.push(Routes.settingsLibrary),
            ),
          ),
          if (scan.phase == ScanPhase.paused)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                scan.pauseReason == PauseReason.user
                    ? 'You paused the scan.'
                    : (scan.pauseReason?.name ?? 'Scan paused'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          StreamBuilder<List<MediaRow>>(
            stream: ref.watch(libraryRepositoryProvider).watchFailedMedia(),
            builder: (context, snapshot) {
              final failed = snapshot.data ?? const [];
              if (failed.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${failed.length} failed files',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(libraryRepositoryProvider)
                            .requeueFailed();
                      },
                      child: const Text('Retry all'),
                    ),
                  ],
                ),
              );
            },
          ),
          if (scan.failed > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.warning_amber_rounded),
                label: Text('${scan.failed} files could not be scanned'),
                onPressed: () {
                  SheetScaffold.show(
                    context: context,
                    builder: (_) => FailedItemsSheet(failedCount: scan.failed),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
        ],

        // 2. Active Background AI Tasks
        if (activeJobs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Active Tasks (${activeJobs.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final job in activeJobs)
            ProgressCard(
              data: ProgressCardData(
                type: ProgressCardType.job,
                title: jobTypeLabel(l10n, job.type),
                subtitle: jobStatusLabel(l10n, job.status),
                progress: job.progress,
                isPaused: false,
                onTap: () => context.push('${Routes.activity}/${job.id}'),
                onCancel: () async {
                  final confirmed = await ConfirmSheet.show(
                    context: context,
                    title: 'Cancel Task',
                    message:
                        'Are you sure you want to cancel this ${jobTypeLabel(l10n, job.type)} task?',
                    confirmLabel: 'Cancel Task',
                    isDanger: true,
                  );
                  if (confirmed == true) {
                    final tracker = ref.read(jobTrackerProvider);
                    await tracker.pause(job);
                    await tracker.remove(job);
                  }
                },
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context, List<JobRow> jobs) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final finishedJobs = jobs.where((j) {
      if (_historyFilter == 1) return j.status == 'completed';
      if (_historyFilter == 2) {
        return j.status == 'failed' || j.status == 'lost';
      }
      return const [
        'completed',
        'failed',
        'lost',
        'cancelled',
      ].contains(j.status);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedBar<int>(
            segments: const [
              SegmentItem(value: 0, label: 'All'),
              SegmentItem(value: 1, label: 'Completed'),
              SegmentItem(value: 2, label: 'Failed'),
            ],
            selected: _historyFilter,
            onSelected: (val) => setState(() => _historyFilter = val),
          ),
        ),
        Expanded(
          child: finishedJobs.isEmpty
              ? const Center(
                  child: EmptyState(
                    icon: Icons.history,
                    title: 'No task history',
                    subtitle: 'Finished and failed tasks will appear here.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: finishedJobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final job = finishedJobs[index];
                    final isFailed =
                        job.status == 'failed' || job.status == 'lost';
                    final isCompleted = job.status == 'completed';

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: isFailed
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          isFailed
                              ? Icons.error_outline
                              : (isCompleted
                                    ? Icons.check
                                    : Icons.hourglass_empty),
                          color: isFailed
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(jobTypeLabel(l10n, job.type)),
                      subtitle: Text(
                        '${jobStatusLabel(l10n, job.status)}${job.error != null ? ' · ${job.error}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFailed)
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: 'Retry',
                              onPressed: () async {
                                await ref.read(jobTrackerProvider).resume(job);
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () {
                              context.push('${Routes.activity}/${job.id}');
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Sheet showing failed scan items with direct retry option.
class FailedItemsSheet extends ConsumerWidget {
  const FailedItemsSheet({super.key, required this.failedCount});

  final int failedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final db = ref.watch(databaseProvider);

    return SheetScaffold(
      title: 'Failed Scan Items',
      actions: [
        FilledButton(
          onPressed: () {
            ref.read(scanEngineProvider).start(enumerate: false);
            Navigator.pop(context);
          },
          child: const Text('Retry scan'),
        ),
      ],
      child: FutureBuilder<List<MediaRow>>(
        future:
            (db.select(db.media)
                  ..where((m) => m.scanStatus.equals('failed'))
                  ..limit(50))
                .get(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No detailed error records found.',
                style: theme.textTheme.bodyMedium,
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final media = items[index];
              return ListTile(
                leading: const Icon(Icons.broken_image_outlined),
                title: Text(
                  media.assetId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  media.scanError ?? 'Scan failed',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
