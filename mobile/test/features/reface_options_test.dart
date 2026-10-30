import 'package:antigravity_mobile/features/reface/reface_options.dart';
import 'package:antigravity_mobile/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'restorer purposes remain readable and selectable on a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final l10n = AppLocalizationsEn();
      var value = 'auto';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) => RefaceOptionPicker(
                  fieldKey: const Key('restorer'),
                  descriptionKey: const Key('description'),
                  label: l10n.refaceRestorer,
                  value: value,
                  options: restorationOptions(l10n, [
                    'gpen_bfr_512',
                    'gpen_bfr_1024',
                    'codeformer',
                    'gfpgan_1.4',
                    'restoreformer_plus_plus',
                  ], 'gpen_bfr_512'),
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('restorer')));
      await tester.pumpAndSettle();
      expect(find.text('Starts with GPEN 512 on this PC'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('RestoreFormer++'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('RestoreFormer++')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Alternative face restoration · extra AI processing'),
        findsOneWidget,
      );
      await tester.tap(find.text('RestoreFormer++').last);
      await tester.pumpAndSettle();
      expect(value, 'restoreformer_plus_plus');
      expect(
        tester.widget<Text>(find.byKey(const Key('description'))).data,
        contains('Reconstructs'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown PC models retain their name and avoid invented performance claims',
    (tester) async {
      final l10n = AppLocalizationsEn();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RefaceOptionPicker(
              fieldKey: const Key('restorer'),
              descriptionKey: const Key('description'),
              label: l10n.refaceRestorer,
              value: 'future_model',
              options: restorationOptions(l10n, ['future_model'], null),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('future_model'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('description'))).data,
        contains('No speed or likeness comparison'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
