import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../domain/scan/scan_math.dart';
import '../api/dtos/analyze.dart';
import '../db/app_database.dart';
import '../files/file_store.dart';
import '../index/embedding_index.dart';

typedef _Box = ({double x, double y, double w, double h});

/// A correction made on one video frame applies to the samples this close to it.
const videoCorrectionToleranceMs = 500;

String otherKind(String kind) => kind == 'person' ? 'character' : 'person';

Iterable<List<int>> _chunks(Iterable<int> ids, [int size = 400]) sync* {
  final list = ids.toSet().toList();
  for (var i = 0; i < list.length; i += size) {
    yield list.sublist(i, math.min(i + size, list.length));
  }
}

String _marks(int n) => List.filled(n, '?').join(',');

/// Same detection seen again: a face box may come back a little bigger or smaller.
/// `part` is 'face' or 'body'.
bool sameDetectionBox(
  ({double x, double y, double w, double h}) a,
  ({double x, double y, double w, double h}) b,
  String part,
) {
  if (iou(a, b) >= (part == 'face' ? .4 : .5)) return true;
  if (part != 'face') return false;
  final ix = math.max(0.0, math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x));
  final iy = math.max(0.0, math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y));
  final smaller = math.min(a.w * a.h, b.w * b.h);
  return smaller > 0 && ix * iy / smaller >= .6;
}

bool _nearInTime(int? a, int? b) =>
    a == null || b == null || (a - b).abs() <= videoCorrectionToleranceMs;

/// A file's corrections, the way a scan sends them to the PC.
class KindCorrectionSet {
  const KindCorrectionSet({this.forceKind, this.overrides = const []});

  /// 'person' | 'character' for the whole file, or null (decided per detection).
  final String? forceKind;
  final List<KindOverrideRow> overrides;

  /// Single-detection corrections; for one video frame only those near its time.
  List<KindOverrideDto> dtos({int? timestampMs}) => [
    for (final o in overrides)
      if (_nearInTime(o.timestampMs, timestampMs))
        KindOverrideDto(
          kind: o.kind,
          part: o.part!,
          box: (x: o.x!, y: o.y!, w: o.w!, h: o.h!),
          timestampMs: o.timestampMs,
        ),
  ];
}

/// Reads the corrections for scans and, inside a scan's transaction, puts what was found at a
/// corrected detection into the person or character it was moved to.
class KindOverrideStore {
  KindOverrideStore(this._db);
  final AppDatabase _db;

  Future<KindCorrectionSet> forAsset(String assetId) async {
    final rows =
        await (_db.select(_db.kindOverrides)
              ..where((o) => o.assetId.equals(assetId))
              ..orderBy([(o) => OrderingTerm.asc(o.id)]))
            .get();
    String? force;
    for (final r in rows) {
      if (r.part == null) force = r.kind;
    }
    return KindCorrectionSet(
      forceKind: force,
      overrides: [
        for (final r in rows)
          if (r.part != null) r,
      ],
    );
  }

  /// Call after a photo or frame was stored. Each correction names its target only once, so a
  /// later move by hand is not undone by the next rescan.
  Future<void> applyTargets(
    MediaRow media, {
    int? frameNumber,
    int? timestampMs,
  }) async {
    final pending =
        await (_db.select(_db.kindOverrides)..where(
              (o) =>
                  o.assetId.equals(media.assetId) &
                  o.targetPersonId.isNotNull() &
                  o.part.isNotNull(),
            ))
            .get();
    if (pending.isEmpty) return;
    final found = await _db
        .customSelect(
          '''SELECT d.kind AS part, d.ref_id, d.x, d.y, d.w, d.h,
               CASE d.kind WHEN 'f' THEN (SELECT kind FROM faces WHERE id = d.ref_id)
                           ELSE (SELECT kind FROM bodies WHERE id = d.ref_id) END AS row_kind
             FROM media_detections d WHERE d.media_id = ? AND d.frame_number IS ?''',
          variables: [Variable.withInt(media.id), Variable<int>(frameNumber)],
          readsFrom: {_db.mediaDetections, _db.faces, _db.bodies},
        )
        .get();
    for (final o in pending) {
      if (!_nearInTime(o.timestampMs, timestampMs)) continue;
      final target = await (_db.select(
        _db.persons,
      )..where((p) => p.id.equals(o.targetPersonId!))).getSingleOrNull();
      if (target == null) continue;
      final part = o.part == 'face' ? 'f' : 'b';
      final box = (x: o.x!, y: o.y!, w: o.w!, h: o.h!);
      for (final d in found) {
        if (d.read<String>('part') != part ||
            d.readNullable<String>('row_kind') != target.kind) {
          continue;
        }
        final seen = (
          x: d.read<double>('x'),
          y: d.read<double>('y'),
          w: d.read<double>('w'),
          h: d.read<double>('h'),
        );
        if (!sameDetectionBox(box, seen, o.part!)) continue;
        final id = Variable.withInt(d.read<int>('ref_id'));
        final person = Variable.withInt(target.id);
        if (part == 'f') {
          await _db.customUpdate(
            'UPDATE faces SET person_id = ?, review_dismissed = 0 WHERE id = ?',
            variables: [person, id],
            updates: {_db.faces},
          );
          await _db.customUpdate(
            'DELETE FROM review_matches WHERE face_id = ?',
            variables: [id],
            updates: {_db.reviewMatches},
          );
        } else {
          await _db.customUpdate(
            "UPDATE bodies SET person_id = ?, link_method = 'manual', link_confidence = NULL WHERE id = ?",
            variables: [person, id],
            updates: {_db.bodies},
          );
        }
        await (_db.update(_db.kindOverrides)..where((r) => r.id.equals(o.id)))
            .write(const KindOverridesCompanion(targetPersonId: Value(null)));
        break;
      }
    }
  }
}

