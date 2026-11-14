import 'package:flutter/material.dart';

enum SelectionTool {
  brush,
  eraser,
  smartTap,
  move,
}

enum PhotoEditOperation {
  remove,
  replace,
}

@immutable
class SelectionStroke {
  const SelectionStroke({
    required this.points,
    required this.radius,
    this.filledRects,
    this.isEraser = false,
  });

  /// Normalized coordinates (0.0 .. 1.0) on the original upright image.
  final List<Offset> points;

  /// Normalized stroke radius (0.005 .. 0.15).
  final double radius;

  /// Normalized rectangular regions (e.g. from Smart Select).
  final List<Rect>? filledRects;

  final bool isEraser;

  SelectionStroke copyWith({
    List<Offset>? points,
    double? radius,
    List<Rect>? filledRects,
    bool? isEraser,
  }) {
    return SelectionStroke(
      points: points ?? this.points,
      radius: radius ?? this.radius,
      filledRects: filledRects ?? this.filledRects,
      isEraser: isEraser ?? this.isEraser,
    );
  }
}

class SelectionModel extends ChangeNotifier {
  SelectionModel({List<SelectionStroke>? initialStrokes})
      : _strokes = List.of(initialStrokes ?? []);

  final List<SelectionStroke> _strokes;
  final List<List<SelectionStroke>> _undoStack = [];
  final List<List<SelectionStroke>> _redoStack = [];

  List<SelectionStroke> get strokes => List.unmodifiable(_strokes);

  bool get canUndo => _undoStack.isNotEmpty || _strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasSelection => _strokes.any((s) =>
      !s.isEraser &&
      (s.points.isNotEmpty || (s.filledRects != null && s.filledRects!.isNotEmpty)));

  void addStroke(SelectionStroke stroke) {
    if (stroke.points.isEmpty &&
        (stroke.filledRects == null || stroke.filledRects!.isEmpty)) {
      return;
    }
    _undoStack.add(List.of(_strokes));
    _redoStack.clear();
    _strokes.add(stroke);
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(List.of(_strokes));
    if (_undoStack.isNotEmpty) {
      final prev = _undoStack.removeLast();
      _strokes
        ..clear()
        ..addAll(prev);
    } else {
      _strokes.clear();
    }
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(List.of(_strokes));
    final next = _redoStack.removeLast();
    _strokes
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clear() {
    if (_strokes.isEmpty) return;
    _undoStack.add(List.of(_strokes));
    _redoStack.clear();
    _strokes.clear();
    notifyListeners();
  }
}
