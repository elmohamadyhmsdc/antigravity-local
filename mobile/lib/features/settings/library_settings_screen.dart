import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/app_settings.dart';
import '../../data/repositories/insights_repository.dart';
import '../../domain/cleanup/background_faces.dart';
import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../review/review_screen.dart';
import '../scan/scan_progress_card.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';

final insightsProvider = StreamProvider.autoDispose<LibraryInsights>(
  (ref) => InsightsRepository(ref.watch(databaseProvider)).watch(),
);

/// S3 — Library & Scanning settings screen.
/// Unifies album sources, scan defaults, grouping strictness, insights, and analysis.
class LibrarySettingsScreen extends ConsumerStatefulWidget {
  const LibrarySettingsScreen({super.key});

  @override
  ConsumerState<LibrarySettingsScreen> createState() =>
      _LibrarySettingsScreenState();
}

class _LibrarySettingsScreenState extends ConsumerState<LibrarySettingsScreen> {
  double? _gateDraft;
  bool _retryingOutlines = false;
  bool _stopOutlineRetry = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final albums = ref.watch(albumsProvider);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final progress =
        ref.watch(scanProgressProvider).value ?? const ScanProgress();
    final counts = ref.watch(scanCountsProvider).value;
    final settingsStore = ref.read(appSettingsProvider);
    final chosen = settings.albumIds.toSet();
    final illustrated = settings.characterAlbumIds.toSet();
    final gate = _gateDraft ?? settings.qualityGate;
    final insightsAsync = ref.watch(insightsProvider);

