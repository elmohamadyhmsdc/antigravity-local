import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Keeps a review decision visible and prevents a second action until it commits.
class ReviewActionScope extends StatefulWidget {
  const ReviewActionScope({super.key, required this.child});

  final Widget child;

  static Future<void> run(
    BuildContext context,
    Future<void> Function() action,
  ) => context.findAncestorStateOfType<_ReviewActionScopeState>()!.run(action);

  @override
  State<ReviewActionScope> createState() => _ReviewActionScopeState();
}

class _ReviewActionScopeState extends State<ReviewActionScope> {
  bool _busy = false;

  Future<void> run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Paint feedback before starting a potentially large database transaction.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).peopleActionError('$error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Stack(
      children: [
        AbsorbPointer(absorbing: _busy, child: widget.child),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .65),
              child: const Center(child: ReviewSavingIndicator()),
            ),
          ),
      ],
    ),
  );
}

class ReviewSavingIndicator extends StatelessWidget {
  const ReviewSavingIndicator({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(AppLocalizations.of(context).reviewSaving),
          ],
        ),
      ),
    ),
  );
}
