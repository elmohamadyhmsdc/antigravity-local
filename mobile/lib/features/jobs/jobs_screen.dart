import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../studio_providers.dart';
import '../../domain/jobs/job_progress.dart';
import 'package:intl/intl.dart';
import '../shared/empty_state.dart';

String jobStatusLabel(AppLocalizations l10n, String status) => switch (status) {
  'uploading' => l10n.statusUploading,
  'queued' => l10n.statusQueued,
  'running' => l10n.statusRunning,
  'paused' => l10n.statusPaused,
  'downloading' => l10n.statusDownloading,
  'completed' => l10n.statusCompleted,
  'failed' => l10n.statusFailed,
  _ => l10n.statusLost,
};
String jobTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'undress_image' => l10n.restyleTitle,
  'build_lora_dataset' => l10n.loraDatasetBuild,
  'train_lora' => l10n.loraTrain,
  'generate_lora_images' => l10n.loraGenerate,
  _ =>
    '${l10n.refaceTitle} · ${type.contains('video') ? l10n.resultVideo : l10n.resultPhoto} · ${type.endsWith('v2')
        ? l10n.refaceLegacy
        : type.endsWith('dfm')
        ? l10n.refacePro
        : l10n.refaceHd}',
};

class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navJobs),
        actions: [
          IconButton(
            tooltip: l10n.jobSync,
            onPressed: () => ref.read(jobTrackerProvider).start(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ref
          .watch(jobsProvider)
          .when(
            loading: () => const LoadingBox(),
            error: (e, _) => Center(child: Text('$e')),
            data: (jobs) => jobs.isEmpty
                ? EmptyState(
                    icon: Icons.pending_actions_outlined,
                    title: l10n.jobsEmpty,
                    body: l10n.jobsEmptyHint,
                    actionLabel: l10n.refaceTitle,
                    onAction: () => context.push(Routes.reface),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final states in const [
                        ['uploading', 'running', 'downloading'],
                        ['queued'],
                        ['paused'],
                        ['failed', 'lost'],
                        ['completed'],
                      ])
                        if (jobs.any((j) => states.contains(j.status))) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              jobStatusLabel(l10n, states.first),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          for (final job in jobs.where(
                            (j) => states.contains(j.status),
                          ))
                            _JobTile(job: job),
                        ],
                    ],
                  ),
          ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});
  final JobRow job;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: ListTile(
        key: Key('job-${job.id}'),
        leading: Icon(
          job.status == 'completed'
              ? Icons.check_circle_outline
              : Icons.pending_actions,
        ),
        title: Text(jobTypeLabel(l10n, job.type)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${jobStatusLabel(l10n, job.status)} · ${(job.progress * 100).round()}%',
            ),
            if (!const [
              'completed',
              'failed',
              'lost',
              'paused',
            ].contains(job.status))
              LinearProgressIndicator(value: job.progress),
            if (job.error != null)
              Text(job.error!, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('${Routes.jobs}/${job.id}'),
      ),
    );
  }
}

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.id});
  final String id;

  Future<void> _action(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.jobDetails)),
      body: ref
          .watch(jobProvider(id))
          .when(
            loading: () => const LoadingBox(),
            error: (e, _) => Center(child: Text('$e')),
            data: (job) {
              if (job == null) {
                return EmptyState(
                  icon: Icons.pending_actions_outlined,
                  title: l10n.jobsEmpty,
                );
              }
              final tracker = ref.read(jobTrackerProvider);
              final progress = JobProgress(job.detailsJson);
              final remaining = progress.remaining(job.status);
              final detailLabels = {
                'stage': l10n.jobStage,
                'epoch': l10n.jobEpoch,
                'total_epochs': l10n.jobTotalEpochs,
                'step': l10n.jobStep,
                'total_steps': l10n.jobTotalSteps,
                'loss': l10n.jobLoss,
                'seconds_per_step': l10n.jobSecondsPerStep,
              };
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    jobTypeLabel(l10n, job.type),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    jobStatusLabel(l10n, job.status),
                    key: const Key('job-status'),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: job.progress),
                  Text('${(job.progress * 100).round()}%'),
                  if (job.message?.isNotEmpty == true) Text(job.message!),
                  if (remaining != null)
                    Text(
                      l10n.jobTimeRemaining(
                        remaining.inHours > 0
                            ? l10n.jobHoursMinutes(
                                remaining.inHours,
                                remaining.inMinutes % 60,
                              )
                            : l10n.jobMinutes(
                                remaining.inMinutes +
                                    (remaining.inSeconds % 60 > 0 ? 1 : 0),
                              ),
                      ),
                      key: const Key('job-eta'),
                    ),
                  if (progress.details.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(l10n.trainingDetails),
                    for (final entry in progress.details.entries)
                      if (detailLabels.containsKey(entry.key))
                        Text('${detailLabels[entry.key]}: ${entry.value}'),
                  ],
                  ref
                      .watch(jobEventsProvider(id))
                      .when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (events) => events.isEmpty
                            ? const SizedBox.shrink()
                            : ExpansionTile(
                                key: const Key('job-history'),
                                tilePadding: EdgeInsets.zero,
                                title: Text(l10n.jobHistory),
                                children: [
                                  for (final event in events)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        jobStatusLabel(l10n, event.status),
                                      ),
                                      subtitle: Text(
                                        [
                                          DateFormat.yMd().add_Hms().format(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              event.createdAt,
                                            ),
                                          ),
                                          if (event.message?.isNotEmpty == true)
                                            event.message!,
                                        ].join('\n'),
                                      ),
                                    ),
                                ],
                              ),
                      ),
                  if (job.error != null) ...[
                    const SizedBox(height: 16),
                    Text(job.error!),
                    Text(l10n.jobErrorHint),
                  ],
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (const [
                        'uploading',
                        'running',
                        'queued',
                        'downloading',
                      ].contains(job.status))
                        OutlinedButton.icon(
                          key: const Key('job-pause'),
                          onPressed: () =>
                              _action(context, () => tracker.pause(job)),
                          icon: const Icon(Icons.pause),
                          label: Text(l10n.jobPause),
                        ),
                      if (const [
                        'paused',
                        'failed',
                        'lost',
                      ].contains(job.status))
                        FilledButton.icon(
                          key: const Key('job-resume'),
                          onPressed: () =>
                              _action(context, () => tracker.resume(job)),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            job.status == 'paused'
                                ? l10n.jobResume
                                : l10n.jobRetry,
                          ),
                        ),
                      if (job.status == 'completed')
                        FilledButton.icon(
                          key: const Key('job-result'),
                          onPressed: () =>
                              context.push('${Routes.results}/${job.id}'),
                          icon: const Icon(Icons.photo),
                          label: Text(l10n.jobResult),
                        ),
                      if (const [
                        'completed',
                        'paused',
                        'failed',
                        'lost',
                      ].contains(job.status))
                        TextButton.icon(
                          onPressed: () => _action(context, () async {
                            if (!await confirm(
                              context,
                              title: l10n.jobRemove,
                              body: l10n.jobRemoveBody,
                              confirmLabel: l10n.jobRemove,
                              cancelLabel: l10n.cancel,
                              destructive: true,
                            )) {
                              return;
                            }
                            await tracker.remove(job);
                            if (context.mounted) leave(context, Routes.jobs);
                          }),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(l10n.jobRemove),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
    );
  }
}
