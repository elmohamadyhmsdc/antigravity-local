import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../studio_providers.dart';

/// Flow component: reusable dataset picker for Training.
class DatasetPicker extends ConsumerWidget {
  const DatasetPicker({
    super.key,
    required this.selectedDatasetId,
    required this.onDatasetSelected,
  });

  final String? selectedDatasetId;
  final void Function(DatasetRow dataset) onDatasetSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final datasetsAsync = ref.watch(datasetsProvider);

    return datasetsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Error loading datasets: $e',
          style: TextStyle(color: scheme.error),
        ),
      ),
      data: (datasets) {
        if (datasets.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No training datasets available. Create a new dataset first.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in datasets)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selectedDatasetId == d.id
                        ? scheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  key: Key('dataset-tile-${d.id}'),
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondaryContainer,
                    child: Icon(
                      Icons.folder_outlined,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(d.triggerWord),
                  subtitle: Text(
                    'Repeats: ${d.repeats} · ID: ${d.id.length > 8 ? d.id.substring(0, 8) : d.id}',
                  ),
                  trailing: selectedDatasetId == d.id
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () => onDatasetSelected(d),
                ),
              ),
          ],
        );
      },
    );
  }
}
