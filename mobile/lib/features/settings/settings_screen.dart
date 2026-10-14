import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/app_settings.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../review/review_screen.dart';
import '../privacy/app_lock.dart';

/// S24 (the library part) - how strictly the PC groups faces, how good a face must be to be kept,
/// scan defaults, and the way into Sources, Backup and "Sort now".
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double? _gateDraft; // while the slider is dragged

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings =
        ref.watch(settingsProvider).value ?? const SettingsSnapshot();
    final store = ref.read(appSettingsProvider);
    final session = ref.watch(sessionProvider);
    final text = Theme.of(context).textTheme;
    final gate = _gateDraft ?? settings.qualityGate;

    String strictnessHint(String s) => switch (s) {
      'strict' => l10n.strictnessStrictHint,
      'loose' => l10n.strictnessLooseHint,
      _ => l10n.strictnessBalancedHint,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            key: const Key('app-lock'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.appLockTitle),
            subtitle: Text(l10n.appLockHint),
            value: ref.watch(appLockEnabledProvider).value ?? false,
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.storageTitle),
            leading: const Icon(Icons.storage_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.storage),
          ),
          Text(l10n.settingsGrouping, style: text.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('strictness'),
            segments: [
              ButtonSegment(
                value: 'strict',
                label: Text(l10n.strictnessStrict),
              ),
              ButtonSegment(
                value: 'balanced',
                label: Text(l10n.strictnessBalanced),
              ),
              ButtonSegment(value: 'loose', label: Text(l10n.strictnessLoose)),
            ],
            selected: {settings.strictness},
            onSelectionChanged: (s) => store.setStrictness(s.first),
          ),
          const SizedBox(height: 6),
          Text(strictnessHint(settings.strictness), style: text.bodySmall),
          const SizedBox(height: 24),
          Text(l10n.settingsQualityGate, style: text.titleMedium),
          Text(l10n.settingsQualityGateHint, style: text.bodySmall),
          Slider(
            key: const Key('quality-gate'),
            value: gate.clamp(minQualityGate, maxQualityGate),
            min: minQualityGate,
            max: maxQualityGate,
            divisions: 12,
            label: gate.toStringAsFixed(2),
            onChanged: (v) => setState(() => _gateDraft = v),
            onChangeEnd: (v) async {
              await store.setQualityGate(v);
              if (mounted) setState(() => _gateDraft = null);
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              l10n.qualityGateValue(gate.toStringAsFixed(2)),
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.settingsScanDefaults, style: text.titleMedium),
          SwitchListTile(
            key: const Key('settings-bodies'),
            contentPadding: EdgeInsets.zero,
            value: settings.scanBodies,
            title: Text(l10n.optionBodies),
            subtitle: Text(l10n.optionBodiesHint),
            onChanged: store.setScanBodies,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.optionImageSize),
            subtitle: Text(l10n.optionImageSizeHint),
            trailing: DropdownButton<int>(
              key: const Key('settings-max-side'),
              value: maxSideChoices.contains(settings.maxSide)
                  ? settings.maxSide
                  : defaultMaxSide,
              underline: const SizedBox.shrink(),
              items: [
                for (final s in maxSideChoices)
                  DropdownMenuItem(value: s, child: Text('$s px')),
              ],
              onChanged: (v) {
                if (v != null) store.setMaxSide(v);
              },
            ),
          ),
          const Divider(height: 32),
          ListTile(
            key: const Key('settings-sources'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.sourcesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.sources),
          ),
          ListTile(
            key: const Key('settings-sort-now'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high),
            title: Text(l10n.sortNow),
            subtitle: Text(l10n.sortNowHint),
            onTap: () => sortNow(context, ref),
          ),
          ListTile(
            key: const Key('settings-backup'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_outlined),
            title: Text(l10n.backupTitle),
            subtitle: Text(l10n.backupSettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.backup),
          ),
          const Divider(height: 32),
          Text(l10n.settingsPc, style: text.titleMedium),
          ListTile(
            key: const Key('settings-background'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.battery_charging_full),
            title: Text(l10n.backgroundTitle),
            subtitle: Text(l10n.backgroundSettingsHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.background),
          ),
          ListTile(
            key: const Key('settings-pc'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.computer_outlined),
            title: Text(session?.name ?? l10n.notPaired),
            subtitle: session == null
                ? null
                : Text('${session.host}:${session.port}'),
          ),
        ],
      ),
    );
  }
}
