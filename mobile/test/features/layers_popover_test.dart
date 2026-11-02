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

    testWidgets('enables areas toggle when availability hasAreas is true', (
      tester,
    ) async {
      var layers = const ViewerLayers(areas: false);
      const availability = LayerAvailability(hasAreas: true);

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

      expect(find.text('No areas detected'), findsNothing);

      // Tap areas toggle
      await tester.tap(find.byKey(const Key('layer-toggle-areas')));
      await tester.pumpAndSettle();

      expect(layers.areas, isTrue);
    });

    testWidgets('LayersPopover.show updates checkboxes interactively without desync', (
      tester,
    ) async {
      var activeLayers = const ViewerLayers(faces: true, bodies: false, areas: false);
      const availability = LayerAvailability(
        hasFaces: true,
        hasBodies: true,
        hasAreas: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open-sheet'),
                onPressed: () => LayersPopover.show(
                  context: context,
                  layers: activeLayers,
                  availability: availability,
                  onChanged: (updated) => activeLayers = updated,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open-sheet')));
      await tester.pumpAndSettle();

      expect(find.text('Detection Layers'), findsOneWidget);

      // Verify areas checkbox is unchecked initially
      final areasCheckboxFinder = find.byKey(const Key('layer-toggle-areas'));
      expect(tester.widget<CheckboxListTile>(areasCheckboxFinder).value, isFalse);

      // Tap areas checkbox in bottom sheet
      await tester.tap(areasCheckboxFinder);
      await tester.pumpAndSettle();

      // In the bottom sheet, the checkbox should now immediately be checked!
      expect(tester.widget<CheckboxListTile>(areasCheckboxFinder).value, isTrue);
      expect(activeLayers.areas, isTrue);

      // Tap again to toggle off
      await tester.tap(areasCheckboxFinder);
      await tester.pumpAndSettle();

      expect(tester.widget<CheckboxListTile>(areasCheckboxFinder).value, isFalse);
      expect(activeLayers.areas, isFalse);
    });
  });
}
