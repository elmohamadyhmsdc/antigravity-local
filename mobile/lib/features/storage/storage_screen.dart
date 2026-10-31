import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../domain/storage/storage_sweeper.dart';
import '../shared/empty_state.dart';
import '../shared/screen_layout.dart';

final storageSizesProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final sizes = <String, int>{};
  for (final entry in await ref.watch(fileStoreProvider).allFiles()) {
    final folder = entry.$1.split('/').first;
    sizes[folder] = (sizes[folder] ?? 0) + await entry.$2.length();
  }
  return sizes;
});

/// What the per-folder sizes do not show: the database, cache/scratch space and the leftovers
/// that a sweep would remove. Its own provider, so a failure here never hides the sizes above.
final storageExtrasProvider =
    FutureProvider.autoDispose<({StorageUsage usage, Leftovers leftovers})>((
      ref,
    ) async {
      final sweeper = await ref.watch(storageSweeperProvider.future);
      return (
        usage: await sweeper.usage(),
        leftovers: await sweeper.findLeftovers(),
      );
    });

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});
  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  bool _busy = false;

  Future<bool> _workIsRunning() async {
    final db = ref.read(databaseProvider);
    final jobs = await db.select(db.jobs).get();
    return ref.read(scanEngineProvider).isRunning ||
        jobs.any(
          (j) => !const [
            'completed',
            'failed',
            'paused',
            'lost',
          ].contains(j.status),
        );
  }

  Future<void> _cleanLeftovers() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (await _workIsRunning()) {
      messenger.showSnackBar(SnackBar(content: Text(l.storageBusy)));
      return;
    }
    if (!mounted ||
        !await confirm(
          context,
          title: l.storageCleanLeftovers,
          body: l.storageLeftoversConfirm,
          confirmLabel: l.delete,
          cancelLabel: l.cancel,
          destructive: true,
        )) {
      return;
    }
    setState(() => _busy = true);
    final tracker = ref.read(jobTrackerProvider);
    final wasActive = await tracker.suspendForMaintenance();
    try {
      final sweeper = await ref.read(storageSweeperProvider.future);
      final result = await sweeper.sweep();
      // photo_manager keeps its own copies of originals opened by this app
      await ref.read(mediaLibraryProvider).clearCache();
      ref.invalidate(storageSizesProvider);
      ref.invalidate(storageExtrasProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l.storageLeftoversDone(_size(result.removedBytes))),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      tracker.resumeAfterMaintenance(wasActive);
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(1)} GB'
      : '${(bytes / 1048576).toStringAsFixed(1)} MB';

  Future<void> _clean(String category) async {
    final l = AppLocalizations.of(context);
    final repository = ref.read(studioRepositoryProvider);
    final db = ref.read(databaseProvider);
    final files = ref.read(fileStoreProvider);
    final jobs = await db.select(db.jobs).get();
    if (ref.read(scanEngineProvider).isRunning ||
        jobs.any(
          (j) => !const [
            'completed',
            'failed',
            'paused',
            'lost',
          ].contains(j.status),
        )) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.storageBusy)));
      }
      return;
    }
    if (!mounted ||
        !await confirm(
          context,
          title: switch (category) {
            'results' => l.storageDeleteResults,
            'datasets' => l.storageDeleteDatasets,
            'loras' => l.storageDeleteLoras,
            _ => l.storageDeleteTemporary,
          },
          body: l.storageConfirm,
          confirmLabel: l.delete,
          cancelLabel: l.cancel,
          destructive: true,
        )) {
      return;
    }
    setState(() => _busy = true);
    final tracker = ref.read(jobTrackerProvider);
    final wasActive = await tracker.suspendForMaintenance();
    try {
      if (category == 'results') {
        for (final row in await db.select(db.results).get()) {
          if (row.mime.startsWith('image/') || row.mime.startsWith('video/')) {
            await repository.deleteResult(row);
          }
        }
      } else if (category == 'datasets') {
        for (final data in await db.select(db.datasets).get()) {
          final result = await (db.select(
            db.results,
          )..where((r) => r.id.equals(data.id))).getSingleOrNull();
          if (result != null) {
            await repository.deleteResult(result);
          } else {
            final items = await (db.select(
              db.datasetItems,
            )..where((i) => i.datasetId.equals(data.id))).get();
            await (db.delete(
              db.datasets,
            )..where((d) => d.id.equals(data.id))).go();
            await files.deleteAll(items.map((i) => i.path));
          }
        }
      } else if (category == 'loras') {
        for (final model in await db.select(db.loras).get()) {
          final result = await (db.select(
            db.results,
          )..where((r) => r.id.equals(model.id))).getSingleOrNull();
          if (result != null) {
            await repository.deleteResult(result);
          } else {
            await (db.delete(
              db.loras,
            )..where((r) => r.id.equals(model.id))).go();
            await files.delete(model.path);
          }
        }
      } else {
        final protected = <String>{for (final job in jobs) job.targetPath};
        for (final job in jobs) {
          protected.addAll(
            (jsonDecode(job.inputFiles) as Map).values.cast<String>(),
          );
        }
        for (final entry in await files.allFiles()) {
          if (entry.$1.startsWith('work/') && !protected.contains(entry.$1)) {
            await files.delete(entry.$1);
          }
        }
      }
      ref.invalidate(storageSizesProvider);
      ref.invalidate(storageExtrasProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.storageCleaned)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      tracker.resumeAfterMaintenance(wasActive);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final sizeLabel = _size;
    String categoryLabel(String category) => switch (category) {
      'faces' => l.navPeople,
      'bodies' => l.tabBodies,
      'characters' => l.charactersTitle,
      'datasets' => l.loraDatasetTitle,
      'portraits' => l.loraGenerate,
      'results' => l.privateResults,
      'loras' || 'models' => l.storageModels,
      'work' => l.storageTemporary,
      _ => l.storageOther,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.storageTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          ScreenIntro(title: l.storageSavedTitle, body: l.storageHint),
          if (_busy) const LinearProgressIndicator(),
          ref
              .watch(storageSizesProvider)
              .when(
                loading: () => const LoadingBox(),
                error: (_, _) => RetryState(
                  onRetry: () => ref.invalidate(storageSizesProvider),
                ),
                data: (sizes) {
                  final total = sizes.values.fold<int>(
                    0,
                    (sum, bytes) => sum + bytes,
                  );
                  final entries = sizes.entries.toList()
                    ..sort((a, b) => b.value.compareTo(a.value));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SurfaceSection(
                        key: const Key('storage-total'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.storage_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              sizeLabel(total),
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(l.storageUsed),
                          ],
                        ),
                      ),
                      if (entries.isNotEmpty) ...[
                        SectionHeading(title: l.storageCategories),
                        for (final entry in entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Text(categoryLabel(entry.key)),
                                    Text(sizeLabel(entry.value)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: total == 0 ? 0 : entry.value / total,
                                  minHeight: 6,
                                  semanticsLabel: categoryLabel(entry.key),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
          ref
              .watch(storageExtrasProvider)
              .maybeWhen(
                data: (extras) => Column(
                  key: const Key('storage-extras'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in [
                      (l.storageDatabase, extras.usage.databaseBytes),
                      (l.storageCache, extras.usage.tempBytes),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          children: [Text(row.$1), Text(sizeLabel(row.$2))],
                        ),
                      ),
                    SectionHeading(title: l.storageLeftoversTitle),
                    Text(
                      extras.leftovers.isEmpty
                          ? l.storageLeftoversNone
                          : l.storageLeftoversFound(
                              sizeLabel(extras.leftovers.totalBytes),
                            ),
                      key: const Key('storage-leftovers-summary'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      key: const Key('storage-clean-leftovers'),
                      onPressed: _busy || extras.leftovers.isEmpty
                          ? null
                          : _cleanLeftovers,
                      icon: const Icon(Icons.auto_delete_outlined),
                      label: Text(l.storageCleanLeftovers),
                    ),
                  ],
                ),
                orElse: () => const SizedBox.shrink(),
              ),
          const SizedBox(height: 12),
          StatusNotice(
            message: l.storageOriginalsHint,
            icon: Icons.photo_library_outlined,
          ),
          SectionHeading(title: l.storageManage),
          OutlinedButton.icon(
            key: const Key('storage-clean-temporary'),
            onPressed: _busy ? null : () => _clean('temporary'),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(l.storageDeleteTemporary),
          ),
          const SizedBox(height: 8),
          ExpansionTile(
            key: const Key('storage-saved-files'),
            tilePadding: EdgeInsets.zero,
            title: Text(l.storageRemoveSaved),
            subtitle: Text(l.storageConfirm),
            children: [
              for (final action in [
                ('results', l.storageDeleteResults),
                ('datasets', l.storageDeleteDatasets),
                ('loras', l.storageDeleteLoras),
              ])
                ListTile(
                  key: Key('storage-delete-${action.$1}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(action.$2),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : () => _clean(action.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
