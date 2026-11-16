import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:antigravity_mobile/features/media/targeted_region_screen.dart';
import 'package:antigravity_mobile/features/media/roi_selection_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/features/inspector/targeted_detect_sheet.dart';

void main() {
  group('TargetedDetectSheet & Naming', () {
    testWidgets('anime faces always open a manual region selection', (tester) async {
      String? kind;
      bool? roi;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TargetedDetectSheet(
        onStart: (value, selected) { kind = value; roi = selected; },
      ))));
      await tester.tap(find.byKey(const Key('target-kind-anime-face')));
      await tester.pump();
      expect(find.byKey(const Key('target-mode-full')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('target-start-detect')));
      await tester.tap(find.byKey(const Key('target-start-detect')));
      await tester.pump();
      expect(kind, 'anime_face');
      expect(roi, isTrue);
    });

    testWidgets('anime recovery explains a missed detection and retains failed saves', (tester) async {
      final pending = Completer<void>();
      var saves = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TargetedNameSheet(
        kind: 'anime_face', bbox: const BBox(x: .2, y: .2, w: .3, h: .3),
        manual: true,
        onSave: (_, _, _) { saves++; return pending.future; },
      ))));
      expect(find.textContaining('The detector missed this face.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('target-save')));
      await tester.pump();
      expect(find.text('Saving...'), findsOneWidget);
      await tester.tap(find.byKey(const Key('target-save')));
      expect(saves, 1);
      pending.completeError(StateError('Fixture save failed'));
      await tester.pump();
      expect(find.textContaining('Fixture save failed'), findsOneWidget);
      expect(find.text('Save & Apply'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('region selection uses fitted image dimensions and preserves normalized bounds', (tester) async {
      final fixture = jsonDecode(File('../the app/mobile_api/contract/fixtures/TargetedAnalysisResponse.anime_face.json')
          .readAsStringSync()) as Map<String, dynamic>;
      final bytes = base64Decode((fixture['detections'] as List).first['crop_jpeg'] as String);
      BBox? selected;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
        body: TextButton(onPressed: () async {
          selected = await Navigator.of(context).push<BBox>(MaterialPageRoute(
            builder: (_) => TargetedRegionScreen(bytes: bytes, kind: 'anime_face')));
        }, child: const Text('Open selection')),
      ))));
      await tester.tap(find.text('Open selection'));
      await tester.pump();
      // Native codec completion needs real event-loop time in a widget test.
      for (var attempt = 0; attempt < 20 && find.byType(RoiSelectionOverlay).evaluate().isEmpty; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      final overlay = tester.widget<RoiSelectionOverlay>(find.byType(RoiSelectionOverlay));
      // The shared crop is square; the available viewer body is rectangular.
      expect(overlay.fittedSize.width, closeTo(overlay.fittedSize.height, .01));
      await tester.tap(find.byKey(const Key('target-region-scan')));
      await tester.pumpAndSettle();
      expect(selected?.x, .25);
      expect(selected?.y, .25);
      expect(selected?.w, .5);
      expect(selected?.h, .5);
      expect(tester.takeException(), isNull);
    });

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
