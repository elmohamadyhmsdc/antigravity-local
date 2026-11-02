import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers.dart';

class ReadinessBanner extends ConsumerWidget {
  const ReadinessBanner({super.key, this.requiredOperation, this.requiredKind});

  final String? requiredOperation;
  final String? requiredKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider).value;
    final theme = Theme.of(context);

    if (status is ServerReady) {
      if (requiredOperation != null && requiredKind != null) {
        final supported = status.capabilities.supportsOperation(
          requiredOperation!,
          requiredKind!,
        );
        if (!supported) {
          return Container(
            color: theme.colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.onErrorContainer,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Computer does not support this operation.',
                    style: TextStyle(
                      color: theme.colorScheme.onErrorContainer,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      }
      return const SizedBox.shrink();
    }

    if (status is ServerChecking) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('Connecting to computer...', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    // Offline / Revoked
    final isRevoked = status is ServerRevoked;
    final message = isRevoked
        ? 'Computer connection was revoked.'
        : 'Computer is offline. AI features are unavailable.';

    return Container(
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            color: theme.colorScheme.onTertiaryContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: theme.colorScheme.onTertiaryContainer,
                fontSize: 12,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/pair'),
            child: Text(
              isRevoked ? 'Re-pair' : 'Connect',
              style: TextStyle(
                color: theme.colorScheme.onTertiaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
