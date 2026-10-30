import 'package:flutter/material.dart';

/// Shared hierarchy for collection, creation and settings screens.
class ScreenIntro extends StatelessWidget {
  const ScreenIntro({super.key, required this.title, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineMedium),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            Text(
              body!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A quiet, readable surface for related information, without fixed heights.
class SurfaceSection extends StatelessWidget {
  const SurfaceSection({super.key, required this.child, this.padding = 16});

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

/// Messages stay readable with large text and never compete with an action row.
class StatusNotice extends StatelessWidget {
  const StatusNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.isError = false,
  });

  final String message;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isError ? scheme.onErrorContainer : scheme.onSurface;
    return Semantics(
      liveRegion: isError,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isError ? scheme.errorContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: TextStyle(color: foreground)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Side-by-side comparisons stack when either width or text size needs it.
class AdaptivePair extends StatelessWidget {
  const AdaptivePair({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(14) > 20) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 12), second],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second),
        ],
      );
    },
  );
}

/// One full-width tap target, with room for text scaling and long translations.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: emphasized ? scheme.primaryContainer : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          color: emphasized ? scheme.onPrimaryContainer : scheme.primary,
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }
}

/// Keep the primary action above system navigation and clear of the keyboard.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.child,
    this.avoidKeyboard = true,
  });
  final Widget child;
  final bool avoidKeyboard;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: EdgeInsets.only(
        bottom: avoidKeyboard ? MediaQuery.viewInsetsOf(context).bottom : 0,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    ),
  );
}

/// A single visible step: content scrolls independently from its primary action.
/// Uses Material's Step/ControlsDetails so existing validation stays in the form.
class GuidedWorkflow extends StatelessWidget {
  const GuidedWorkflow({
    super.key,
    required this.currentStep,
    required this.steps,
    required this.progressLabel,
    required this.controlsBuilder,
    this.onStepContinue,
    this.onStepCancel,
  });
  final int currentStep;
  final List<Step> steps;
  final String progressLabel;
  final ControlsWidgetBuilder controlsBuilder;
  final VoidCallback? onStepContinue;
  final VoidCallback? onStepCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Semantics(
            liveRegion: true,
            label: progressLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Text(
                    progressLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Expanded(
                        child: Container(
                          height: 4,
                          margin: EdgeInsetsDirectional.only(
                            end: i == steps.length - 1 ? 0 : 6,
                          ),
                          decoration: BoxDecoration(
                            color: i <= currentStep
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: currentStep,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < steps.length; i++)
                TickerMode(
                  enabled: i == currentStep,
                  child: SingleChildScrollView(
                    key: PageStorageKey('workflow-step-$i'),
                    padding: const EdgeInsets.all(20),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: DefaultTextStyle(
                            style: theme.textTheme.headlineSmall!,
                            child: steps[i].title,
                          ),
                        ),
                        const SizedBox(height: 20),
                        steps[i].content,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        StickyActionBar(
          avoidKeyboard: false,
          child: controlsBuilder(
            context,
            ControlsDetails(
              currentStep: currentStep,
              stepIndex: currentStep,
              onStepContinue: onStepContinue,
              onStepCancel: onStepCancel,
            ),
          ),
        ),
      ],
    );
  }
}
