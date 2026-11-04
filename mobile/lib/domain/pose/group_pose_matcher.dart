/// Named actions involving two to six people. Coordinates share one origin and
/// torso scale, preserving distance, overlap and relative size between people.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import 'pose_descriptor.dart';
import 'pose_geometry.dart';
import 'pose_rules.dart';

const groupPoseKind = 'group_pose';
const maxGroupPosePeople = 6;

class GroupPoseFeature {
  const GroupPoseFeature(this.members, {this.tags = const []});
  final List<PoseFeature> members;
  final List<List<String>> tags;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': 1,
        'tags': tags,
        'members': [
          for (final m in members) {'points': m.data.toList(), 'mask': m.mask},
        ],
      }),
    ),
  );

  static GroupPoseFeature decode(Uint8List blob) {
    final json = jsonDecode(utf8.decode(blob)) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unknown group pose version');
    }
    final members = [
      for (final m in json['members'] as List)
        PoseFeature(
          Float32List.fromList(
            (m['points'] as List).cast<num>().map((n) => n.toDouble()).toList(),
          ),
          m['mask'] as int,
          'group',
        ),
    ];
    if (members.length < 2 ||
        members.length > maxGroupPosePeople ||
        members.any(
          (m) => m.data.length != 34 || m.data.any((v) => !v.isFinite),
        )) {
      throw const FormatException('Invalid group pose');
    }
    final rawTags = json['tags'];
    final tags = rawTags is List && rawTags.length == members.length
        ? [for (final value in rawTags) (value as List).cast<String>()]
        : [for (final member in members) _memberTags(member)];
    return GroupPoseFeature(members, tags: tags);
  }
}

GroupPoseFeature? buildGroupPose(List<Pose> poses) {
  if (poses.length < 2 || poses.length > maxGroupPosePeople) return null;
  final torsos = <double>[];
  for (final pose in poses) {
    final torso = pose.torso;
    if (torso == null ||
        torso <= 1 ||
        !torso.isFinite ||
        pose.visibleCount < minSharedPoints) {
      return null;
    }
    torsos.add(torso);
  }
  torsos.sort();
  final scale = torsos.length.isOdd
      ? torsos[torsos.length ~/ 2]
      : (torsos[torsos.length ~/ 2 - 1] + torsos[torsos.length ~/ 2]) / 2;
  final x = poses.fold<double>(0, (s, p) => s + p.hipMid.x) / poses.length;
  final y = poses.fold<double>(0, (s, p) => s + p.hipMid.y) / poses.length;
  final members = <PoseFeature>[];
  for (final pose in poses) {
    final data = Float32List(34);
    var mask = 0;
    for (var i = 0; i < 17; i++) {
      if (!pose[i].visible) continue;
      if (!pose[i].x.isFinite || !pose[i].y.isFinite) return null;
      mask |= 1 << i;
      data[2 * i] = (pose[i].x - x) / scale;
      data[2 * i + 1] = (pose[i].y - y) / scale;
    }
    members.add(PoseFeature(data, mask, 'group'));
  }
  return GroupPoseFeature(
    members,
    tags: [for (final pose in poses) tierATags(pose).toList()],
  );
}

List<String> _memberTags(PoseFeature member) => tierATags(
  Pose([
    for (var i = 0; i < 17; i++)
      Pt(
        member.data[2 * i],
        member.data[2 * i + 1],
        member.mask & (1 << i) == 0 ? 0 : 1,
      ),
  ], extent: 'full'),
).toList();

