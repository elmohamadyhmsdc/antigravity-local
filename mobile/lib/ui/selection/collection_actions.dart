import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/media_queries.dart';
import '../../library_providers.dart';
import '../../studio_providers.dart';
import '../../providers.dart';
import '../../features/privacy/app_lock.dart';
import '../../features/shared/person_picker.dart';
import 'selection_collection.dart';

/// One share sheet for the entire selection. Injectable for platform tests.
final collectionShareProvider = Provider<Future<void> Function(List<File>)>(
  (_) => (files) async {
    if (files.isEmpty) throw StateError('No readable files selected');
    for (final file in files) {
      if (!await file.exists())
        throw StateError('A selected file is unavailable');
    }
    await SharePlus.instance.share(
      ShareParams(files: [for (final file in files) XFile(file.path)]),
    );
  },
);

Future<List<MediaRow>> selectedMedia(WidgetRef ref, Iterable<int> ids) async {
  final db = ref.read(databaseProvider);
  final all = ids.toSet().toList();
  final rows = <MediaRow>[];
  for (var i = 0; i < all.length; i += 400) {
    rows.addAll(
      await (db.select(
        db.media,
      )..where((m) => m.id.isIn(all.skip(i).take(400)))).get(),
    );
  }
  if (rows.length != all.length)
    throw StateError('Some selected media is no longer available');
  return rows;
}

List<CollectionAction<T>> mediaCollectionActions<T>(
  WidgetRef ref,
  Future<List<MediaRow>> Function(List<T>) resolve, {
  int? personId,
}) => [
  CollectionAction(
    id: 'share',
    label: 'Share originals',
    icon: Icons.share_outlined,
    run: (context, items) async {
      final library = ref.read(mediaLibraryProvider);
      if (library is! OriginalMediaLibrary)
        throw StateError('Original files are unavailable');
      final files = <File>[];
      for (final row in await resolve(items)) {
        final file = await (library as OriginalMediaLibrary).originalFile(
          row.assetId,
        );
        if (file == null) throw StateError('An original is unavailable');
        files.add(file);
      }
      await ref.read(collectionShareProvider)(files);
      return true;
    },
  ),
  CollectionAction(
    id: 'queue-scan',
    label: 'Queue for scanning',
    icon: Icons.document_scanner_outlined,
    run: (context, items) async {
      final rows = await resolve(items);
      if (rows.any((row) => row.scanStatus == 'scanning'))
        throw StateError('Wait for the selected file currently being scanned');
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        for (final row in rows) {
          await ref.read(libraryRepositoryProvider).requeue(row.id);
        }
      });
      return true;
    },
  ),
  if (personId != null)
    CollectionAction(
      id: 'not-person',
      label: 'Not this person',
      icon: Icons.person_off_outlined,
      confirmation:
          'Remove this identity from the selected photos and remember the correction. Original files and other people are kept.',
      run: (context, items) async {
        final rows = await resolve(items);
        final detections = <MediaDetection>[];
        for (final row in rows) {
          detections.addAll(
            (await ref.read(mediaQueriesProvider).watchDetections(row.id).first)
                .where((d) => d.personId == personId),
          );
        }
        final db = ref.read(databaseProvider);
        await db.transaction(() async {
          final people = ref.read(peopleRepositoryProvider);
          await people.rejectFaces(
            detections.where((d) => d.isFace).map((d) => d.refId).toSet(),
            fromPersonId: personId,
          );
          for (final id
              in detections
                  .where((d) => d.isBody)
                  .map((d) => d.refId)
                  .toSet()) {
            await people.rejectBody(id, personId: personId);
          }
        });
        return true;
      },
    ),
];

