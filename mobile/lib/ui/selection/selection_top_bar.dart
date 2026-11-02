import 'package:flutter/material.dart';

class SelectionTopBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionTopBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onSelectAll,
    this.totalCount,
  });

  final int count;
  final VoidCallback onClear;
  final VoidCallback onSelectAll;
  final int? totalCount;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close selection',
        onPressed: onClear,
      ),
      title: Text(
        '$count selected',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        TextButton(onPressed: onSelectAll, child: const Text('Select all')),
      ],
    );
  }
}
