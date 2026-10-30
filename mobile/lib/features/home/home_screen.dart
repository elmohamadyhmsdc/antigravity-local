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
import '../shared/screen_layout.dart';

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
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
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
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _StatusChip(
              status: status,
              serverName: serverName,
              onTap: () => ref.invalidate(serverStatusProvider),
            ),
          ),
          const SizedBox(height: 20),
          ScreenIntro(title: l10n.homeIntro, body: l10n.homeIntroHint),
          _StatusBanner(
            status: status,
            onPairAgain: () => ref.read(sessionProvider.notifier).forget(),
          ),
          const ScanProgressCard(),
          if (review > 0)
            ActionRow(
              key: const Key('needs-review'),
              icon: Icons.fact_check_outlined,
              title: l10n.needsReview(review),
              emphasized: true,
              onTap: () => context.push(Routes.review),
            ),
          if (stats.isEmpty) ...[
            Text(
              l10n.emptyLibraryTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.emptyLibraryBody,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            key: const Key('scan-library'),
            onPressed: () => context.push(Routes.sources),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l10n.scanLibrary),
          ),
          SectionHeading(title: l10n.homeOrganize),
          _StatsGrid(stats: stats),
          const SizedBox(height: 12),
          Text(
            l10n.unsortedFaces(stats.unsorted),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SectionHeading(title: l10n.homeCreate),
          ActionRow(
            key: const Key('home-studio'),
            icon: Icons.face_retouching_natural,
            title: l10n.studioRefaceAction,
            subtitle: l10n.studioRefaceDescription,
            onTap: () => context.push(Routes.reface),
          ),
          ActionRow(
            key: const Key('home-results'),
            icon: Icons.photo_library_outlined,
            title:
                '${l10n.privateResults} (${(ref.watch(resultsProvider).value ?? const []).length})',
            onTap: () => context.push(Routes.results),
          ),
          SectionHeading(title: l10n.homeActivity),
          ActionRow(
            key: const Key('home-jobs'),
            icon: Icons.pending_actions_outlined,
            title:
                '${l10n.navJobs} (${(ref.watch(jobsProvider).value ?? const []).where((j) => !const ['completed', 'failed', 'lost'].contains(j.status)).length})',
            onTap: () => context.go(Routes.jobs),
          ),
          ActionRow(
            key: const Key('open-insights'),
            icon: Icons.insights_outlined,
            title: l10n.insightsTitle,
            subtitle: l10n.insightsHint,
            onTap: () => context.push(Routes.insights),
          ),
          if (backupDue)
            ActionRow(
              key: const Key('backup-reminder'),
              icon: Icons.backup_outlined,
              title: last == null
                  ? l10n.backupReminderNever
                  : l10n.backupReminderOld,
              subtitle: l10n.backupReminderBody,
              onTap: () => context.push(Routes.backup),
            ),
          ActionRow(
            key: const Key('try-detection'),
            icon: Icons.center_focus_strong,
            title: l10n.tryDetectionTitle,
            subtitle: l10n.tryDetectionBody,
            onTap: () => context.push(Routes.analyze),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                key: const Key('status-banner'),
                style: TextStyle(color: fg),
              ),
              if (status is ServerRevoked)
                TextButton(
                  onPressed: onPairAgain,
                  child: Text(l10n.homePairAgain),
                ),
              if (status is ServerOffline)
                TextButton(
                  onPressed: () => context.push(Routes.connection),
                  child: Text(l10n.connectionFix),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = MediaQuery.textScalerOf(context).scale(14) > 24 ? 1 : 2;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, icon) in tiles)
              SizedBox(
                width: width,
                child: Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.go(
                      label == l10n.statPeople || label == l10n.statFaces
                          ? Routes.people
                          : Routes.library,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '$value',
                            key: Key('stat-$label'),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
