import 'package:antigravity_mobile/data/api/dtos/resources.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('PC resource fixture preserves totals and unavailable process VRAM', () {
    final value = ResourceSnapshot.fromJson(fixture('ResourceSnapshot.idle'));
    expect(value.appRamBytes, 2147483648);
    expect(value.availableRamBytes, 8589934592);
    expect(value.gpus.single.usedBytes, 2147483648);
    expect(value.gpus.single.appUsedBytes, isNull);
    expect(value.diskFreeBytes, 549755813888);
    expect(value.admissionBlocked, isFalse);
  });

  test('missing RAM and GPU telemetry is distinct from zero usage', () {
    final json = copyOf(fixture('ResourceSnapshot.idle'))
      ..['app_ram_bytes'] = null
      ..['ram'] = null
      ..['disk'] = null
      ..['gpus'] = [];
    final value = ResourceSnapshot.fromJson(json);
    expect(value.appRamBytes, isNull);
    expect(value.totalRamBytes, isNull);
    expect(value.availableRamBytes, isNull);
    expect(value.diskFreeBytes, isNull);
    expect(value.gpus, isEmpty);
  });

  test('admission pressure and measurement completeness survive parsing', () {
    final json = copyOf(fixture('ResourceSnapshot.idle'))
      ..['admission_blocked'] = true
      ..['admission_reasons'] = ['RAM threshold reached.']
      ..['processes_complete'] = false
      ..['storage_complete'] = false;
    final value = ResourceSnapshot.fromJson(json);
    expect(value.admissionBlocked, isTrue);
    expect(value.admissionReasons, ['RAM threshold reached.']);
    expect(value.processesComplete, isFalse);
    expect(value.storageComplete, isFalse);
  });
}
