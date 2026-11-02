import 'package:flutter/material.dart';

import '../../data/repositories/people_repository.dart';

/// Flow component: reusable identity picker supporting people, characters, and identity sets.
class IdentityPicker extends StatelessWidget {
  const IdentityPicker({
    super.key,
    this.selectedPerson,
    this.allowedKind = 'all',
    required this.onIdentitySelected,
    this.onClear,
  });

  final PersonSummary? selectedPerson;
  final String allowedKind; // 'person', 'character', or 'all'
  final void Function(PersonSummary person) onIdentitySelected;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (selectedPerson == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: FilledButton.tonalIcon(
            key: const Key('flow-identity-pick'),
            icon: const Icon(Icons.person_search_outlined),
            label: const Text('Choose Source Identity'),
            onPressed: () async {
              // Open group/person picker
            },
          ),
        ),
      );
    }

    final isCharacter = selectedPerson!.kind == 'character';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isCharacter
                ? scheme.tertiaryContainer
                : scheme.primaryContainer,
            child: Icon(
              isCharacter ? Icons.draw_outlined : Icons.person_outline,
              color: isCharacter
                  ? scheme.onTertiaryContainer
                  : scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedPerson!.name ?? 'Unnamed #${selectedPerson!.id}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isCharacter
                      ? 'Anime / Illustration (CCIP)'
                      : 'Photorealistic (ArcFace)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear',
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
