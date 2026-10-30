import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/app_settings.dart';
import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';
import 'scan_progress_card.dart';

/// S05 - choose which albums to scan, the scan options, start / pause / resume, and watch progress.
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final albums = ref.watch(albumsProvider);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final progress =
        ref.watch(scanProgressProvider).value ?? const ScanProgress();
    final counts = ref.watch(scanCountsProvider).value;
    final settingsStore = ref.read(appSettingsProvider);
    final chosen = settings.albumIds.toSet();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.sourcesTitle),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.tune),
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton.icon(
          key: const Key('scan-start'),
          icon: const Icon(Icons.play_arrow),
          label: Text(chosen.isEmpty ? l10n.chooseAlbumsFirst : l10n.scanNow),
          onPressed: progress.isActive || chosen.isEmpty
              ? null
              : () => startScan(ref),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ScanProgressCard(),
          if (counts != null && counts.total > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l10n.scanCountsLine(
                  counts.done,
                  counts.remaining,
                  counts.failed,
                ),
                key: const Key('scan-counts'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.albumsTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(l10n.albumsHint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          albums.when(
            loading: () => const LoadingBox(),
            error: (_, _) =>
                RetryState(onRetry: () => ref.invalidate(albumsProvider)),
            data: (list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: l10n.noPhotoAccessTitle,
                  body: l10n.noPhotoAccessBody,
                  actionLabel: l10n.allowPhotoAccess,
                  onAction: () => ref.invalidate(albumsProvider),
                );
              }
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final a in list)
                      CheckboxListTile(
                        key: Key('album-${a.id}'),
                        value: chosen.contains(a.id),
                        title: Text(a.isAll ? l10n.allMedia : a.name),
                        subtitle: Text(l10n.mediaCount(a.count)),
                        onChanged: (on) {
                          final next = {...chosen};
                          on == true ? next.add(a.id) : next.remove(a.id);
                          settingsStore.setAlbumIds(next);
                        },
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  key: const Key('scan-videos'),
                  value: settings.scanVideos,
                  title: Text(l10n.includeVideos),
                  subtitle: Text(l10n.includeVideosHint),
                  onChanged: progress.isActive
                      ? null
                      : settingsStore.setScanVideos,
                ),
                if (settings.scanVideos)
                  SwitchListTile(
                    key: const Key('adaptive-video-sampling'),
                    value: settings.adaptiveVideoSampling,
                    title: Text(l10n.videoAdaptiveSampling),
                    subtitle: Text(l10n.videoAdaptiveSamplingHint),
                    onChanged: progress.isActive
                        ? null
                        : settingsStore.setAdaptiveVideoSampling,
                  ),
                if (settings.scanVideos && !settings.adaptiveVideoSampling)
                  ListTile(
                    title: Text(l10n.videoFrameInterval),
                    trailing: DropdownButton<double>(
                      key: const Key('video-frame-interval'),
                      value:
                          [0.5, 1.0, 2.0, 5.0].contains(settings.frameInterval)
                          ? settings.frameInterval
                          : 1.0,
                      items: [
                        for (final seconds in [0.5, 1.0, 2.0, 5.0])
                          DropdownMenuItem(
                            value: seconds,
                            child: Text(l10n.videoEverySeconds('$seconds')),
                          ),
                      ],
                      onChanged: progress.isActive
                          ? null
                          : (v) {
                              if (v != null) settingsStore.setFrameInterval(v);
                            },
                    ),
                  ),
                SwitchListTile(
                  key: const Key('scan-bodies'),
                  value: settings.scanBodies,
                  title: Text(l10n.optionBodies),
                  subtitle: Text(l10n.optionBodiesHint),
                  onChanged: settingsStore.setScanBodies,
                ),
                SwitchListTile(
                  key: const Key('scan-characters'),
                  value: settings.scanCharacters,
                  title: Text(l10n.charactersScan),
                  subtitle: Text(l10n.charactersScanHint),
                  onChanged: progress.isActive
                      ? null
                      : settingsStore.setScanCharacters,
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(l10n.charactersTitle),
                  onTap: () => context.push(Routes.characters),
                ),
                ListTile(
                  title: Text(l10n.optionImageSize),
                  subtitle: Text(l10n.optionImageSizeHint),
                  trailing: DropdownButton<int>(
                    key: const Key('scan-max-side'),
                    value: maxSideChoices.contains(settings.maxSide)
                        ? settings.maxSide
                        : defaultMaxSide,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final s in maxSideChoices)
                        DropdownMenuItem(value: s, child: Text('$s px')),
                    ],
                    onChanged: (v) {
                      if (v != null) settingsStore.setMaxSide(v);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.scanFootnote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
