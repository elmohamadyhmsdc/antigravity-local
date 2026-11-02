import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:antigravity_mobile/ui/scaffolds/tab_root_scaffold.dart';

void main() {
  testWidgets(
    'TabRootScaffold renders title, primary action and settings gear',
    (tester) async {
      bool settingsTapped = false;
      bool primaryTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: TabRootScaffold(
            title: const Text('Library'),
            primaryAction: IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => primaryTapped = true,
            ),
            onSettingsTap: () => settingsTapped = true,
            body: const Center(child: Text('Content')),
          ),
        ),
      );

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byKey(const Key('tab-root-settings')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      expect(primaryTapped, isTrue);

      await tester.tap(find.byKey(const Key('tab-root-settings')));
      expect(settingsTapped, isTrue);
    },
  );

  testWidgets('TabRootScaffold asserts against PopupMenuButton in debug mode', (
    tester,
  ) async {
    expect(
      () => TabRootScaffold(
        title: const Text('Invalid'),
        primaryAction: PopupMenuButton<int>(itemBuilder: (_) => []),
        body: const SizedBox(),
      ).build(tester.element(find.byType(Container))),
      throwsA(isA<FlutterError>()),
    );
  });
}
