import 'package:flutter/foundation.dart';

import 'collection_source.dart';

enum CollectionStatus { loading, empty, content, error }

class CollectionState<T> {
  const CollectionState({
    this.status = CollectionStatus.loading,
    this.items = const [],
    this.totalCount = 0,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.query = '',
    this.sort,
    this.filters = const {},
    this.selectedIds = const {},
  });

  final CollectionStatus status;
  final List<T> items;
  final int totalCount;
  final bool hasMore;
  final bool isLoadingMore;
  final String? errorMessage;
  final String query;
  final String? sort;
  final Map<String, dynamic> filters;
  final Set<Object> selectedIds;

  bool get isSelecting => selectedIds.isNotEmpty;

  CollectionState<T> copyWith({
    CollectionStatus? status,
    List<T>? items,
    int? totalCount,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    String? query,
    String? sort,
    Map<String, dynamic>? filters,
    Set<Object>? selectedIds,
  }) => CollectionState<T>(
    status: status ?? this.status,
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    hasMore: hasMore ?? this.hasMore,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    errorMessage: errorMessage ?? this.errorMessage,
    query: query ?? this.query,
    sort: sort ?? this.sort,
    filters: filters ?? this.filters,
    selectedIds: selectedIds ?? this.selectedIds,
  );
}

class CollectionController<T> extends ChangeNotifier {
  CollectionController({
    required this.source,
    required this.idExtractor,
    this.pageSize = 60,
    String initialQuery = '',
    String? initialSort,
    Map<String, dynamic> initialFilters = const {},
  }) : _state = CollectionState<T>(
         query: initialQuery,
         sort: initialSort,
         filters: initialFilters,
       );

  final CollectionSource<T> source;
  final Object Function(T item) idExtractor;
  final int pageSize;

  CollectionState<T> _state;
  CollectionState<T> get state => _state;

  Future<void> loadInitial() async {
    _state = _state.copyWith(
      status: CollectionStatus.loading,
      errorMessage: null,
    );
    notifyListeners();

    try {
      final total = await source.totalCount(
        query: _state.query,
        filters: _state.filters,
      );
      final items = await source.loadPage(
        offset: 0,
        limit: pageSize,
        query: _state.query,
        sort: _state.sort,
        filters: _state.filters,
      );

      _state = _state.copyWith(
        status: items.isEmpty
            ? CollectionStatus.empty
            : CollectionStatus.content,
        items: items,
        totalCount: total,
        hasMore: items.length < total,
      );
    } catch (e) {
      _state = _state.copyWith(
        status: CollectionStatus.error,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_state.isLoadingMore || !_state.hasMore) return;

    _state = _state.copyWith(isLoadingMore: true);
    notifyListeners();

    try {
      final more = await source.loadPage(
        offset: _state.items.length,
        limit: pageSize,
        query: _state.query,
        sort: _state.sort,
        filters: _state.filters,
      );

      final newItems = [..._state.items, ...more];
      _state = _state.copyWith(
        items: newItems,
        hasMore: newItems.length < _state.totalCount,
        isLoadingMore: false,
      );
    } catch (_) {
      _state = _state.copyWith(isLoadingMore: false);
    }
    notifyListeners();
  }

  void setQuery(String query) {
    if (_state.query == query) return;
    _state = _state.copyWith(query: query);
    loadInitial();
  }

  void setSort(String? sort) {
    if (_state.sort == sort) return;
    _state = _state.copyWith(sort: sort);
    loadInitial();
  }

  void setFilter(String key, dynamic value) {
    final next = Map<String, dynamic>.from(_state.filters);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    _state = _state.copyWith(filters: next);
    loadInitial();
  }

  void clearFilters() {
    _state = _state.copyWith(filters: const {});
    loadInitial();
  }

  void toggleSelection(T item) {
    final id = idExtractor(item);
    final next = Set<Object>.from(_state.selectedIds);
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    _state = _state.copyWith(selectedIds: next);
    notifyListeners();
  }

  void selectAll() {
    final next = _state.items.map(idExtractor).toSet();
    _state = _state.copyWith(selectedIds: next);
    notifyListeners();
  }

  void clearSelection() {
    if (_state.selectedIds.isEmpty) return;
    _state = _state.copyWith(selectedIds: const {});
    notifyListeners();
  }

  bool isSelected(T item) => _state.selectedIds.contains(idExtractor(item));
}
