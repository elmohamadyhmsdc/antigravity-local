import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/collection/collection_controller.dart';
import 'package:antigravity_mobile/ui/collection/collection_source.dart';
import 'package:antigravity_mobile/ui/collection/collection_view.dart';
import 'package:antigravity_mobile/ui/states/empty_state.dart';

void main() {
  testWidgets('CollectionView renders loading, empty and content states', (
    tester,
  ) async {
    final source = InMemoryCollectionSource<String>(
      ['Item 1', 'Item 2', 'Item 3'],
      filterFn: (item, query, _) {
        if (query != null && query.isNotEmpty) {
          return item.toLowerCase().contains(query.toLowerCase());
        }
        return true;
      },
    );
    final controller = CollectionController<String>(
      source: source,
      idExtractor: (item) => item,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionView<String>(
            controller: controller,
            itemBuilder: (context, item, index) => Text(item),
          ),
        ),
      ),
    );

    // Initial state is loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Load items
    await controller.loadInitial();
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
    expect(find.text('Item 3'), findsOneWidget);

    // Set query with no results
    controller.setQuery('nonexistent');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(EmptyState), findsOneWidget);
  });
}
