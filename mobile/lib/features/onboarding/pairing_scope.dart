import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import 'pairing_controller.dart';

/// Wraps a pairing screen: shows progress while connecting, an error snackbar when pairing
/// fails and moves on to the permissions screen when it succeeds.
class PairingScope extends ConsumerWidget {
  const PairingScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<PairingState>(pairingControllerProvider, (previous, next) {
      switch (next) {
        case PairingDone():
          context.go(Routes.permissions);
        case PairingFailed(:final error):
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(error.message),
                duration: const Duration(seconds: 6),
              ),
            );
        default:
          break;
      }
    });
    final state = ref.watch(pairingControllerProvider);
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        child,
        if (state is PairingBusy)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.5),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(l10n.pairingConnecting(state.host)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
