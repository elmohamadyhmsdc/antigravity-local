import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

Future<void> chooseMultiple(
  WidgetTester tester,
  String collection,
  String id,
) async {
  await tester.longPress(find.byKey(Key('$collection-item-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('$collection-select-multiple')));
  await tester.pumpAndSettle();
}

Future<void> action(WidgetTester tester, String collection, String id) async {
  await tester.tap(find.byKey(Key('$collection-actions')));
  await tester.pumpAndSettle();
  final target = find.byKey(Key('$collection-action-$id'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'results apply an explicit favourite state only to selected records',
    (tester, env) async {
      for (var i = 1; i <= 3; i++) {
        await env.db
            .into(env.db.results)
            .insert(
              ResultsCompanion.insert(
                id: 'r$i',
                type: 'reface_image',
                path: 'results/r$i.jpg',
                originalPath: 'source.jpg',
                mime: 'image/jpeg',
                sizeBytes: 1,
                sha256: 'a',
                createdAt: i,
                favourite: Value(i == 2),
              ),
            );
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/results')],
      );
      await chooseMultiple(tester, 'results', 'r1');
      await tester.tap(find.byKey(const Key('results-item-r2')));
      await tester.pumpAndSettle();
      await action(tester, 'results', 'favourite');
      final rows = {
        for (final row in await env.db.select(env.db.results).get())
          row.id: row.favourite,
      };
      expect(rows, {'r1': true, 'r2': true, 'r3': false});
    },
    session: testSession,
  );

  appTest(
    'native gallery selection queues only chosen assets and keeps originals',
    (tester, env) async {
      final library = FakeMediaLibrary(
        albums: [
          const AlbumInfo(id: 'all', name: 'All', count: 3, isAll: true),
        ],
        assets: {'all': syntheticAssets(3)},
      );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/gallery'),
          mediaLibraryProvider.overrideWithValue(library),
        ],
      );
      await chooseMultiple(tester, 'gallery', 'asset-1');
      await tester.tap(find.byKey(const Key('gallery-item-asset-2')));
      await tester.pumpAndSettle();
      await action(tester, 'gallery', 'queue-scan');
      final rows = await env.db.select(env.db.media).get();
      expect(rows.map((r) => r.assetId).toSet(), {'asset-1', 'asset-2'});
      expect(rows.every((r) => r.scanStatus == 'pending'), isTrue);
      expect(find.byKey(const Key('asset-3')), findsOneWidget);
    },
    session: testSession,
  );

  appTest(
    'dataset batch exclusion leaves unselected captions and inclusion intact',
    (tester, env) async {
      await env.db
          .into(env.db.datasets)
          .insert(
            DatasetsCompanion.insert(
              id: 'data',
              triggerWord: 'sara',
              createdAt: 1,
            ),
          );
      final ids = <int>[];
      for (var i = 1; i <= 3; i++) {
        ids.add(
          await env.db
              .into(env.db.datasetItems)
              .insert(
                DatasetItemsCompanion.insert(
                  datasetId: 'data',
                  path: 'datasets/$i.jpg',
                  caption: 'Caption $i',
                ),
              ),
        );
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/datasets/data')],
      );
      await chooseMultiple(tester, 'dataset-items', '${ids.first}');
      await tester.scrollUntilVisible(
        find.byKey(Key('dataset-items-item-${ids[1]}')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('dataset-items-item-${ids[1]}')));
      await tester.pumpAndSettle();
      await action(tester, 'dataset-items', 'exclude');
      final items = await env.db.select(env.db.datasetItems).get();
      expect(items.map((i) => i.included), [false, false, true]);
      expect(items.map((i) => i.caption), [
        'Caption 1',
        'Caption 2',
        'Caption 3',
      ]);
    },
    session: testSession,
  );

  appTest(
    'removing selected paused tasks keeps unselected tasks and saved outputs',
    (tester, env) async {
      for (var i = 1; i <= 3; i++) {
        await env.db
            .into(env.db.jobs)
            .insert(
              JobsCompanion.insert(
                id: 'j$i',
                serverId: testSession.serverId,
                type: 'reface_image',
                requestJson: '{}',
                targetPath: 'target.jpg',
                targetSha: 'a' * 64,
                targetSize: 1,
                status: 'paused',
                createdAt: i,
                updatedAt: i,
                acknowledged: const Value(true),
              ),
            );
        await env.db
            .into(env.db.results)
            .insert(
              ResultsCompanion.insert(
                id: 'j$i',
                type: 'reface_image',
                path: 'results/$i.jpg',
                originalPath: 'source.jpg',
                mime: 'image/jpeg',
                sizeBytes: 1,
                sha256: 'a',
                createdAt: i,
              ),
            );
      }
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/activity')],
      );
      await chooseMultiple(tester, 'active-jobs', 'j1');
      await tester.tap(find.byKey(const Key('active-jobs-item-j2')));
      await tester.pumpAndSettle();
      await action(tester, 'active-jobs', 'remove');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Remove selected tasks'),
      );
      await tester.pumpAndSettle();
      expect((await env.db.select(env.db.jobs).get()).map((j) => j.id), ['j3']);
      expect(await env.db.select(env.db.results).get(), hasLength(3));
    },
    session: testSession,
  );
}
