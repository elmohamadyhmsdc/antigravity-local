import 'json_util.dart';

int? _optionalBytes(Map<String, dynamic> json, String key) =>
    json[key] == null ? null : integer(json, key);

/// PC measurements. Missing telemetry stays null rather than looking like zero.
class ResourceGpu {
  const ResourceGpu({
    required this.index,
    required this.name,
    required this.totalBytes,
    required this.usedBytes,
    required this.freeBytes,
    this.appUsedBytes,
  });

  final int index;
  final String name;
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  final int? appUsedBytes;

  factory ResourceGpu.fromJson(Map<String, dynamic> json) => ResourceGpu(
    index: integer(json, 'index'),
    name: field<String>(json, 'name'),
    totalBytes: integer(json, 'total_bytes'),
    usedBytes: integer(json, 'used_bytes'),
    freeBytes: integer(json, 'free_bytes'),
    appUsedBytes: _optionalBytes(json, 'app_used_bytes'),
  );
}

class ResourceSnapshot {
  const ResourceSnapshot({
    required this.sampledAt,
    this.appRamBytes,
    this.totalRamBytes,
    this.availableRamBytes,
    this.ramUsedPercent,
    this.diskTotalBytes,
    this.diskFreeBytes,
    required this.appStorageBytes,
    required this.storageComplete,
    required this.processesComplete,
    required this.gpus,
    required this.alerts,
    required this.warnings,
    required this.admissionBlocked,
    required this.admissionReasons,
  });

  final DateTime sampledAt;
  final int? appRamBytes;
  final int? totalRamBytes;
  final int? availableRamBytes;
  final double? ramUsedPercent;
  final int? diskTotalBytes;
  final int? diskFreeBytes;
  final int appStorageBytes;
  final bool storageComplete;
  final bool processesComplete;
  final List<ResourceGpu> gpus;
  final List<String> alerts;
  final List<String> warnings;
  final bool admissionBlocked;
  final List<String> admissionReasons;

  factory ResourceSnapshot.fromJson(Map<String, dynamic> json) {
    final ram = json['ram'] == null ? null : map(json['ram'], 'ram');
    final disk = json['disk'] == null ? null : map(json['disk'], 'disk');
    return ResourceSnapshot(
      sampledAt: DateTime.parse(field<String>(json, 'sampled_at')),
      appRamBytes: _optionalBytes(json, 'app_ram_bytes'),
      totalRamBytes: ram == null ? null : integer(ram, 'total_bytes'),
      availableRamBytes: ram == null ? null : integer(ram, 'available_bytes'),
      ramUsedPercent: ram == null ? null : number(ram, 'used_percent'),
      diskTotalBytes: disk == null ? null : integer(disk, 'total_bytes'),
      diskFreeBytes: disk == null ? null : integer(disk, 'free_bytes'),
      appStorageBytes: integer(json, 'app_storage_bytes'),
      storageComplete: field<bool>(json, 'storage_complete'),
      processesComplete: field<bool>(json, 'processes_complete'),
      gpus: [
        for (final gpu in list(json['gpus'], 'gpus'))
          ResourceGpu.fromJson(map(gpu, 'gpu')),
      ],
      alerts: list(json['alerts'], 'alerts').cast<String>(),
      warnings: list(json['warnings'], 'warnings').cast<String>(),
      admissionBlocked: field<bool>(json, 'admission_blocked'),
      admissionReasons: list(
        json['admission_reasons'],
        'admission_reasons',
      ).cast<String>(),
    );
  }
}
