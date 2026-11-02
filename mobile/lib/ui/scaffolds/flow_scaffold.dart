import 'package:flutter/material.dart';

import '../../features/shared/screen_layout.dart';
import '../sheets/confirm_sheet.dart';

class FlowScaffold extends StatelessWidget {
  const FlowScaffold({
    super.key,
    required this.title,
    required this.currentStep,
    required this.steps,
    required this.progressLabel,
    required this.controlsBuilder,
    this.hasUnsavedChanges = false,
    this.onStepContinue,
    this.onStepCancel,
    this.onClose,
  });

  final Widget title;
  final int currentStep;
  final List<Step> steps;
  final String progressLabel;
  final ControlsWidgetBuilder controlsBuilder;
  final bool hasUnsavedChanges;
  final VoidCallback? onStepContinue;
  final VoidCallback? onStepCancel;
  final VoidCallback? onClose;

  Future<bool> _confirmExit(BuildContext context) async {
    if (!hasUnsavedChanges) return true;
    final confirmed = await ConfirmSheet.show(
      context: context,
      title: 'Discard changes?',
      message:
          'You have unsaved changes in this workflow. Are you sure you want to exit?',
      confirmLabel: 'Discard',
      isDanger: true,
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmExit(context);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: title,
          leading: IconButton(
            key: const Key('flow-close'),
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (onClose != null) {
                onClose!();
              } else {
                final shouldPop = await _confirmExit(context);
                if (shouldPop && context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ),
        body: SafeArea(
          child: GuidedWorkflow(
            currentStep: currentStep,
            steps: steps,
            progressLabel: progressLabel,
            controlsBuilder: controlsBuilder,
            onStepContinue: onStepContinue,
            onStepCancel: onStepCancel,
          ),
        ),
      ),
    );
  }
}
