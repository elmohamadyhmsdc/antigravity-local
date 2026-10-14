import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../domain/scan/scan_state.dart';

/// Android foreground service with a progress notification: keeps the app's process (and its
/// network sockets) alive while a scan runs with the screen off. The scan itself runs in the app's
/// own isolate; the service has no Dart task of its own.
class ForegroundServiceKeepAlive implements ScanKeepAlive {
  const ForegroundServiceKeepAlive({
    required this.channelName,
    required this.channelDescription,
  });

  final String channelName;
  final String channelDescription;

  static const _serviceId = 4711;
  static var _initialised = false;

  void _init() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'antigravity_scan',
        channelName: channelName,
        channelDescription: channelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialised = true;
  }

  @override
  Future<void> start({required String title, required String text}) async {
    try {
      _init();
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: title,
          notificationText: text,
        );
        return;
      }
      // A refused service (no notification permission, Android restriction) only costs background
      // time: the scan still runs while the app is open.
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: title,
        notificationText: text,
      );
    } on Object {
      // never let the notification break the scan
    }
  }

  @override
  Future<void> update(String text) async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(notificationText: text);
      }
    } on Object {
      // best effort
    }
  }

  @override
  Future<void> stop() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } on Object {
      // best effort
    }
  }
}
