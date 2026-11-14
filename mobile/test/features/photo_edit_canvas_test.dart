import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/photo_edit/selection_model.dart';
import 'package:antigravity_mobile/features/photo_edit/mask_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SelectionModel supports stroke recording, undo, redo, and clear', () {
    final model = SelectionModel();
    expect(model.canUndo, isFalse);
    expect(model.hasSelection, isFalse);

    model.addStroke(
      const SelectionStroke(
        points: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
        radius: 0.05,
      ),
    );
    expect(model.canUndo, isTrue);
    expect(model.hasSelection, isTrue);
    expect(model.strokes.length, 1);

    model.undo();
    expect(model.strokes.length, 0);
    expect(model.canRedo, isTrue);
    expect(model.hasSelection, isFalse);

    model.redo();
    expect(model.strokes.length, 1);
    expect(model.hasSelection, isTrue);

    model.clear();
    expect(model.strokes.length, 0);
    expect(model.canUndo, isTrue);
  });

  test('MaskBuilder generates valid normalized PNG mask bytes', () async {
    final model = SelectionModel();
    model.addStroke(
      const SelectionStroke(
        points: [Offset(0.5, 0.5)],
        radius: 0.1,
      ),
    );
    final pngBytes = await MaskBuilder.buildMaskPng(
      model,
      width: 100,
      height: 100,
    );
    expect(pngBytes, isNotNull);
    expect(pngBytes.length, greaterThan(50));
    // Verify PNG magic signature: [137, 80, 78, 71, 13, 10, 26, 10]
    expect(pngBytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('MaskBuilder correctly rasterizes filledRects from Smart Select', () async {
    final model = SelectionModel();
    model.addStroke(
      const SelectionStroke(
        points: [Offset(0.5, 0.5)],
        radius: 0.01,
        filledRects: [
          Rect.fromLTWH(0.2, 0.2, 0.6, 0.6),
        ],
      ),
    );
    expect(model.hasSelection, isTrue);

    final pngBytes = await MaskBuilder.buildMaskPng(
      model,
      width: 120,
      height: 120,
    );
    expect(pngBytes, isNotNull);
    expect(pngBytes.length, greaterThan(50));
    expect(pngBytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}