List<CollectionAction<int>> bodyCollectionActions(
  WidgetRef ref, {
  int? personId,
}) => [
  CollectionAction(
    id: 'assign',
    label: 'Assign to person / character',
    icon: Icons.person_add_alt,
    run: (context, ids) async {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(
        db.bodies,
      )..where((b) => b.id.isIn(ids))).get();
      final kinds = rows.map((row) => row.kind).toSet();
      if (kinds.length != 1)
        throw StateError('Select bodies of one identity type at a time');
      if (!context.mounted) return false;
      final choice = await pickPerson(
        context,
        allowNew: true,
        kind: kinds.single,
      );
      if (choice == null || !context.mounted) return false;
      await db.transaction(() async {
        final people = peopleRepositoryFor(ref, kinds.single);
        final target =
            choice.personId ?? await people.createPerson(name: choice.newName);
        for (final id in ids) {
          final current = await people.body(id);
          if (current?.personId != null && current!.personId != target) {
            await people.rejectBody(id, personId: current.personId);
          }
          await ref.read(bodyLinkGuardProvider).onManualLink(id, target);
          await people.linkBody(id, target);
          await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
            const BodiesCompanion(ownership: Value(null), hidden: Value(false)),
          );
        }
      });
      return true;
    },
  ),
  if (personId != null)
    CollectionAction(
      id: 'not-person',
      label: 'Not this person',
      icon: Icons.person_off_outlined,
      confirmation:
          'Unlink the selected bodies and remember that they do not belong to this identity. Original files are kept.',
      run: (context, ids) async {
        await ref.read(databaseProvider).transaction(() async {
          for (final id in ids) {
            await ref
                .read(peopleRepositoryProvider)
                .rejectBody(id, personId: personId);
          }
        });
        return true;
      },
    ),
  CollectionAction(
    id: 'share',
    label: 'Share selected crops',
    icon: Icons.share_outlined,
    run: (context, ids) async {
      final db = ref.read(databaseProvider);
      final rows = await (db.select(
        db.bodies,
      )..where((b) => b.id.isIn(ids))).get();
      final files = ref.read(fileStoreProvider);
      if (rows.length != ids.length || rows.any((row) => row.cropPath == null))
        throw StateError('Some body crops are unavailable');
      await ref.read(collectionShareProvider)([
        for (final row in rows) files.resolve(row.cropPath!),
      ]);
      return true;
    },
  ),
  CollectionAction(
    id: 'hide',
    label: 'Hide selected detections',
    icon: Icons.visibility_off_outlined,
    confirmation:
        'Hide these body detections from browsing. Original files and identity records are kept.',
    run: (context, ids) async {
      final db = ref.read(databaseProvider);
      await (db.update(db.bodies)..where((b) => b.id.isIn(ids))).write(
        const BodiesCompanion(hidden: Value(true)),
      );
      return true;
    },
  ),
];

List<CollectionAction<ResultRow>> resultCollectionActions(
  WidgetRef ref,
  List<ResultRow> items,
) => [
  if (items.any((r) => !r.favourite))
    CollectionAction(
      id: 'favourite',
      label: 'Add to favourites',
      icon: Icons.star_outline,
      run: (context, rows) async {
        final db = ref.read(databaseProvider);
        await (db.update(db.results)
              ..where((r) => r.id.isIn(rows.map((r) => r.id))))
            .write(const ResultsCompanion(favourite: Value(true)));
        return true;
      },
    ),
  if (items.any((r) => r.favourite))
    CollectionAction(
      id: 'unfavourite',
      label: 'Remove from favourites',
      icon: Icons.star_border,
      run: (context, rows) async {
        final db = ref.read(databaseProvider);
        await (db.update(db.results)
              ..where((r) => r.id.isIn(rows.map((r) => r.id))))
            .write(const ResultsCompanion(favourite: Value(false)));
        return true;
      },
    ),
  CollectionAction(
    id: 'share',
    label: 'Share selected results',
    icon: Icons.share_outlined,
    run: (context, rows) async {
      final files = ref.read(fileStoreProvider);
      await ref.read(collectionShareProvider)([
        for (final row in rows) files.resolve(row.path),
      ]);
      return true;
    },
  ),
  if (items.every(
    (r) => r.mime.startsWith('image/') || r.mime.startsWith('video/'),
  ))
    CollectionAction(
      id: 'save-gallery',
      label: 'Save to gallery',
      icon: Icons.save_alt,
      run: (context, rows) async {
        final files = ref.read(fileStoreProvider);
        await performBatch(rows, (r) => r.id, (r) async {
          final saved = await ref
              .read(privacyServiceProvider)
              .exportMedia(files.resolve(r.path), r.mime);
          if (!saved) throw StateError('Could not save a selected result');
        });
        return true;
      },
    ),
  CollectionAction(
    id: 'delete',
    label: 'Delete selected results',
    icon: Icons.delete_outline,
    destructive: true,
    confirmation:
        'Delete the selected private results and their files. Selected training results also remove their associated dataset or trained model. Phone originals are kept.',
    run: (context, rows) async {
      await performBatch(
        rows,
        (r) => r.id,
        ref.read(studioRepositoryProvider).deleteResult,
      );
      return true;
    },
  ),
];

