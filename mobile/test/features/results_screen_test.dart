import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import '../support/harness.dart';

void main() {
  appTest('ResultsScreen mounts and displays results with keys', (
    tester,
    env,
  ) async {
    // Insert a dummy result in the database
    await env.db
        .into(env.db.results)
        .insert(
          ResultsCompanion.insert(
            id: 'res-test-1',
            type: 'reface',
            path: 'results/res-test-1.jpg',
            originalPath: 'photos/orig.jpg',
            mime: 'image/jpeg',
            sizeBytes: 1024,
            sha256: 'abc123',
            createdAt: 1000,
          ),
        );

    await env.pump(
      tester,
      settle: false,
      extra: [initialLocationProvider.overrideWithValue('/results')],
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('result-res-test-1')), findsOneWidget);
  });
}
