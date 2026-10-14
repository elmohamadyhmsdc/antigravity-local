import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  appTest('shell shows the five tabs and switches between them', (
    tester,
    env,
  ) async {
    await env.pump(tester);

    // Home is the landing tab; every destination is in the bottom bar.
    for (final label in ['Home', 'People', 'Library', 'Studio', 'Jobs']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.text('Antigravity'), findsWidgets);

    await tester.tap(find.widgetWithText(NavigationDestination, 'People'));
    await tester.pumpAndSettle();
    expect(
      find.text('No people yet'),
      findsOneWidget,
      reason: 'the real People screen, empty',
    );

    await tester.tap(find.widgetWithText(NavigationDestination, 'Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Coming in phase P4'), findsOneWidget);
  }, session: testSession);

  appTest('before pairing there are no tabs - only the Welcome screen', (
    tester,
    env,
  ) async {
    await env.pump(tester);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Connect to your PC'), findsOneWidget);
  });
}
