import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

void main() {
  appTest('shell shows the four tabs and switches between them', (
    tester,
    env,
  ) async {
    await env.pump(tester);

    // Gallery is the landing tab; four destinations remain available.
    for (final label in ['Gallery', 'People', 'Explore', 'Studio']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.text('Gallery'), findsWidgets);

    await tester.tap(find.widgetWithText(NavigationDestination, 'People'));
    await tester.pumpAndSettle();
    expect(
      find.text('No people yet'),
      findsOneWidget,
      reason: 'the real People screen, empty',
    );

    await tester.tap(find.widgetWithText(NavigationDestination, 'Explore'));
    await tester.pumpAndSettle();
    expect(find.text('Poses'), findsOneWidget);
  }, session: testSession);

  appTest('before pairing Gallery and navigation remain available', (
    tester,
    env,
  ) async {
    await env.pump(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Gallery'), findsWidgets);
  });
}
