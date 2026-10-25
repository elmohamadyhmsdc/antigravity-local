import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// `testWidgets` + a [TestEnv] (in-memory database, fakes for every platform seam) that is
/// always torn down cleanly: the app is unmounted first so polling timers are cancelled, then
/// the database is closed.
void appTest(
  String description,
  Future<void> Function(WidgetTester tester, TestEnv env) body, {
  ServerSession? session,
  FakeMobileApi? api,
}) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final env = TestEnv(session: session, api: api);
    try {
      await body(tester, env);
    } finally {
      await env.dispose(tester);
    }
  });
}

Finder textContaining(String part) => find.byWidgetPredicate(
  (w) =>
      w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(part),
  description: 'Text containing "$part"',
);

Future<void> pickRefaceTarget(
  WidgetTester tester, {
  String source = 'files',
}) async {
  await tester.ensureVisible(find.byKey(const Key('reface-target')));
  await tester.tap(find.byKey(const Key('reface-target')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('reface-source-$source')));
  await tester.pumpAndSettle();
}