/// Find a one-to-one assignment, invariant to detection order. Only a reflection
/// of the ENTIRE group is allowed: independently flipping people changes an action.
double? compareGroupPoses(GroupPoseFeature a, GroupPoseFeature b) {
  if (a.members.length != b.members.length) return null;
  double? assignment(List<PoseFeature> candidates) {
    final n = a.members.length;
    final costs = List.generate(
      n,
      (i) => List.generate(n, (j) {
        final left = a.members[i], right = candidates[j];
        final leftTags = a.tags.length == n ? a.tags[i] : _memberTags(left);
        final rightTags = b.tags.length == n ? b.tags[j] : _memberTags(right);
        for (final dimension in [
          PoseTag.orientation,
          PoseTag.posture,
          PoseTag.arms,
        ]) {
          final x = leftTags.where(dimension.contains).toSet();
          final y = rightTags.where(dimension.contains).toSet();
          if (x.isNotEmpty && y.isNotEmpty && x.intersection(y).isEmpty) {
            return 0.0;
          }
        }
        final match = comparePoses(
          left,
          right,
          sigma: 0.30,
          allowMirror: false,
        );
        if (match == null || match.coverage < minimumPoseCoverage) return 0.0;
        return match.score;
      }),
    );
    // Maximise the weakest member, so one different pose cannot be hidden
    // by five matching people. Reflection is applied to the whole group below.
    final dp = List.filled(1 << n, -1.0)..[0] = 1.0;
    for (var mask = 0; mask < dp.length; mask++) {
      var person = 0;
      for (var bits = mask; bits != 0; bits &= bits - 1) {
        person++;
      }
      if (person == n || dp[mask] < 0) continue;
      for (var j = 0; j < n; j++) {
        if (mask & (1 << j) != 0) continue;
        final next = mask | (1 << j);
        dp[next] = math.max(dp[next], math.min(dp[mask], costs[person][j]));
      }
    }
    return dp.last < 0 ? null : dp.last;
  }

  final straight = assignment(b.members);
  final mirrored = assignment([for (final m in b.members) mirrorFeature(m)]);
  if (straight == null) return mirrored;
  if (mirrored == null) return straight;
  return math.max(straight, mirrored);
}

class GroupPosePhoto {
  const GroupPosePhoto({
    required this.mediaId,
    required this.assetId,
    required this.bodies,
    required this.feature,
  });
  final int mediaId;
  final String assetId;
  final List<BodyRow> bodies;
  final GroupPoseFeature? feature;
}

typedef GroupPoseResult = ({GroupPosePhoto photo, double score});

List<({int index, double score})> _rankGroups(
  GroupPoseFeature query,
  List<GroupPoseFeature?> candidates,
) {
  final ranked = <({int index, double score})>[];
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    if (candidate == null) continue;
    final score = compareGroupPoses(query, candidate);
    if (score != null && score >= 0.65) ranked.add((index: i, score: score));
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return ranked;
}

Future<List<({int index, double score})>> _rankIsolated(
  GroupPoseFeature query,
  List<GroupPoseFeature?> candidates,
) => Isolate.run(() => _rankGroups(query, candidates));

class GroupPoseMatcher {
  GroupPoseMatcher(this.db);
  final AppDatabase db;

  /// Photos only: tracked video poses may come from different frames. Never
  /// silently drop an unmeasurable person and turn a three-person action into two.
  Future<List<GroupPosePhoto>> photos({int? personId}) async {
    final rows = await db
        .customSelect(
          '''SELECT m.id FROM media m
      WHERE m.kind = 'photo' AND EXISTS (SELECT 1 FROM bodies b
      LEFT JOIN faces f ON f.id = b.face_id WHERE b.media_id = m.id AND b.hidden = 0 AND b.kind = 'person'
      ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'})
      AND (SELECT COUNT(*) FROM bodies b WHERE b.media_id = m.id AND b.hidden = 0
      AND b.kind = 'person' AND b.frame_number IS NULL) BETWEEN 2 AND $maxGroupPosePeople ORDER BY m.id DESC''',
          variables: [if (personId != null) Variable.withInt(personId)],
          readsFrom: {db.media, db.bodies, db.faces},
        )
        .get();
    final result = <GroupPosePhoto>[];
    // Batch reads avoid two SQLite round-trips for every candidate photo.
    for (var start = 0; start < rows.length; start += 300) {
      final ids = rows
          .skip(start)
          .take(300)
          .map((r) => r.read<int>('id'))
          .toList();
      final media = await (db.select(
        db.media,
      )..where((m) => m.id.isIn(ids))).get();
      final bodies =
          await (db.select(db.bodies)
                ..where(
                  (b) =>
                      b.mediaId.isIn(ids) &
                      b.frameNumber.isNull() &
                      b.hidden.equals(false) &
                      b.kind.equals('person'),
                )
                ..orderBy([(b) => OrderingTerm.asc(b.id)]))
              .get();
      final byMedia = <int, List<BodyRow>>{};
      for (final b in bodies) {
        byMedia.putIfAbsent(b.mediaId!, () => []).add(b);
      }
      final mediaById = {for (final m in media) m.id: m};
      for (final id in ids) {
        final m = mediaById[id];
        if (m == null) continue;
        final entry = _assemble(m, byMedia[id] ?? []);
        if (entry != null) result.add(entry);
      }
    }
    return result;
  }

