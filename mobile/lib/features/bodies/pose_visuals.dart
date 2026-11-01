import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/pose/group_pose_matcher.dart';
import '../../domain/pose/pose_geometry.dart';
import '../../domain/pose/pose_rules.dart';
import '../../library_providers.dart';
import '../../l10n/app_localizations.dart';
import '../shared/image_preview.dart';

String poseLabel(AppLocalizations l, String tag) => switch (tag) {
  PoseTag.lying => l.poseTagLying,
  PoseTag.standing => l.poseTagStanding,
  PoseTag.sitting => l.poseTagSitting,
  PoseTag.armsUp => l.poseTagArmsUp,
  PoseTag.oneArmUp => l.poseTagOneArmUp,
  PoseTag.armsSpread => l.poseTagArmsSpread,
  PoseTag.handsOnHips => l.poseTagHandsOnHips,
  PoseTag.frontal => l.poseTagFrontal,
  PoseTag.profile => l.poseTagProfile,
  PoseTag.back => l.poseTagBack,
  _ => tag,
};

class PoseDiagram extends StatelessWidget {
  const PoseDiagram({super.key, this.tag, this.group, this.area});
  final String? tag, area;
  final GroupPoseFeature? group;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PosePainter(
      Theme.of(context).colorScheme,
      tag: tag,
      group: group,
      area: area,
    ),
    child: const SizedBox.expand(),
  );
}

const _bones = [
  (5, 6),
  (5, 7),
  (7, 9),
  (6, 8),
  (8, 10),
  (5, 11),
  (6, 12),
  (11, 12),
  (11, 13),
  (13, 15),
  (12, 14),
  (14, 16),
  (0, 5),
  (0, 6),
];

class _PosePainter extends CustomPainter {
  _PosePainter(this.scheme, {this.tag, this.group, this.area});
  final ColorScheme scheme;
  final String? tag, area;
  final GroupPoseFeature? group;
  @override
  void paint(Canvas canvas, Size size) {
    final groups = <List<Offset>>[];
    final masks = <int>[];
    if (group != null) {
      for (final m in group!.members) {
        groups.add([
          for (var i = 0; i < 17; i++) Offset(m.data[2 * i], m.data[2 * i + 1]),
        ]);
        masks.add(m.mask);
      }
    } else {
      final p = <Offset>[
        const Offset(.5, .12),
        const Offset(.54, .1),
        const Offset(.46, .1),
        const Offset(.58, .12),
        const Offset(.42, .12),
        const Offset(.65, .28),
        const Offset(.35, .28),
        const Offset(.73, .46),
        const Offset(.27, .46),
        const Offset(.74, .64),
        const Offset(.26, .64),
        const Offset(.59, .57),
        const Offset(.41, .57),
        const Offset(.61, .75),
        const Offset(.39, .75),
        const Offset(.65, .95),
        const Offset(.35, .95),
      ];
      if (tag == PoseTag.armsUp || tag == PoseTag.oneArmUp) {
        p[7] = const Offset(.77, .15);
        p[9] = const Offset(.8, 0);
        if (tag == PoseTag.armsUp) {
          p[8] = const Offset(.23, .15);
          p[10] = const Offset(.2, 0);
        }
      }
      if (tag == PoseTag.armsSpread) {
        p[7] = const Offset(.82, .28);
        p[9] = const Offset(1, .28);
        p[8] = const Offset(.18, .28);
        p[10] = const Offset(0, .28);
      }
      if (tag == PoseTag.handsOnHips) {
        p[7] = const Offset(.86, .43);
        p[9] = p[11];
        p[8] = const Offset(.14, .43);
        p[10] = p[12];
      }
      if (tag == PoseTag.sitting) {
        p[13] = const Offset(.83, .6);
        p[15] = const Offset(.86, .9);
        p[14] = const Offset(.26, .6);
        p[16] = const Offset(.23, .9);
      }
      if (tag == PoseTag.profile) {
        for (var i = 0; i < p.length; i++) {
          p[i] = Offset(.5 + (p[i].dx - .5) * .4, p[i].dy);
        }
        p[0] = const Offset(.66, .12);
      }
      groups.add(
        tag == PoseTag.lying
            ? [for (final point in p) Offset(point.dy, 1 - point.dx)]
            : p,
      );
      masks.add((1 << 17) - 1);
    }
    final visible = <Offset>[
      for (var g = 0; g < groups.length; g++)
        for (var i = 0; i < 17; i++)
          if (masks[g] & (1 << i) != 0) groups[g][i],
    ];
    if (visible.isEmpty) return;
    final minX = visible.map((p) => p.dx).reduce(math.min),
        maxX = visible.map((p) => p.dx).reduce(math.max);
    final minY = visible.map((p) => p.dy).reduce(math.min),
        maxY = visible.map((p) => p.dy).reduce(math.max);
    final scale = math.min(
      (size.width - 16) / math.max(.1, maxX - minX),
      (size.height - 16) / math.max(.1, maxY - minY),
    );
    Offset fit(Offset p) => Offset(
      size.width / 2 + (p.dx - (minX + maxX) / 2) * scale,
      size.height / 2 + (p.dy - (minY + maxY) / 2) * scale,
    );
    for (var g = 0; g < groups.length; g++) {
      final paint = Paint()
        ..color = (g.isEven ? scheme.primary : scheme.secondary)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;
      final points = groups[g].map(fit).toList();
      for (final (a, b) in _bones) {
        if (masks[g] & (1 << a) != 0 && masks[g] & (1 << b) != 0) {
          canvas.drawLine(points[a], points[b], paint);
        }
      }
      if (masks[g] & 1 != 0) {
        canvas.drawCircle(
          points[0],
          4.5,
          Paint()
            ..color = paint.color
            ..style = tag == PoseTag.back
                ? PaintingStyle.stroke
                : PaintingStyle.fill
            ..strokeWidth = 2,
        );
      }
      if (area != null) {
        final chest = Offset.lerp(points[Kp.lShoulder], points[Kp.rHip], .45)!;
        final lower = Offset.lerp(points[Kp.lHip], points[Kp.rHip], .5)!;
        canvas.drawOval(
          Rect.fromCenter(
            center: area == 'chest' ? chest : lower,
            width: scale * .32,
            height: scale * .23,
          ),
          Paint()..color = scheme.primary.withValues(alpha: .3),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PosePainter old) =>
      old.scheme != scheme ||
      old.tag != tag ||
      old.group != group ||
      old.area != area;
}

final _groupPhotoProvider = FutureProvider.autoDispose
    .family<Uint8List?, String>((ref, asset) async {
      try {
        return await ref
            .watch(mediaLibraryProvider)
            .viewerImage(asset, maxSide: 1000);
      } catch (_) {
        return null;
      }
    });

/// The complete photo preserves interactions that disappear in individual crops.
class GroupPhotoPreview extends ConsumerWidget {
  const GroupPhotoPreview({super.key, required this.assetId, this.feature});
  final String assetId;
  final GroupPoseFeature? feature;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(_groupPhotoProvider(assetId))
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => PoseDiagram(group: feature),
        data: (bytes) => bytes == null
            ? PoseDiagram(group: feature)
            : ImageExpand(
                source: ImagePreviewSource.asset(assetId),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
      );
}
