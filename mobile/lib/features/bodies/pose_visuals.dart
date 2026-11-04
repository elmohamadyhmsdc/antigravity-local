import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/pose/group_pose_matcher.dart';
import '../../domain/pose/pose_geometry.dart';
import '../../domain/pose/pose_rules.dart';
import '../../data/files/crop_cache.dart' show cropPixels, CropKind;
import '../../library_providers.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';
import '../shared/image_preview.dart';

String poseLabel(AppLocalizations l, String tag) => switch (tag) {
  PoseTag.lying => l.poseTagLying,
  PoseTag.standing => l.poseTagStanding,
  PoseTag.sitting => l.poseTagSitting,
  PoseTag.bent => l.discoveryBent,
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
      if (tag == PoseTag.bent) {
        for (var i = 0; i < 11; i++) {
          p[i] = p[i] + const Offset(.23, .12);
        }
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

/// Visual crop viewer with toggleable pose skeleton wireframe and area highlights.
class BodyCropAnnotatedView extends StatelessWidget {
  const BodyCropAnnotatedView({
    super.key,
    this.cropPath,
    this.kpts,
    this.bbox,
    this.imageSize,
    this.showSkeleton = false,
    this.showArea = false,
    this.area,
    this.fit = BoxFit.contain,
  });

  final String? cropPath;
  final String? kpts;
  final ({double x, double y, double w, double h})? bbox;
  final Size? imageSize;
  final bool showSkeleton;
  final bool showArea;
  final String? area;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        CropImage(
          path: cropPath,
          fit: fit,
          placeholderIcon: Icons.accessibility_new,
          expandable: false,
          cacheWidth: 768,
        ),
        if ((showSkeleton || showArea) && kpts != null && bbox != null)
          CustomPaint(
            key: const Key('body-crop-skeleton-painter'),
            painter: _BodyCropOverlayPainter(
              scheme: scheme,
              kpts: kpts!,
              bbox: bbox!,
              imageSize: imageSize,
              fit: fit,
              showSkeleton: showSkeleton,
              showArea: showArea,
              area: area,
            ),
          ),
      ],
    );
  }
}

class _BodyCropOverlayPainter extends CustomPainter {
  _BodyCropOverlayPainter({
    required this.scheme,
    required this.kpts,
    required this.bbox,
    required this.showSkeleton,
    required this.showArea,
    required this.fit,
    this.imageSize,
    this.area,
  });

  final ColorScheme scheme;
  final String kpts;
  final ({double x, double y, double w, double h}) bbox;
  final bool showSkeleton;
  final bool showArea;
  final String? area;
  final Size? imageSize;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final List<dynamic> raw;
    try {
      raw = jsonDecode(kpts) as List<dynamic>;
      if (raw.any(
        (p) =>
            p is! List ||
            p.length != 3 ||
            p.any((v) => v is! num || !v.isFinite),
      )) {
        return;
      }
    } catch (_) {
      return;
    }
    if (raw.length != 17 || bbox.w <= 0 || bbox.h <= 0) return;

    final points = <Offset>[];
    final visible = <bool>[];

