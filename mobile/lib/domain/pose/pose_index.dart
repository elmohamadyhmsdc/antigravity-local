/// Roadmap Phase 2: the cached pose descriptor of every body, the Tier-A chips and "find similar".
///
/// * The cache is `body_pose_features`; a row is (re)built when its `version` is old or the body is new,
///   and the scan store deletes the row when it rewrites a body's keypoints in place.
/// * `tags` holds the Tier-A tags as `,standing,frontal,` so `LIKE '%,standing,%'` matches whole tags.
/// * Heavy work (parsing, rules, scoring 50k descriptors) runs in a short-lived isolate with plain data;
///   the database is only touched on the calling isolate.
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import 'outfit_palette.dart';
import 'pose_descriptor.dart';
import 'pose_geometry.dart';
import 'pose_rules.dart';

/// Bump when the rules or the descriptor change: every row is rebuilt.
const poseRulesVersion = poseFeatureVersion;

const _maxResults = 200;

typedef _Job = ({
  int id,
  String? kpts,
  int? w,
  int? h,
  String? extent,
  double? yaw,
});
typedef _Built = ({
  int id,
  Uint8List feature,
  int mask,
  String scaleSource,
  String tags,
});

String encodeTags(Iterable<String> tags) {
  final sorted = tags.toList()..sort();
  return sorted.isEmpty ? '' : ',${sorted.join(',')},';
}

List<String> decodeTags(String tags) => [
  for (final t in tags.split(','))
    if (t.isNotEmpty) t,
];

List<_Built> _build(List<_Job> jobs) {
  final out = <_Built>[];
  for (final j in jobs) {
    final pose = Pose.fromJson(
      j.kpts,
      j.w,
      j.h,
      extent: j.extent,
      faceYaw: j.yaw,
    );
    if (pose == null) {
      out.add((
        id: j.id,
        feature: Uint8List(0),
        mask: 0,
        scaleSource: '',
        tags: '',
      ));
      continue;
    }
    final feature = buildPoseFeature(pose);
    out.add((
      id: j.id,
      feature: feature == null ? Uint8List(0) : feature.toBlob(),
      mask: feature?.mask ?? 0,
      scaleSource: feature?.scaleSource ?? '',
      tags: encodeTags(tierATags(pose)),
    ));
  }
  return out;
}

typedef _Candidate = ({
  int id,
  Uint8List feature,
  int mask,
  String scaleSource,
});

List<({int id, double score, double similarity, double coverage})> _rank(
  ({Uint8List feature, int mask, String scaleSource}) query,
  List<_Candidate> candidates,
  int limit,
  double sigma,
) {
  final q = PoseFeature.fromBlob(query.feature, query.mask, query.scaleSource);
  final scored =
      <({int id, double score, double similarity, double coverage})>[];
  for (final c in candidates) {
    final m = comparePoses(
      q,
      PoseFeature.fromBlob(c.feature, c.mask, c.scaleSource),
      sigma: sigma,
    );
    if (m != null) {
      scored.add((
        id: c.id,
        score: m.score,
        similarity: m.similarity,
        coverage: m.coverage,
      ));
    }
  }
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.take(limit).toList();
}

List<int> _colorMatches(
  List<({int id, Uint8List appearance})> rows,
  OutfitColor color,
  OutfitRegion? region,
) {
  final out = <int>[];
  for (final r in rows) {
    final view = ByteData.sublistView(r.appearance);
    final d = [
      for (var i = 0; i + 4 <= r.appearance.length; i += 4)
        view.getFloat32(i, Endian.little),
    ];
    if (hasColor(d, color, region: region)) out.add(r.id);
  }
  return out;
}

class PoseIndex {
  PoseIndex(this._db);

  final AppDatabase _db;

  /// Bodies with keypoints and no up-to-date row.
  Future<int> pending() async =>
      (await _db
              .customSelect(
                '''SELECT COUNT(*) AS n FROM bodies b JOIN media m ON m.id = b.media_id
               WHERE b.kpts IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM body_pose_features x WHERE x.body_id = b.id AND x.version = ?)''',
                variables: [Variable.withInt(poseRulesVersion)],
                readsFrom: {_db.bodies, _db.media, _db.bodyPoseFeatures},
              )
              .getSingle())
          .read<int>('n');

