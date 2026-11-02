import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../ui/settings/setting_group.dart';
import '../../ui/settings/setting_tile.dart';
import '../../ui/settings/settings_scaffold.dart';
import '../privacy/app_lock.dart';

/// S4 — Privacy & Lock settings screen.
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appLockEnabled = ref.watch(appLockEnabledProvider).value ?? false;

    return SettingsScaffold(
      title: l10n.appLockTitle,
      children: [
        SettingGroup(
          title: l10n.settingsPrivacySection,
          children: [
            SettingTile.toggle(
              key: const Key('app-lock'),
              leading: const Icon(Icons.lock_outline),
              title: l10n.appLockTitle,
              subtitle: l10n.appLockHint,
              boolValue: appLockEnabled,
              onChanged: (enabled) async {
                try {
                  if (enabled) {
                    final ok = await ref
                        .read(privacyServiceProvider)
                        .authenticate(l10n.appLockTitle, l10n.unlockBody);
                    if (!ok) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.unlockFailed)),
                        );
                      }
                      return;
                    }
                    ref.read(lockSessionProvider.notifier).unlock();
                  }
                  await ref
                      .read(databaseProvider)
                      .putSetting('privacy.app_lock', '$enabled');
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
