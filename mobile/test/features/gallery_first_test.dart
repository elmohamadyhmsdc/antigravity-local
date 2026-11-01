import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  appTest('unpaired gallery opens native media without queueing analysis', (
    tester,
    env,
  ) async {
    final assets = syntheticAssets(2);
    env.library.addAlbum(
      const AlbumInfo(id: 'all', name: 'All', count: 2, isAll: true),
      assets,
    );
    await env.pump(tester);
    expect(find.text('Gallery'), findsWidgets);
    expect(find.byKey(const ValueKey('asset-asset-1')), findsOneWidget);
    expect(await env.db.select(env.db.media).get(), isEmpty);
    await tester.tap(find.byKey(const ValueKey('asset-asset-1')));
    await tester.pumpAndSettle();
    final rows = await env.db.select(env.db.media).get();
    expect(rows.length, 2);
    expect(rows.every((row) => row.scanStatus == 'skipped'), isTrue);
    expect(find.byKey(const Key('media-page-view')), findsOneWidget);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('This photo has not been scanned yet.'), findsOneWidget);
  });

  appTest('folder browsing uses its own native collection', (
    tester,
    env,
  ) async {
    env.library.addAlbum(
      const AlbumInfo(id: 'all', name: 'All', count: 2, isAll: true),
      syntheticAssets(2),
    );
    env.library.addAlbum(
      const AlbumInfo(id: 'camera', name: 'Camera', count: 1),
      syntheticAssets(1),
    );
    await env.pump(tester);
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('asset-asset-1')), findsOneWidget);
  });
  appTest(
    'folder viewer loads only the selected kind across empty pages',
    (tester, env) async {
      final assets = <AssetInfo>[
        const AssetInfo(
          id: 'first',
          width: 10,
          height: 10,
          modifiedAt: 1,
          takenAt: 1,
        ),
        for (var i = 0; i < 239; i++)
          AssetInfo(
            id: 'video-$i',
            width: 10,
            height: 10,
            modifiedAt: 1,
            takenAt: 1,
            kind: 'video',
          ),
        const AssetInfo(
          id: 'last',
          width: 10,
          height: 10,
          modifiedAt: 1,
          takenAt: 1,
        ),
      ];
      env.library.addAlbum(
        const AlbumInfo(id: 'all', name: 'All', count: 241, isAll: true),
        assets,
      );
      env.library.addAlbum(
        const AlbumInfo(id: 'camera', name: 'Camera', count: 241),
        assets,
      );
      await env.pump(tester);
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('asset-first')));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if ((await env.db.select(env.db.media).get()).length == 2) break;
      }
      final rows = await env.db.select(env.db.media).get();
      expect(rows.map((row) => row.assetId).toSet(), {'first', 'last'});
      await tester.pumpAndSettle();
      final view = tester.widget<PageView>(
        find.byKey(const Key('media-page-view')),
      );
      expect(view.childrenDelegate.estimatedChildCount, 2);
    },
    session: testSession,
  );
}
