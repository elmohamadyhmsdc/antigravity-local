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
      expect(find.text('Right now: Sharp and natural'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Alternative finish'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Alternative finish')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      expect(find.text('Alternative finish · slower'), findsOneWidget);
      await tester.tap(find.text('Alternative finish').last);
      await tester.pumpAndSettle();
      expect(value, 'restoreformer_plus_plus');
      expect(
        tester.widget<Text>(find.byKey(const Key('description'))).data,
        contains('Another way of sharpening'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'quality choices say what they do and, when the PC reports it, how long they take',
    () {
      final l10n = AppLocalizationsEn();
      final plain = qualityOptions(l10n);
      expect(plain.map((o) => o.value), ['fast', 'balanced', 'detail']);
      expect(plain.first.summary, 'Quickest · skin a little soft');
      expect(plain[1].summary, isNot(contains('Takes')));

      final timed = qualityOptions(
        l10n,
        takes: {'fast': 'about 40 s', 'detail': 'about 9 min'},
      );
      expect(
        timed[0].summary,
        'Quickest · skin a little soft · Takes about 40 s on your PC',
      );
      expect(timed[0].description, endsWith('Takes about 40 s on your PC.'));
      expect(
        timed[1].summary,
        plain[1].summary,
        reason: 'no figure for balanced, no claim',
      );
      expect(timed[2].summary, contains('Takes about 9 min on your PC'));
    },
  );

  test(
    'a finishing step is named by its look, with the model only as a footnote',
    () {
      final l10n = AppLocalizationsEn();
      final options = restorationOptions(l10n, [
        'gpen_bfr_512',
        'gpen_bfr_1024',
        'codeformer',
        'gfpgan_1.4',
      ], 'gpen_bfr_512');
      expect(options.map((o) => o.title), [
        'Automatic',
        'No sharpening',
        'Sharp and natural',
        'Extra sharp for big faces',
        'Rebuilds blurry faces',
        'Smooth and clean',
      ]);
      final gpen = options.firstWhere((o) => o.value == 'gpen_bfr_512');
      expect(gpen.title, isNot(contains('GPEN')));
      expect(gpen.description, endsWith('(GPEN 512)'));
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
        contains('not known here'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
