import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'activity_state_provider.dart';

/// The global activity pill shown above navigation on root screens or hosted
/// at the bottom of interior screens. Tapping opens `/activity`.
class ActivityPill extends ConsumerWidget {
  const ActivityPill({super.key, this.onTap, this.enabled = true});

  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activityStateProvider);
    if (state.isIdle) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget iconWidget;
    String label;
    Widget? progressWidget;
    Color? iconColor;

    switch (state) {
      case ActivityScanning(
        done: final done,
        total: final total,
        progress: final progress,
      ):
        iconWidget = const Icon(Icons.sync, size: 18);
        label = total > 0 ? 'Scanning $done / $total' : 'Preparing scan...';
        progressWidget = SizedBox(
          width: 48,
          child: LinearProgressIndicator(
            value: total > 0 ? progress : null,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case ActivityJob(type: final type, progress: final progress):
        iconWidget = const Icon(Icons.auto_awesome, size: 18);
        label = '$type ${(progress * 100).toInt()}%';
        progressWidget = SizedBox(
          width: 48,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case ActivityMultiple(
        primaryDescription: final primary,
        extraCount: final extra,
      ):
        iconWidget = const Icon(Icons.layers, size: 18);
        label = '$primary (+$extra)';
      case ActivityFailed(message: final message):
        iconWidget = const Icon(Icons.error_outline, size: 18);
        iconColor = colorScheme.error;
        label = message;
      case ActivityIdle():
        return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Material(
          key: const Key('activity-pill'),
          color: colorScheme.surfaceContainerHighest,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: state is ActivityFailed
                  ? colorScheme.error.withValues(alpha: 0.5)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: enabled
                ? () {
                    if (onTap != null) {
                      onTap!();
                    } else {
                      context.push('/activity');
                    }
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconTheme(
                    data: IconThemeData(
                      color: iconColor ?? colorScheme.primary,
                    ),
                    child: iconWidget,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: state is ActivityFailed
                            ? colorScheme.error
                            : colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (progressWidget != null) ...[
                    const SizedBox(width: 10),
                    progressWidget,
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