/// "This is a person, not a character" (and the other way round) for a whole file, single
/// faces and bodies, or a whole person. The correction is remembered per file and sent with
/// every scan; the affected rows go, and the file is scanned again so the PC measures them
/// with the other kind's model (ArcFace for people, CCIP for characters).
class KindCorrections {
  KindCorrections(
    this._db,
    this._files, {
    this._index,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final EmbeddingIndex? _index;
  final DateTime Function() _clock;

  /// The file's kind: 'person', 'character', or null to decide per detection again.
  Future<String?> mediaKind(int mediaId) async {
    final media = await _media(mediaId);
    if (media == null) return null;
    return (await KindOverrideStore(_db).forAsset(media.assetId)).forceKind;
  }

  Future<void> setMediaKind(int mediaId, String? kind) async {
    final removed = _Removed();
    await _db.transaction(() async {
      final media = await _media(mediaId);
      if (media == null) return;
      await (_db.delete(
        _db.kindOverrides,
      )..where((o) => o.assetId.equals(media.assetId) & o.part.isNull())).go();
      if (kind != null) {
        await _db
            .into(_db.kindOverrides)
            .insert(
              KindOverridesCompanion.insert(
                assetId: media.assetId,
                kind: kind,
                createdAt: _clock().millisecondsSinceEpoch,
              ),
            );
      }
      // What the file holds of the other kind goes (everything, back to automatic); the
      // rescan finds it again as the right kind. People already named keep their names.
      final kinds = kind == null
          ? const ['person', 'character']
          : [otherKind(kind)];
      final marks = _marks(kinds.length);
      final vars = [
        Variable.withInt(media.id),
        for (final k in kinds) Variable.withString(k),
      ];
      final faces = await _db
          .customSelect(
            'SELECT id FROM faces WHERE media_id = ? AND kind IN ($marks)',
            variables: vars,
            readsFrom: {_db.faces},
          )
          .get();
      final bodies = await _db
          .customSelect(
            'SELECT id FROM bodies WHERE media_id = ? AND kind IN ($marks)',
            variables: vars,
            readsFrom: {_db.bodies},
          )
          .get();
      await _remove(
        [for (final r in faces) r.read<int>('id')],
        [for (final r in bodies) r.read<int>('id')],
        removed,
      );
      await _rescan([media.id]);
    });
    await removed.finish(_files, _index);
  }

  /// Faces (each with its body) and bodies become `toKind`. With `intoPersonId` they join that
  /// person or character once scanned again. Returns how many files are scanned again.
  Future<int> moveDetections({
    Iterable<int> faceIds = const [],
    Iterable<int> bodyIds = const [],
    required String toKind,
    int? intoPersonId,
  }) async {
    final removed = _Removed();
    final media = <int>{};
    await _db.transaction(() async {
      media.addAll(
        await _move(faceIds, bodyIds, toKind, intoPersonId, removed),
      );
    });
    await removed.finish(_files, _index);
    return media.length;
  }

  /// A person becomes a character (or a character a person): a new one of the other kind with
  /// the same name and flags takes everything it was seen as. Returns the new id (null: no such
  /// person) and how many files are scanned again.
  Future<({int? id, int files})> movePerson(int personId) async {
    final removed = _Removed();
    int? newId;
    var files = 0;
    await _db.transaction(() async {
      final person = await (_db.select(
        _db.persons,
      )..where((p) => p.id.equals(personId))).getSingleOrNull();
      if (person == null) return;
      final id = await _db
          .into(_db.persons)
          .insert(
            PersonsCompanion.insert(
              name: Value(person.name),
              kind: Value(otherKind(person.kind)),
              hidden: Value(person.hidden),
              favorite: Value(person.favorite),
              pinned: Value(person.pinned),
              createdAt: _clock().millisecondsSinceEpoch,
            ),
          );
      final faces =
          await (_db.selectOnly(_db.faces)
                ..addColumns([_db.faces.id])
                ..where(_db.faces.personId.equals(personId)))
              .map((r) => r.read(_db.faces.id)!)
              .get();
      final bodies =
          await (_db.selectOnly(_db.bodies)
                ..addColumns([_db.bodies.id])
                ..where(_db.bodies.personId.equals(personId)))
              .map((r) => r.read(_db.bodies.id)!)
              .get();
      files = (await _move(
        faces,
        bodies,
        otherKind(person.kind),
        id,
        removed,
      )).length;
      await (_db.delete(_db.persons)..where((p) => p.id.equals(personId))).go();
      newId = id;
    });
    await removed.finish(_files, _index);
    return (id: newId, files: files);
  }

  /// Removes detections (rows, their boxes and crops) without remembering a deletion or
  /// requeuing anything: for a re-detect that stores fresh ones right after.
  Future<void> removeDetections({
    Iterable<int> faceIds = const [],
    Iterable<int> bodyIds = const [],
  }) async {
    final removed = _Removed();
    await _db.transaction(() => _remove(faceIds, bodyIds, removed));
    await removed.finish(_files, _index);
  }

  // ---- inside a transaction ---------------------------------------------------------

  Future<Set<int>> _move(
    Iterable<int> faceIds,
    Iterable<int> bodyIds,
    String toKind,
    int? intoPersonId,
    _Removed removed,
  ) async {
    final faces = faceIds.toSet();
    final bodies = bodyIds.toSet();
    for (final chunk in _chunks(faces)) {
      // A face's body is the same figure: it moves with it.
      final linked = await _db
          .customSelect(
            'SELECT id FROM bodies WHERE face_id IN (${_marks(chunk.length)})',
            variables: [for (final i in chunk) Variable.withInt(i)],
            readsFrom: {_db.bodies},
          )
          .get();
      bodies.addAll(linked.map((r) => r.read<int>('id')));
    }
    final media = <int>{};
    final now = _clock().millisecondsSinceEpoch;
    for (final (part, ids) in [('f', faces), ('b', bodies)]) {
      for (final chunk in _chunks(ids)) {
        final rows = await _db
            .customSelect(
              '''SELECT d.media_id, m.asset_id, d.x, d.y, d.w, d.h, d.timestamp_ms, m.kind AS media_kind
                 FROM media_detections d JOIN media m ON m.id = d.media_id
                 WHERE d.kind = ? AND d.ref_id IN (${_marks(chunk.length)})''',
              variables: [
                Variable.withString(part),
                for (final i in chunk) Variable.withInt(i),
              ],
              readsFrom: {_db.mediaDetections, _db.media},
            )
            .get();
        for (final r in rows) {
          final asset = r.read<String>('asset_id');
          final box = (
            x: r.read<double>('x'),
            y: r.read<double>('y'),
            w: r.read<double>('w'),
            h: r.read<double>('h'),
          );
          final video = r.read<String>('media_kind') == 'video';
          final ts = video ? r.readNullable<int>('timestamp_ms') : null;
          await _replaceOverride(
            asset,
            part == 'f' ? 'face' : 'body',
            box,
            ts,
            toKind,
            intoPersonId,
            now,
          );
          media.add(r.read<int>('media_id'));
        }
      }
    }
    await _remove(faces, bodies, removed);
    await _rescan(media);
    return media;
  }

  Future<void> _replaceOverride(
    String asset,
    String part,
    _Box box,
    int? timestampMs,
    String kind,
    int? target,
    int now,
  ) async {
    final old = await (_db.select(
      _db.kindOverrides,
    )..where((o) => o.assetId.equals(asset) & o.part.equals(part))).get();
    for (final o in old) {
      final same =
          sameDetectionBox((x: o.x!, y: o.y!, w: o.w!, h: o.h!), box, part) &&
          (o.timestampMs == null) == (timestampMs == null) &&
          _nearInTime(o.timestampMs, timestampMs);
      if (same) {
        await (_db.delete(
          _db.kindOverrides,
        )..where((r) => r.id.equals(o.id))).go();
      }
    }
    await _db
        .into(_db.kindOverrides)
        .insert(
          KindOverridesCompanion.insert(
            assetId: asset,
            kind: kind,
            part: Value(part),
            x: Value(box.x),
            y: Value(box.y),
            w: Value(box.w),
            h: Value(box.h),
            timestampMs: Value(timestampMs),
            targetPersonId: Value(target),
            createdAt: now,
          ),
        );
  }

  /// Rows go without a suppression: the rescan is meant to find them again, as the other kind.
  Future<void> _remove(
    Iterable<int> faceIds,
    Iterable<int> bodyIds,
    _Removed removed,
  ) async {
    for (final chunk in _chunks(bodyIds)) {
      final marks = _marks(chunk.length);
      final ids = [for (final i in chunk) Variable.withInt(i)];
      final rows = await _db
          .customSelect(
            'SELECT crop_path FROM bodies WHERE id IN ($marks)',
            variables: ids,
            readsFrom: {_db.bodies},
          )
          .get();
      removed.crops.addAll(
        rows.map((r) => r.readNullable<String>('crop_path')),
      );
      await _db.customUpdate(
        "DELETE FROM media_detections WHERE kind = 'b' AND ref_id IN ($marks)",
        variables: ids,
        updates: {_db.mediaDetections},
      );
      await _db.customUpdate(
        'DELETE FROM bodies WHERE id IN ($marks)',
        variables: ids,
        updates: {_db.bodies},
      );
    }
    for (final chunk in _chunks(faceIds)) {
      final marks = _marks(chunk.length);
      final ids = [for (final i in chunk) Variable.withInt(i)];
      final rows = await _db
          .customSelect(
            'SELECT crop_path FROM faces WHERE id IN ($marks)',
            variables: ids,
            readsFrom: {_db.faces},
          )
          .get();
      removed.crops.addAll(
        rows.map((r) => r.readNullable<String>('crop_path')),
      );
      removed.faces.addAll(chunk);
      await _db.customUpdate(
        "DELETE FROM media_detections WHERE kind = 'f' AND ref_id IN ($marks)",
        variables: ids,
        updates: {_db.mediaDetections},
      );
      await _db.customUpdate(
        'UPDATE persons SET avatar_face_id = NULL WHERE avatar_face_id IN ($marks)',
        variables: ids,
        updates: {_db.persons},
      );
      await _db.customUpdate(
        'UPDATE bodies SET face_id = NULL WHERE face_id IN ($marks)',
        variables: ids,
        updates: {_db.bodies},
      );
      await _db.customUpdate(
        'DELETE FROM faces WHERE id IN ($marks)',
        variables: ids,
        updates: {_db.faces},
      );
    }
  }

  /// The file goes back to the scan queue from the start (videos too).
  Future<void> _rescan(Iterable<int> mediaIds) async {
    for (final chunk in _chunks(mediaIds)) {
      final ids = [for (final i in chunk) Variable.withInt(i)];
      await _db.customUpdate(
        '''UPDATE media SET scan_status = 'pending', scan_version = 0, last_scanned_frame = 0,
             scan_attempts = 0, scan_error = NULL WHERE id IN (${_marks(chunk.length)})''',
        variables: ids,
        updates: {_db.media},
      );
      await (_db.delete(_db.settings)..where(
            (s) => s.key.isIn([
              for (final id in chunk) ...['video.job.$id', 'video.local.$id'],
            ]),
          ))
          .go();
    }
  }

  Future<MediaRow?> _media(int id) =>
      (_db.select(_db.media)..where((m) => m.id.equals(id))).getSingleOrNull();
}

class _Removed {
  final crops = <String?>[];
  final faces = <int>[];

  Future<void> finish(FileStore files, EmbeddingIndex? index) async {
    await files.deleteAll(crops);
    if (faces.isNotEmpty) await index?.remove(faces);
  }
}
