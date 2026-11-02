import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/ui/pickers/media_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('MediaPicker', () {
    testWidgets('picks single media on tap when multiple is false', (
      tester,
    ) async {
      final assets = syntheticAssets(5);
      final library = FakeMediaLibrary(
        albums: [
          const AlbumInfo(id: 'all', name: 'All', count: 5, isAll: true),
        ],
        assets: {'all': assets},
      );

      List<AssetInfo>? selected;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mediaLibraryProvider.overrideWithValue(library)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    selected = await MediaPicker.pick(context, multiple: false);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaPicker), findsOneWidget);
      expect(
        find.byKey(ValueKey('picker-item-${assets.first.id}')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(ValueKey('picker-item-${assets.first.id}')));
      await tester.pumpAndSettle();

      expect(find.byType(MediaPicker), findsNothing);
      expect(selected?.length, equals(1));
      expect(selected?.first.id, equals(assets.first.id));
    });

    testWidgets('picks multiple media with checkboxes and done button', (
      tester,
    ) async {
      final assets = syntheticAssets(5);
      final library = FakeMediaLibrary(
        albums: [
          const AlbumInfo(id: 'all', name: 'All', count: 5, isAll: true),
        ],
        assets: {'all': assets},
      );

      List<AssetInfo>? selected;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [mediaLibraryProvider.overrideWithValue(library)],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    selected = await MediaPicker.pick(context, multiple: true);
                  },
                  child: const Text('Open Multi'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Multi'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('media-picker-done')), findsOneWidget);

      // Select first two assets
      await tester.tap(find.byKey(ValueKey('picker-item-${assets[0].id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('picker-item-${assets[1].id}')));
      await tester.pumpAndSettle();

      expect(find.text('Done (2)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('media-picker-done')));
      await tester.pumpAndSettle();

      expect(selected?.length, equals(2));
      expect(
        selected?.map((a) => a.id).toSet(),
        containsAll([assets[0].id, assets[1].id]),
      );
    });
  });
}
