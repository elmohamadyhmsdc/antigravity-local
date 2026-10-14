import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/app_settings.dart';
import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';
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
            error: (e, _) => Text('$e'),
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
                        title: Text(a.isAll ? l10n.allPhotos : a.name),
                        subtitle: Text(l10n.photosCount(a.count)),
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
                  key: const Key('scan-bodies'),
                  value: settings.scanBodies,
                  title: Text(l10n.optionBodies),
                  subtitle: Text(l10n.optionBodiesHint),
                  onChanged: settingsStore.setScanBodies,
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
          FilledButton.icon(
            key: const Key('scan-start'),
            icon: const Icon(Icons.play_arrow),
            label: Text(chosen.isEmpty ? l10n.chooseAlbumsFirst : l10n.scanNow),
            onPressed: progress.isActive || chosen.isEmpty
                ? null
                : () => startScan(ref),
          ),
          const SizedBox(height: 8),
          Text(l10n.scanFootnote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
