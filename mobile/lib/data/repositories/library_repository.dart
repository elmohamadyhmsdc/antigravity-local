import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../media/media_library.dart';

/// Bump when what a scan extracts changes, so older results are redone.
const scanVersion = 1;

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
  });

  final int added; // never seen before
  final int changed; // the file was edited since its last scan
  final int
  requeued; // known, but needed another go (failed / skipped / older scan version)
  final int unchanged;

  int get queued => added + changed + requeued;

  SyncResult operator +(SyncResult o) => SyncResult(
    added: added + o.added,
    changed: changed + o.changed,
    requeued: requeued + o.requeued,
    unchanged: unchanged + o.unchanged,
  );
}

/// The scan queue and the media table.
class LibraryRepository {
  LibraryRepository(this._db);

  final AppDatabase _db;

  Future<void> skipPending() =>
      (_db.update(_db.media)..where((m) => m.scanStatus.equals('pending')))
          .write(const MediaCompanion(scanStatus: Value('skipped')));

  /// Diffs MediaStore against what is known: new files are queued, edited files are queued again,
  /// unchanged scanned files are left alone. Idempotent - running it twice queues nothing new.
  Future<SyncResult> syncAssets(List<AssetInfo> assets) async {
    if (assets.isEmpty) return const SyncResult();
    return _db.transaction(() async {
      var added = 0, changed = 0, requeued = 0, unchanged = 0;
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
        for (final a in chunk) {
          if (!seen.add(a.id)) continue; // the same photo twice in one page
          final row = known[a.id];
          if (row == null) {
            fresh.add(
              MediaCompanion.insert(
                assetId: a.id,
                kind: 'photo',
                modifiedAt: Value(a.modifiedAt),
                width: Value(a.width),
                height: Value(a.height),
                takenAt: Value(a.takenAt),
              ),
            );
            added++;
            continue;
          }
          final same = a.sameSignatureAs(
            modifiedAt: row.modifiedAt,
            width: row.width ?? 0,
            height: row.height ?? 0,
          );
          if (!same) {
            await (_db.update(
              _db.media,
            )..where((m) => m.id.equals(row.id))).write(
              MediaCompanion(
                modifiedAt: Value(a.modifiedAt),
                width: Value(a.width),
                height: Value(a.height),
                takenAt: Value(a.takenAt),
                scanStatus: const Value('pending'),
                scanAttempts: const Value(0),
                scanError: const Value(null),
              ),
            );
            changed++;
          } else if (row.scanStatus == 'skipped' ||
              row.scanStatus == 'failed' ||
              (row.scanStatus == 'done' && row.scanVersion < scanVersion)) {
            await (_db.update(
              _db.media,
            )..where((m) => m.id.equals(row.id))).write(
              const MediaCompanion(
                scanStatus: Value('pending'),
                scanAttempts: Value(0),
                scanError: Value(null),
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
      );
    });
  }

  /// Takes the next waiting photo (newest first) and marks it as being scanned.
  Future<MediaRow?> claimNext() => _db.transaction(() async {
    final row =
        await (_db.select(_db.media)
              ..where(
                (m) => m.scanStatus.equals('pending') & m.kind.equals('photo'),
              )
              ..orderBy([(m) => OrderingTerm.asc(m.id)])
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
      FROM media WHERE kind = 'photo'
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
    FROM media WHERE kind = 'photo'
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
  Future<void> deleteMedia(Iterable<int> ids) =>
      (_db.delete(_db.media)..where((m) => m.id.isIn(ids.toList()))).go();
}
