import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/api/dtos/grouping.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/app_settings.dart' show SettingKeys;
import '../identity/identity_selection.dart';
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

/// The model the phone sends for a person: [buildPersonModel] over the faces that really are them, with
/// the members chosen to cover how they look instead of being the N sharpest.
///
/// - Outliers (a stranger grouped in by mistake, a ruined crop) are left out, so one wrong face cannot
///   drag the prototype toward someone else and then attract more wrong faces. Gentle on purpose
///   (`floor` 0.30, at most 40% trimmed, never under 6 faces): a profile of the right person must stay.
/// - When there are more faces than [cap], half of the members are the best quality and the other half
///   are picked farthest-first in embedding space, so profiles, tilts and lighting changes stay
///   represented (the match score uses the most similar members). The best-quality half comes first: the
///   PC reads only the first 50 for duplicate-person scoring.
/// With few clean faces this is exactly [buildPersonModel].
GroupingModel robustPersonModel(
  int personId,
  List<FaceVector> faces, {
  int cap = groupingMemberCap,
}) {
  final selection = selectIdentity(
    [
      for (var i = 0; i < faces.length; i++)
        IdentityFace(
          id: i,
          embedding: faces[i].embedding,
          quality: faces[i].quality,
        ),
    ],
    floor: 0.30,
    minToTrim: 6,
    dedupe: false,
    medoidSample:
        40, // this runs on every grouping round for every person: keep it cheap
  );
  final keptIds = {for (final f in selection.kept) f.id};
  final clean = [
    for (var i = 0; i < faces.length; i++)
      if (keptIds.contains(i)) faces[i],
  ];
  if (clean.isEmpty) return buildPersonModel(personId, faces, cap: cap);
  final base = buildPersonModel(personId, clean, cap: cap);
  if (clean.length <= cap) return base;

  final unit = [for (final f in clean) _normalized(f.embedding)];
  final byQuality = List<int>.generate(clean.length, (i) => i)
    ..sort((a, b) {
      final c = clean[b].quality.compareTo(clean[a].quality);
      return c != 0 ? c : a.compareTo(b);
    });
  final chosen = byQuality.take(cap ~/ 2).toList();
  // the farthest-first search costs candidates x members x dimensions: a person with thousands of faces
  // (a long video) is searched among an evenly spaced 600 of them
  final candidates = clean.length <= 600
      ? List<int>.generate(clean.length, (i) => i)
      : [for (var i = 0; i < 600; i++) i * clean.length ~/ 600];
  // farthest-first: the face least like anything chosen so far
  final nearest = List<double>.filled(clean.length, double.negativeInfinity);
  void touch(int added) {
    for (final i in candidates) {
      var dot = 0.0;
      for (var d = 0; d < unit[i].length; d++) {
        dot += unit[i][d] * unit[added][d];
      }
      if (dot > nearest[i]) nearest[i] = dot;
    }
  }

  for (final c in chosen) {
    touch(c);
  }
  final taken = chosen.toSet();
  while (chosen.length < cap) {
    var pick = -1;
    var lowest = double.infinity;
    for (final i in candidates) {
      if (taken.contains(i)) continue;
      if (nearest[i] < lowest) {
        lowest = nearest[i];
        pick = i;
      }
    }
    if (pick < 0) break;
    chosen.add(pick);
    taken.add(pick);
    touch(pick);
  }
  return GroupingModel(
    pid: base.pid,
    proto: base.proto,
    members: [for (final i in chosen) unit[i]],
    count: base.count,
  );
}

