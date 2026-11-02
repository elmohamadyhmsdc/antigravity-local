import 'package:flutter/material.dart';

import '../scaffolds/sheet_scaffold.dart';

class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    this.consequences = const [],
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.isDanger = false,
  });

  final String title;
  final String message;
  final List<String> consequences;
  final String confirmLabel;
  final String cancelLabel;
  final bool isDanger;

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    List<String> consequences = const [],
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDanger = false,
  }) {
    return SheetScaffold.show<bool>(
      context: context,
      builder: (_) => ConfirmSheet(
        title: title,
        message: message,
        consequences: consequences,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDanger: isDanger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SheetScaffold(
      title: title,
      leading: isDanger
          ? Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error)
          : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('confirm-sheet-confirm'),
          style: isDanger
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: theme.textTheme.bodyMedium),
            if (consequences.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDanger
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  border: isDanger
                      ? Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.4),
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Consequences:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isDanger ? theme.colorScheme.error : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final item in consequences) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