    for (final item in raw) {
      final list = item as List<dynamic>;
      final x = (list[0] as num).toDouble();
      final y = (list[1] as num).toDouble();
      final score = (list[2] as num).toDouble();

      points.add(
        bodyCropOverlayPoint(Offset(x, y), bbox, imageSize, size, fit),
      );
      visible.add(score >= keypointVisible);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    if (showArea && area != null && points.length == 17) {
      final areaPaint = Paint()
        ..color = Colors.amberAccent.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      final borderPaint = Paint()
        ..color = Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      if (area == 'chest' && visible[Kp.lShoulder] && visible[Kp.rShoulder]) {
        final shoulderMid = Offset(
          (points[Kp.lShoulder].dx + points[Kp.rShoulder].dx) / 2,
          (points[Kp.lShoulder].dy + points[Kp.rShoulder].dy) / 2,
        );
        final hipMid = (visible[Kp.lHip] && visible[Kp.rHip])
            ? Offset(
                (points[Kp.lHip].dx + points[Kp.rHip].dx) / 2,
                (points[Kp.lHip].dy + points[Kp.rHip].dy) / 2,
              )
            : Offset(shoulderMid.dx, shoulderMid.dy + size.height * 0.3);
        final center = Offset.lerp(shoulderMid, hipMid, 0.45)!;
        final span = (points[Kp.rShoulder].dx - points[Kp.lShoulder].dx).abs();
        final rect = Rect.fromCenter(
          center: center,
          width: math.max(span * 0.85, size.width * 0.35),
          height: size.height * 0.25,
        );
        canvas.drawOval(rect, areaPaint);
        canvas.drawOval(rect, borderPaint);
      } else if ((area == 'lower' || area == 'buttocks') &&
          visible[Kp.lHip] &&
          visible[Kp.rHip]) {
        final hipMid = Offset(
          (points[Kp.lHip].dx + points[Kp.rHip].dx) / 2,
          (points[Kp.lHip].dy + points[Kp.rHip].dy) / 2,
        );
        final kneeMid = (visible[Kp.lKnee] && visible[Kp.rKnee])
            ? Offset(
                (points[Kp.lKnee].dx + points[Kp.rKnee].dx) / 2,
                (points[Kp.lKnee].dy + points[Kp.rKnee].dy) / 2,
              )
            : Offset(hipMid.dx, hipMid.dy + size.height * 0.25);
        final center = Offset.lerp(hipMid, kneeMid, 0.45)!;
        final span = (points[Kp.rHip].dx - points[Kp.lHip].dx).abs();
        final rect = Rect.fromCenter(
          center: center,
          width: math.max(span * 0.95, size.width * 0.35),
          height: size.height * 0.22,
        );
        canvas.drawOval(rect, areaPaint);
        canvas.drawOval(rect, borderPaint);
      }
    }

    if (showSkeleton) {
      final bonePaint = Paint()
        ..color = scheme.primary
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;

      final glowPaint = Paint()
        ..color = scheme.primary.withValues(alpha: 0.35)
        ..strokeWidth = 6.0
        ..strokeCap = StrokeCap.round;

      for (final (a, b) in _bones) {
        if (visible[a] && visible[b]) {
          canvas.drawLine(points[a], points[b], glowPaint);
          canvas.drawLine(points[a], points[b], bonePaint);
        }
      }

      final jointPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final jointBorder = Paint()
        ..color = scheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (var i = 0; i < 17; i++) {
        if (visible[i]) {
          canvas.drawCircle(points[i], 4.5, jointPaint);
          canvas.drawCircle(points[i], 4.5, jointBorder);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodyCropOverlayPainter old) =>
      old.kpts != kpts ||
      old.bbox != bbox ||
      old.showSkeleton != showSkeleton ||
      old.showArea != showArea ||
      old.area != area ||
      old.imageSize != imageSize ||
      old.fit != fit ||
      old.scheme != scheme;
}

/// Uses the exact padded crop framing and the same BoxFit as the image. Do not
/// clamp points to the crop edge: that would invent joints along its border.
Offset bodyCropOverlayPoint(
  Offset point,
  ({double x, double y, double w, double h}) box,
  Size? imageSize,
  Size viewport,
  BoxFit fit,
) {
  if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
    return Offset(
      (point.dx - box.x) / box.w * viewport.width,
      (point.dy - box.y) / box.h * viewport.height,
    );
  }
  final crop = cropPixels(
    CropKind.body,
    box,
    imageSize.width.round(),
    imageSize.height.round(),
  );
  final source = Size(crop.outWidth.toDouble(), crop.outHeight.toDouble());
  final fitted = applyBoxFit(fit, source, viewport);
  final src = Alignment.center.inscribe(fitted.source, Offset.zero & source);
  final dst = Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & viewport,
  );
  final x =
      (point.dx * imageSize.width - crop.left) / crop.width * source.width;
  final y =
      (point.dy * imageSize.height - crop.top) / crop.height * source.height;
  return Offset(
    dst.left + (x - src.left) / src.width * dst.width,
    dst.top + (y - src.top) / src.height * dst.height,
  );
}
