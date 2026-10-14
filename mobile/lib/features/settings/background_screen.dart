import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/background_execution.dart';
import '../../data/platform/foreground_keep_alive.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

const _promptedKey = 'background.prompted';

/// Ask once after a user starts work. Declining never blocks the scan.
Future<void> prepareBackgroundForWork(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final service = ref.read(backgroundExecutionProvider);
    final status = await service.status();
    if (!status.supported || status.ready || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (await db.setting(_promptedKey) == 'true' || !context.mounted) return;
    await db.putSetting(_promptedKey, 'true');
    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    final allow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.backgroundTitle),
        content: Text(l.backgroundIntro),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.backgroundLater),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.backgroundEnable),
          ),
        ],
      ),
    );
    if (allow == true) await service.request();
  } on Object {
    // Optional permissions must never discard the work the user requested.
  }
}

class BackgroundScreen extends ConsumerStatefulWidget {
  const BackgroundScreen({super.key});
  @override
  ConsumerState<BackgroundScreen> createState() => _BackgroundScreenState();
}

class _BackgroundScreenState extends ConsumerState<BackgroundScreen>
    with WidgetsBindingObserver {
  BackgroundStatus? _status;
  String? _error;
  var _busy = false;
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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await ref.read(backgroundExecutionProvider).status();
      if (mounted) {
        setState(() {
          _status = status;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      await ref.read(databaseProvider).putSetting(_promptedKey, 'true');
      await ref.read(backgroundExecutionProvider).request();
      await _refresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = _status;
    Widget row(IconData icon, String title, bool enabled) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: Icon(
        enabled ? Icons.check_circle : Icons.pending_outlined,
        color: enabled ? Theme.of(context).colorScheme.primary : null,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.backgroundTitle),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: l.backgroundRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.backgroundIntro),
          const SizedBox(height: 20),
          if (status == null && _error == null) const LinearProgressIndicator(),
          if (status != null && !status.supported)
            Text(l.backgroundAndroidOnly),
          if (status != null && status.supported) ...[
            row(
              Icons.notifications_outlined,
              l.backgroundNotifications,
              status.notifications,
            ),
            row(
              Icons.battery_charging_full,
              l.backgroundBattery,
              status.unrestricted,
            ),
            row(
              Icons.sync,
              status.running ? l.backgroundRunning : l.backgroundIdle,
              status.running,
            ),
            const SizedBox(height: 16),
            if (!status.ready)
              FilledButton(
                key: const Key('background-enable'),
                onPressed: _busy ? null : _request,
                child: Text(l.backgroundEnable),
              ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await ref
                          .read(backgroundExecutionProvider)
                          .openSettings();
                      await _refresh();
                    },
              child: Text(l.backgroundOpenSettings),
            ),
          ],
          ValueListenableBuilder<Object?>(
            valueListenable: foregroundServiceCoordinator.error,
            builder: (context, error, _) => error == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l.backgroundServiceFailed),
                  ),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 20),
          Text(
            l.backgroundLimits,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
