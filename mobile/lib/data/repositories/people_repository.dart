import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../files/file_store.dart';
import '../index/embedding_index.dart';
import 'face_suppression_store.dart';

class PersonSummary {
  const PersonSummary({
    required this.id,
    required this.name,
    required this.faceCount,
    required this.avatarCropPath,
    required this.createdAt,
  });

  final int id;
  final String? name; // null = never named; the UI shows "Person <id>"
  final int faceCount;
  final String? avatarCropPath;
  final DateTime createdAt;

  bool get isNamed => (name ?? '').trim().isNotEmpty;
}

class FaceItem {
  const FaceItem({
    required this.id,
    required this.personId,
    required this.mediaId,
    required this.quality,
    required this.cropPath,
    required this.facePx,
    required this.dismissed,
  });

  final int id;
  final int? personId;
  final int? mediaId;
  final double quality;
  final String? cropPath;
  final double facePx;
  final bool dismissed;
}

class BodyItem {
  const BodyItem({
    required this.id,
    required this.mediaId,
    required this.faceId,
    required this.personId,
    required this.cropPath,
    required this.extent,
    required this.linkMethod,
    required this.linkConfidence,
    required this.score,
  });

  final int id;
  final int? mediaId;
  final int? faceId;
  final int?
  personId; // through its face, else the link made by hand / by outfit
  final String? cropPath;
  final String? extent; // full | knee | upper | head
  final String? linkMethod; // manual | appearance | weak_face
  final double? linkConfidence;
  final double score;
}

Iterable<List<int>> _chunks(Iterable<int> ids, [int size = 400]) sync* {
  final list = ids.toSet().toList();
  for (var i = 0; i < list.length; i += size) {
    yield list.sublist(i, i + size > list.length ? list.length : i + size);
  }
}

String _marks(int n) => List.filled(n, '?').join(',');

