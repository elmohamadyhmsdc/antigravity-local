import 'package:flutter/material.dart';

enum EmptyStateKind { firstRun, noResults, noPermission, noPc, custom }

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.kind = EmptyStateKind.noResults,
    this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final EmptyStateKind kind;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData effectiveIcon;
    String effectiveTitle;
    String? effectiveSubtitle;

    switch (kind) {
      case EmptyStateKind.firstRun:
        effectiveIcon = icon ?? Icons.photo_library_outlined;
        effectiveTitle = title ?? 'No media yet';
        effectiveSubtitle =
            subtitle ?? 'Scan your device or take photos to get started.';
        break;
      case EmptyStateKind.noResults:
        effectiveIcon = icon ?? Icons.search_off_outlined;
        effectiveTitle = title ?? 'No matching items';
        effectiveSubtitle = subtitle ?? 'Try adjusting your search or filters.';
        break;
      case EmptyStateKind.noPermission:
        effectiveIcon = icon ?? Icons.lock_outline;
        effectiveTitle = title ?? 'Permission required';
        effectiveSubtitle =
            subtitle ?? 'Grant media permissions in Settings to view photos.';
        break;
      case EmptyStateKind.noPc:
        effectiveIcon = icon ?? Icons.computer_outlined;
        effectiveTitle = title ?? 'Computer offline';
        effectiveSubtitle =
            subtitle ?? 'Connect to your PC to use AI features and models.';
        break;
      case EmptyStateKind.custom:
        effectiveIcon = icon ?? Icons.inbox_outlined;
        effectiveTitle = title ?? 'Nothing here';
        effectiveSubtitle = subtitle;
        break;
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(effectiveIcon, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              effectiveTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (effectiveSubtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                effectiveSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
