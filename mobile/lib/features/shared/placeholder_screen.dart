import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Stand-in for a screen that a later phase builds. Each phase replaces the
/// placeholder in `core/router.dart` with the real screen.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.description,
    required this.phase,
    this.actions,
  });

  final String title;
  final String description;
  final String phase;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                description,
                textAlign: TextAlign.center,
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.comingInPhase(phase),
                style: text.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
