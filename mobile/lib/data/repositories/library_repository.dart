import 'action_frames.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../media/media_library.dart';
import 'kind_corrections.dart';
import '../../domain/organization/sidecar_ingestion_service.dart';
import '../../domain/organization/sidecar_storage.dart';

/// Bump when what a scan extracts changes, so older results are redone.
/// 3: characters get pose keypoints, body extent/outline and the people's face-body pairing;
/// person/character corrections. 4: drawn faces boxed by the people's face detector.
// v5 retains distinct same-outfit bodies and real per-frame action poses for
// both identity kinds. The next explicit scan requeues older completed media.
const scanVersion = 5;

/// How many photos are where in the scan queue. The queue is the `media` table itself:
/// `scan_status` = pending (waiting) | scanning (a worker has it) | done | failed | skipped
/// (not in the albums chosen for the current scan).
class ScanCounts {
  const ScanCounts({
    this.pending = 0,
    this.scanning = 0,
    this.done = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int pending;
  final int scanning;
  final int done;
  final int failed;
  final int skipped;

  /// Photos in scope of the current scan.
  int get total => pending + scanning + done + failed;
  int get remaining => pending + scanning;

  @override
  bool operator ==(Object other) =>
      other is ScanCounts &&
      other.pending == pending &&
      other.scanning == scanning &&
      other.done == done &&
      other.failed == failed &&
      other.skipped == skipped;

  @override
  int get hashCode => Object.hash(pending, scanning, done, failed, skipped);

  @override
  String toString() =>
      'ScanCounts(pending: $pending, scanning: $scanning, done: $done, failed: $failed, skipped: $skipped)';
}

class SyncResult {
  const SyncResult({
    this.added = 0,
    this.changed = 0,
    this.requeued = 0,
    this.unchanged = 0,
    this.restored = 0,
  });

  final int added; // never seen before
  final int changed; // the file was edited since its last scan
  final int
  requeued; // known, but needed another go (failed / skipped / older scan version)
  final int unchanged;
  final int restored;

  int get queued => added + changed + requeued;

  SyncResult operator +(SyncResult o) => SyncResult(
    added: added + o.added,
    changed: changed + o.changed,
    requeued: requeued + o.requeued,
    unchanged: unchanged + o.unchanged,
    restored: restored + o.restored,
  );
}

/// The scan queue and the media table.
class LibraryRepository {
  LibraryRepository(
    this._db, {
    this.ingestionService,
    this.sidecarStorage = const SidecarStorage(),
  });

  final AppDatabase _db;
  final SidecarIngestionService? ingestionService;
  final SidecarStorage sidecarStorage;

  /// Finds any analysis already associated with a device original.
  Future<MediaRow?> mediaByAssetId(String assetId) => (_db.select(
    _db.media,
  )..where((m) => m.assetId.equals(assetId))).getSingleOrNull();

  /// Registers visible originals for the viewer without enrolling them in a scan.
  /// Existing analysis, corrections, checkpoints and queue states stay untouched.
  /// Explicit source enumeration later promotes skipped records through syncAssets.
  Future<List<MediaRow>> ensureBrowsableAssets(List<AssetInfo> assets) async {
    if (assets.isEmpty) return const [];
    return _db.transaction(() async {
      final rows = <String, MediaRow>{};
      for (var offset = 0; offset < assets.length; offset += 400) {
        final end = offset + 400 < assets.length ? offset + 400 : assets.length;
        final chunk = assets.sublist(offset, end);
        final ids = chunk.map((asset) => asset.id).toSet();
        final known = await (_db.select(
          _db.media,
        )..where((m) => m.assetId.isIn(ids))).get();
        rows.addEntries(known.map((row) => MapEntry(row.assetId, row)));
        final added = <String>{};
        final fresh = <MediaCompanion>[
          for (final asset in chunk)
            if (!rows.containsKey(asset.id) && added.add(asset.id))
              MediaCompanion.insert(
                assetId: asset.id,
                kind: asset.kind,
                durationMs: Value(asset.durationMs),
                modifiedAt: Value(asset.modifiedAt),
                width: Value(asset.width),
                height: Value(asset.height),
                takenAt: Value(asset.takenAt),
                illustrated: Value(asset.illustrated),
                scanStatus: const Value('skipped'),
              ),
        ];
        if (fresh.isNotEmpty) {
          await _db.batch((batch) {
            batch.insertAll(_db.media, fresh, mode: InsertMode.insertOrIgnore);
          });
          final saved = await (_db.select(
            _db.media,
          )..where((m) => m.assetId.isIn(ids))).get();
          rows.addEntries(saved.map((row) => MapEntry(row.assetId, row)));
        }
      }
      return [for (final asset in assets) rows[asset.id]!];
    });
  }

  Future<void> skipPending() =>
      (_db.update(_db.media)..where((m) => m.scanStatus.equals('pending')))
          .write(const MediaCompanion(scanStatus: Value('skipped')));

  Stream<List<MediaRow>> watchFailedMedia({int limit = 200}) =>
      (_db.select(_db.media)
            ..where((row) => row.scanStatus.equals('failed'))
            ..orderBy([(row) => OrderingTerm.desc(row.id)])
            ..limit(limit))
          .watch();

  /// Retry only changes the persisted queue. It never overrides a user's pause,
  /// changes sources or discards an interrupted video's saved frame checkpoint.
  Future<int> requeueFailed({Iterable<int>? mediaIds}) {
    final ids = mediaIds?.toSet();
    if (ids != null && ids.isEmpty) return Future.value(0);
    final update = _db.update(_db.media)
      ..where((row) => row.scanStatus.equals('failed'));
    if (ids != null) update.where((row) => row.id.isIn(ids));
    return update.write(
      const MediaCompanion(
        scanStatus: Value('pending'),
        scanAttempts: Value(0),
        scanError: Value(null),
      ),
    );
  }

  /// Diffs MediaStore against what is known: new files are queued, edited files are queued again,
  /// unchanged scanned files are left alone. Idempotent - running it twice queues nothing new.
  /// Drawn characters found in one file go (faces, bodies, their detections), and so do
  /// unnamed characters left with nothing. The file is scanned again right after.
  Future<void> _dropCharactersOf(int mediaId) async {
    final id = [Variable.withInt(mediaId)];
    await _db.customUpdate(
      "DELETE FROM media_detections WHERE media_id = ?1 AND "
      "((kind = 'f' AND ref_id IN (SELECT id FROM faces WHERE media_id = ?1 AND kind = 'character')) "
      "OR (kind = 'b' AND ref_id IN (SELECT id FROM bodies WHERE media_id = ?1 AND kind = 'character')))",
      variables: id,
      updates: {_db.mediaDetections},
    );
    await _db.customUpdate(
      "DELETE FROM bodies WHERE media_id = ? AND kind = 'character'",
      variables: id,
      updates: {_db.bodies},
    );
    await _db.customUpdate(
      "DELETE FROM faces WHERE media_id = ? AND kind = 'character'",
      variables: id,
      updates: {_db.faces},
    );
    await _db.customUpdate(
      "DELETE FROM persons WHERE kind = 'character' AND (name IS NULL OR name = '') "
      'AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.person_id = persons.id) '
      'AND NOT EXISTS (SELECT 1 FROM bodies b WHERE b.person_id = persons.id)',
      updates: {_db.persons},
    );
  }

  Future<SyncResult> syncAssets(
    List<AssetInfo> assets, {
    Map<String, String>? assetPaths,
  }) async {
    if (assets.isEmpty) return const SyncResult();
    return _db.transaction(() async {
      var added = 0, changed = 0, requeued = 0, unchanged = 0, restored = 0;
      for (var start = 0; start < assets.length; start += 400) {
        final chunk = assets.sublist(
          start,
          start + 400 > assets.length ? assets.length : start + 400,
        );
        final known = {
          for (final row in await (_db.select(
            _db.media,
          )..where((m) => m.assetId.isIn([for (final a in chunk) a.id]))).get())
            row.assetId: row,
        };
        final fresh = <MediaCompanion>[];
        final seen = <String>{};
        final organized = {
          for (final move
              in await (_db.select(_db.personMediaMoves)..where(
                    (j) =>
                        j.assetId.isIn(chunk.map((a) => a.id)) &
                        j.state.isIn(['pending', 'moved']),
                  ))
                  .get())
            move.assetId,
        };
        for (final incoming in chunk) {
          if (ingestionService != null &&
              assetPaths != null &&
              assetPaths.containsKey(incoming.id)) {
            final path = assetPaths[incoming.id];
            if (path != null) {
              final sidecar = await sidecarStorage.readSidecar(path);
              if (sidecar != null && sidecar.assetId == incoming.id) {
                await ingestionService!.ingest(sidecar);
                restored++;
                continue;
              }
            }
          }
          final previous = known[incoming.id];
          // Moving to a new Android album must not change a file's real/anime
          // scan mode and discard its character identities on the next sync.
          final a = previous != null && organized.contains(incoming.id)
              ? incoming.withIllustrated(previous.illustrated)
              : incoming;
          if (!seen.add(a.id)) continue; // the same photo twice in one page
          final row = known[a.id];
          if (row == null) {
            fresh.add(
              MediaCompanion.insert(
                assetId: a.id,
                kind: a.kind,
                durationMs: Value(a.durationMs),
                modifiedAt: Value(a.modifiedAt),
                width: Value(a.width),
                height: Value(a.height),
                takenAt: Value(a.takenAt),
                illustrated: Value(a.illustrated),
              ),
            );
            added++;
            continue;
          }
          if (row.illustrated != a.illustrated) {
            // Its album was marked/unmarked as anime/cartoon: rescan it in the other
            // mode. Characters of a file that is no longer illustrated are wrong.
            if (!a.illustrated) await _dropCharactersOf(row.id);
            await (_db.delete(_db.settings)..where(
                  (s) => s.key.isIn([
                    'video.job.${row.id}',
                    'video.local.${row.id}',
                  ]),
                ))
                .go();
            await (_db.update(
              _db.media,
            )..where((m) => m.id.equals(row.id))).write(
              MediaCompanion(
                illustrated: Value(a.illustrated),
                scanVersion: const Value(0),
                lastScannedFrame: const Value(0),
                scanStatus: const Value('pending'),
                scanAttempts: const Value(0),
                scanError: const Value(null),
              ),
            );
            changed++;
            continue;
          }
          final same =
              row.kind == a.kind &&
              row.durationMs == a.durationMs &&
              a.sameSignatureAs(
                modifiedAt: row.modifiedAt,
                width: row.width ?? 0,
                height: row.height ?? 0,
              );
          if (!same) {
            await (_db.delete(
              _db.settings,
            )..where((s) => s.key.like('$actionFramePrefix${row.id}.%'))).go();
            await (_db.update(
              _db.media,
            )..where((m) => m.id.equals(row.id))).write(
              MediaCompanion(
                modifiedAt: Value(a.modifiedAt),
                width: Value(a.width),
                height: Value(a.height),
                takenAt: Value(a.takenAt),
                kind: Value(a.kind),
                durationMs: Value(a.durationMs),
                lastScannedFrame: const Value(0),
                scanStatus: const Value('pending'),
                scanAttempts: const Value(0),
                scanError: const Value(null),
              ),
            );
            changed++;
          } else if (row.scanStatus == 'skipped' ||
              row.scanStatus == 'failed' ||
              (row.scanStatus == 'done' && row.scanVersion < scanVersion)) {
            // An interrupted video resumes where it stopped; a finished one redone for a new
            // version starts again (it would otherwise resume at its last frame and redo nothing).
            final redo = row.scanStatus == 'done';
            await (_db.update(
              _db.media,
            )..where((m) => m.id.equals(row.id))).write(
              MediaCompanion(
                scanStatus: const Value('pending'),
                scanAttempts: const Value(0),
                scanError: const Value(null),
                lastScannedFrame: redo ? const Value(0) : const Value.absent(),
              ),
            );
            requeued++;
          } else {
            unchanged++;
          }
        }
        if (fresh.isNotEmpty) {
          await _db.batch((b) => b.insertAll(_db.media, fresh));
        }
      }
      return SyncResult(
        added: added,
        changed: changed,
        requeued: requeued,
        unchanged: unchanged,
        restored: restored,
      );
    });
  }

  /// Photos first (seconds each), then videos shortest first, so one long video
  /// never holds up the rest of a large library.
  static final _queueOrder = <OrderClauseGenerator<$MediaTable>>[
    (m) => OrderingTerm.asc(m.kind.equals('video')),
    (m) => OrderingTerm.asc(m.durationMs),
    (m) => OrderingTerm.asc(m.id),
  ];

  /// Looks ahead by one item without claiming it; used for bounded JPEG preparation.
  Future<MediaRow?> nextPending() =>
      (_db.select(_db.media)
            ..where(
              (m) =>
                  m.scanStatus.equals('pending') &
                  m.kind.isIn(['photo', 'video']),
            )
            ..orderBy(_queueOrder)
            ..limit(1))
          .getSingleOrNull();

  /// Takes the next waiting item and marks it as being scanned.
  Future<MediaRow?> claimNext() => _db.transaction(() async {
    final row =
        await (_db.select(_db.media)
              ..where(
                (m) =>
                    m.scanStatus.equals('pending') &
                    m.kind.isIn(['photo', 'video']),
              )
              ..orderBy(_queueOrder)
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    await (_db.update(_db.media)..where((m) => m.id.equals(row.id))).write(
      MediaCompanion(
        scanStatus: const Value('scanning'),
        scanAttempts: Value(row.scanAttempts + 1),
      ),
    );
    return row;
  });

  Future<void> markFailed(int mediaId, String error) =>
      (_db.update(_db.media)..where((m) => m.id.equals(mediaId))).write(
        MediaCompanion(
          scanStatus: const Value('failed'),
          scanError: Value(error),
        ),
      );

  /// The user's person/character corrections for one file, sent with its scan.
  Future<KindCorrectionSet> kindCorrections(String assetId) =>
      KindOverrideStore(_db).forAsset(assetId);

  /// Gives a claimed photo back (the PC was busy / unreachable): it is not the photo's fault.
  Future<void> requeue(int mediaId) async {
    final row = await mediaById(mediaId);
    if (row == null) return;
    await (_db.update(_db.media)..where((m) => m.id.equals(mediaId))).write(
      MediaCompanion(
        scanStatus: const Value('pending'),
        scanAttempts: Value(row.scanAttempts > 0 ? row.scanAttempts - 1 : 0),
      ),
    );
  }

  /// Files a scan finished with an older [scanVersion] go back to the queue, from their start.
  Future<int> requeueOutdated() => _db.customUpdate(
    '''UPDATE media SET scan_status = 'pending', scan_attempts = 0, scan_error = NULL,
         last_scanned_frame = 0
       WHERE scan_status = 'done' AND scan_version < ?''',
    variables: [Variable.withInt(scanVersion)],
    updates: {_db.media},
    updateKind: UpdateKind.update,
  );

  /// After the app was killed mid-photo: whatever was being scanned goes back to the queue.
  Future<int> resetScanning() =>
      (_db.update(_db.media)..where((m) => m.scanStatus.equals('scanning')))
          .write(const MediaCompanion(scanStatus: Value('pending')));

  Future<ScanCounts> scanCounts() async {
    final row = await _db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(scan_status = 'pending'), 0) AS pending,
        COALESCE(SUM(scan_status = 'scanning'), 0) AS scanning,
        COALESCE(SUM(scan_status = 'done'), 0) AS done,
        COALESCE(SUM(scan_status = 'failed'), 0) AS failed,
        COALESCE(SUM(scan_status = 'skipped'), 0) AS skipped
      FROM media WHERE kind IN ('photo', 'video')
      ''',
          readsFrom: {_db.media},
        )
        .getSingle();
    return _counts(row);
  }

  Stream<ScanCounts> watchScanCounts() => _db
      .customSelect(
        '''
    SELECT
      COALESCE(SUM(scan_status = 'pending'), 0) AS pending,
      COALESCE(SUM(scan_status = 'scanning'), 0) AS scanning,
      COALESCE(SUM(scan_status = 'done'), 0) AS done,
      COALESCE(SUM(scan_status = 'failed'), 0) AS failed,
      COALESCE(SUM(scan_status = 'skipped'), 0) AS skipped
    FROM media WHERE kind IN ('photo', 'video')
    ''',
        readsFrom: {_db.media},
      )
      .watchSingle()
      .map(_counts);

  static ScanCounts _counts(QueryRow row) => ScanCounts(
    pending: row.read<int>('pending'),
    scanning: row.read<int>('scanning'),
    done: row.read<int>('done'),
    failed: row.read<int>('failed'),
    skipped: row.read<int>('skipped'),
  );

  Future<MediaRow?> mediaById(int id) =>
      (_db.select(_db.media)..where((m) => m.id.equals(id))).getSingleOrNull();

  Stream<MediaRow?> watchMedia(int id) => (_db.select(
    _db.media,
  )..where((m) => m.id.equals(id))).watchSingleOrNull();

  Future<int> faceCount() async =>
      (await _db
              .customSelect(
                'SELECT COUNT(*) AS n FROM faces',
                readsFrom: {_db.faces},
              )
              .getSingle())
          .read<int>('n');

  /// Faces found by the scan since `sinceMs` (for the progress card).
  Future<int> facesCreatedSince(int sinceMs) async =>
      (await _db
              .customSelect(
                'SELECT COUNT(*) AS n FROM faces WHERE created_at >= ?',
                variables: [Variable.withInt(sinceMs)],
                readsFrom: {_db.faces},
              )
              .getSingle())
          .read<int>('n');

  /// Deletes media rows (and, through the foreign keys, their faces and detections).
  Future<void> deleteMedia(Iterable<int> ids) => _db.transaction(() async {
    final list = ids.toSet().toList();
    for (final id in list) {
      await (_db.delete(
        _db.settings,
      )..where((s) => s.key.like('$actionFramePrefix$id.%'))).go();
    }
    for (var start = 0; start < list.length; start += 400) {
      await (_db.delete(
        _db.media,
      )..where((m) => m.id.isIn(list.skip(start).take(400)))).go();
    }
  });
}
