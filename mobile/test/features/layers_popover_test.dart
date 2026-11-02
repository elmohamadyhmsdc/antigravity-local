import 'package:antigravity_mobile/features/media/layers_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayersPopover', () {
    testWidgets('displays layers with availability and triggers callbacks', (
      tester,
    ) async {
      var layers = const ViewerLayers(faces: true, bodies: false);
      const availability = LayerAvailability(
        hasFaces: true,
        hasBodies: true,
        hasAreas: false,
        hasEquipment: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return LayersPopover(
                  layers: layers,
                  availability: availability,
                  onChanged: (updated) => setState(() => layers = updated),
                );
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('layer-toggle-faces')), findsOneWidget);
      expect(find.byKey(const Key('layer-toggle-bodies')), findsOneWidget);
      expect(find.byKey(const Key('layer-toggle-areas')), findsOneWidget);

      // Areas should be disabled with subtitle
      expect(find.text('No areas detected'), findsOneWidget);

      // Tap bodies toggle
      await tester.tap(find.byKey(const Key('layer-toggle-bodies')));
      await tester.pumpAndSettle();

      expect(layers.bodies, isTrue);
    });
  });
}
