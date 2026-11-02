import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/features/storage/storage_screen.dart';
import '../support/harness.dart';

void main() {
  appTest('StorageScreen mounts with expected keys and scaffold', (
    tester,
    env,
  ) async {
    await env.pump(
      tester,
      settle: false,
      extra: [initialLocationProvider.overrideWithValue('/storage')],
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(StorageScreen), findsOneWidget);
    expect(find.byKey(const Key('storage-clean-temporary')), findsOneWidget);
    expect(find.byKey(const Key('storage-saved-files')), findsOneWidget);
  });
}
