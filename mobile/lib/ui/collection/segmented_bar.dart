import 'package:flutter/material.dart';

class SegmentItem<T> {
  const SegmentItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class SegmentedBar<T> extends StatelessWidget {
  const SegmentedBar({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelected,
    this.padding,
  });

  final List<SegmentItem<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<T>(
        segments: [
          for (final s in segments)
            ButtonSegment<T>(
              value: s.value,
              label: Text(s.label),
              icon: s.icon != null ? Icon(s.icon) : null,
            ),
        ],
        selected: {selected},
        onSelectionChanged: (set) {
          if (set.isNotEmpty) {
            onSelected(set.first);
          }
        },
      ),
    );
  }
}
