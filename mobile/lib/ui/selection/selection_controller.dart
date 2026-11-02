import 'package:flutter/foundation.dart';

class SelectionController<T> extends ChangeNotifier {
  SelectionController({required this.idExtractor});

  final Object Function(T item) idExtractor;
  final Set<Object> _selectedIds = {};
  final Map<Object, T> _selectedItems = {};

  bool get isSelecting => _selectedIds.isNotEmpty;
  int get count => _selectedIds.length;
  Set<Object> get selectedIds => Set.unmodifiable(_selectedIds);
  List<T> get selectedItems => _selectedItems.values.toList();

  bool isSelected(T item) => _selectedIds.contains(idExtractor(item));

  void toggle(T item) {
    final id = idExtractor(item);
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
      _selectedItems.remove(id);
    } else {
      _selectedIds.add(id);
      _selectedItems[id] = item;
    }
    notifyListeners();
  }

  void selectAll(Iterable<T> items) {
    for (final item in items) {
      final id = idExtractor(item);
      _selectedIds.add(id);
      _selectedItems[id] = item;
    }
    notifyListeners();
  }

  void clear() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _selectedItems.clear();
    notifyListeners();
  }
}
