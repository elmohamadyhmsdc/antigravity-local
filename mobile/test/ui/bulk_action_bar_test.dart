import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/domain/actions/action_id.dart';
import 'package:antigravity_mobile/domain/actions/entity_ref.dart';
import 'package:antigravity_mobile/ui/selection/bulk_action_bar.dart';

void main() {
  testWidgets('BulkActionBar renders common actions and overflow button if > 4', (
    tester,
  ) async {
    ActionId? triggered;

    // A single entity has many actions (open, info, expand, refaceThis, restyleThis, addToDataset, share, analyzeNow, redetect)
    final entities = [const MediaEntityRef(1)];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: BulkActionBar(
              selectedEntities: entities,
              onActionDispatched: (id) => triggered = id,
            ),
          ),
        ),
      ),
    );

    // Should have up to 4 actions visible + more overflow button
    expect(find.byType(BulkActionBar), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);

    // Tap the first visible action (Open)
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(triggered, equals(ActionId.open));
  });
}
