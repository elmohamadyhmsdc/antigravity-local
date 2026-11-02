import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../studio_providers.dart';

/// Flow component: reusable model picker for Generate and Fine-Tuning.
class ModelPicker extends ConsumerWidget {
  const ModelPicker({
    super.key,
    required this.selectedModelId,
    required this.onModelSelected,
  });

  final String? selectedModelId;
  final void Function(LoraRow model) onModelSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final modelsAsync = ref.watch(lorasProvider);

    return modelsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Error loading models: $e',
          style: TextStyle(color: scheme.error),
        ),
      ),
      data: (models) {
        if (models.isEmpty) {
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
                    'No trained models available. Train a model first.',
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
            for (final m in models)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: selectedModelId == m.id
                        ? scheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  key: Key('model-tile-${m.id}'),
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      Icons.model_training,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(m.triggerWord),
                  subtitle: Text(
                    'Trigger: ${m.triggerWord} · Model ID: ${m.id.length > 8 ? m.id.substring(0, 8) : m.id}',
                  ),
                  trailing: selectedModelId == m.id
                      ? Icon(Icons.check_circle, color: scheme.primary)
                      : null,
                  onTap: () => onModelSelected(m),
                ),
              ),
          ],
        );
      },
    );
  }
}
