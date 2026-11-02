import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/cards/entity_card.dart';

void main() {
  testWidgets('EntityCard renders grid layout with title and selected state', (
    tester,
  ) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: EntityCard(
              visual: const IconVisual(Icons.photo),
              title: 'Card 1',
              state: EntityCardState.selected,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Card 1'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Card 1'));
    expect(tapped, isTrue);
  });

  testWidgets('EntityCard respects disabled state', (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            height: 150,
            child: EntityCard(
              visual: const IconVisual(Icons.photo),
              title: 'Disabled Card',
              state: EntityCardState.disabled,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Disabled Card'));
    expect(tapped, isFalse);
  });
}
