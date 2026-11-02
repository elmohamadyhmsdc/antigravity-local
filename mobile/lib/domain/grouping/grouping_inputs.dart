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
  final dim = unit.first.length; // 512 for people, 768 for characters
  final sum = Float64List(dim);
  for (var i = 0; i < unit.length; i++) {
    final w = q[i] * q[i];
    final e = unit[i];
    for (var d = 0; d < dim; d++) {
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

const _derivedLinks = ['appearance', 'weak_face', 'event_outfit'];

/// Event-context window (matches person_linking.GroupingParams.event_window_ms): identified bodies
/// further than this from every faceless body are not sent.
const eventWindowMs = 6 * 3600 * 1000;

/// Reads the library out of the database in the shapes the PC's grouping function takes.
class GroupingInputs {
  GroupingInputs(this._db, {this.kind = 'person'});

  final AppDatabase _db;

  /// 'person' (buffalo_l, 512-d) or 'character' (CCIP, 768-d): only that kind's rows are read.
  final String kind;

  Future<List<GroupingModel>> models({int cap = groupingMemberCap}) async {
    final people = await _db
        .customSelect(
          'SELECT DISTINCT person_id FROM faces WHERE person_id IS NOT NULL AND EXISTS (SELECT 1 FROM persons p WHERE p.id = faces.person_id AND p.grouping_locked = 0 AND p.kind = ?) ORDER BY person_id',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.faces, _db.persons},
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
              vectorFromBlob(r.read<Uint8List>('embedding')),
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
              'SELECT fr.face_id, fr.person_id FROM face_rejections fr JOIN faces f ON f.id = fr.face_id WHERE f.person_id IS NULL AND f.kind = ?',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.faceRejections, _db.faces},
            )
            .get()) {
      rejected
          .putIfAbsent(r.read<int>('face_id'), () => [])
          .add(r.read<int>('person_id'));
    }
    final rows = await _db
        .customSelect(
          "SELECT id, embedding, quality_score, media_id, frame_number FROM faces WHERE person_id IS NULL AND (ownership IS NULL OR ownership != 'none') AND hidden = 0 AND kind = ? ORDER BY id",
          variables: [Variable.withString(kind)],
          readsFrom: {_db.faces},
        )
        .get();
    return [
      for (final r in rows)
        GroupingFace(
          id: r.read<int>('id'),
          embedding: vectorFromBlob(r.read<Uint8List>('embedding')),
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
              'SELECT id FROM faces WHERE person_id IS NULL AND review_dismissed = 1 AND kind = ? ORDER BY id',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.faces},
            )
            .get())
      r.read<int>('id'),
  ];

  Future<List<(int, int)>> distinctPairs() async => [
    for (final r
        in await _db
            .customSelect(
              'SELECT d.person_a, d.person_b FROM person_distinct d JOIN persons p ON p.id = d.person_a WHERE p.kind = ? ORDER BY d.person_a, d.person_b',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.personDistinct, _db.persons},
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
              'SELECT r.body_id, r.person_id FROM body_rejections r JOIN bodies b ON b.id = r.body_id WHERE b.kind = ?',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.bodyRejections, _db.bodies},
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
                 b.link_method, bf.person_id AS face_person_id, m.taken_at AS taken_at
          FROM bodies b LEFT JOIN faces bf ON bf.id = b.face_id LEFT JOIN media m ON m.id = b.media_id
          WHERE b.kind = ? AND (b.ownership IS NULL OR b.ownership != 'none') AND b.hidden = 0
          ORDER BY b.id
          ''',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.bodies, _db.faces, _db.media},
        )
        .get();

    final all = <GroupingBody>[];
    final looseWithEvidenceMedia = <int?>{};
    final looseTimes =
        <int>[]; // taken_at of faceless bodies with an outfit (event context)
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
        weakFaceEmbedding: weak == null ? null : vectorFromBlob(weak),
        rejectedPersonIds: rejected[r.read<int>('id')] ?? const [],
        takenAt: r.readNullable<int>('taken_at'),
      );
      all.add(body);
      if (anchor == null &&
          (body.appearance != null || body.weakFaceEmbedding != null)) {
        looseWithEvidenceMedia.add(body.mediaId);
        final t = body.takenAt;
        if (t != null && body.appearance != null) looseTimes.add(t);
      }
    }
    looseTimes.sort();
    return [
      for (final b in all)
        if ((looseWithEvidenceMedia.contains(b.mediaId) &&
                (b.anchorPersonId != null ||
                    b.appearance != null ||
                    b.weakFaceEmbedding != null)) ||
            _anchorForEvent(b, looseTimes))
          b,
    ];
  }

  /// An identified body whose outfit and time could explain a faceless body of another photo taken
  /// within [eventWindowMs] (binary search over the sorted times of those faceless bodies).
  static bool _anchorForEvent(GroupingBody b, List<int> looseTimes) {
    final t = b.takenAt;
    if (b.anchorPersonId == null ||
        t == null ||
        b.appearance == null ||
        looseTimes.isEmpty) {
      return false;
    }
    var lo = 0, hi = looseTimes.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (looseTimes[mid] < t - eventWindowMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo < looseTimes.length && looseTimes[lo] <= t + eventWindowMs;
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
      dismissedFaceIds: await dismissedFaceIds(),
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
