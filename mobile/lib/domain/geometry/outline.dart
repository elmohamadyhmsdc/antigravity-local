import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../data/api/dtos/analyze.dart';

/// Encodes outline points to box-relative flat JSON.
///
/// Returns null if [px] is null, has fewer than 3 points, or [box] has zero/negative size.
String? encodeOutline(List<Offset>? px, BBox box) {
  if (px == null || px.length < 3 || box.w <= 0 || box.h <= 0) {
    return null;
  }
  final flat = <double>[];
  final bool isImageRelative = px.any(
    (p) => p.dx > box.w + 0.05 && box.x > 0.05,
  );
  for (final p in px) {
    var relX = isImageRelative ? (p.dx - box.x) / box.w : p.dx;
    var relY = isImageRelative ? (p.dy - box.y) / box.h : p.dy;
    relX = relX.clamp(-0.25, 1.25);
    relY = relY.clamp(-0.25, 1.25);
    flat.add(double.parse(relX.toStringAsFixed(3)));
    flat.add(double.parse(relY.toStringAsFixed(3)));
  }
  return jsonEncode(flat);
}

/// Decodes box-relative flat JSON back to a list of [Offset] points.
///
/// Returns null if [text] is null, empty, or malformed. Never throws.
List<Offset>? decodeOutline(String? text) {
  if (text == null) return null;
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! List || decoded.length < 6 || decoded.length % 2 != 0) {
      return null;
    }
    final points = <Offset>[];
    for (var i = 0; i < decoded.length; i += 2) {
      final x = decoded[i];
      final y = decoded[i + 1];
      if (x is! num || y is! num) return null;
      final dx = x.toDouble();
      final dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite) return null;
      points.add(Offset(dx, dy));
    }
    return points;
  } catch (_) {
    return null;
  }
}

/// Builds a smooth closed [Path] for a detection within [box].
///
/// If [outline] is provided (box-relative coordinates), maps it to [box]
/// and builds a closed cubic Bézier spline (Catmull-Rom with tension 0.5).
/// Otherwise falls back to an oval (for faces) or rounded rectangle (for bodies).
Path detectionPath(Rect box, {List<Offset>? outline, required bool isFace}) {
  final path = Path();
  if (outline != null && outline.length >= 3) {
    final mapped = [
      for (final p in outline)
        Offset(box.left + p.dx * box.width, box.top + p.dy * box.height),
    ];
    final n = mapped.length;
    path.moveTo(mapped[0].dx, mapped[0].dy);
    for (var i = 0; i < n; i++) {
      final pPrev = mapped[(i - 1 + n) % n];
      final pCurr = mapped[i];
      final pNext = mapped[(i + 1) % n];
      final pAfter = mapped[(i + 2) % n];
      final c1 = pCurr + (pNext - pPrev) / 6.0;
      final c2 = pNext - (pAfter - pCurr) / 6.0;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, pNext.dx, pNext.dy);
    }
    path.close();
    return path;
  }

  if (isFace) {
    path.addOval(box);
  } else {
    final shorter = box.width < box.height ? box.width : box.height;
    path.addRRect(
      RRect.fromRectAndRadius(box, Radius.circular(shorter * 0.08)),
    );
  }
  return path;
}

/// CustomPainter rendering a face or body detection overlay using [detectionPath].
class DetectionBoxPainter extends CustomPainter {
  const DetectionBoxPainter({
    required this.isFace,
    this.outline,
    this.fillColor,
    required this.borderColor,
    this.borderWidth = 2.0,
  });

  final bool isFace;
  final List<Offset>? outline;
  final Color? fillColor;
  final Color borderColor;
  final double borderWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = detectionPath(
      Offset.zero & size,
      outline: outline,
      isFace: isFace,
    );
    if (fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = fillColor!
          ..style = PaintingStyle.fill,
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );
  }

  @override
  bool shouldRepaint(DetectionBoxPainter oldDelegate) =>
      oldDelegate.isFace != isFace ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      !listEquals(oldDelegate.outline, outline);
}
