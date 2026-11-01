/// User-named examples, compared geometrically. Scores rank proposals; they are
/// not probabilities or claims about what a person is doing.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'group_pose_matcher.dart';
import 'pose_descriptor.dart';
import 'pose_geometry.dart';

class ActionPoseFrame {
  const ActionPoseFrame({required this.timeMs, required this.members});
  final int timeMs;
  final List<PoseFeature> members;

  Map<String, dynamic> toJson() => {
    'time': timeMs,
    'members': [
      for (final p in members)
        {'points': p.data.toList(), 'mask': p.mask, 'scale': p.scaleSource},
    ],
  };

  static ActionPoseFrame fromJson(Map<String, dynamic> json) {
    final members = [
      for (final raw in json['members'] as List)
        PoseFeature(
          Float32List.fromList(
            (raw['points'] as List).map((v) => (v as num).toDouble()).toList(),
          ),
          raw['mask'] as int,
          raw['scale'] as String,
        ),
    ];
    if (members.isEmpty ||
        members.length > 6 ||
        members.any(
          (p) =>
              p.data.length != 34 ||
              p.data.any((v) => !v.isFinite) ||
              p.visibleCount < minSharedPoints,
        )) {
      throw const FormatException('Invalid action pose evidence');
    }
    return ActionPoseFrame(timeMs: json['time'] as int, members: members);
  }
}

ActionPoseFrame? actionPoseFrame(int timeMs, List<Pose> poses) {
  if (poses.length == 1) {
    final p = buildPoseFeature(poses.single);
    return p == null ? null : ActionPoseFrame(timeMs: timeMs, members: [p]);
  }
  final group = buildGroupPose(poses);
  return group == null
      ? null
      : ActionPoseFrame(timeMs: timeMs, members: group.members);
}

double _distance(PoseFeature a, PoseFeature b) {
  if (a.scaleSource != b.scaleSource) return double.infinity;
  var shared = 0, visible = 0;
  var distance = 0.0;
  for (var i = 0; i < 17; i++) {
    final bit = 1 << i;
    if ((a.mask | b.mask) & bit != 0) visible++;
    if ((a.mask & b.mask) & bit == 0) continue;
    shared++;
    final dx = a.data[2 * i] - b.data[2 * i];
    final dy = a.data[2 * i + 1] - b.data[2 * i + 1];
    distance += math.sqrt(dx * dx + dy * dy);
  }
  if (shared < minSharedPoints || shared / visible < .7) return double.infinity;
  return distance / shared + (1 - shared / visible) * .5;
}

List<int> _assignment(ActionPoseFrame a, ActionPoseFrame b) {
  final n = a.members.length;
  final cost = List.filled(1 << n, double.infinity)..[0] = 0;
  final chosen = List.filled(1 << n, -1);
  for (var mask = 0; mask < cost.length; mask++) {
    var i = 0;
    for (var bits = mask; bits != 0; bits &= bits - 1) {
      i++;
    }
    if (i == n || !cost[mask].isFinite) continue;
    for (var j = 0; j < n; j++) {
      if (mask & (1 << j) != 0) continue;
      final next = mask | (1 << j);
      final score = cost[mask] + _distance(a.members[i], b.members[j]);
      if (score < cost[next]) {
        cost[next] = score;
        chosen[next] = j;
      }
    }
  }
  if (!cost.last.isFinite) return [];
  var mask = cost.length - 1;
  final order = List.filled(n, 0);
  for (var i = n - 1; i >= 0; i--) {
    final j = chosen[mask];
    order[i] = j;
    mask ^= 1 << j;
  }
  return order;
}

List<ActionPoseFrame> _sample(List<ActionPoseFrame> frames) {
  if (frames.length <= 20) return frames;
  return [
    for (var i = 0; i < 20; i++) frames[(i * (frames.length - 1) / 19).round()],
  ];
}

/// The actor assignment and optional reflection stay fixed over the entire
/// sequence. A different actor cannot silently take over another actor's motion.
double? compareActionSequences(
  List<ActionPoseFrame> query,
  List<ActionPoseFrame> candidate, {
  bool allowMirror = false,
}) {
  if (query.isEmpty || candidate.isEmpty) return null;
  final n = query.first.members.length;
  if ([...query, ...candidate].any((f) => f.members.length != n)) return null;
  final a = _sample(query), original = _sample(candidate);
  double? best;
  for (final mirror in [false, if (allowMirror) true]) {
    final b = mirror
        ? [
            for (final f in original)
              ActionPoseFrame(
                timeMs: f.timeMs,
                members: [for (final m in f.members) mirrorFeature(m)],
              ),
          ]
        : original;
    final order = _assignment(a.first, b.first);
    if (order.isEmpty) continue;
    double distance(ActionPoseFrame left, ActionPoseFrame right) {
      var d = 0.0;
      for (var k = 0; k < n; k++) {
        d += _distance(left.members[k], right.members[order[k]]);
      }
      return d / n;
    }

    // Anchored, monotonic DTW permits modest timing variation, never reversal.
    final dp = List.generate(
      a.length + 1,
      (_) => List.filled(b.length + 1, double.infinity),
    );
    final steps = List.generate(
      a.length + 1,
      (_) => List.filled(b.length + 1, 0),
    );
    dp[0][0] = 0;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        if ((i / a.length - j / b.length).abs() > .3 &&
            a.length > 1 &&
            b.length > 1) {
          continue;
        }
        final previous = [(i - 1, j - 1), (i - 1, j), (i, j - 1)]
          ..sort((x, y) => dp[x.$1][x.$2].compareTo(dp[y.$1][y.$2]));
        final p = previous.first;
        dp[i][j] = dp[p.$1][p.$2] + distance(a[i - 1], b[j - 1]);
        steps[i][j] = steps[p.$1][p.$2] + 1;
      }
    }
    if (!dp.last.last.isFinite) continue;
    final mean = dp.last.last / steps.last.last;
    // Endpoints matter: sitting down must not match standing up through warping.
    final ends = (distance(a.first, b.first) + distance(a.last, b.last)) / 2;
    final d = math.max(mean, ends * .8);
    final score = math.exp(-d * d / (2 * .35 * .35));
    best = best == null ? score : math.max(best, score);
  }
  return best;
}
