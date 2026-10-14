import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/api/dtos/grouping.dart';
import '../../data/db/app_database.dart';
import 'grouping_config.dart';

/// One face as the grouping maths sees it.
class FaceVector {
  const FaceVector(this.embedding, this.quality);

  final Float32List embedding;
  final double quality;
}

Float32List _normalized(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final out = Float32List(v.length);
  if (sum <= 0) return out;
  final inv = 1.0 / math.sqrt(sum);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] * inv;
  }
  return out;
}

/// `person_linking.build_person_models` for one person: `proto` is the unit-length mean of ALL the
/// faces weighted by clip(quality, 0.05, 1)^2, `members` the best-quality faces (unit vectors,
/// at most [cap]) and `count` how many faces the person has.
GroupingModel buildPersonModel(
  int personId,
  List<FaceVector> faces, {
  int cap = groupingMemberCap,
}) {
  assert(faces.isNotEmpty);
  final unit = [for (final f in faces) _normalized(f.embedding)];
  final q = [for (final f in faces) f.quality.clamp(0.05, 1.0).toDouble()];
  final sum = Float64List(embeddingDim);
  for (var i = 0; i < unit.length; i++) {
    final w = q[i] * q[i];
    final e = unit[i];
    for (var d = 0; d < embeddingDim; d++) {
      sum[d] += e[d] * w;
    }
  }
  final proto = _normalized(Float32List.fromList(sum));
  final order = List<int>.generate(faces.length, (i) => i)
    ..sort((a, b) {
      final byQuality = q[b].compareTo(q[a]);
      return byQuality != 0 ? byQuality : a.compareTo(b); // best first, stable
    });
  return GroupingModel(
    pid: personId,
    proto: proto,
    members: [for (final i in order.take(cap)) unit[i]],
    count: faces.length,
  );
}

/// "Same photo / frame" key: faces sharing it cannot be one person (person_linking's one-person-
/// per-frame rule). Null = no constraint.
String? frameKeyOf(int? mediaId, int? frameNumber) =>
    mediaId == null ? null : '$mediaId:${frameNumber ?? ''}';

const _derivedLinks = ['appearance', 'weak_face'];

/// Reads the library out of the database in the shapes the PC's grouping function takes.
class GroupingInputs {
  GroupingInputs(this._db);

  final AppDatabase _db;

  Future<List<GroupingModel>> models({int cap = groupingMemberCap}) async {
    final people = await _db
        .customSelect(
          'SELECT DISTINCT person_id FROM faces WHERE person_id IS NOT NULL ORDER BY person_id',
          readsFrom: {_db.faces},
        )
        .get();
    final out = <GroupingModel>[];
    for (final p in people) {
      final pid = p.read<int>('person_id');
      final rows = await _db
          .customSelect(
            'SELECT quality_score, embedding FROM faces WHERE person_id = ?',
            variables: [Variable.withInt(pid)],
            readsFrom: {_db.faces},
          )
          .get();
      if (rows.isEmpty) continue;
      out.add(
        buildPersonModel(pid, [
          for (final r in rows)
            FaceVector(
              embeddingFromBlob(r.read<Uint8List>('embedding')),
              r.read<double>('quality_score'),
            ),
        ], cap: cap),
      );
    }
    return out;
  }

  /// Faces that belong to nobody, with the people they were told they are NOT.
  Future<List<GroupingFace>> pending() async {
    final rejected = <int, List<int>>{};
    for (final r
        in await _db
            .customSelect(
              'SELECT fr.face_id, fr.person_id FROM face_rejections fr JOIN faces f ON f.id = fr.face_id WHERE f.person_id IS NULL',
              readsFrom: {_db.faceRejections, _db.faces},
            )
            .get()) {
      rejected
          .putIfAbsent(r.read<int>('face_id'), () => [])
          .add(r.read<int>('person_id'));
    }
    final rows = await _db
        .customSelect(
          'SELECT id, embedding, quality_score, media_id, frame_number FROM faces WHERE person_id IS NULL ORDER BY id',
          readsFrom: {_db.faces},
        )
        .get();
    return [
      for (final r in rows)
        GroupingFace(
          id: r.read<int>('id'),
          embedding: embeddingFromBlob(r.read<Uint8List>('embedding')),
          quality: r.read<double>('quality_score'),
          frameKey: frameKeyOf(
            r.readNullable<int>('media_id'),
            r.readNullable<int>('frame_number'),
          ),
          rejectedPersonIds: rejected[r.read<int>('id')] ?? const [],
        ),
    ];
  }

