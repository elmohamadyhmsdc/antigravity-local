import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../shared/empty_state.dart';

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

class StorageScreen extends ConsumerStatefulWidget {
  const StorageScreen({super.key});
  @override
  ConsumerState<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends ConsumerState<StorageScreen> {
  bool _busy = false;
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
          title: l.storageTitle,
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
    return Scaffold(
      appBar: AppBar(title: Text(l.storageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.storageHint),
          if (_busy) const LinearProgressIndicator(),
          ref
              .watch(storageSizesProvider)
              .when(
                loading: () => const LoadingBox(),
                error: (e, _) => Text('$e'),
                data: (sizes) => Column(
                  children: [
                    ListTile(
                      title: Text(l.storageUsed),
                      trailing: Text(
                        '${(sizes.values.fold<int>(0, (a, b) => a + b) / 1048576).toStringAsFixed(1)} MB',
                      ),
                    ),
                    for (final entry in sizes.entries)
                      ListTile(
                        title: Text(switch (entry.key) {
                          'faces' => l.navPeople,
                          'bodies' => l.tabBodies,
                          'datasets' => l.loraDatasetTitle,
                          'portraits' => l.loraGenerate,
                          'results' => l.privateResults,
                          _ => l.storageDeleteTemporary,
                        }),
                        trailing: Text(
                          '${(entry.value / 1048576).toStringAsFixed(1)} MB',
                        ),
                      ),
                  ],
                ),
              ),
          const SizedBox(height: 16),
          for (final action in [
            ('results', l.storageDeleteResults),
            ('datasets', l.storageDeleteDatasets),
            ('loras', l.storageDeleteLoras),
            ('temporary', l.storageDeleteTemporary),
          ])
            OutlinedButton(
              onPressed: _busy ? null : () => _clean(action.$1),
              child: Text(action.$2),
            ),
        ],
      ),
    );
  }
}
