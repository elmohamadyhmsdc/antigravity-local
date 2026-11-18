import '../../data/api/dtos/analyze.dart';

class MeasuredHeadPose {
  const MeasuredHeadPose({
    required this.pose,
    required this.count,
    required this.timestampMs,
    this.minimum,
    this.maximum,
  });

  final Pose pose;
  final int count;
  final int timestampMs;
  final Pose? minimum, maximum;
}

class RefacePoseReport {
  RefacePoseReport.fromJson(Map<String, dynamic> json)
    : totalFrames = _count(json, 'total_frames'),
      decodedFrames = _count(json, 'decoded_frames'),
      unreadableFrames = _count(json, 'unreadable_frames'),
      framesWithoutPose = _count(json, 'frames_without_pose'),
      facesWithoutPose = _count(json, 'faces_without_pose'),
      poses = [
        for (final raw in json['poses'] as List)
          MeasuredHeadPose(
            pose: _pose(Map<String, dynamic>.from(raw as Map)),
            count: _count(raw, 'count'),
            timestampMs: _count(raw, 'timestamp_ms'),
            minimum: _bound(raw['minimum']),
            maximum: _bound(raw['maximum']),
          ),
      ] {
    if (totalFrames == 0 ||
        decodedFrames + unreadableFrames != totalFrames ||
        framesWithoutPose > decodedFrames ||
        poses.any((row) => row.count == 0)) {
      throw const FormatException('Invalid Reface pose report.');
    }
  }

  final int totalFrames, decodedFrames, unreadableFrames;
  final int framesWithoutPose, facesWithoutPose;
  final List<MeasuredHeadPose> poses;

  static int _count(Map json, String key) {
    final value = json[key];
    if (value is! int || value < 0) {
      throw const FormatException('Invalid Reface pose count.');
    }
    return value;
  }

  static Pose _pose(Map<String, dynamic> json) {
    final pose = Pose.fromJson(json);
    if (pose.roll == null ||
        [
          pose.yaw,
          pose.pitch,
          pose.roll!,
        ].any((v) => !v.isFinite || v.abs() > 180)) {
      throw const FormatException('Invalid measured head angles.');
    }
    return pose;
  }

  static Pose? _bound(Object? value) {
    if (value == null) return null;
    final values = value as List;
    if (values.length != 3)
      throw const FormatException('Invalid head pose range.');
    return _pose({'yaw': values[0], 'pitch': values[1], 'roll': values[2]});
  }
}

class VerifiedRefacePortrait {
  const VerifiedRefacePortrait({
    required this.path,
    required this.source,
    this.pose,
  });

  final String path;
  final Map<String, dynamic> source;
  final Pose? pose;

  bool covers(Pose target) {
    final measured = pose;
    return measured != null &&
        measured.roll != null &&
        target.roll != null &&
        (measured.yaw - target.yaw).abs() <= 15 &&
        (measured.pitch - target.pitch).abs() <= 15 &&
        (measured.roll! - target.roll!).abs() <= 25;
  }

  bool coversGroup(MeasuredHeadPose target) =>
      covers(target.pose) &&
      covers(target.minimum ?? target.pose) &&
      covers(target.maximum ?? target.pose);
}

class PreparedRefaceReferences {
  const PreparedRefaceReferences({
    required this.report,
    required this.targetSha,
    required this.portraits,
    required this.anchors,
    required this.prior,
  });

  final RefacePoseReport report;
  final String targetSha;
  final List<VerifiedRefacePortrait> portraits;
  final List<Map<String, dynamic>> anchors;
  final List<VerifiedRefacePortrait> prior;

  bool covers(MeasuredHeadPose pose) =>
      portraits.any((portrait) => portrait.coversGroup(pose));

  List<Map<String, dynamic>> get sources => [
    ...anchors,
    for (final portrait in portraits) portrait.source,
  ];
}

/// Pick the references covering the most measured appearances, within the
/// source payload budget. Count coverage only from references actually used.
List<VerifiedRefacePortrait> selectPoseReferences(
  RefacePoseReport report,
  List<VerifiedRefacePortrait> portraits, {
  int limit = 80,
}) {
  final remaining = Set<int>.of(Iterable<int>.generate(report.poses.length));
  final byCell = <(int, int, int), List<int>>{};
  (int, int, int) cell(Pose pose) => (
    (pose.yaw / 15 + .5).floor(),
    (pose.pitch / 15 + .5).floor(),
    ((pose.roll ?? 0) / 25 + .5).floor(),
  );
  for (final (i, row) in report.poses.indexed) {
    (byCell[cell(row.pose)] ??= []).add(i);
  }
  Set<int> matching(VerifiedRefacePortrait portrait) {
    final pose = portrait.pose;
    if (pose == null || pose.roll == null) return {};
    final (yaw, pitch, roll) = cell(pose);
    return {
      for (var y = yaw - 1; y <= yaw + 1; y++)
        for (var p = pitch - 1; p <= pitch + 1; p++)
          for (var r = roll - 1; r <= roll + 1; r++)
            for (final index in byCell[(y, p, r)] ?? const <int>[])
              if (portrait.coversGroup(report.poses[index])) index,
    };
  }

  final matches = [for (final portrait in portraits) matching(portrait)];
  final chosen = <VerifiedRefacePortrait>[];
  while (remaining.isNotEmpty && chosen.length < limit) {
    var winner = -1;
    var best = 0;
    for (final (index, angles) in matches.indexed) {
      final score = angles
          .intersection(remaining)
          .fold<int>(0, (sum, key) => sum + report.poses[key].count);
      if (score > best) {
        winner = index;
        best = score;
      }
    }
    if (winner == -1) break;
    chosen.add(portraits[winner]);
    remaining.removeAll(matches[winner]);
  }
  if (chosen.isEmpty && portraits.isNotEmpty && limit > 0) {
    chosen.add(portraits.first);
  }
  return chosen;
}
