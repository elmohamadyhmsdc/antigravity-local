import 'dart:convert';
import 'dart:io';

/// The golden fixtures shared with the PC server's tests:
/// `the app/mobile_api/contract/fixtures/<Schema>.<variant>.json`.
/// `flutter test` runs from the mobile/ folder, so the path is relative to it.
final fixtureDir = Directory('../the app/mobile_api/contract/fixtures');

Map<String, dynamic> fixture(String name) {
  final file = File('${fixtureDir.path}/$name.json');
  if (!file.existsSync()) {
    throw StateError(
      'Missing fixture $name.json - run flutter test from mobile/ and regenerate with make_fixtures.py',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// A deep copy that tests can mutate to break one field.
Map<String, dynamic> copyOf(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
