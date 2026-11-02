import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';

/// Flow component: sticky submit bar with readiness validation and non-intrusive activity notification.
class JobSubmitBar extends StatelessWidget {
  const JobSubmitBar({
    super.key,
    required this.label,
    required this.onSubmit,
    this.ready = true,
    this.busy = false,
    this.reasonNotReady,
    this.activityRoute = Routes.activity,
  });

  final String label;
  final Future<void> Function() onSubmit;
  final bool ready;
  final bool busy;
  final String? reasonNotReady;
  final String activityRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!ready && reasonNotReady != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  reasonNotReady!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            FilledButton(
              key: const Key('job-submit-button'),
              onPressed: (!ready || busy)
                  ? null
                  : () async {
                      try {
                        await onSubmit();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Job started'),
                              action: SnackBarAction(
                                label: 'View Activity',
                                onPressed: () => context.push(activityRoute),
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to submit job: $e'),
                              backgroundColor: scheme.error,
                            ),
                          );
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