  Future<GroupPosePhoto?> photo(int mediaId) async {
    final media =
        await (db.select(db.media)
              ..where((m) => m.id.equals(mediaId) & m.kind.equals('photo')))
            .getSingleOrNull();
    if (media == null) return null;
    final bodies =
        await (db.select(db.bodies)
              ..where((b) => b.mediaId.equals(mediaId) & b.frameNumber.isNull())
              ..orderBy([(b) => OrderingTerm.asc(b.id)]))
            .get();
    return _assemble(media, bodies);
  }

  GroupPosePhoto? _assemble(MediaRow media, List<BodyRow> bodies) {
    if (bodies.length < 2 || bodies.length > maxGroupPosePeople) return null;
    final poses = [
      for (final b in bodies)
        Pose.fromJson(b.kpts, media.width, media.height, extent: b.extent),
    ];
    return GroupPosePhoto(
      mediaId: media.id,
      assetId: media.assetId,
      bodies: bodies,
      feature: poses.any((p) => p == null)
          ? null
          : buildGroupPose(poses.cast<Pose>()),
    );
  }

  Future<List<PoseCategoryRow>> categories() =>
      (db.select(db.poseCategories)
            ..where((c) => c.kind.equals(groupPoseKind))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .get();

  Future<int> save(String name, GroupPosePhoto exemplar) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80 || exemplar.feature == null) {
      throw ArgumentError('A name and measurable group are required');
    }
    return db
        .into(db.poseCategories)
        .insert(
          PoseCategoriesCompanion.insert(
            name: trimmed,
            kind: const Value(groupPoseKind),
            exemplarBodyId: Value(exemplar.bodies.first.id),
            exemplarFeature: exemplar.feature!.encode(),
            exemplarMask: exemplar.bodies.length,
            exemplarScaleSource: 'group-v1',
            threshold: 0.65,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  Future<List<GroupPoseResult>> similar(
    GroupPoseFeature feature, {
    int? excludingMedia,
    int? personId,
    int? categoryId,
  }) async {
    final candidates = await photos(personId: personId);
    final ranked = await _rankIsolated(feature, [
      for (final p in candidates) p.feature,
    ]);
    final rejected = categoryId == null
        ? <int>{}
        : {
            for (final r
                in await (db.select(db.bodyPoseMatches)..where(
                      (m) =>
                          m.categoryId.equals(categoryId) &
                          m.state.equals('rejected'),
                    ))
                    .get())
              r.bodyId,
          };
    return [
      for (final r in ranked)
        if (candidates[r.index].mediaId != excludingMedia &&
            !candidates[r.index].bodies.any((b) => rejected.contains(b.id)))
          (photo: candidates[r.index], score: r.score),
    ];
  }

  Future<void> reject(int categoryId, GroupPosePhoto photo) =>
      db.transaction(() async {
        for (final b in photo.bodies) {
          await db
              .into(db.bodyPoseMatches)
              .insertOnConflictUpdate(
                BodyPoseMatchesCompanion.insert(
                  bodyId: b.id,
                  categoryId: categoryId,
                  similarity: 0,
                  state: 'rejected',
                ),
              );
        }
      });
}
