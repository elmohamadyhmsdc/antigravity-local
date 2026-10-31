import 'package:drift/drift.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Counts shown on Home. `unsorted` = faces that belong to nobody yet and were
/// not dismissed from review.
class LibraryStats {
  const LibraryStats({
    this.people = 0,
    this.faces = 0,
    this.photos = 0,
    this.videos = 0,
    this.unsorted = 0,
  });

  final int people;
  final int faces;
  final int photos;
  final int videos;
  final int unsorted;

  bool get isEmpty => people == 0 && faces == 0 && photos == 0 && videos == 0;

  @override
  bool operator ==(Object other) =>
      other is LibraryStats &&
      other.people == people &&
      other.faces == faces &&
      other.photos == photos &&
      other.videos == videos &&
      other.unsorted == unsorted;

  @override
  int get hashCode => Object.hash(people, faces, photos, videos, unsorted);

  @override
  String toString() =>
      'LibraryStats(people: $people, faces: $faces, photos: $photos, videos: $videos, unsorted: $unsorted)';
}

@DriftDatabase(
  tables: [
    Persons,
    Media,
    Faces,
    FaceSuppressions,
    Bodies,
    FaceRejections,
    BodyRejections,
    PersonDistinct,
    Servers,
    Settings,
    UploadQueue,
    BlobHints,
    MediaDetections,
    ReviewMatches,
    ReviewGroups,
    ReviewDuplicates,
    ReviewBodyLinks,
    Jobs,
    Results,
    Datasets,
    DatasetItems,
    Loras,
    IdentitySets,
    IdentitySetFaces,
    JobEvents,
    CharacterIdentities,
    CharacterSamples,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Bump together with a new `if (from < N)` step in [migration] and a test in
  /// test/data/app_database_test.dart.
  static const currentSchemaVersion = 9;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(uploadQueue);
        await m.createTable(blobHints);
      }
      if (from < 3) {
        await m.addColumn(media, media.takenAt);
        await m.addColumn(media, media.scanAttempts);
        await m.addColumn(media, media.scanError);
        await m.createTable(mediaDetections);
        await m.createTable(reviewMatches);
        await m.createTable(reviewGroups);
        await m.createTable(reviewDuplicates);
        await m.createTable(reviewBodyLinks);
        for (final index in [
          mediaScanStatus,
          facesPersonId,
          facesMediaId,
          bodiesMediaId,
          bodiesPersonId,
          bodiesFaceId,
          faceRejectionsPersonId,
          mediaDetectionsMediaId,
          mediaDetectionsRef,
        ]) {
          await m.createIndex(index);
        }
      }
      if (from < 4) {
        await m.createTable(jobs);
        await m.createTable(results);
        await m.createIndex(jobsStatus);
        await m.createIndex(resultsCreatedAt);
      }
      if (from < 5) {
        // Fresh v4 tables already use the current shape when upgrading from v1-v3.
        if (from >= 4) {
          await m.addColumn(jobs, jobs.inputFiles);
          await m.addColumn(jobs, jobs.detailsJson);
        }
        await m.createTable(datasets);
        await m.createTable(datasetItems);
        await m.createTable(loras);
      }
      if (from < 6) {
        await m.createTable(identitySets);
        await m.createTable(identitySetFaces);
        await m.createTable(jobEvents);
      }
      if (from < 7) {
        await m.createTable(faceSuppressions);
        await m.createIndex(faceSuppressionsAsset);
      }
      if (from < 8) {
        await m.createTable(characterIdentities);
        await m.createTable(characterSamples);
        await m.createIndex(characterSamplesIdentity);
        await m.createIndex(characterSamplesMedia);
      }
      if (from < 9) {
        // Also tolerate imports/tests whose table already has newer columns.
        Future<void> addMissing(
          TableInfo<Table, dynamic> table,
          List<GeneratedColumn<Object>> columns,
        ) async {
          final existing = (await customSelect(
            'PRAGMA table_info(${table.actualTableName})',
          ).get()).map((r) => r.read<String>('name')).toSet();
          for (final column in columns) {
            if (!existing.contains(column.name)) {
              await m.addColumn(table, column);
            }
          }
        }

        await addMissing(persons, [
          persons.hidden,
          persons.favorite,
          persons.pinned,
          persons.groupingLocked,
        ]);
        await addMissing(faces, [faces.hidden]);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Live library counts for Home.
  Stream<LibraryStats> watchLibraryStats() {
    return customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM persons) AS people,
        (SELECT COUNT(*) FROM faces) AS faces,
        (SELECT COUNT(*) FROM media WHERE kind = 'photo') AS photos,
        (SELECT COUNT(*) FROM media WHERE kind = 'video') AS videos,
        (SELECT COUNT(*) FROM faces WHERE person_id IS NULL AND review_dismissed = 0) AS unsorted
      ''',
      readsFrom: {persons, faces, media},
    ).watchSingle().map(
      (row) => LibraryStats(
        people: row.read<int>('people'),
        faces: row.read<int>('faces'),
        photos: row.read<int>('photos'),
        videos: row.read<int>('videos'),
        unsorted: row.read<int>('unsorted'),
      ),
    );
  }

  Future<LibraryStats> libraryStats() => watchLibraryStats().first;

  // ---- servers + settings (used by the session store) ----------------------------

  Future<ServerRow?> latestServer() {
    return (select(servers)
          ..orderBy([(s) => OrderingTerm.desc(s.pairedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsertServer(ServersCompanion row) =>
      into(servers).insertOnConflictUpdate(row);

  Future<void> deleteServer(String id) =>
      (delete(servers)..where((s) => s.id.equals(id))).go();

  Future<void> touchServer(String id, int nowMs) =>
      (update(servers)..where((s) => s.id.equals(id))).write(
        ServersCompanion(lastSeenAt: Value(nowMs)),
      );

  Future<String?> setting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> moveServer(String id, String host, int port) async {
    await (update(servers)..where((s) => s.id.equals(id))).write(
      ServersCompanion(host: Value(host), port: Value(port)),
    );
  }

  Future<void> putSetting(String key, String value) => into(
    settings,
  ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
