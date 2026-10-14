import 'package:drift/drift.dart';

import '../db/app_database.dart';

enum ScanFilter { all, scanned, unscanned, failed }

/// What the Library grid shows. `personId` = only photos that person is in; `hasFaces` null = any.
class MediaFilter {
  const MediaFilter({
    this.personId,
    this.scan = ScanFilter.all,
    this.hasFaces,
    this.kind,
  });

  final int? personId;
  final ScanFilter scan;
  final bool? hasFaces;
  final String? kind;

  bool get isDefault =>
      personId == null &&
      scan == ScanFilter.all &&
      hasFaces == null &&
      kind == null;

  MediaFilter copyWith({
    int? personId,
    bool clearPerson = false,
    ScanFilter? scan,
    bool? hasFaces,
    bool clearHasFaces = false,
    String? kind,
    bool clearKind = false,
  }) => MediaFilter(
    personId: clearPerson ? null : (personId ?? this.personId),
    scan: scan ?? this.scan,
    hasFaces: clearHasFaces ? null : (hasFaces ?? this.hasFaces),
    kind: clearKind ? null : (kind ?? this.kind),
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFilter &&
      other.personId == personId &&
      other.scan == scan &&
      other.hasFaces == hasFaces &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(personId, scan, hasFaces, kind);
}

class MediaListItem {
  const MediaListItem({
    required this.id,
    required this.assetId,
    required this.width,
    required this.height,
    required this.takenAt,
    required this.scanStatus,
    required this.faceCount,
    this.kind = 'photo',
    this.durationMs,
  });

  final int id;
  final String assetId;
  final int width;
  final int height;
  final DateTime? takenAt;
  final String scanStatus;
  final int faceCount;
  final String kind;
  final int? durationMs;
}

/// One face or body box inside a photo (normalised 0..1), with whoever it belongs to.
class MediaDetection {
  const MediaDetection({
    required this.id,
    required this.kind,
    required this.refId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.personId,
    required this.cropPath,
    this.linkMethod,
    this.frameNumber,
    this.timestampMs,
  });

  final int id;
  final String kind; // f | b
  final int refId; // faces.id / bodies.id
  final double x, y, w, h;
  final int? personId;
  final String? cropPath;
  final String? linkMethod; // bodies only
  final int? frameNumber;
  final int? timestampMs;

  bool get isFace => kind == 'f';
}

class MediaQueries {
  MediaQueries(this._db);

  final AppDatabase _db;

  static const _hasFace =
      "EXISTS (SELECT 1 FROM media_detections d WHERE d.media_id = m.id AND d.kind = 'f')";

  (String, List<Variable>) _where(MediaFilter f) {
    final clauses = <String>["m.kind IN ('photo', 'video')"];
    final vars = <Variable>[];
    if (f.kind != null) {
      clauses.add('m.kind = ?');
      vars.add(Variable.withString(f.kind!));
    }
    switch (f.scan) {
      case ScanFilter.all:
        break;
      case ScanFilter.scanned:
        clauses.add("m.scan_status = 'done'");
      case ScanFilter.unscanned:
        clauses.add("m.scan_status IN ('pending', 'scanning', 'skipped')");
      case ScanFilter.failed:
        clauses.add("m.scan_status = 'failed'");
    }
    if (f.hasFaces == true) clauses.add(_hasFace);
    if (f.hasFaces == false) {
      clauses.add("m.scan_status = 'done' AND NOT $_hasFace");
    }
    if (f.personId != null) {
      clauses.add(
        "EXISTS (SELECT 1 FROM media_detections d LEFT JOIN faces fa ON d.kind = 'f' AND fa.id = d.ref_id "
        "LEFT JOIN bodies b ON d.kind = 'b' AND b.id = d.ref_id "
        'LEFT JOIN faces bf ON bf.id = b.face_id WHERE d.media_id = m.id AND '
        'COALESCE(fa.person_id, bf.person_id, b.person_id) = ?)',
      );
      vars.add(Variable.withInt(f.personId!));
    }
    return (clauses.join(' AND '), vars);
  }

