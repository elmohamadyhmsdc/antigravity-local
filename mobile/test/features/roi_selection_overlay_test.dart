import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/features/media/roi_selection_overlay.dart';

void main() {
  group('RoiSelectionOverlay', () {
    testWidgets('renders handles and allows dragging to resize box', (
      tester,
    ) async {
      BBox? currentBBox;
      BBox? confirmedBBox;
      var canceled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: RoiSelectionOverlay(
                  fittedSize: const Size(400, 400),
                  initialBBox: const BBox(x: 0.25, y: 0.25, w: 0.5, h: 0.5),
                  onChanged: (b) => currentBBox = b,
                  onConfirm: (b) => confirmedBBox = b,
                  onCancel: () => canceled = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('roi-box')), findsOneWidget);
      expect(find.byKey(const Key('roi-handle-br')), findsOneWidget);
      expect(find.byKey(const Key('roi-confirm')), findsOneWidget);
      expect(find.byKey(const Key('roi-cancel')), findsOneWidget);

      // Drag bottom-right handle outwards (+50, +50)
      await tester.drag(
        find.byKey(const Key('roi-handle-br')),
        const Offset(40, 40),
      );
      await tester.pump();

      expect(currentBBox, isNotNull);
      expect(currentBBox!.w, greaterThan(0.5));
      expect(currentBBox!.h, greaterThan(0.5));

      // Confirm
      await tester.tap(find.byKey(const Key('roi-confirm')));
      await tester.pump();
      expect(confirmedBBox, isNotNull);

      // Cancel
      await tester.tap(find.byKey(const Key('roi-cancel')));
      await tester.pump();
      expect(canceled, isTrue);
    });
  });
}
