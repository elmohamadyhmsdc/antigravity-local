import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Things only the phone's OS can do, behind small interfaces so screens are testable.

// ---- permissions ---------------------------------------------------------------

enum AppPermission { media, camera, notifications }

enum PermissionState { granted, denied, blocked }

abstract interface class PermissionsService {
  Future<Map<AppPermission, PermissionState>> status();
  Future<PermissionState> request(AppPermission permission);
  Future<bool> openSettings();
}

class OsPermissionsService implements PermissionsService {
  const OsPermissionsService();

  // Android 13+: READ_MEDIA_IMAGES + READ_MEDIA_VIDEO. permission_handler maps `photos`/`videos` to the
  // legacy READ_EXTERNAL_STORAGE on older versions.
  static const _media = [Permission.photos, Permission.videos];

  static PermissionState _from(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermissionState.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return PermissionState.blocked;
    return PermissionState.denied;
  }

  static PermissionState _all(Iterable<PermissionState> states) {
    if (states.every((s) => s == PermissionState.granted)) {
      return PermissionState.granted;
    }
    if (states.any((s) => s == PermissionState.blocked)) {
      return PermissionState.blocked;
    }
    return PermissionState.denied;
  }

  @override
  Future<Map<AppPermission, PermissionState>> status() async => {
    AppPermission.media: _all([for (final p in _media) _from(await p.status)]),
    AppPermission.camera: _from(await Permission.camera.status),
    AppPermission.notifications: _from(await Permission.notification.status),
  };

  @override
  Future<PermissionState> request(AppPermission permission) async {
    switch (permission) {
      case AppPermission.media:
        final result = await _media.request();
        return _all(result.values.map(_from));
      case AppPermission.camera:
        return _from(await Permission.camera.request());
      case AppPermission.notifications:
        return _from(await Permission.notification.request());
    }
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}

// ---- photo picking -------------------------------------------------------------

abstract interface class PhotoPicker {
  /// One photo, already downscaled so its long side is at most [maxSide] px (null = cancelled).
  Future<Uint8List?> pickPhoto({int maxSide = 2560});
}

class GalleryPhotoPicker implements PhotoPicker {
  GalleryPhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pickPhoto({int maxSide = 2560}) async {
    // The Android photo picker needs no storage permission; image_picker rotates by EXIF and downscales natively.
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxSide.toDouble(),
      maxHeight: maxSide.toDouble(),
      imageQuality: 92,
    );
    return file?.readAsBytes();
  }
}

// ---- device name ---------------------------------------------------------------

Future<String> readDeviceName() async {
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    final name = '${info.manufacturer} ${info.model}'.trim();
    return name.isEmpty ? 'Android phone' : name;
  } catch (_) {
    return 'Android phone';
  }
}