  /// Fires whenever something the grid shows may have changed.
  Stream<void> changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.media,
          _db.faces,
          _db.bodies,
          _db.mediaDetections,
        ]),
      )
      .map((_) {});

  Future<int> count(MediaFilter filter) async {
    final (where, vars) = _where(filter);
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM media m WHERE $where',
          variables: vars,
          readsFrom: {_db.media, _db.faces, _db.bodies, _db.mediaDetections},
        )
        .getSingle();
    return row.read<int>('n');
  }

  Future<List<MediaListItem>> page(
    MediaFilter filter, {
    required int offset,
    required int limit,
  }) async {
    final (where, vars) = _where(filter);
    final rows = await _db
        .customSelect(
          '''
          SELECT m.id, m.asset_id, m.kind, m.duration_ms, m.width, m.height, m.taken_at, m.modified_at, m.scan_status,
            (SELECT COUNT(*) FROM media_detections d WHERE d.media_id = m.id AND d.kind = 'f') AS face_count
          FROM media m WHERE $where
          ORDER BY COALESCE(m.taken_at, m.modified_at) DESC, m.id DESC
          LIMIT ? OFFSET ?
          ''',
          variables: [
            ...vars,
            Variable.withInt(limit),
            Variable.withInt(offset),
          ],
          readsFrom: {_db.media, _db.faces, _db.bodies, _db.mediaDetections},
        )
        .get();
    return [
      for (final r in rows)
        MediaListItem(
          id: r.read<int>('id'),
          kind: r.read<String>('kind'),
          durationMs: r.readNullable<int>('duration_ms'),
          assetId: r.read<String>('asset_id'),
          width: r.readNullable<int>('width') ?? 0,
          height: r.readNullable<int>('height') ?? 0,
          takenAt: _date(
            r.readNullable<int>('taken_at') ??
                r.readNullable<int>('modified_at'),
          ),
          scanStatus: r.read<String>('scan_status'),
          faceCount: r.read<int>('face_count'),
        ),
    ];
  }

  static DateTime? _date(int? ms) =>
      ms == null || ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  /// Every box in one photo, with the person each belongs to.
  Stream<List<MediaDetection>> watchDetections(int mediaId) => _db
      .customSelect(
        '''
        SELECT d.id, d.kind, d.ref_id, d.x, d.y, d.w, d.h, d.frame_number, d.timestamp_ms,
          CASE WHEN d.kind = 'f' THEN f.person_id
               ELSE COALESCE((SELECT person_id FROM faces WHERE id = b.face_id), b.person_id) END AS person_id,
          CASE WHEN d.kind = 'f' THEN f.crop_path ELSE b.crop_path END AS crop_path,
          b.link_method AS link_method
        FROM media_detections d
        LEFT JOIN faces f ON d.kind = 'f' AND f.id = d.ref_id
        LEFT JOIN bodies b ON d.kind = 'b' AND b.id = d.ref_id
        WHERE d.media_id = ?
        ORDER BY d.kind DESC, d.x
        ''',
        variables: [Variable.withInt(mediaId)],
        readsFrom: {_db.mediaDetections, _db.faces, _db.bodies},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            MediaDetection(
              id: r.read<int>('id'),
              frameNumber: r.readNullable<int>('frame_number'),
              timestampMs: r.readNullable<int>('timestamp_ms'),
              kind: r.read<String>('kind'),
              refId: r.read<int>('ref_id'),
              x: r.read<double>('x'),
              y: r.read<double>('y'),
              w: r.read<double>('w'),
              h: r.read<double>('h'),
              personId: r.readNullable<int>('person_id'),
              cropPath: r.readNullable<String>('crop_path'),
              linkMethod: r.readNullable<String>('link_method'),
            ),
        ],
      );
}
