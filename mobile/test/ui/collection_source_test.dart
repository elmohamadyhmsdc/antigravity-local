import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/collection/collection_source.dart';

void main() {
  test('InMemoryCollectionSource pages and filters correctly', () async {
    final items = List.generate(100, (i) => 'Item $i');
    final source = InMemoryCollectionSource<String>(
      items,
      filterFn: (item, query, filters) {
        if (query != null && query.isNotEmpty) {
          return item.toLowerCase().contains(query.toLowerCase());
        }
        return true;
      },
    );

    // Total count
    final total = await source.totalCount();
    expect(total, equals(100));

    // Page 0: 0..20
    final page1 = await source.loadPage(offset: 0, limit: 20);
    expect(page1.length, equals(20));
    expect(page1.first, equals('Item 0'));
    expect(page1.last, equals('Item 19'));

    // Page 1: 20..40
    final page2 = await source.loadPage(offset: 20, limit: 20);
    expect(page2.length, equals(20));
    expect(page2.first, equals('Item 20'));
    expect(page2.last, equals('Item 39'));

    // Query filter
    final filtered = await source.loadPage(
      offset: 0,
      limit: 20,
      query: 'Item 5',
    );
    // Item 5, Item 50, Item 51, ..., Item 59
    expect(filtered.length, equals(11));
    expect(filtered.first, equals('Item 5'));
  });
}
