import 'package:flutter/material.dart';

class UndoSnackbar {
  UndoSnackbar._();

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required BuildContext context,
    required String message,
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 8),
    String undoLabel = 'Undo',
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    return messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
  }
}
