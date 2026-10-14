import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../scan/scan_progress_card.dart';

/// S03 - Home: PC status chip, library stats from the local database, entry points.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status =
        ref.watch(serverStatusProvider).value ?? const ServerChecking();
    final stats = ref.watch(libraryStatsProvider).value ?? const LibraryStats();
    final serverName = ref.watch(sessionProvider)?.name ?? '';
    final review = ref.watch(reviewCountsProvider).value?.total ?? 0;
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final last = settings.lastBackupAt;
    final backupDue =
        !stats.isEmpty &&
        (last == null ||
            DateTime.now().difference(last) > const Duration(days: 14));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _StatusChip(
              status: status,
              serverName: serverName,
              onTap: () => ref.invalidate(serverStatusProvider),
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('home-menu'),
            onSelected: (value) {
              if (value == 'settings') context.push(Routes.settings);
              if (value == 'forget') _confirmForget(context, ref, serverName);
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'settings', child: Text(l10n.settings)),
              PopupMenuItem(value: 'forget', child: Text(l10n.forgetPc)),
            ],
          ),
        ],
      ),
      body: ListView(
        key: const Key('home-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _StatusBanner(
            status: status,
            onPairAgain: () => ref.read(sessionProvider.notifier).forget(),
          ),
          _StatsGrid(stats: stats),
          Card(
            child: ListTile(
              key: const Key('open-insights'),
              leading: const Icon(Icons.insights_outlined),
              title: Text(l10n.insightsTitle),
              subtitle: Text(l10n.insightsHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.insights),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.unsortedFaces(stats.unsorted),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          const ScanProgressCard(),
          if (stats.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l10n.emptyLibraryTitle),
                subtitle: Text(l10n.emptyLibraryBody),
              ),
            ),
          Card(
            child: ListTile(
              key: const Key('scan-library'),
              leading: const Icon(Icons.document_scanner_outlined),
              title: Text(l10n.scanLibrary),
              subtitle: Text(l10n.scanLibraryHint),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.sources),
            ),
          ),
          if (review > 0)
            Card(
              child: ListTile(
                key: const Key('needs-review'),
                leading: const Icon(Icons.fact_check_outlined),
                title: Text(l10n.needsReview(review)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.review),
              ),
            ),
          if (backupDue)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                key: const Key('backup-reminder'),
                leading: const Icon(Icons.backup_outlined),
                title: Text(
                  last == null
                      ? l10n.backupReminderNever
                      : l10n.backupReminderOld,
                ),
                subtitle: Text(l10n.backupReminderBody),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.backup),
              ),
            ),
          Card(
            child: ListTile(
              key: const Key('try-detection'),
              leading: const Icon(Icons.face_retouching_natural),
              title: Text(l10n.tryDetectionTitle),
              subtitle: Text(l10n.tryDetectionBody),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.analyze),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('home-jobs'),
              leading: const Icon(Icons.pending_actions_outlined),
              title: Text(
                '${l10n.navJobs} (${(ref.watch(jobsProvider).value ?? const []).where((j) => !const ['completed', 'failed', 'lost'].contains(j.status)).length})',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(Routes.jobs),
            ),
          ),
          Card(
            child: ListTile(
              key: const Key('home-results'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(
                '${l10n.privateResults} (${(ref.watch(resultsProvider).value ?? const []).length})',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.results),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForget(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.forgetPcTitle(name)),
        content: Text(l10n.forgetPcBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.forgetPcConfirm),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionProvider.notifier).forget();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.serverName,
    required this.onTap,
  });

  final ServerStatus status;
  final String serverName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (Color color, String label) = switch (status) {
      ServerChecking() => (scheme.outline, l10n.homeStatusChecking),
      ServerReady(:final capabilities) => (
        Colors.green,
        l10n.homeStatusConnected(capabilities.name),
      ),
      ServerBusy(:final capabilities) => (
        Colors.amber,
        l10n.homeStatusBusy(capabilities.name),
      ),
      ServerOffline() => (scheme.error, l10n.homeStatusOffline),
      ServerRevoked() => (scheme.error, l10n.homeStatusRevoked),
    };
    return Tooltip(
      message: l10n.homeStatusTooltip,
      child: ActionChip(
        key: const Key('status-chip'),
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(label),
        onPressed: onTap,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.onPairAgain});

  final ServerStatus status;
  final VoidCallback onPairAgain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, String? text) = switch (status) {
      ServerBusy(:final busy) => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        l10n.homeBusyBanner(busy.jobType),
      ),
      ServerOffline() => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        l10n.homeOfflineBanner,
      ),
      ServerRevoked() => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        l10n.homeRevokedBanner,
      ),
      _ => (scheme.surface, scheme.onSurface, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  key: const Key('status-banner'),
                  style: TextStyle(color: fg),
                ),
              ),
              if (status is ServerRevoked)
                TextButton(
                  onPressed: onPairAgain,
                  child: Text(l10n.homePairAgain),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = [
      (l10n.statPeople, stats.people, Icons.people_outline),
      (l10n.statFaces, stats.faces, Icons.face_outlined),
      (l10n.statPhotos, stats.photos, Icons.photo_outlined),
      (l10n.statVideos, stats.videos, Icons.videocam_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.1,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        for (final (label, value, icon) in tiles)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$value',
                        key: Key('stat-$label'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