List<CollectionAction<JobRow>> jobCollectionActions(
  WidgetRef ref,
  List<JobRow> jobs,
) {
  const running = {'uploading', 'running', 'queued', 'downloading'};
  const resumable = {'paused', 'failed', 'lost'};
  return [
    if (jobs.every((j) => running.contains(j.status)))
      CollectionAction(
        id: 'pause',
        label: 'Pause selected tasks',
        icon: Icons.pause,
        run: (context, rows) async {
          await performBatch(rows, (j) => j.id, (row) async {
            final current = await ref
                .read(studioRepositoryProvider)
                .job(row.id);
            if (current != null && running.contains(current.status))
              await ref.read(jobTrackerProvider).pause(current);
          });
          return true;
        },
      ),
    if (jobs.every((j) => resumable.contains(j.status)))
      CollectionAction(
        id: 'resume',
        label: 'Resume / retry selected tasks',
        icon: Icons.play_arrow,
        run: (context, rows) async {
          await performBatch(rows, (j) => j.id, (row) async {
            final current = await ref
                .read(studioRepositoryProvider)
                .job(row.id);
            if (current != null && resumable.contains(current.status))
              await ref.read(jobTrackerProvider).resume(current);
          });
          return true;
        },
      ),
    CollectionAction(
      id: 'remove',
      label: 'Remove selected tasks',
      icon: Icons.delete_outline,
      destructive: true,
      confirmation:
          'Stop unfinished selected tasks and remove their task records. Saved results are kept.',
      run: (context, rows) async {
        await performBatch(rows, (j) => j.id, (row) async {
          final repo = ref.read(studioRepositoryProvider);
          var current = await repo.job(row.id);
          if (current == null) return;
          if (running.contains(current.status)) {
            await ref.read(jobTrackerProvider).pause(current);
            current = await repo.job(row.id);
          }
          if (current != null)
            await ref.read(jobTrackerProvider).remove(current);
        });
        return true;
      },
    ),
  ];
}

List<CollectionAction<LoraRow>> modelCollectionActions(WidgetRef ref) => [
  CollectionAction<LoraRow>(
    id: 'share',
    label: 'Share selected models',
    icon: Icons.share_outlined,
    run: (context, items) async {
      await ref.read(collectionShareProvider)([
        for (final item in items)
          ref.read(fileStoreProvider).resolve(item.path),
      ]);
      return true;
    },
  ),
];

List<CollectionAction<DatasetRow>> datasetCollectionActions(WidgetRef ref) => [
  CollectionAction<DatasetRow>(
    id: 'export',
    label: 'Export selected datasets',
    icon: Icons.ios_share,
    run: (context, items) async {
      final files = <File>[];
      for (final item in items) {
        files.add(
          await ref.read(loraRepositoryProvider).exportDataset(item.id),
        );
      }
      await ref.read(collectionShareProvider)(files);
      return true;
    },
  ),
];
