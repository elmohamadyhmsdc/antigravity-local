import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/bodies/body_inspection_sheet.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';

void main() {
  testWidgets(
    'BodyInspectionSheet renders preview with skeleton and area toggles and actions',
    (tester) async {
      final kpts = jsonEncode([
        [0.5, 0.2, 0.9],
        [0.48, 0.18, 0.9],
        [0.52, 0.18, 0.9],
        [0.46, 0.18, 0.9],
        [0.54, 0.18, 0.9],
        [0.42, 0.3, 0.9],
        [0.58, 0.3, 0.9],
        [0.38, 0.45, 0.9],
        [0.62, 0.45, 0.9],
        [0.35, 0.6, 0.9],
        [0.65, 0.6, 0.9],
        [0.45, 0.6, 0.9],
        [0.55, 0.6, 0.9],
        [0.45, 0.8, 0.9],
        [0.55, 0.8, 0.9],
        [0.45, 0.98, 0.9],
        [0.55, 0.98, 0.9],
      ]);

      String? selectedAction;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  key: const Key('open-sheet-btn'),
                  onPressed: () async {
                    selectedAction = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => BodyInspectionSheet(
                        bodyId: 101,
                        mediaId: 202,
                        kpts: kpts,
                        bbox: (x: 0.3, y: 0.1, w: 0.4, h: 0.8),
                        tags: ['standing', 'frontal'],
                        exposedAreas: ['chest'],
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      // 1. Open the sheet
      await tester.tap(find.byKey(const Key('open-sheet-btn')));
      await tester.pumpAndSettle();

      // 2. Verify sheet components
      expect(find.byKey(const Key('body-inspection-sheet')), findsOneWidget);
      expect(find.byKey(const Key('toggle-skeleton-btn')), findsOneWidget);
      expect(find.byKey(const Key('toggle-area-btn')), findsOneWidget);
      expect(find.text('Standing'), findsOneWidget);
      expect(find.text('Facing the camera'), findsOneWidget);

      // 3. Toggle skeleton
      await tester.tap(find.byKey(const Key('toggle-skeleton-btn')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('body-crop-skeleton-painter')),
        findsOneWidget,
      );

      // 4. Tap action
      await tester.tap(find.byKey(const Key('action-similar')));
      await tester.pumpAndSettle();
      expect(selectedAction, equals('similar'));
    },
  );
}
