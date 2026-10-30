import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/pairing_payload.dart';
import '../../l10n/app_localizations.dart';
import '../shared/screen_layout.dart';
import 'pairing_controller.dart';
import 'pairing_scope.dart';

/// S01 - Welcome / Pair.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.link});

  /// An `agmobile://pair?...` link the user tapped (the pairing page offers one next to the QR).
  final String? link;

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.link != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleLink(widget.link!),
      );
    }
  }

  /// A link can come from anywhere (a web page, a chat), so it never pairs silently: the user
  /// sees which address it points to and confirms. Non-LAN addresses are rejected outright.
  Future<void> _handleLink(String link) async {
    final l10n = AppLocalizations.of(context);
    final payload = PairingPayload.tryParse(link);
    if (payload == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.pairLinkInvalid)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.pairLinkTitle(payload.host)),
        content: Text(l10n.pairLinkBody(payload.host)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.pairLinkContinue),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(pairingControllerProvider.notifier)
          .pairFromPayload(payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PairingScope(
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.photo_library_outlined,
                          size: 44,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ScreenIntro(
                      title: l10n.welcomeTitle,
                      body: l10n.welcomeBody,
                    ),
                    StatusNotice(
                      message: l10n.welcomeStep,
                      icon: Icons.computer_outlined,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.welcomeSameWifi,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => context.push(Routes.scan),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(l10n.welcomeScan),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push(Routes.manual),
                      icon: const Icon(Icons.keyboard_outlined),
                      label: Text(l10n.welcomeManual),
                    ),
                    TextButton(
                      onPressed: () => context.push(Routes.connection),
                      child: Text(l10n.connectionTitle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
