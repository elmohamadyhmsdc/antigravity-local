import 'package:antigravity_mobile/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest(
    'encrypted export validates and confirms the password before creating an archive',
    (tester, env) async {
      await seedFace(env.db);
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/backup')],
      );
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('backup-encryption')))
            .value,
        isTrue,
      );
      await tester.ensureVisible(find.byKey(const Key('backup-export')));
      await tester.tap(find.byKey(const Key('backup-export')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('backup-password')), 'short');
      await tester.tap(find.byKey(const Key('backup-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Use 12–1024 characters.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('backup-password')),
        'a long private password',
      );
      await tester.enterText(
        find.byKey(const Key('backup-password-confirm')),
        'different password',
      );
      await tester.tap(find.byKey(const Key('backup-password-submit')));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await env.db.setting('backup.last_at'), isNull);
      expect(find.byKey(const Key('backup-password')), findsNothing);
    },
    session: testSession,
  );
}
