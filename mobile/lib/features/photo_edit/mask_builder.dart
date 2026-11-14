import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'selection_model.dart';

class MaskBuilder {
  /// Builds a PNG mask where selected pixels are 255 (white) and unselected pixels are 0 (black).
  static Future<Uint8List> buildMaskPng(
    SelectionModel model, {
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Initial background: solid black (0)
    final bgPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    final fgPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final eraserPaint = Paint()
      ..color = const Color(0xFF000000)
      ..blendMode = BlendMode.src
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    final fillEraser = Paint()
      ..color = const Color(0xFF000000)
      ..blendMode = BlendMode.src
      ..style = PaintingStyle.fill;

    for (final stroke in model.strokes) {
      if (stroke.filledRects != null && stroke.filledRects!.isNotEmpty) {
        final p = stroke.isEraser ? fillEraser : fillPaint;
        for (final r in stroke.filledRects!) {
          canvas.drawRect(
            Rect.fromLTRB(
              r.left * width,
              r.top * height,
              r.right * width,
              r.bottom * height,
            ),
            p,
          );
        }
      }

      if (stroke.points.isNotEmpty) {
        final strokeWidth = stroke.radius * 2 * width;
        final paint = stroke.isEraser
            ? (eraserPaint..strokeWidth = strokeWidth)
            : (fgPaint..strokeWidth = strokeWidth);

        if (stroke.points.length == 1) {
          final p = Offset(
            stroke.points[0].dx * width,
            stroke.points[0].dy * height,
          );
          canvas.drawCircle(
            p,
            stroke.radius * width,
            stroke.isEraser ? fillEraser : fillPaint,
          );
        } else {
          final path = Path();
          final first = Offset(
            stroke.points[0].dx * width,
            stroke.points[0].dy * height,
          );
          path.moveTo(first.dx, first.dy);
          for (var i = 1; i < stroke.points.length; i++) {
            final pt = Offset(
              stroke.points[i].dx * width,
              stroke.points[i].dy * height,
            );
            path.lineTo(pt.dx, pt.dy);
          }
          canvas.drawPath(path, paint);
        }
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