/// People, their faces and bodies, and every manual correction. All writes are transactions and
/// keep the "auto-grouping never redoes a correction" memory (face_rejections, person_distinct).
class PeopleRepository {
  PeopleRepository(
    this._db,
    this._files, {
    this._index,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final FileStore _files;
  final EmbeddingIndex? _index;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  // ---- reading --------------------------------------------------------------------

  static const _personSql = '''
    SELECT p.id, p.name, p.created_at,
      (SELECT COUNT(*) FROM faces f WHERE f.person_id = p.id) AS face_count,
      COALESCE(
        (SELECT crop_path FROM faces WHERE id = p.avatar_face_id AND person_id = p.id),
        (SELECT crop_path FROM faces WHERE person_id = p.id AND crop_path IS NOT NULL
           ORDER BY quality_score DESC LIMIT 1)
      ) AS avatar_crop
    FROM persons p
  ''';

  PersonSummary _person(QueryRow r) => PersonSummary(
    id: r.read<int>('id'),
    name: r.readNullable<String>('name'),
    faceCount: r.read<int>('face_count'),
    avatarCropPath: r.readNullable<String>('avatar_crop'),
    createdAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('created_at')),
  );

  Stream<List<PersonSummary>> watchPeople() => _db
      .customSelect(
        '$_personSql ORDER BY face_count DESC, p.id',
        readsFrom: {_db.persons, _db.faces},
      )
      .watch()
      .map((rows) => rows.map(_person).toList());

  Future<List<PersonSummary>> people() async =>
      (await _db
              .customSelect(
                '$_personSql ORDER BY face_count DESC, p.id',
                readsFrom: {_db.persons, _db.faces},
              )
              .get())
          .map(_person)
          .toList();

  Stream<PersonSummary?> watchPerson(int id) => _db
      .customSelect(
        '$_personSql WHERE p.id = ?',
        variables: [Variable.withInt(id)],
        readsFrom: {_db.persons, _db.faces},
      )
      .watch()
      .map((rows) => rows.isEmpty ? null : _person(rows.first));

  Future<PersonSummary?> person(int id) async {
    final rows = await _db
        .customSelect(
          '$_personSql WHERE p.id = ?',
          variables: [Variable.withInt(id)],
          readsFrom: {_db.persons, _db.faces},
        )
        .get();
    return rows.isEmpty ? null : _person(rows.first);
  }

  FaceItem _face(QueryRow r) => FaceItem(
    id: r.read<int>('id'),
    personId: r.readNullable<int>('person_id'),
    mediaId: r.readNullable<int>('media_id'),
    quality: r.read<double>('quality_score'),
    cropPath: r.readNullable<String>('crop_path'),
    facePx: r.read<double>('face_px'),
    dismissed: r.read<bool>('review_dismissed'),
  );

  static const _faceCols =
      'id, person_id, media_id, quality_score, crop_path, face_px, review_dismissed';

  /// A person's faces, best quality first. `personId == null` lists the unsorted faces.
  Stream<List<FaceItem>> watchFaces(int? personId) => _db
      .customSelect(
        personId == null
            ? 'SELECT $_faceCols FROM faces WHERE person_id IS NULL ORDER BY quality_score DESC, id'
            : 'SELECT $_faceCols FROM faces WHERE person_id = ? ORDER BY quality_score DESC, id',
        variables: [if (personId != null) Variable.withInt(personId)],
        readsFrom: {_db.faces},
      )
      .watch()
      .map((rows) => rows.map(_face).toList());

  Future<List<FaceItem>> facesByIds(Iterable<int> ids) async {
    final out = <FaceItem>[];
    for (final chunk in _chunks(ids)) {
      final rows = await _db
          .customSelect(
            'SELECT $_faceCols FROM faces WHERE id IN (${_marks(chunk.length)})',
            variables: [for (final i in chunk) Variable.withInt(i)],
            readsFrom: {_db.faces},
          )
          .get();
      out.addAll(rows.map(_face));
    }
    return out;
  }

  Stream<int> watchUnsortedCount() => _db
      .customSelect(
        'SELECT COUNT(*) AS n FROM faces WHERE person_id IS NULL',
        readsFrom: {_db.faces},
      )
      .watchSingle()
      .map((r) => r.read<int>('n'));

  Stream<List<BodyItem>> watchBodies(int personId) => _db
      .customSelect(
        '''
        SELECT b.id, b.media_id, b.face_id, b.crop_path, b.extent, b.link_method, b.link_confidence,
               b.score, COALESCE(bf.person_id, b.person_id) AS person_id
        FROM bodies b LEFT JOIN faces bf ON bf.id = b.face_id
        WHERE bf.person_id = ?1 OR (bf.person_id IS NULL AND b.person_id = ?1)
        ORDER BY b.score DESC, b.id LIMIT 600
        ''',
        variables: [Variable.withInt(personId)],
        readsFrom: {_db.bodies, _db.faces},
      )
      .watch()
      .map((rows) => rows.map(_body).toList());

  Future<BodyItem?> body(int id) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT b.id, b.media_id, b.face_id, b.crop_path, b.extent, b.link_method, b.link_confidence,
                 b.score, COALESCE(bf.person_id, b.person_id) AS person_id
          FROM bodies b LEFT JOIN faces bf ON bf.id = b.face_id WHERE b.id = ?
          ''',
          variables: [Variable.withInt(id)],
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();
    return rows.isEmpty ? null : _body(rows.first);
  }

  BodyItem _body(QueryRow r) => BodyItem(
    id: r.read<int>('id'),
    mediaId: r.readNullable<int>('media_id'),
    faceId: r.readNullable<int>('face_id'),
    personId: r.readNullable<int>('person_id'),
    cropPath: r.readNullable<String>('crop_path'),
    extent: r.readNullable<String>('extent'),
    linkMethod: r.readNullable<String>('link_method'),
    linkConfidence: r.readNullable<double>('link_confidence'),
    score: r.read<double>('score'),
  );

  // ---- people ---------------------------------------------------------------------

  /// A new person, optionally from faces (the best quality one becomes the cover).
  Future<int> createPerson({String? name, Iterable<int> faceIds = const []}) =>
      _db.transaction(() async {
        final trimmed = name?.trim();
        final id = await _db
            .into(_db.persons)
            .insert(
              PersonsCompanion.insert(
                name: Value(
                  trimmed == null || trimmed.isEmpty ? null : trimmed,
                ),
                createdAt: _now,
              ),
            );
        if (faceIds.isNotEmpty) {
          await _assign(faceIds, id);
          await _setBestAvatar(id, faceIds);
        }
        return id;
      });

  Future<void> renamePerson(int id, String? name) {
    final trimmed = name?.trim();
    return (_db.update(_db.persons)..where((p) => p.id.equals(id))).write(
      PersonsCompanion(
        name: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
      ),
    );
  }

  Future<void> setAvatar(int personId, int faceId) async {
    final face = await (_db.select(
      _db.faces,
    )..where((f) => f.id.equals(faceId))).getSingleOrNull();
    if (face == null || face.personId != personId) return;
    await (_db.update(_db.persons)..where((p) => p.id.equals(personId))).write(
      PersonsCompanion(avatarFaceId: Value(faceId)),
    );
  }

  Future<void> _setBestAvatar(
    int personId,
    Iterable<int> candidateFaceIds,
  ) async {
    FaceItem? best;
    for (final f in await facesByIds(candidateFaceIds)) {
      if (f.personId == personId &&
          (best == null || f.quality > best.quality)) {
        best = f;
      }
    }
    if (best != null) {
      await (_db.update(_db.persons)..where((p) => p.id.equals(personId)))
          .write(PersonsCompanion(avatarFaceId: Value(best.id)));
    }
  }

  /// Faces and bodies come loose, then the person goes.
  Future<void> deletePerson(int id) => _db.transaction(() async {
    await _db.customUpdate(
      'UPDATE faces SET review_dismissed = 1 WHERE person_id = ?',
      variables: [Variable.withInt(id)],
      updates: {_db.faces},
    );
    await _db.customUpdate(
      'UPDATE bodies SET link_method = NULL, link_confidence = NULL WHERE person_id = ?',
      variables: [Variable.withInt(id)],
      updates: {_db.bodies},
    );
    await (_db.delete(_db.persons)..where((p) => p.id.equals(id))).go();
  });

  // ---- faces ----------------------------------------------------------------------

  Future<void> _assign(Iterable<int> faceIds, int personId) async {
    for (final chunk in _chunks(faceIds)) {
      final marks = _marks(chunk.length);
      final ids = [for (final i in chunk) Variable.withInt(i)];
      await _db.customUpdate(
        'UPDATE faces SET person_id = ?, review_dismissed = 0 WHERE id IN ($marks)',
        variables: [Variable.withInt(personId), ...ids],
        updates: {_db.faces},
      );
      await _db.customUpdate(
        'DELETE FROM face_rejections WHERE person_id = ? AND face_id IN ($marks)',
        variables: [Variable.withInt(personId), ...ids],
        updates: {_db.faceRejections},
      );
      await _db.customUpdate(
        'DELETE FROM review_matches WHERE face_id IN ($marks)',
        variables: ids,
        updates: {_db.reviewMatches},
      );
    }
  }

  /// Assign (or move) faces to a person. A rejection of that very pair is forgotten.
  Future<void> assignFaces(Iterable<int> faceIds, int personId) =>
      _db.transaction(() => _assign(faceIds, personId));

  /// "This is not that person": the face leaves the person and auto-grouping never puts it back.
  /// `fromPersonId` null = whoever it is assigned to now.
  Future<void> rejectFaces(Iterable<int> faceIds, {int? fromPersonId}) =>
      _db.transaction(() async {
        for (final face in await facesByIds(faceIds)) {
          final pid = fromPersonId ?? face.personId;
          if (pid == null) continue;
          await _db
              .into(_db.faceRejections)
              .insert(
                FaceRejectionsCompanion.insert(faceId: face.id, personId: pid),
                mode: InsertMode.insertOrIgnore,
              );
          if (face.personId == pid) {
            await (_db.update(_db.faces)..where((f) => f.id.equals(face.id)))
                .write(const FacesCompanion(personId: Value(null)));
          }
          await _db.customUpdate(
            'DELETE FROM review_matches WHERE face_id = ? AND person_id = ?',
            variables: [Variable.withInt(face.id), Variable.withInt(pid)],
            updates: {_db.reviewMatches},
          );
        }
      });

  /// Removes faces/crops and remembers their occurrences so rescanning cannot recreate them.
  Future<void> deleteFaces(Iterable<int> faceIds) async {
    final crops = <String?>[];
    await _db.transaction(() async {
      for (final chunk in _chunks(faceIds)) {
        final marks = _marks(chunk.length);
        final ids = [for (final i in chunk) Variable.withInt(i)];
        await FaceSuppressionStore(_db).remember(chunk);
        final rows = await _db
            .customSelect(
              'SELECT crop_path FROM faces WHERE id IN ($marks)',
              variables: ids,
              readsFrom: {_db.faces},
            )
            .get();
        crops.addAll(rows.map((r) => r.readNullable<String>('crop_path')));
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
          'DELETE FROM faces WHERE id IN ($marks)',
          variables: ids,
          updates: {_db.faces},
        );
      }
    });
    await _files.deleteAll(crops);
    await _index?.remove(faceIds);
  }

  /// Hides faces from automatic grouping and review until manually assigned.
  Future<void> dismissFaces(Iterable<int> faceIds) async {
    await _db.transaction(() async {
      for (final chunk in _chunks(faceIds)) {
        await _db.customUpdate(
          'UPDATE faces SET review_dismissed = 1 WHERE id IN (${_marks(chunk.length)})',
          variables: [for (final i in chunk) Variable.withInt(i)],
          updates: {_db.faces},
        );
        await _db.customUpdate(
          'DELETE FROM review_matches WHERE face_id IN (${_marks(chunk.length)})',
          variables: [for (final id in chunk) Variable.withInt(id)],
          updates: {_db.reviewMatches},
        );
      }
    });
  }

  // ---- people vs people -----------------------------------------------------------

  (int, int) _ordered(int a, int b) => a < b ? (a, b) : (b, a);

  Future<void> markDistinct(int a, int b) async {
    if (a == b) return;
    final (x, y) = _ordered(a, b);
    await _db
        .into(_db.personDistinct)
        .insert(
          PersonDistinctCompanion.insert(personA: x, personB: y),
          mode: InsertMode.insertOrIgnore,
        );
    await _db.customUpdate(
      'DELETE FROM review_duplicates WHERE (person_a = ?1 AND person_b = ?2) OR (person_a = ?2 AND person_b = ?1)',
      variables: [Variable.withInt(x), Variable.withInt(y)],
      updates: {_db.reviewDuplicates},
    );
  }

  Future<bool> areDistinct(int a, int b) async {
    final (x, y) = _ordered(a, b);
    final row =
        await (_db.select(_db.personDistinct)
              ..where((d) => d.personA.equals(x) & d.personB.equals(y)))
            .getSingleOrNull();
    return row != null;
  }

  /// Everything of `sourceId` moves to `targetId`, then `sourceId` is deleted (the PC's
  /// database.merge_persons). Corrections made against the source ("not this person",
  /// "different from ...") now hold for the target.
  Future<void> mergePeople({
    required int sourceId,
    required int targetId,
  }) async {
    if (sourceId == targetId) return;
    await _db.transaction(() async {
      final source = await (_db.select(
        _db.persons,
      )..where((p) => p.id.equals(sourceId))).getSingleOrNull();
      final target = await (_db.select(
        _db.persons,
      )..where((p) => p.id.equals(targetId))).getSingleOrNull();
      if (source == null || target == null) return;
      final s = Variable.withInt(sourceId);
      final t = Variable.withInt(targetId);

      await _db.customUpdate(
        'UPDATE faces SET person_id = ? WHERE person_id = ?',
        variables: [t, s],
        updates: {_db.faces},
      );
      await (_db.update(_db.identitySets)
            ..where((set) => set.personId.equals(sourceId)))
          .write(IdentitySetsCompanion(personId: Value(targetId)));
      await _db.customUpdate(
        'INSERT OR IGNORE INTO face_rejections (face_id, person_id) SELECT face_id, ? FROM face_rejections WHERE person_id = ?',
        variables: [t, s],
        updates: {_db.faceRejections},
      );
      await _db.customUpdate(
        'UPDATE bodies SET person_id = ? WHERE person_id = ?',
        variables: [t, s],
        updates: {_db.bodies},
      );
      await _db.customUpdate(
        'INSERT OR IGNORE INTO body_rejections (body_id, person_id) SELECT body_id, ? FROM body_rejections WHERE person_id = ?',
        variables: [t, s],
        updates: {_db.bodyRejections},
      );
      // a face that was rejected from the target must not stay rejected from the person it now is
      await _db.customUpdate(
        'DELETE FROM face_rejections WHERE person_id = ? AND face_id IN (SELECT id FROM faces WHERE person_id = ?)',
        variables: [t, t],
        updates: {_db.faceRejections},
      );

      final partners = <int>{};
      for (final r
          in await _db
              .customSelect(
                'SELECT person_a, person_b FROM person_distinct WHERE person_a = ?1 OR person_b = ?1',
                variables: [s],
                readsFrom: {_db.personDistinct},
              )
              .get()) {
        partners
          ..add(r.read<int>('person_a'))
          ..add(r.read<int>('person_b'));
      }
      partners
        ..remove(sourceId)
        ..remove(targetId);
      for (final other in partners) {
        final (x, y) = _ordered(other, targetId);
        await _db
            .into(_db.personDistinct)
            .insert(
              PersonDistinctCompanion.insert(personA: x, personB: y),
              mode: InsertMode.insertOrIgnore,
            );
      }

      await _db.customUpdate(
        'UPDATE review_matches SET person_id = ? WHERE person_id = ?',
        variables: [t, s],
        updates: {_db.reviewMatches},
      );
      await _db.customUpdate(
        '''DELETE FROM review_matches WHERE
        face_id IN (SELECT id FROM faces WHERE person_id IS NOT NULL)
        OR EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = review_matches.face_id AND r.person_id = review_matches.person_id)
      ''',
        updates: {_db.reviewMatches},
      );
      await _db.customUpdate(
        '''DELETE FROM review_duplicates WHERE EXISTS (
        SELECT 1 FROM person_distinct d WHERE d.person_a = review_duplicates.person_a AND d.person_b = review_duplicates.person_b)
      ''',
        updates: {_db.reviewDuplicates},
      );
      await _db.customUpdate(
        'DELETE FROM body_rejections WHERE person_id = ? AND body_id IN (SELECT id FROM bodies WHERE person_id = ?)',
        variables: [t, t],
        updates: {_db.bodyRejections},
      );

      final updates = PersonsCompanion(
        name:
            (target.name ?? '').trim().isEmpty &&
                (source.name ?? '').trim().isNotEmpty
            ? Value(source.name)
            : const Value.absent(),
        avatarFaceId: target.avatarFaceId == null && source.avatarFaceId != null
            ? Value(source.avatarFaceId)
            : const Value.absent(),
      );
      await (_db.update(
        _db.persons,
      )..where((p) => p.id.equals(targetId))).write(updates);
      await (_db.delete(_db.persons)..where((p) => p.id.equals(sourceId))).go();
    });
  }

  // ---- bodies ---------------------------------------------------------------------

  /// "This body is that person" (made by hand, so regrouping never undoes it).
  Future<void> linkBody(int bodyId, int personId) => _db.transaction(() async {
    await (_db.update(_db.bodies)..where((b) => b.id.equals(bodyId))).write(
      BodiesCompanion(
        personId: Value(personId),
        linkMethod: const Value('manual'),
        linkConfidence: const Value(null),
      ),
    );
    await (_db.delete(
      _db.reviewBodyLinks,
    )..where((l) => l.bodyId.equals(bodyId))).go();
    await _db.customUpdate(
      'DELETE FROM body_rejections WHERE body_id = ? AND person_id = ?',
      variables: [Variable.withInt(bodyId), Variable.withInt(personId)],
      updates: {_db.bodyRejections},
    );
  });

  /// "This body is not that person": remembered, so outfit matching does not suggest it again.
  Future<void> rejectBody(int bodyId, {int? personId}) => _db.transaction(
    () async {
      final body = await this.body(bodyId);
      if (body == null) return;
      final pid = personId ?? body.personId;
      if (pid == null) return;
      await _db
          .into(_db.bodyRejections)
          .insert(
            BodyRejectionsCompanion.insert(bodyId: bodyId, personId: pid),
            mode: InsertMode.insertOrIgnore,
          );
      final row = await (_db.select(
        _db.bodies,
      )..where((b) => b.id.equals(bodyId))).getSingle();
      if (row.personId == pid) {
        await (_db.update(_db.bodies)..where((b) => b.id.equals(bodyId))).write(
          const BodiesCompanion(
            personId: Value(null),
            linkMethod: Value(null),
            linkConfidence: Value(null),
          ),
        );
      }
      if (row.faceId != null) {
        final face = await (_db.select(
          _db.faces,
        )..where((f) => f.id.equals(row.faceId!))).getSingleOrNull();
        if (face?.personId == pid) {
          // the face stays, it just is not this body's face
          await (_db.update(_db.bodies)..where((b) => b.id.equals(bodyId)))
              .write(const BodiesCompanion(faceId: Value(null)));
        }
      }
      await (_db.delete(
        _db.reviewBodyLinks,
      )..where((l) => l.bodyId.equals(bodyId))).go();
    },
  );

  /// The crop of a person's cover, resolved to a file.
  Future<String?> avatarOf(int personId) async =>
      (await person(personId))?.avatarCropPath;

  /// Faces' ids of a review group stored as JSON.
  static List<int> decodeFaceIds(String json) => [
    for (final v in jsonDecode(json) as List) v as int,
  ];
}
