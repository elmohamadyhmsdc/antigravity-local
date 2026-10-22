import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../domain/scan/scan_state.dart';

const _workPortName = 'antigravity.active_phone_work';
ReceivePort? _workPort;

void _registerWorkPort() {
  if (_workPort != null) return;
  final port = ReceivePort();
  IsolateNameServer.removePortNameMapping(_workPortName);
  IsolateNameServer.registerPortWithName(port.sendPort, _workPortName);
  port.listen((message) {
    if (message is SendPort) message.send(foregroundServiceCoordinator.hasWork);
  });
  _workPort = port;
}

@pragma('vm:entry-point')
void backgroundWorkEntryPoint() =>
    FlutterForegroundTask.setTaskHandler(_WorkGuard());

/// A service restarted by Android must not show stale progress after the app's
/// process was killed. Only the retained main engine owns the actual queue.
class _WorkGuard extends TaskHandler {
  Future<void> _check() async {
    final owner = IsolateNameServer.lookupPortByName(_workPortName);
    var active = false;
    if (owner != null) {
      final reply = ReceivePort();
      try {
        owner.send(reply.sendPort);
        active =
            await reply.first.timeout(
              const Duration(seconds: 10),
              onTimeout: () => false,
            ) ==
            true;
      } finally {
        reply.close();
      }
    }
    if (!active) await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) => _check();
  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_check());
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
  @override
  void onNotificationPressed() => FlutterForegroundTask.launchApp();
}

abstract interface class ForegroundBackend {
  Future<bool> get running;
  Future<void> start(String title, String text);
  Future<void> update(String title, String text);
  Future<void> stop();
}

class AndroidForegroundBackend implements ForegroundBackend {
  var _initialised = false;
  void _init() {
    if (_initialised) return;
    _registerWorkPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'antigravity_scan',
        channelName: 'Background work',
        channelDescription: 'Scan and Studio progress while the screen is off.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: false,
        // Work lives in the retained engine. Do not restart a notification
        // alone in a fresh process without restoring the phone's job queue.
        allowAutoRestart: false,
      ),
    );
    _initialised = true;
  }

  void _check(ServiceRequestResult result) {
    if (result case ServiceRequestFailure(:final error)) throw error;
  }

  @override
  Future<bool> get running async =>
      Platform.isAndroid && await FlutterForegroundTask.isRunningService;
  @override
  Future<void> start(String title, String text) async {
    if (!Platform.isAndroid) return;
    _init();
    _check(
      await FlutterForegroundTask.startService(
        serviceId: 4711,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
        callback: backgroundWorkEntryPoint,
      ),
    );
  }

  @override
  Future<void> update(String title, String text) async {
    _check(
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      ),
    );
  }

  @override
  Future<void> stop() async =>
      _check(await FlutterForegroundTask.stopService());
}

/// Serialize Scan/Studio leases: a finishing scan must not stop Studio's service.
class ForegroundServiceCoordinator {
  ForegroundServiceCoordinator(this.backend);
  final ForegroundBackend backend;
  final error = ValueNotifier<Object?>(null);
  final _leases = <String, ({String title, String text})>{};
  Future<void> _pending = Future.value();
  bool get hasWork => _leases.isNotEmpty;
  Future<void> _enqueue(void Function() change) {
    return _pending = _pending.then((_) async {
      change();
      try {
        final running = await backend.running;
        if (_leases.isEmpty) {
          if (running) await backend.stop();
        } else {
          final title = _leases.length == 1
              ? _leases.values.first.title
              : 'Your Gallery';
          final text = _leases.values.map((lease) => lease.text).join(' • ');
          if (running) {
            await backend.update(title, text);
          } else {
            await backend.start(title, text);
          }
        }
        error.value = null;
      } on Object catch (failure) {
        // Keep foreground work available, expose the restriction, retry later.
        error.value = failure;
      }
    });
  }

  Future<void> acquire(String key, String title, String text) =>
      _enqueue(() => _leases[key] = (title: title, text: text));
  Future<void> update(String key, String text) => _enqueue(() {
    final lease = _leases[key];
    if (lease != null) _leases[key] = (title: lease.title, text: text);
  });
  Future<void> release(String key) => _enqueue(() => _leases.remove(key));
}

final foregroundServiceCoordinator = ForegroundServiceCoordinator(
  AndroidForegroundBackend(),
);

/// Work stays in the retained app isolate, with wake/Wi-Fi locks and progress.
class ForegroundServiceKeepAlive implements ScanKeepAlive {
  const ForegroundServiceKeepAlive({
    required this.channelName,
    required this.channelDescription,
    this.coordinator,
  });
  final String channelName, channelDescription;
  final ForegroundServiceCoordinator? coordinator;
  ForegroundServiceCoordinator get _service =>
      coordinator ?? foregroundServiceCoordinator;
  @override
  Future<void> start({required String title, required String text}) =>
      _service.acquire(channelName, title, text);
  @override
  Future<void> update(String text) => _service.update(channelName, text);
  @override
  Future<void> stop() => _service.release(channelName);
}
