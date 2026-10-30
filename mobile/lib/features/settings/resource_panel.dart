import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/dtos/resources.dart';
import '../../data/api/resource_api.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../shared/screen_layout.dart';

final resourceApiProvider = Provider<ResourceApi?>((ref) {
  final api = ref.watch(mobileApiProvider);
  return switch (api) {
    ResourceApi resourceApi => resourceApi,
    _ => null,
  };
});

final resourceSnapshotProvider = StreamProvider.autoDispose<ResourceSnapshot>((
  ref,
) {
  final api = ref.watch(resourceApiProvider);
  final events = StreamController<ResourceSnapshot>();
  var closed = false;
  var paused = false;
  var inFlight = false;
  var foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  Timer? timer;
  Future<void> poll() async {
    if (closed || paused || !foreground || inFlight || api == null) return;
    inFlight = true;
    var keepPolling = true;
    try {
      final snapshot = await api.resources();
      if (!closed && !paused && foreground) events.add(snapshot);
    } on Object catch (error, stack) {
      if (!closed && !paused && foreground) events.addError(error, stack);
      if (error is ApiException &&
          (error.statusCode == 404 || error.isUnauthorized)) {
        keepPolling = false;
      }
    } finally {
      inFlight = false;
    }
    if (!closed && !paused && foreground && keepPolling) {
      timer = Timer(const Duration(seconds: 5), poll);
    }
  }

  // Backgrounding can suspend rendering before a widget rebuild removes its
  // subscription, so cancel the timer directly from the lifecycle event too.
  final lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      foreground = state == AppLifecycleState.resumed;
      if (foreground) {
        poll();
      } else {
        timer?.cancel();
      }
    },
  );
  poll();
  ref.onCancel(() {
    paused = true;
    timer?.cancel();
  });
  ref.onResume(() {
    paused = false;
    poll();
  });
  ref.onDispose(() {
    closed = true;
    lifecycle.dispose();
    timer?.cancel();
    events.close();
  });
  return events.stream;
}, retry: (count, error) => null);

/// Poll only when expanded, visible, and the app is in the foreground.
class ResourcePanel extends ConsumerStatefulWidget {
  const ResourcePanel({super.key});

  @override
  ConsumerState<ResourcePanel> createState() => _ResourcePanelState();
}

class _ResourcePanelState extends ConsumerState<ResourcePanel>
    with WidgetsBindingObserver {
  bool _expanded = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final api = ref.watch(resourceApiProvider);
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final active = _expanded && _foreground && visible && api != null;
    final value = active ? ref.watch(resourceSnapshotProvider) : null;
    return ExpansionTile(
      key: const Key('pc-resources'),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.memory_outlined),
      title: Text(l10n.resourcesTitle),
      subtitle: Text(l10n.resourcesSubtitle),
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
      children: [
        if (_expanded && api == null)
          StatusNotice(message: l10n.resourcesUnavailable)
        else if (value != null)
          value.when(
            skipLoadingOnRefresh: false,
            skipError: false,
            data: (snapshot) => _ResourceReadings(snapshot: snapshot),
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatusNotice(message: l10n.resourcesUnavailable, isError: true),
                TextButton(
                  onPressed: () => ref.invalidate(resourceSnapshotProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _bytes(int? bytes, String unavailable) {
  if (bytes == null) return unavailable;
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class _ResourceReadings extends StatelessWidget {
  const _ResourceReadings({required this.snapshot});
  final ResourceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String bytes(int? value) => _bytes(value, l10n.resourcesUnknown);
    Widget reading(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          reading(l10n.resourcesAppRam, bytes(snapshot.appRamBytes)),
          reading(
            l10n.resourcesRamAvailable,
            bytes(snapshot.availableRamBytes),
          ),
          if (snapshot.ramUsedPercent != null)
            LinearProgressIndicator(
              value: (snapshot.ramUsedPercent! / 100).clamp(0.0, 1.0),
              semanticsLabel: l10n.resourcesSystemRam,
              semanticsValue: '${snapshot.ramUsedPercent!.toStringAsFixed(0)}%',
            ),
          if (snapshot.gpus.isEmpty)
            reading(l10n.resourcesGpuTotal, l10n.resourcesUnknown),
          for (final gpu in snapshot.gpus) ...[
            const Divider(),
            Text(gpu.name, style: Theme.of(context).textTheme.titleSmall),
            reading(
              l10n.resourcesGpuTotal,
              '${bytes(gpu.usedBytes)} / ${bytes(gpu.totalBytes)}',
            ),
            LinearProgressIndicator(
              value: gpu.totalBytes > 0
                  ? (gpu.usedBytes / gpu.totalBytes).clamp(0.0, 1.0)
                  : 0,
              semanticsLabel: l10n.resourcesGpuTotal,
            ),
            reading(l10n.resourcesAppVram, bytes(gpu.appUsedBytes)),
          ],
          const Divider(),
          reading(l10n.resourcesDiskAvailable, bytes(snapshot.diskFreeBytes)),
          reading(l10n.resourcesScratch, bytes(snapshot.appStorageBytes)),
          if (!snapshot.storageComplete) Text(l10n.resourcesStoragePartial),
          if (!snapshot.processesComplete) Text(l10n.resourcesProcessPartial),
          for (final alert in {...snapshot.alerts, ...snapshot.warnings})
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StatusNotice(message: alert),
            ),
          if (snapshot.admissionBlocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StatusNotice(
                message:
                    '${l10n.resourcesWaiting}\n${snapshot.admissionReasons.join(' ')}',
                isError: true,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l10n.resourcesScopeHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.resourcesLimitsHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.resourcesUpdated}: ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(snapshot.sampledAt.toLocal()))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
