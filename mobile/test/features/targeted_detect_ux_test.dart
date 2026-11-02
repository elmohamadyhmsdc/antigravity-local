import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/features/inspector/targeted_detect_sheet.dart';

void main() {
  group('TargetedDetectSheet & Naming', () {
    testWidgets('selects target kind and mode', (tester) async {
      String? selectedKind;
      bool? isRoiMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TargetedDetectSheet(
              onStart: (kind, roiMode) {
                selectedKind = kind;
                isRoiMode = roiMode;
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('target-kind-area')), findsOneWidget);
      expect(find.byKey(const Key('target-kind-body')), findsOneWidget);
      expect(find.byKey(const Key('target-kind-face')), findsOneWidget);
      expect(find.byKey(const Key('target-kind-object')), findsOneWidget);

      // Select body and ROI mode
      await tester.tap(find.byKey(const Key('target-kind-body')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('target-mode-roi')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('target-start-detect')));
      await tester.pump();

      expect(selectedKind, 'body');
      expect(isRoiMode, isTrue);
    });

    testWidgets('naming sheet accepts custom name and triggers onSave', (
      tester,
    ) async {
      String? savedName;
      String? savedScope;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TargetedNameSheet(
              kind: 'area',
              bbox: const BBox(x: 0.1, y: 0.2, w: 0.3, h: 0.4),
              isVideo: true,
              onSave: (name, personId, scope) {
                savedName = name;
                savedScope = scope;
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('target-name-input')), findsOneWidget);
      expect(find.byKey(const Key('target-save')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('target-name-input')),
        'Custom Tattoo',
      );
      await tester.pump();

      // Tap scope track
      if (find.byKey(const Key('scope-track')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('scope-track')));
        await tester.pump();
      }

      await tester.tap(find.byKey(const Key('target-save')));
      await tester.pump();

      expect(savedName, 'Custom Tattoo');
      expect(savedScope, isNotNull);
    });
  });
}
