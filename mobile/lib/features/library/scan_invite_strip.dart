import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scan/scan_state.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';

/// L1 — ScanInviteStrip: Banner shown when unanalyzed media exist and no scan is active.
/// Disappears when a scan is active, replaced by ActivityPill.
class ScanInviteStrip extends ConsumerWidget {
  const ScanInviteStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final counts = ref.watch(scanCountsProvider).value;
    final scanProgress = ref.watch(scanProgressProvider).value;

    final isScanning =
        (scanProgress?.isActive ?? false) ||
        (scanProgress?.phase != null && scanProgress!.phase != ScanPhase.idle);

    if (isScanning || counts == null || counts.pending <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      key: const Key('scan-invite-strip'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${counts.pending} unanalyzed items',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Analyze to recognize faces and bodies',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            key: const Key('scan-invite-start'),
            onPressed: () => ref.read(scanEngineProvider).start(),
            child: Text(l10n.scanNow),
          ),
        ],
      ),
    );
  }
}
