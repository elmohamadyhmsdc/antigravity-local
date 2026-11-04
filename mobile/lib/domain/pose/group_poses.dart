/// Roadmap section 4 (Tier A): multi-person facts about one PHOTO. Photos only: in a video a detection can
/// point at one of up to three views of a track, whose keypoints come from another frame.
///
/// Known limits (roadmap 4.0): the scan keeps at most 40 faceless bodies per photo and drops faceless
/// bodies wearing the same outfit as another one in the same photo (a team in uniform is mostly missing),
/// and a face's yaw exists only for faces that passed the quality gate. A rule that needs data a body does not
/// have yields nothing instead of a wrong answer.
library;

import 'dart:math' as math;

import '../../data/db/app_database.dart';
import 'pose_geometry.dart';

abstract final class GroupTag {
  static const group = 'group'; // 3 or more bodies
  static const lineup =
      'lineup'; // side by side, shoulders level, not overlapping
  static const allFacing =
      'all_facing'; // every body has a face looking at the camera
  static const all = [group, lineup, allFacing];
}

class GroupMember {
  const GroupMember({required this.box, this.pose, this.faceYaw});

  /// Normalised x, y, w, h of the body box.
  final ({double x, double y, double w, double h}) box;
  final Pose? pose;

  /// Of the linked face, when one passed the quality gate.
  final double? faceYaw;
}

double _iou(
  ({double x, double y, double w, double h}) a,
  ({double x, double y, double w, double h}) b,
) {
  final ix = math.max(0.0, math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x));
  final iy = math.max(0.0, math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y));
  final inter = ix * iy;
  final union = a.w * a.h + b.w * b.h - inter;
  return union > 0 ? inter / union : 0;
}

double _median(List<double> v) {
  final s = [...v]..sort();
  return s.length.isOdd
      ? s[s.length ~/ 2]
      : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
}

/// The Tier-A multi-person tags of one photo.
Set<String> multiPersonTags(List<GroupMember> members) {
  final tags = <String>{};
  if (members.length >= 3) tags.add(GroupTag.group);
  if (members.length >= 2 && _lineup(members)) tags.add(GroupTag.lineup);
  if (members.length >= 2 &&
      members.every((m) => m.faceYaw != null && m.faceYaw!.abs() < 20)) {
    tags.add(GroupTag.allFacing);
  }
  return tags;
}

bool _lineup(List<GroupMember> members) {
  // every body needs measurable shoulders AND a torso to say "level"
  final shoulders = <double>[];
  final torsos = <double>[];
  for (final m in members) {
    final p = m.pose;
    final torso = p?.torso;
    if (p == null || !p.hasShoulders || torso == null) return false;
    shoulders.add(p.shoulderMid.y);
    torsos.add(torso);
  }
  final limit = 0.3 * _median(torsos);
  if (shoulders.reduce(math.max) - shoulders.reduce(math.min) > limit) {
    return false;
  }
  for (var i = 0; i < members.length; i++) {
    for (var j = i + 1; j < members.length; j++) {
      if (_iou(members[i].box, members[j].box) > 0.3) return false;
    }
  }
  return true;
}

class GroupPhotos {
  GroupPhotos(this._db);

  final AppDatabase _db;

  /// Every photo with two or more people-bodies and the multi-person tags that hold for it.
  Future<Map<int, Set<String>>> tagsByPhoto() async {
    final rows = await _db
        .customSelect(
          '''SELECT b.media_id, b.kpts, b.extent, b.bbox_x, b.bbox_y, b.bbox_w, b.bbox_h,
                    m.width, m.height, f.yaw
             FROM bodies b JOIN media m ON m.id = b.media_id LEFT JOIN faces f ON f.id = b.face_id
             WHERE b.kind = 'person' AND b.hidden = 0 AND b.frame_number IS NULL AND m.kind = 'photo'
               AND b.media_id IN (SELECT media_id FROM bodies WHERE kind = 'person' AND hidden = 0 AND frame_number IS NULL
                                  GROUP BY media_id HAVING COUNT(*) >= 2)
             ORDER BY b.media_id, b.id''',
          readsFrom: {_db.bodies, _db.media, _db.faces},
        )
        .get();
    final byMedia = <int, List<GroupMember>>{};
    for (final r in rows) {
      byMedia
          .putIfAbsent(r.read<int>('media_id'), () => [])
          .add(
            GroupMember(
              box: (
                x: r.read<double>('bbox_x'),
                y: r.read<double>('bbox_y'),
                w: r.read<double>('bbox_w'),
                h: r.read<double>('bbox_h'),
              ),
              pose: Pose.fromJson(
                r.readNullable<String>('kpts'),
                r.readNullable<int>('width'),
                r.readNullable<int>('height'),
                extent: r.readNullable<String>('extent'),
              ),
              faceYaw: r.readNullable<double>('yaw'),
            ),
          );
    }
    return {
      for (final e in byMedia.entries)
        if (multiPersonTags(e.value).isNotEmpty)
          e.key: multiPersonTags(e.value),
    };
  }

  /// Photos carrying [tag], newest first.
  Future<List<int>> photosWith(String tag) async {
    final all = await tagsByPhoto();
    final ids = [
      for (final e in all.entries)
        if (e.value.contains(tag)) e.key,
    ];
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  Future<Map<String, int>> counts() async {
    final counts = <String, int>{};
    for (final tags in (await tagsByPhoto()).values) {
      for (final t in tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts;
  }
}
