import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/sheets/name_sheet.dart';

void main() {
  testWidgets('NameSheet validates input and returns text on save', (
    tester,
  ) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await NameSheet.show(
                  context: context,
                  title: 'Rename Person',
                  initialValue: 'Alice',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Rename Person'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);

    // Edit name
    await tester.enterText(find.byKey(const Key('name-sheet-input')), 'Bob');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('name-sheet-save')));
    await tester.pumpAndSettle();

    expect(result, equals('Bob'));
  });
}
