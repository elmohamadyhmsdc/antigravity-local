import 'dart:io';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/features/inspector/media_inspector.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/ui/selection/collection_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

Future<void> chooseMultiple(
  WidgetTester tester,
  String collection,
  String id,
) async {
  await tester.ensureVisible(find.byKey(Key('$collection-item-$id')));
  await tester.pumpAndSettle();
  await tester.longPress(find.byKey(Key('$collection-item-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('$collection-select-multiple')));
  await tester.pumpAndSettle();
}

Future<void> action(
  WidgetTester tester,
  String collection,
  String id, {
  bool settle = true,
}) async {
  await tester.tap(find.byKey(Key('$collection-actions')));
  await tester.pumpAndSettle();
  final target = find.byKey(Key('$collection-action-$id'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }
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
      env.library.addAlbum(
        const AlbumInfo(id: 'all', name: 'All', count: 3, isAll: true),
        syntheticAssets(3),
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/library')],
      );
      await chooseMultiple(tester, 'gallery', 'asset-1');
      await tester.tap(find.byKey(const Key('gallery-item-asset-2')));
      await tester.pumpAndSettle();
      await action(tester, 'gallery', 'queue-scan');
      final rows = await env.db.select(env.db.media).get();
      expect(rows.map((r) => r.assetId).toSet(), {'asset-1', 'asset-2'});
      expect(rows.every((r) => r.scanStatus == 'pending'), isTrue);
      expect(find.byKey(const Key('gallery-item-asset-3')), findsOneWidget);
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
  appTest('batch assignment detaches wrong body link and keeps face identity', (
    tester,
    env,
  ) async {
    final oldOwner = await seedPerson(env.db, name: 'Old owner');
    final target = await seedPerson(env.db, name: 'Target owner');
    final media = await seedMedia(env.db);
    final face = await seedFace(env.db, mediaId: media, personId: oldOwner);
    final bodies = <int>[];
    for (var i = 0; i < 3; i++) {
      bodies.add(await seedBody(env.db, mediaId: media, faceId: face));
    }
    await env.pump(
      tester,
      extra: [initialLocationProvider.overrideWithValue('/bodies')],
    );
    await chooseMultiple(tester, 'bodies', '${bodies[0]}');
    await tester.tap(find.byKey(Key('bodies-item-${bodies[1]}')));
    await tester.pumpAndSettle();
    await action(tester, 'bodies', 'assign', settle: false);
    expect(find.byKey(const Key('person-picker-search')), findsOneWidget);
    final targetChoice = find.byKey(Key('person-picker-$target'));
    for (var i = 0; i < 20 && targetChoice.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(targetChoice);
    await tester.pumpAndSettle();
    final rows = await env.db.select(env.db.bodies).get();
    expect(rows.take(2).map((r) => r.personId), [target, target]);
    expect(rows.take(2).every((r) => r.faceId == null), isTrue);
    expect(rows.last.faceId, face);
    expect((await env.db.select(env.db.faces).get()).single.personId, oldOwner);
    expect(await env.db.select(env.db.bodyRejections).get(), hasLength(2));
  }, session: testSession);

  appTest('sharing selected results opens one share request', (
    tester,
    env,
  ) async {
    for (var i = 1; i <= 3; i++) {
      await env.db
          .into(env.db.results)
          .insert(
            ResultsCompanion.insert(
              id: 's$i',
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
    final requests = <List<File>>[];
    await env.pump(
      tester,
      extra: [
        initialLocationProvider.overrideWithValue('/results'),
        collectionShareProvider.overrideWithValue(
          (files) async => requests.add(files),
        ),
      ],
    );
    await chooseMultiple(tester, 'results', 's1');
    await tester.tap(find.byKey(const Key('results-item-s2')));
    await tester.pumpAndSettle();
    await action(tester, 'results', 'share');
    expect(requests, hasLength(1));
    expect(
      requests.single.map((file) => file.path),
      unorderedEquals([
        env.files.resolve('results/2.jpg').path,
        env.files.resolve('results/1.jpg').path,
      ]),
    );
  }, session: testSession);

  appTest('inspector hides only selected detections, preserving originals', (
    tester,
    env,
  ) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mediaId = await seedMedia(env.db);
    final face = await seedFace(env.db, mediaId: mediaId);
    final body = await seedBody(env.db, mediaId: mediaId);
    final otherFace = await seedFace(env.db, mediaId: mediaId, seed: 2);
    final media = (await env.db.select(env.db.media).get()).single;
    final queries = ProviderContainer(overrides: env.overrides);
    final detections = await queries
        .read(mediaQueriesProvider)
        .watchDetections(mediaId)
        .first;
    queries.dispose();
    await tester.pumpWidget(
      ProviderScope(
        overrides: env.overrides,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaInspectorContent(
              media: media,
              faces: detections.where((d) => d.isFace).toList(),
              bodies: detections.where((d) => d.isBody).toList(),
              people: const {},
              scrollController: ScrollController(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await chooseMultiple(tester, 'inspector-detections', 'f:$face');
    await tester.tap(find.byKey(Key('inspector-detections-item-b:$body')));
    await tester.pumpAndSettle();
    await action(tester, 'inspector-detections', 'false-detections');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Hide false detections'),
    );
    await tester.pumpAndSettle();
    final faces = {
      for (final row in await env.db.select(env.db.faces).get()) row.id: row,
    };
    expect(faces[face]!.hidden, isTrue);
    expect(faces[otherFace]!.hidden, isFalse);
    expect((await env.db.select(env.db.bodies).get()).single.hidden, isTrue);
    expect(await env.db.select(env.db.media).get(), hasLength(1));
    expect(
      find.byKey(Key('inspector-detections-item-f:$otherFace')),
      findsOneWidget,
    );
    expect(find.byKey(Key('inspector-detections-item-f:$face')), findsNothing);
  }, session: testSession);
  appTest(
    'album batch correction survives background refresh and preserves other people',
    (tester, env) async {
      final owner = await seedPerson(env.db, name: 'Album owner');
      final other = await seedPerson(env.db, name: 'Other person');
      final media = <int>[];
      final faces = <int>[];
      for (var i = 0; i < 3; i++) {
        final id = await seedMedia(env.db, asset: 'album-$i');
        media.add(id);
        faces.add(await seedFace(env.db, mediaId: id, personId: owner));
      }
      final otherFace = await seedFace(
        env.db,
        mediaId: media.first,
        personId: other,
        seed: 9,
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$owner')],
      );
      await tester.tap(find.byKey(const Key('media-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('media-item-${media[0]}')));
      await tester.tap(find.byKey(Key('media-item-${media[1]}')));
      await tester.pumpAndSettle();
      await (env.db.update(env.db.media)
            ..where((m) => m.id.equals(media.first)))
          .write(const MediaCompanion(sizeBytes: Value(99)));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await action(tester, 'media', 'not-person');
      await tester.tap(find.widgetWithText(FilledButton, 'Not this person'));
      await tester.pumpAndSettle();
      final rows = {
        for (final f in await env.db.select(env.db.faces).get()) f.id: f,
      };
      expect(rows[faces[0]]!.personId, isNull);
      expect(rows[faces[1]]!.personId, isNull);
      expect(rows[faces[2]]!.personId, owner);
      expect(rows[otherFace]!.personId, other);
      final rejected = await env.db.select(env.db.faceRejections).get();
      expect(rejected.map((r) => (r.faceId, r.personId)).toSet(), {
        (faces[0], owner),
        (faces[1], owner),
      });
      expect(await env.db.select(env.db.media).get(), hasLength(3));
    },
    session: testSession,
  );
}
