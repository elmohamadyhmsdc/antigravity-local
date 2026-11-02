abstract class CollectionSource<T> {
  const CollectionSource();

  Future<List<T>> loadPage({
    required int offset,
    required int limit,
    String? query,
    String? sort,
    Map<String, dynamic>? filters,
  });

  Future<int> totalCount({String? query, Map<String, dynamic>? filters});
}

class InMemoryCollectionSource<T> extends CollectionSource<T> {
  InMemoryCollectionSource(this.items, {this.filterFn, this.sortFn});

  final List<T> items;
  final bool Function(T item, String? query, Map<String, dynamic>? filters)?
  filterFn;
  final int Function(T a, T b, String? sort)? sortFn;

  @override
  Future<List<T>> loadPage({
    required int offset,
    required int limit,
    String? query,
    String? sort,
    Map<String, dynamic>? filters,
  }) async {
    var filtered = items.where((item) {
      if (filterFn != null) {
        return filterFn!(item, query, filters);
      }
      return true;
    }).toList();

    if (sortFn != null) {
      filtered.sort((a, b) => sortFn!(a, b, sort));
    }

    if (offset >= filtered.length) {
      return [];
    }
    final end = (offset + limit > filtered.length)
        ? filtered.length
        : offset + limit;
    return filtered.sublist(offset, end);
  }

  @override
  Future<int> totalCount({String? query, Map<String, dynamic>? filters}) async {
    if (filterFn == null &&
        (query == null || query.isEmpty) &&
        (filters == null || filters.isEmpty)) {
      return items.length;
    }
    return items.where((item) => filterFn!(item, query, filters)).length;
  }
}
