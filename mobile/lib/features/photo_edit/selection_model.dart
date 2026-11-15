import 'package:flutter/material.dart';

enum SelectionTool { brush, eraser, smartTap, move }

enum PhotoEditOperation { remove, replace }

enum PhotoEditModel { realisticVision, sdxlGguf, cyberRealistic, sdxl }

extension PhotoEditModelExt on PhotoEditModel {
  String get id {
    switch (this) {
      case PhotoEditModel.realisticVision:
        return 'realistic_vision';
      case PhotoEditModel.cyberRealistic:
        return 'cyber_realistic';
      case PhotoEditModel.sdxl:
        return 'sdxl';
      case PhotoEditModel.sdxlGguf:
        return 'sdxl_gguf';
    }
  }

  String get displayName {
    switch (this) {
      case PhotoEditModel.realisticVision:
        return 'Realistic Vision';
      case PhotoEditModel.cyberRealistic:
        return 'CyberRealistic';
      case PhotoEditModel.sdxl:
        return 'SDXL 1024p';
      case PhotoEditModel.sdxlGguf:
        return 'SDXL GGUF';
    }
  }

  String get description {
    switch (this) {
      case PhotoEditModel.realisticVision:
        return 'Balanced photorealism & clean edge inpainting (768p)';
      case PhotoEditModel.cyberRealistic:
        return 'High contrast studio textures & sharp garments (768p)';
      case PhotoEditModel.sdxl:
        return 'Ultra high-definition native inpainting (1024p)';
      case PhotoEditModel.sdxlGguf:
        return 'Experimental 1024px inpainting on the PC';
    }
  }
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
  bool get hasSelection => _strokes.any(
    (s) =>
        !s.isEraser &&
        (s.points.isNotEmpty ||
            (s.filledRects != null && s.filledRects!.isNotEmpty)),
  );

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
