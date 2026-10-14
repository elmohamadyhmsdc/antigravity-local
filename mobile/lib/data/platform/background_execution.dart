import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

class BackgroundStatus {
  const BackgroundStatus({
    required this.supported,
    this.notifications = false,
    this.unrestricted = false,
    this.running = false,
  });
  final bool supported, notifications, unrestricted, running;
  bool get ready => notifications && unrestricted;
}

abstract interface class BackgroundExecution {
  Future<BackgroundStatus> status();
  Future<void> request();
  Future<void> openSettings();
}

class AndroidBackgroundExecution implements BackgroundExecution {
  @override
  Future<BackgroundStatus> status() async {
    if (!Platform.isAndroid) return const BackgroundStatus(supported: false);
    return BackgroundStatus(
      supported: true,
      notifications:
          await FlutterForegroundTask.checkNotificationPermission() ==
          NotificationPermission.granted,
      unrestricted: await FlutterForegroundTask.isIgnoringBatteryOptimizations,
      running: await FlutterForegroundTask.isRunningService,
    );
  }

  @override
  Future<void> request() async {
    if (!Platform.isAndroid) return;
    if (await FlutterForegroundTask.checkNotificationPermission() !=
        NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}

final backgroundExecutionProvider = Provider<BackgroundExecution>(
  (ref) => AndroidBackgroundExecution(),
);