  /// Builds the missing / outdated rows, [batch] at a time, until none is left or [shouldContinue]
  /// turns false. Returns how many rows were written.
  Future<int> rebuild({
    int batch = 400,
    bool Function()? shouldContinue,
  }) async {
    var written = 0;
    while (shouldContinue?.call() ?? true) {
      final rows = await _db
          .customSelect(
            '''SELECT b.id, b.kpts, b.extent, m.width, m.height, f.yaw
               FROM bodies b JOIN media m ON m.id = b.media_id LEFT JOIN faces f ON f.id = b.face_id
               WHERE b.kpts IS NOT NULL
                 AND NOT EXISTS (SELECT 1 FROM body_pose_features x WHERE x.body_id = b.id AND x.version = ?)
               ORDER BY b.id LIMIT ?''',
            variables: [
              Variable.withInt(poseRulesVersion),
              Variable.withInt(batch),
            ],
            readsFrom: {_db.bodies, _db.media, _db.faces, _db.bodyPoseFeatures},
          )
          .get();
      if (rows.isEmpty) break;
      final jobs = <_Job>[
        for (final r in rows)
          (
            id: r.read<int>('id'),
            kpts: r.readNullable<String>('kpts'),
            w: r.readNullable<int>('width'),
            h: r.readNullable<int>('height'),
            extent: r.readNullable<String>('extent'),
            yaw: r.readNullable<double>('yaw'),
          ),
      ];
      final built = await _buildIsolated(jobs);
      await _db.batch((b) {
        for (final x in built) {
          b.insert(
            _db.bodyPoseFeatures,
            BodyPoseFeaturesCompanion.insert(
              bodyId: Value(x.id),
              version: poseRulesVersion,
              feature: x.feature,
              visibleMask: x.mask,
              scaleSource: x.scaleSource,
              tags: Value(x.tags),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
      written += built.length;
    }
    return written;
  }

  /// Drops the cached row of a body whose keypoints were rewritten.
  Future<void> invalidate(int bodyId) => (_db.delete(
    _db.bodyPoseFeatures,
  )..where((x) => x.bodyId.equals(bodyId))).go();

  /// Bodies carrying a Tier-A [tag] (optionally one person's), newest first.
  Future<List<int>> bodiesWithTag(
    String tag, {
    int? personId,
    int limit = 500,
  }) async {
    final rows = await _db
        .customSelect(
          '''SELECT x.body_id FROM body_pose_features x JOIN bodies b ON b.id = x.body_id
             LEFT JOIN faces f ON f.id = b.face_id
             WHERE x.tags LIKE ? ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}
             ORDER BY x.body_id DESC LIMIT ?''',
          variables: [
            Variable.withString('%,$tag,%'),
            if (personId != null) Variable.withInt(personId),
            Variable.withInt(limit),
          ],
          readsFrom: {_db.bodyPoseFeatures, _db.bodies, _db.faces},
        )
        .get();
    return [for (final r in rows) r.read<int>('body_id')];
  }

  /// Count of bodies per Tier-A tag (for the chips).
  Future<Map<String, int>> tagCounts({int? personId}) async {
    final rows = await _db
        .customSelect(
          '''SELECT x.tags FROM body_pose_features x JOIN bodies b ON b.id = x.body_id
             LEFT JOIN faces f ON f.id = b.face_id
             WHERE x.tags != '' ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}''',
          variables: [if (personId != null) Variable.withInt(personId)],
          readsFrom: {_db.bodyPoseFeatures, _db.bodies, _db.faces},
        )
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      for (final t in decodeTags(r.read<String>('tags'))) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// The [limit] bodies whose pose looks most like [bodyId]'s, best first (ranked by
  /// similarity x coverage; bodies that cannot be compared are left out; the body itself too).
  Future<List<({int bodyId, double score, double similarity, double coverage})>>
  findSimilar(
    int bodyId, {
    int limit = _maxResults,
    double sigma = defaultPoseSigma,
    int? personId,
  }) async {
    final query =
        await (_db.select(_db.bodyPoseFeatures)..where(
              (x) =>
                  x.bodyId.equals(bodyId) & x.visibleMask.isBiggerThanValue(0),
            ))
            .getSingleOrNull();
    if (query == null) return const [];
    final candidates = await _candidates(excluding: bodyId, personId: personId);
    final q = (
      feature: query.feature,
      mask: query.visibleMask,
      scaleSource: query.scaleSource,
    );
    final ranked = await _rankIsolated(q, candidates, limit, sigma);
    return [
      for (final r in ranked)
        (
          bodyId: r.id,
          score: r.score,
          similarity: r.similarity,
          coverage: r.coverage,
        ),
    ];
  }

  /// Same, from a stored exemplar copy (a named pose whose exemplar body may be gone).
  Future<List<({int bodyId, double score, double similarity, double coverage})>>
  findSimilarToFeature(
    PoseFeature exemplar, {
    int limit = _maxResults,
    double sigma = defaultPoseSigma,
    int? personId,
  }) async {
    final candidates = await _candidates(personId: personId);
    final q = (
      feature: exemplar.toBlob(),
      mask: exemplar.mask,
      scaleSource: exemplar.scaleSource,
    );
    final ranked = await _rankIsolated(q, candidates, limit, sigma);
    return [
      for (final r in ranked)
        (
          bodyId: r.id,
          score: r.score,
          similarity: r.similarity,
          coverage: r.coverage,
        ),
    ];
  }

  Future<List<_Candidate>> _candidates({int? excluding, int? personId}) async {
    final rows = await _db
        .customSelect(
          '''SELECT x.body_id, x.feature, x.visible_mask, x.scale_source
             FROM body_pose_features x JOIN bodies b ON b.id = x.body_id
             LEFT JOIN faces f ON f.id = b.face_id
             WHERE x.visible_mask > 0 ${excluding == null ? '' : 'AND x.body_id != ?'}
             ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}''',
          variables: [
            if (excluding != null) Variable.withInt(excluding),
            if (personId != null) Variable.withInt(personId),
          ],
          readsFrom: {_db.bodyPoseFeatures, _db.bodies, _db.faces},
        )
        .get();
    return [
      for (final r in rows)
        (
          id: r.read<int>('body_id'),
          feature: r.read<Uint8List>('feature'),
          mask: r.read<int>('visible_mask'),
          scaleSource: r.read<String>('scale_source'),
        ),
    ];
  }

  /// Bodies whose torso / legs (or either) are mostly [color]: a colour chip.
  Future<List<int>> bodiesWithColor(
    OutfitColor color, {
    OutfitRegion? region,
    int? personId,
  }) async {
    final rows = await _db
        .customSelect(
          '''SELECT b.id, b.appearance FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
             WHERE b.appearance IS NOT NULL
             ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}
             ORDER BY b.id DESC''',
          variables: [if (personId != null) Variable.withInt(personId)],
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();
    final data = [
      for (final r in rows)
        (id: r.read<int>('id'), appearance: r.read<Uint8List>('appearance')),
    ];
    return _colorsIsolated(data, color, region);
  }
}

// Top-level wrappers: a closure created inside a method would capture `this` (and with it SQLite),
// which cannot cross into an isolate.
Future<List<_Built>> _buildIsolated(List<_Job> jobs) =>
    Isolate.run(() => _build(jobs));

Future<List<({int id, double score, double similarity, double coverage})>>
_rankIsolated(
  ({Uint8List feature, int mask, String scaleSource}) query,
  List<_Candidate> candidates,
  int limit,
  double sigma,
) => Isolate.run(() => _rank(query, candidates, limit, sigma));

Future<List<int>> _colorsIsolated(
  List<({int id, Uint8List appearance})> rows,
  OutfitColor color,
  OutfitRegion? region,
) => Isolate.run(() => _colorMatches(rows, color, region));
