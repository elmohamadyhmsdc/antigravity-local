import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/sheets/confirm_sheet.dart';

void main() {
  testWidgets(
    'ConfirmSheet displays consequences and returns true on confirm',
    (tester) async {
      bool? confirmed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  confirmed = await ConfirmSheet.show(
                    context: context,
                    title: 'Delete Person',
                    message: 'Are you sure you want to delete this person?',
                    consequences: [
                      'All faces will be unassigned',
                      'Trained model will be deleted',
                    ],
                    confirmLabel: 'Delete',
                    isDanger: true,
                  );
                },
                child: const Text('Delete'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Person'), findsOneWidget);
      expect(find.text('All faces will be unassigned'), findsOneWidget);
      expect(find.text('Trained model will be deleted'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-sheet-confirm')));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    },
  );
}