    String strictnessHint(String s) => switch (s) {
      'strict' => l10n.strictnessStrictHint,
      'loose' => l10n.strictnessLooseHint,
      _ => l10n.strictnessBalancedHint,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsLibrarySection)),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton.icon(
          key: const Key('scan-start'),
          icon: const Icon(Icons.play_arrow),
          label: Text(chosen.isEmpty ? l10n.chooseAlbumsFirst : l10n.scanNow),
          onPressed: progress.isActive || chosen.isEmpty
              ? null
              : () => ref.read(scanEngineProvider).start(),
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
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: 8),

          // --- Section 1: Sources / Albums ---
          Text(l10n.albumsTitle, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(l10n.albumsHint, style: text.bodySmall),
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
                    for (final a in list) ...[
                      CheckboxListTile(
                        key: Key('album-${a.id}'),
                        value: chosen.contains(a.id),
                        title: Text(a.isAll ? l10n.allMedia : a.name),
                        subtitle: Text(l10n.mediaCount(a.count)),
                        onChanged: progress.isActive
                            ? null
                            : (on) {
                                final next = {...chosen};
                                if (a.isAll) {
                                  on == true ? next.add(a.id) : next.clear();
                                } else {
                                  next.remove('all');
                                  on == true
                                      ? next.add(a.id)
                                      : next.remove(a.id);
                                }
                                settingsStore.setAlbumIds(next);
                              },
                      ),
                      if (chosen.contains(a.id) && !a.isAll)
                        SwitchListTile(
                          key: Key('album-anime-${a.id}'),
                          contentPadding: const EdgeInsetsDirectional.only(
                            start: 32,
                            end: 16,
                          ),
                          title: Text(l10n.charactersAlbumToggle),
                          value: illustrated.contains(a.id),
                          onChanged: progress.isActive
                              ? null
                              : (on) {
                                  final next = {...illustrated};
                                  on ? next.add(a.id) : next.remove(a.id);
                                  settingsStore.setCharacterAlbumIds(next);
                                },
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // --- Section 2: Grouping & Quality Gate ---
          SectionHeading(title: l10n.settingsGrouping),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('strictness'),
            segments: [
              ButtonSegment(
                value: 'strict',
                label: Text(l10n.strictnessStrict),
              ),
              ButtonSegment(
                value: 'balanced',
                label: Text(l10n.strictnessBalanced),
              ),
              ButtonSegment(value: 'loose', label: Text(l10n.strictnessLoose)),
            ],
            selected: {settings.strictness},
            onSelectionChanged: (s) => settingsStore.setStrictness(s.first),
          ),
          const SizedBox(height: 6),
          Text(strictnessHint(settings.strictness), style: text.bodySmall),
          const SizedBox(height: 16),
          Text(l10n.settingsQualityGate, style: text.titleMedium),
          Text(l10n.settingsQualityGateHint, style: text.bodySmall),
          Slider(
            key: const Key('quality-gate'),
            value: gate.clamp(minQualityGate, maxQualityGate),
            min: minQualityGate,
            max: maxQualityGate,
            divisions: 12,
            label: gate.toStringAsFixed(2),
            onChanged: (v) => setState(() => _gateDraft = v),
            onChangeEnd: (v) async {
              await settingsStore.setQualityGate(v);
              if (mounted) setState(() => _gateDraft = null);
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.qualityGateValue(gate.toStringAsFixed(2)),
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            key: const Key('settings-retry-outlines'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.polyline_outlined),
            title: Text(l10n.outlineRetryTitle),
            subtitle: Text(
              l10n.outlineRetryPending(
                ref.watch(pendingOutlinesProvider).value ?? 0,
              ),
            ),
            trailing: TextButton(
              onPressed: _retryingOutlines
                  ? () => setState(() => _stopOutlineRetry = true)
                  : (ref.watch(pendingOutlinesProvider).value ?? 0) == 0 ||
                        ref.watch(serverStatusProvider).value is! ServerReady ||
                        ref.watch(scanProgressProvider).value?.isActive == true
                  ? null
                  : _retryOutlines,
              child: Text(_retryingOutlines ? l10n.pause : l10n.retry),
            ),
          ),
          const SizedBox(height: 16),

          // --- Section 3: Scan Options & Video Sampling ---
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
                ListTile(
                  key: const Key('settings-characters'),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(l10n.charactersScan),
                  subtitle: Text(
                    l10n.charactersAlbumsCount(
                      settings.characterAlbumIds.length,
                    ),
                  ),
                  onTap: () => context.push(Routes.characters),
                ),
                ListTile(
                  title: Text(l10n.optionImageSize),
                  subtitle: Text(l10n.optionImageSizeHint),
                  trailing: DropdownButton<int>(
                    key: const Key('settings-max-side'),
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

          // --- Section 4: Library Overview / Insights ---
          SectionHeading(title: l10n.homeOrganize),
          insightsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (data) {
              if (data.stats.isEmpty) return const SizedBox.shrink();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.insightsCoverage, style: text.titleMedium),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: data.mediaCount == 0
                            ? 0
                            : data.scanned / data.mediaCount,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.insightsScanned(data.scanned, data.mediaCount),
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${l10n.statPhotos}: ${data.stats.photos} · ${l10n.statVideos}: ${data.stats.videos} · ${l10n.insightsFaces}: ${data.stats.faces}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // --- Section 5: Scan Actions & Tools ---
          ListTile(
            key: const Key('settings-sort-now'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high),
            title: Text(l10n.sortNow),
            subtitle: Text(l10n.sortNowHint),
            onTap: () => sortNow(context, ref),
          ),
          ListTile(
            key: const Key('settings-clean-background'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.blur_off),
            title: const Text('Clean up background faces'),
            subtitle: const Text(
              'Hide tiny faces and the small faces in crowd photos. They stay in the library and can be restored.',
            ),
            onTap: () => _cleanBackgroundFaces(context, ref),
          ),
          ListTile(
            key: const Key('try-detection'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.center_focus_strong),
            title: Text(l10n.tryDetectionTitle),
            subtitle: Text(l10n.tryDetectionBody),
            onTap: () => context.push(Routes.analyze),
          ),
          SwitchListTile(
            key: const Key('settings-review-advanced'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.percent),
            value: settings.reviewAdvanced,
            title: Text(l10n.reviewAdvancedTitle),
            subtitle: Text(l10n.reviewAdvancedBody),
            onChanged: settingsStore.setReviewAdvanced,
          ),
          SwitchListTile(
            key: const Key('settings-auto-organize'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.sync_alt),
            value: settings.autoOrganizeEnabled,
            title: Text(l10n.autoSyncOrganizedFolders),
            subtitle: Text(l10n.autoSyncOrganizedFoldersHint),
            onChanged: settingsStore.setAutoOrganizeEnabled,
          ),
          SwitchListTile(
            key: const Key('settings-save-sidecar'),
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.description_outlined),
            value: settings.saveSidecarEnabled,
            title: Text(l10n.saveSidecarMetadata),
            subtitle: Text(l10n.saveSidecarMetadataHint),
            onChanged: settingsStore.setSaveSidecarEnabled,
          ),
        ],
      ),
    );
  }

  Future<void> _retryOutlines() async {
    setState(() {
      _retryingOutlines = true;
      _stopOutlineRetry = false;
    });
    final backfill = ref.read(outlineBackfillProvider);
    try {
      await backfill.retryPending(
        shouldContinue: () =>
            mounted &&
            !_stopOutlineRetry &&
            !ref.read(scanEngineProvider).isRunning &&
            ref.read(serverStatusProvider).value is ServerReady,
      );
    } finally {
      if (mounted) setState(() => _retryingOutlines = false);
    }
  }
}

/// "Clean up background faces": finds the tiny faces and the small faces of crowd photos already in the
/// library (new scans never store them), asks, hides them, and offers Undo.
Future<void> _cleanBackgroundFaces(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final cleaner = BackgroundFaces(ref.read(databaseProvider));
  final ids = await cleaner.find();
  if (!context.mounted) return;
  if (ids.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No background faces found.')),
    );
    return;
  }
  final yes = await confirm(
    context,
    title: 'Hide ${ids.length} background face${ids.length == 1 ? '' : 's'}?',
    body:
        'Tiny faces and the small faces in crowd photos are hidden from People, Review and grouping. '
        'Nothing is deleted; faces you confirmed by hand are kept. You can undo this right after.',
    confirmLabel: 'Hide',
    cancelLabel: l10n.cancel,
  );
  if (!yes) return;
  await cleaner.hide(ids);
  messenger.showSnackBar(
    SnackBar(
      content: Text('Hid ${ids.length} background faces.'),
      action: SnackBarAction(
        label: l10n.peopleAction('undo'),
        onPressed: () => cleaner.restore(ids),
      ),
    ),
  );
}