  Future<List<int>> dismissedFaceIds() async => [
    for (final r
        in await _db
            .customSelect(
              'SELECT id FROM faces WHERE person_id IS NULL AND review_dismissed = 1 ORDER BY id',
              readsFrom: {_db.faces},
            )
            .get())
      r.read<int>('id'),
  ];

  Future<List<(int, int)>> distinctPairs() async => [
    for (final r
        in await _db
            .customSelect(
              'SELECT person_a, person_b FROM person_distinct ORDER BY person_a, person_b',
              readsFrom: {_db.personDistinct},
            )
            .get())
      (r.read<int>('person_a'), r.read<int>('person_b')),
  ];

  /// Bodies the PC needs to link faceless ones by outfit / weak face. Only photos that hold at
  /// least one faceless body with something to go on are sent (an identified body matters only as
  /// an anchor for faceless bodies of its own photo), which keeps the payload small.
  ///
  /// `dropDerived`: round 2 re-derives the outfit / weak-face links, so those are not anchors; the
  /// review round sends every current link, exactly like the PC's review_state.
  Future<List<GroupingBody>> bodies({required bool dropDerived}) async {
    final rejected = <int, List<int>>{};
    for (final r
        in await _db
            .customSelect(
              'SELECT body_id, person_id FROM body_rejections',
              readsFrom: {_db.bodyRejections},
            )
            .get()) {
      rejected
          .putIfAbsent(r.read<int>('body_id'), () => [])
          .add(r.read<int>('person_id'));
    }
    final rows = await _db
        .customSelect(
          '''
          SELECT b.id, b.media_id, b.frame_number, b.appearance, b.weak_face_embedding, b.person_id,
                 b.link_method, bf.person_id AS face_person_id
          FROM bodies b LEFT JOIN faces bf ON bf.id = b.face_id
          ORDER BY b.id
          ''',
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();

    final all = <GroupingBody>[];
    final looseWithEvidenceMedia = <int?>{};
    for (final r in rows) {
      final facePerson = r.readNullable<int>('face_person_id');
      var anchor = facePerson ?? r.readNullable<int>('person_id');
      if (facePerson == null &&
          dropDerived &&
          _derivedLinks.contains(r.readNullable<String>('link_method'))) {
        anchor = null;
      }
      final appearance = r.readNullable<Uint8List>('appearance');
      final weak = r.readNullable<Uint8List>('weak_face_embedding');
      final body = GroupingBody(
        id: r.read<int>('id'),
        mediaId: r.readNullable<int>('media_id'),
        frameNumber: r.readNullable<int>('frame_number'),
        anchorPersonId: anchor,
        appearance: appearance == null ? null : _floats(appearance),
        weakFaceEmbedding: weak == null ? null : embeddingFromBlob(weak),
        rejectedPersonIds: rejected[r.read<int>('id')] ?? const [],
      );
      all.add(body);
      if (anchor == null &&
          (body.appearance != null || body.weakFaceEmbedding != null)) {
        looseWithEvidenceMedia.add(body.mediaId);
      }
    }
    return [
      for (final b in all)
        if (looseWithEvidenceMedia.contains(b.mediaId) &&
            (b.anchorPersonId != null ||
                b.appearance != null ||
                b.weakFaceEmbedding != null))
          b,
    ];
  }

  static List<double> _floats(Uint8List blob) {
    final view = ByteData.sublistView(blob);
    return [
      for (var i = 0; i + 4 <= blob.length; i += 4)
        view.getFloat32(i, Endian.little),
    ];
  }

  /// A full request for one round.
  Future<GroupingPlanRequest> request({
    required String mode,
    required List<String> stages,
    required String strictness,
    int cap = groupingMemberCap,
    bool dropDerived = false,
  }) async {
    final needsModels = stages.any((s) => s != 'cluster');
    return GroupingPlanRequest(
      mode: mode,
      stages: stages,
      strictness: strictness,
      models: needsModels ? await models(cap: cap) : const [],
      pending: stages.contains('match') || stages.contains('cluster')
          ? await pending()
          : const [],
      dismissedFaceIds: mode == 'review' ? await dismissedFaceIds() : const [],
      distinctPairs: stages.contains('duplicates')
          ? await distinctPairs()
          : const [],
      bodies: stages.contains('bodies')
          ? await bodies(dropDerived: dropDerived)
          : const [],
      maxSuggestionsPerPerson: groupingMaxSuggestionsPerPerson,
    );
  }
}
