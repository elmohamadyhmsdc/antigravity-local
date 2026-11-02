import 'package:flutter/material.dart';

import '../scaffolds/sheet_scaffold.dart';

class FilterOption<T> {
  const FilterOption({required this.label, required this.value});

  final String label;
  final T value;
}

class FilterSpec<T> {
  const FilterSpec({
    required this.key,
    required this.label,
    required this.options,
    this.currentValue,
  });

  final String key;
  final String label;
  final List<FilterOption<T>> options;
  final T? currentValue;

  bool get isActive => currentValue != null;
}

class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.onFilterChanged,
    this.onClearAll,
  });

  final List<FilterSpec<dynamic>> filters;
  final void Function(String key, dynamic value) onFilterChanged;
  final VoidCallback? onClearAll;

  @override
  Widget build(BuildContext context) {
    final hasActive = filters.any((f) => f.isActive);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (hasActive && onClearAll != null) ...[
            ActionChip(
              avatar: const Icon(Icons.close, size: 16),
              label: const Text('Clear'),
              onPressed: onClearAll,
            ),
            const SizedBox(width: 8),
          ],
          for (final filter in filters) ...[
            FilterChip(
              selected: filter.isActive,
              label: Text(
                filter.isActive
                    ? '${filter.label}: ${filter.options.firstWhere(
                        (o) => o.value == filter.currentValue,
                        orElse: () => FilterOption(label: filter.currentValue.toString(), value: filter.currentValue),
                      ).label}'
                    : filter.label,
              ),
              onSelected: (_) => _openFilterSheet(context, filter),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context, FilterSpec<dynamic> filter) {
    SheetScaffold.show(
      context: context,
      builder: (ctx) => SheetScaffold(
        title: filter.label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All / Any'),
              trailing: filter.currentValue == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                onFilterChanged(filter.key, null);
                Navigator.of(ctx).pop();
              },
            ),
            for (final option in filter.options)
              ListTile(
                title: Text(option.label),
                trailing: filter.currentValue == option.value
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  onFilterChanged(filter.key, option.value);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
