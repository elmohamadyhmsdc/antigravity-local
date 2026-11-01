import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/features/library/native_gallery.dart';
import 'package:antigravity_mobile/features/shared/empty_state.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import '../support/fakes.dart';

class DelayedFakeMediaLibrary extends FakeMediaLibrary {
  DelayedFakeMediaLibrary({super.albums, super.assets});

  @override
  Future<List<AlbumInfo>> albums() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.albums();
  }
}

void main() {
  testWidgets('NativeGallery retains state in memory and renders instantly upon remount', (tester) async {
    final assets = syntheticAssets(10);
    final allAlbum = const AlbumInfo(id: 'all', name: 'All', isAll: true, count: 10);
    final library = DelayedFakeMediaLibrary(
      albums: [allAlbum],
      assets: {'all': assets},
    );

    final container = ProviderContainer(
      overrides: [
        mediaLibraryProvider.overrideWithValue(library),
      ],
    );
    addTearDown(container.dispose);

    // Initial mount and load
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: NativeGallery()),
        ),
      ),
    );

    // Let initial load finish
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('native-gallery-grid')), findsOneWidget);

    // Navigate away by replacing widget with empty container
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('native-gallery-grid')), findsNothing);

    // Remount NativeGallery - must render grid immediately on first frame without LoadingBox
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(body: NativeGallery()),
        ),
      ),
    );

    // FIRST frame: instant render check
    await tester.pump();
    expect(find.byKey(const Key('native-gallery-grid')), findsOneWidget);
    expect(find.byType(LoadingBox), findsNothing);
  });
}
