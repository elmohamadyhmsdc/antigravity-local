import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/router.dart';
import '../../data/repositories/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../studio_providers.dart';
import '../../ui/settings/setting_group.dart';
import '../../ui/settings/setting_tile.dart';
import '../../ui/settings/settings_scaffold.dart';

/// S1 — Settings Hub screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final jobs = ref.watch(jobsProvider).value ?? const [];
    final activeJobs = jobs.where(
      (j) => !const ['completed', 'failed', 'lost'].contains(j.status),
    );
    final scan = ref.watch(scanProgressProvider).value;
    final activeCount = activeJobs.length + (scan?.isActive == true ? 1 : 0);

    final lastBackup = settings.lastBackupAt;
    final lastBackupLabel = lastBackup == null
        ? l10n.neverBackedUp
        : l10n.lastBackup(DateFormat.yMMMd().add_jm().format(lastBackup));

    return SettingsScaffold(
      title: l10n.settings,
      children: [
        // --- Group 1: General ---
        SettingGroup(
          title: 'General',
          children: [
            SettingTile.nav(
              key: const Key('settings-activity'),
              leading: const Icon(Icons.show_chart),
              title: l10n.homeActivity,
              trailing: activeCount > 0
                  ? Badge.count(
                      count: activeCount,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => context.push(Routes.activity),
            ),
          ],
        ),

        // --- Group 2: Computer ---
        SettingGroup(
          title: l10n.settingsDeviceSection,
          children: [
            SettingTile.nav(
              key: const Key('settings-pc'),
              leading: const Icon(Icons.computer_outlined),
              title: session?.name ?? l10n.notPaired,
              subtitle: session == null
                  ? null
                  : '${session.host}:${session.port}',
              onTap: () => context.push(Routes.settingsComputer),
            ),
          ],
        ),

        // --- Group 3: Library ---
        SettingGroup(
          title: l10n.settingsLibrarySection,
          children: [
            SettingTile.nav(
              key: const Key('settings-library'),
              leading: const Icon(Icons.photo_library_outlined),
              title: l10n.settingsLibrarySection,
              subtitle: l10n.sourcesTitle,
              onTap: () => context.push(Routes.settingsLibrary),
            ),
            // Legacy key support for tests expecting settings-sources
            SettingTile.nav(
              key: const Key('settings-sources'),
              leading: const Icon(Icons.folder_special_outlined),
              title: l10n.sourcesTitle,
              onTap: () => context.push(Routes.settingsLibrary),
            ),
          ],
        ),

        // --- Group 4: Privacy & Security ---
        SettingGroup(
          title: l10n.settingsPrivacySection,
          children: [
            SettingTile.nav(
              key: const Key('settings-privacy'),
              leading: const Icon(Icons.lock_outline),
              title: l10n.appLockTitle,
              onTap: () => context.push(Routes.settingsPrivacy),
            ),
            SettingTile.nav(
              key: const Key('settings-storage'),
              leading: const Icon(Icons.storage_outlined),
              title: l10n.storageTitle,
              onTap: () => context.push(Routes.settingsStorage),
            ),
            SettingTile.nav(
              key: const Key('settings-backup'),
              leading: const Icon(Icons.backup_outlined),
              title: l10n.backupTitle,
              subtitle: lastBackupLabel,
              onTap: () => context.push(Routes.settingsBackup),
            ),
          ],
        ),

        // --- Group 5: System ---
        SettingGroup(
          title: 'System',
          children: [
            SettingTile.nav(
              key: const Key('settings-background'),
              leading: const Icon(Icons.battery_charging_full),
              title: l10n.backgroundTitle,
              subtitle: l10n.backgroundSettingsHint,
              onTap: () => context.push(Routes.settingsBackground),
            ),
          ],
        ),

        // --- Group 6: About ---
        SettingGroup(
          title: 'About',
          children: [
            SettingTile.nav(
              leading: const Icon(Icons.info_outline),
              title: l10n.appTitle,
              subtitle: 'v2.0.0',
              trailing: const SizedBox.shrink(),
            ),
            SettingTile.action(
              leading: const Icon(Icons.description_outlined),
              title: 'Licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: 'v2.0.0',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
