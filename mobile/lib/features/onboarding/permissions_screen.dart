import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/platform/platform_services.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../shared/screen_layout.dart';

/// S02 - Permissions: says why each one is wanted before Android asks. All optional.
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<AppPermission, PermissionState>? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(); // back from Android settings
    }
  }

  Future<void> _refresh() async {
    final status = await ref.read(permissionsServiceProvider).status();
    if (mounted) setState(() => _status = status);
  }

  Future<void> _tap(AppPermission permission) async {
    final service = ref.read(permissionsServiceProvider);
    if (_status?[permission] == PermissionState.blocked) {
      await service.openSettings();
      return;
    }
    await service.request(permission);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <(AppPermission, IconData, String, String)>[
      (
        AppPermission.media,
        Icons.photo_library_outlined,
        l10n.permMediaTitle,
        l10n.permMediaWhy,
      ),
      (
        AppPermission.camera,
        Icons.photo_camera_outlined,
        l10n.permCameraTitle,
        l10n.permCameraWhy,
      ),
      (
        AppPermission.notifications,
        Icons.notifications_outlined,
        l10n.permNotificationsTitle,
        l10n.permNotificationsWhy,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.permissionsTitle),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ScreenIntro(
                    title: l10n.permissionsHeadline,
                    body: l10n.permissionsIntro,
                  ),
                  for (final (permission, icon, title, why) in rows)
                    _PermissionCard(
                      key: Key('perm-${permission.name}'),
                      icon: icon,
                      title: title,
                      why: why,
                      state: _status?[permission],
                      onTap: () => _tap(permission),
                    ),
                  ListTile(
                    key: const Key('permissions-background'),
                    leading: const Icon(Icons.battery_charging_full),
                    title: Text(l10n.backgroundTitle),
                    subtitle: Text(l10n.backgroundSettingsHint),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.background),
                  ),
                ],
              ),
            ),
            StickyActionBar(
              avoidKeyboard: false,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('permissions-continue'),
                  onPressed: () => context.go(Routes.home),
                  child: Text(l10n.permContinue),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.why,
    required this.state,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String why;
  final PermissionState? state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Widget trailing = switch (state) {
      null => const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      PermissionState.granted => Chip(
        avatar: Icon(Icons.check_circle, color: theme.colorScheme.primary),
        label: Text(l10n.permGranted),
      ),
      PermissionState.denied => FilledButton.tonal(
        onPressed: onTap,
        child: Text(l10n.permAllow),
      ),
      // too wide for the title row on a narrow phone: the action goes under the explanation
      PermissionState.blocked => const SizedBox.shrink(),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              why,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (state != PermissionState.blocked) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: trailing,
              ),
            ],
            if (state == PermissionState.blocked)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.permBlocked),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
