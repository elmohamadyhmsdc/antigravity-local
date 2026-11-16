import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/features/photo_edit/photo_edit_screen.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoEditScreen renders tools, operations and allows toggling', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: PhotoEditScreen(initialPhotoBytes: tinyPng)),
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

    // Now prompt input, strength slider, and AI model chips are visible
    expect(find.byKey(const Key('instruction-input')), findsOneWidget);
    expect(find.byKey(const Key('strength-slider')), findsOneWidget);
    expect(find.byKey(const Key('model-realistic-vision')), findsOneWidget);
    expect(find.byKey(const Key('model-cyber-realistic')), findsOneWidget);
    expect(find.byKey(const Key('model-sdxl')), findsOneWidget);
    expect(find.byKey(const Key('model-sdxl-gguf')), findsNothing);

    // Select SDXL model chip
    await tester.tap(find.byKey(const Key('model-sdxl')));
    await tester.pump();

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

  testWidgets('GGUF appears only with a ready server capability', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(411, 891);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final statuses = StreamController<ServerStatus>.broadcast();
    addTearDown(() => unawaited(statuses.close()));
    final fixture = File(
      '../the app/mobile_api/contract/fixtures/Capabilities.photo_edit_models.json',
    );
    final capabilities = Capabilities.fromJson(
      jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverStatusProvider.overrideWith((ref) => statuses.stream),
        ],
        child: MaterialApp(home: PhotoEditScreen(initialPhotoBytes: tinyPng)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('op-replace')));
    await tester.pump();
    final gguf = find.byKey(const Key('model-sdxl-gguf'));
    expect(gguf, findsNothing);

    statuses.add(ServerReady(capabilities));
    await tester.pump();
    await tester.pump();
    expect(gguf, findsOneWidget);
    await tester.tap(gguf);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(gguf).selected, isTrue);

    await tester.tap(find.byKey(const Key('tool-smart-tap')));
    await tester.pump();
    expect(tester.takeException(), isNull);

    final prompt = find.byKey(const Key('instruction-input'));
    await tester.enterText(prompt, 'blue ceramic vase');
    tester.view.viewInsets = const FakeViewPadding(bottom: 390);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('blue ceramic vase'), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pump();

    final unavailable =
        jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
    unavailable['photo_edit_models'] = ['realistic_vision'];
    statuses.add(ServerReady(Capabilities.fromJson(unavailable)));
    await tester.pump();
    await tester.pump();
    expect(gguf, findsNothing);
  });

  testWidgets(
    'automatic clothing selection appears only with the PC parser and keeps the body outline',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(411, 891);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final statuses = StreamController<ServerStatus>.broadcast();
      addTearDown(() => unawaited(statuses.close()));
      final json =
          jsonDecode(
                File(
                  '../the app/mobile_api/contract/fixtures/Capabilities.photo_edit_models.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverStatusProvider.overrideWith((ref) => statuses.stream),
          ],
          child: MaterialApp(home: PhotoEditScreen(initialPhotoBytes: tinyPng)),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('op-replace')));
      await tester.pump();
      final auto = find.byKey(const Key('auto-clothing-selection'));
      final outline = find.byKey(const Key('keep-body-outline'));

      (json['engines'] as Map<String, dynamic>)
        ..['photo_edit_auto_body'] = false
        ..['photo_edit_body_shape'] = false;
      statuses.add(ServerReady(Capabilities.fromJson(json)));
      await tester.pump();
      await tester.pump();
      expect(auto, findsNothing);

      (json['engines'] as Map<String, dynamic>)
        ..['photo_edit_auto_body'] = true
        ..['photo_edit_body_shape'] = true;
      statuses.add(ServerReady(Capabilities.fromJson(json)));
      await tester.pump();
      await tester.pump();
      expect(auto, findsOneWidget);
      await tester.tap(auto);
      await tester.pump();
      expect(tester.widget<FilterChip>(auto).selected, isTrue);
      expect(tester.widget<FilterChip>(outline).selected, isTrue);
      final area = find.byKey(const Key('source-clothing-area'));
      expect(area, findsNothing);
      (json['engines'] as Map<String, dynamic>)['photo_edit_clothing_area'] =
          true;
      statuses.add(ServerReady(Capabilities.fromJson(json)));
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(area);
      await tester.tap(area);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('اللبس من تحت').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<DropdownButton<String>>(area).value, 'lower');
      expect(
        tester.widget<FilterChip>(outline).onSelected,
        isNull,
        reason: 'automatic selection always keeps the outline',
      );
      expect(find.textContaining('مايوه'), findsNothing);
    },
  );

  testWidgets('photo guidance offers person and gallery sources', (
    tester,
  ) async {
    final photo = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAQAAAAICAIAAABRUclSAAAAE0lEQVR4nGNkYPjPAANMcBbVOQBoQwEPAG0eYQAAAABJRU5ErkJggg==',
    );
    final picker = FakePhotoPicker()..photo = photo;
    final fixture = File(
      '../the app/mobile_api/contract/fixtures/Capabilities.photo_edit_guided.json',
    );
    final capabilities = Capabilities.fromJson(
      jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverStatusProvider.overrideWith(
            (ref) => Stream.value(ServerReady(capabilities)),
          ),
          photoPickerProvider.overrideWithValue(picker),
        ],
        child: MaterialApp(home: PhotoEditScreen(initialPhotoBytes: photo)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('op-replace')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('photo-guided-edit')));
    await tester.pump();
    expect(find.byKey(const Key('reference-from-person')), findsOneWidget);
    expect(find.byKey(const Key('reference-from-gallery')), findsOneWidget);
    expect(find.text('Optional description / وصف اختياري'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('reference-from-gallery')));
      for (var attempt = 0; attempt < 30; attempt++) {
        await tester.pump();
        if (tester.any(find.text('Reference area'))) break;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(picker.picks, 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('Reference area'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Use reference'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await tester.pump();
    });
    expect(find.text('Photo 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('text-only-edit')));
    await tester.pump();
    expect(find.byKey(const Key('reference-from-person')), findsNothing);
  });
}
