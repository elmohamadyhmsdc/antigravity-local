import 'package:flutter/material.dart';

import '../scaffolds/sheet_scaffold.dart';

class SearchableListSheet<T> extends StatefulWidget {
  const SearchableListSheet({
    super.key,
    required this.title,
    required this.items,
    required this.itemBuilder,
    required this.filterFn,
    this.searchHint = 'Search...',
    this.emptyMessage = 'No matching items',
  });

  final String title;
  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final bool Function(T item, String query) filterFn;
  final String searchHint;
  final String emptyMessage;

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required List<T> items,
    required Widget Function(BuildContext context, T item) itemBuilder,
    required bool Function(T item, String query) filterFn,
    String searchHint = 'Search...',
    String emptyMessage = 'No matching items',
  }) {
    return SheetScaffold.show<T>(
      context: context,
      builder: (_) => SearchableListSheet<T>(
        title: title,
        items: items,
        itemBuilder: itemBuilder,
        filterFn: filterFn,
        searchHint: searchHint,
        emptyMessage: emptyMessage,
      ),
    );
  }

  @override
  State<SearchableListSheet<T>> createState() => _SearchableListSheetState<T>();
}

class _SearchableListSheetState<T> extends State<SearchableListSheet<T>> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(() {
      setState(() => _query = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items.where((item) => widget.filterFn(item, _query)).toList();

    return SheetScaffold(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  widget.emptyMessage,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  return widget.itemBuilder(context, filtered[index]);
                },
              ),
            ),
        ],
      ),
    );
  }
}