/// The embedding model the library's [kind] faces must come from, or null when none is recorded yet.
/// Faces of another model have the same shape but live in another space: comparing them with this
/// library's faces is meaningless, so grouping and the audit leave them out (the scan itself pauses on a
/// model change; a backup or a sidecar can still bring such faces in).
Future<String?> activeEmbeddingModel(AppDatabase db, String kind) async {
  if (kind == 'character') return characterEmbeddingModelId;
  final saved = await db.setting(SettingKeys.modelId);
  return saved == null || saved.isEmpty ? null : saved;
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

  int get _dim => kind == 'character' ? characterEmbeddingDim : embeddingDim;

  double get _minPx =>
      kind == 'character' ? groupingMinCharacterFacePx : groupingMinFacePx;

  /// A stored vector the PC will accept: right length, finite numbers. One damaged row would
  /// otherwise make the PC refuse the whole request (400) on every run, so it is left out instead.
  Float32List? _vector(Uint8List blob) {
    try {
      final v = vectorFromBlob(blob);
      if (v.length != _dim) return null;
      for (final x in v) {
        if (!x.isFinite) return null;
      }
      return v;
    } on FormatException {
      return null;
    }
  }

  Future<List<GroupingModel>> models({int cap = groupingMemberCap}) async {
    final people = await _db
        .customSelect(
          'SELECT DISTINCT person_id FROM faces WHERE person_id IS NOT NULL AND EXISTS (SELECT 1 FROM persons p WHERE p.id = faces.person_id AND p.grouping_locked = 0 AND p.kind = ?) ORDER BY person_id',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.faces, _db.persons},
        )
        .get();
    cap = effectiveMemberCap(people.length, cap);
    final libraryModel = await activeEmbeddingModel(_db, kind);
    final out = <GroupingModel>[];
    final slice = Stopwatch()..start();
    for (final p in people) {
      final pid = p.read<int>('person_id');
      final rows = await _db
          .customSelect(
            'SELECT id, quality_score, embedding FROM faces WHERE person_id = ? AND face_px >= ? AND hidden = 0 AND (?3 IS NULL OR model_id = ?3)',
            variables: [
              Variable.withInt(pid),
              Variable.withReal(_minPx),
              Variable<String>(libraryModel),
            ],
            readsFrom: {_db.faces},
          )
          .get();
      // A person whose faces did not change keeps the model of the last round: grouping runs every
      // 100 new faces, and only a few people change between two runs.
      var idSum = 0, maxId = 0;
      for (final r in rows) {
        final id = r.read<int>('id');
        idSum += id;
        if (id > maxId) maxId = id;
      }
      final signature = '$cap:${rows.length}:$idSum:$maxId';
      final cached = _modelCache[pid];
      if (cached != null && cached.$1 == signature) {
        out.add(cached.$2);
        continue;
      }
      final faces = <FaceVector>[];
      for (final r in rows) {
        final v = _vector(r.read<Uint8List>('embedding'));
        if (v != null) {
          faces.add(FaceVector(v, r.read<double>('quality_score')));
        }
      }
      if (faces.isEmpty) continue;
      final model = robustPersonModel(pid, faces, cap: cap);
      _modelCache[pid] = (signature, model);
      out.add(model);
      // never hold the screen for more than a frame or two: the scan, Pause and every other screen
      // share this thread
      if (slice.elapsedMilliseconds > 12) {
        await Future<void>.delayed(Duration.zero);
        slice
          ..reset()
          ..start();
      }
    }
    final live = {for (final m in out) m.pid};
    _modelCache.removeWhere((pid, _) => !live.contains(pid));
    return out;
  }

  /// person id -> (signature of the faces it was built from, the model).
  final _modelCache = <int, (String, GroupingModel)>{};

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
          "SELECT id, embedding, quality_score, media_id, frame_number FROM faces WHERE person_id IS NULL AND (ownership IS NULL OR ownership != 'none') AND hidden = 0 AND kind = ? AND face_px >= ? AND (?3 IS NULL OR model_id = ?3) ORDER BY id",
          variables: [
            Variable.withString(kind),
            Variable.withReal(_minPx),
            Variable<String>(await activeEmbeddingModel(_db, kind)),
          ],
          readsFrom: {_db.faces},
        )
        .get();
    final out = <GroupingFace>[];
    final slice = Stopwatch()..start();
    for (final r in rows) {
      if (slice.elapsedMilliseconds > 12) {
        await Future<void>.delayed(Duration.zero);
        slice
          ..reset()
          ..start();
      }
      final v = _vector(r.read<Uint8List>('embedding'));
      if (v == null) continue;
      out.add(
        GroupingFace(
          id: r.read<int>('id'),
          embedding: v,
          quality: r.read<double>('quality_score'),
          frameKey: frameKeyOf(
            r.readNullable<int>('media_id'),
            r.readNullable<int>('frame_number'),
          ),
          rejectedPersonIds: rejected[r.read<int>('id')] ?? const [],
        ),
      );
    }
    return out;
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

  /// People the user said are different, plus people who appear in the same photo / video frame:
  /// one person cannot be twice in a frame, so such a pair is never "possibly the same person"
  /// (and, for the PC, never a pair of twins to fold together).
  Future<List<(int, int)>> distinctPairs() async => [
    for (final r
        in await _db
            .customSelect(
              '''
              SELECT d.person_a AS a, d.person_b AS b
              FROM person_distinct d JOIN persons p ON p.id = d.person_a WHERE p.kind = ?1
              UNION
              SELECT x.pid, y.pid
              FROM (SELECT media_id AS m, COALESCE(frame_number, -1) AS fr, person_id AS pid
                    FROM faces WHERE person_id IS NOT NULL AND kind = ?1 AND media_id IS NOT NULL
                    GROUP BY media_id, COALESCE(frame_number, -1), person_id) x
              JOIN (SELECT media_id AS m, COALESCE(frame_number, -1) AS fr, person_id AS pid
                    FROM faces WHERE person_id IS NOT NULL AND kind = ?1 AND media_id IS NOT NULL
                    GROUP BY media_id, COALESCE(frame_number, -1), person_id) y
                ON y.m = x.m AND y.fr = x.fr AND y.pid > x.pid
              ORDER BY 1, 2
              ''',
              variables: [Variable.withString(kind)],
              readsFrom: {_db.personDistinct, _db.persons, _db.faces},
            )
            .get())
      (r.read<int>('a'), r.read<int>('b')),
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
      distinctPairs: stages.any((s) => s != 'bodies')
          ? await distinctPairs()
          : const [],
      bodies: stages.contains('bodies')
          ? await bodies(dropDerived: dropDerived)
          : const [],
      maxSuggestionsPerPerson: groupingMaxSuggestionsPerPerson,
      linkAlikePeople: true,
    );
  }
}
