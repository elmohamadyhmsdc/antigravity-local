import 'dart:async';

import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/ui/selection/selection_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mount(
  WidgetTester tester, {
  List<int> items = const [1, 2, 3],
  bool partial = false,
  required Future<bool> Function(BuildContext, List<int>) run,
  ValueChanged<int>? onOpen,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SelectionCollection<int>(
        name: 'test',
        items: items,
        idOf: (id) => id,
        partial: partial,
        actions: (_) => [
          CollectionAction(
            id: 'apply',
            label: 'Apply selection',
            icon: Icons.check,
            run: run,
          ),
        ],
        builder: (context, selection) => ListView(
          children: [
            for (final id in items)
              selection.tile(
                id,
                child: ListTile(
                  key: Key('item-$id'),
                  title: Text('Item $id'),
                  onTap: () => onOpen?.call(id),
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);

Future<void> startFromLongPress(WidgetTester tester) async {
  await tester.longPress(find.byKey(const Key('item-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('test-select-multiple')));
  await tester.pumpAndSettle();
}

Future<void> apply(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('test-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('test-action-apply')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
    'long press offers actions; selection does not execute or open items',
    (tester) async {
      final calls = <List<int>>[];
      final opened = <int>[];
      await mount(
        tester,
        run: (_, ids) async {
          calls.add(ids);
          return true;
        },
        onOpen: opened.add,
      );
      await startFromLongPress(tester);
      expect(calls, isEmpty);
      expect(opened, isEmpty);
      await tester.tap(find.byKey(const Key('test-item-2')));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await apply(tester);
      await tester.pumpAndSettle();
      expect(calls, [
        [1, 2],
      ]);
      expect(opened, isEmpty);
      expect(find.byKey(const Key('test-actions')), findsNothing);
    },
  );

  testWidgets(
    'select loaded, invert and clearing all keep an explicit selection mode',
    (tester) async {
      await mount(tester, partial: true, run: (_, _) async => true);
      await tester.tap(find.byKey(const Key('test-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('test-selection-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select loaded items (3)'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('test-selection-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invert selection'));
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('test-actions')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('test-item-3')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
    },
  );

  testWidgets('cancelled picker retains the selection', (tester) async {
    await mount(tester, run: (_, _) async => false);
    await startFromLongPress(tester);
    await apply(tester);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('test-check-1'))).value,
      isTrue,
    );
  });

  testWidgets('pending actions show feedback and cannot run twice', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var calls = 0;
    await mount(
      tester,
      run: (_, _) {
        calls++;
        return pending.future;
      },
    );
    await startFromLongPress(tester);
    await apply(tester);
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-2')), warnIfMissed: false);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('partial failures retain only failed items for retry', (
    tester,
  ) async {
    final processed = <int>[];
    await mount(
      tester,
      run: (_, items) async {
        await performBatch(items, (id) => id, (id) async {
          if (id == 2) throw StateError('Unavailable');
          processed.add(id);
        });
        return true;
      },
    );
    await startFromLongPress(tester);
    await tester.tap(find.byKey(const Key('test-item-2')));
    await tester.pumpAndSettle();
    await apply(tester);
    await tester.pumpAndSettle();
    expect(processed, [1]);
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('test-check-1'))).value,
      isFalse,
    );
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('test-check-2'))).value,
      isTrue,
    );
    expect(find.textContaining('1 completed · 1 failed'), findsOneWidget);
  });

  testWidgets('filtered-out records leave the selection', (tester) async {
    Future<bool> run(BuildContext _, List<int> _) async => true;
    await mount(tester, run: run);
    await startFromLongPress(tester);
    await tester.tap(find.byKey(const Key('test-item-2')));
    await tester.pumpAndSettle();
    await mount(tester, items: [2, 3], run: run);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(find.byKey(const Key('test-check-2'))).value,
      isTrue,
    );
  });
}
