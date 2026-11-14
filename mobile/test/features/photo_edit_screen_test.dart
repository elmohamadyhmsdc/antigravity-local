import 'package:antigravity_mobile/features/photo_edit/photo_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoEditScreen renders tools, operations and allows toggling', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PhotoEditScreen(initialPhotoBytes: tinyPng),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Title
    expect(find.text('AI Photo Edit'), findsOneWidget);

    // Verify Tools
    expect(find.byKey(const Key('tool-brush')), findsOneWidget);
    expect(find.byKey(const Key('tool-eraser')), findsOneWidget);
    expect(find.byKey(const Key('tool-smart-tap')), findsOneWidget);
    expect(find.byKey(const Key('tool-move')), findsOneWidget);

    // Verify Operations
    expect(find.byKey(const Key('op-remove')), findsOneWidget);
    expect(find.byKey(const Key('op-replace')), findsOneWidget);

    // Initially Remove is selected: prompt input is not visible
    expect(find.byKey(const Key('instruction-input')), findsNothing);

    // Switch to Replace
    await tester.tap(find.byKey(const Key('op-replace')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Now prompt input and strength slider are visible
    expect(find.byKey(const Key('instruction-input')), findsOneWidget);
    expect(find.byKey(const Key('strength-slider')), findsOneWidget);

    // Switch tool to Smart Tap
    await tester.tap(find.byKey(const Key('tool-smart-tap')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Smart tolerance slider should now be visible
    expect(find.byKey(const Key('smart-tolerance-slider')), findsOneWidget);

    // Switch tool to Eraser
    await tester.tap(find.byKey(const Key('tool-eraser')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tolerance slider disappears for eraser
    expect(find.byKey(const Key('smart-tolerance-slider')), findsNothing);

    // Verify Generate button exists
    expect(find.byKey(const Key('generate-button')), findsOneWidget);
  });
}
