import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class SmartImageThumb {
  const SmartImageThumb({
    required this.rgbaBytes,
    required this.width,
    required this.height,
  });

  final Uint8List rgbaBytes;
  final int width;
  final int height;
}

class SmartSelector {
  /// Extracts downscaled RGBA thumbnail from a [ui.Image] for instant flood-fill.
  static Future<SmartImageThumb> createThumbnail(
    ui.Image image, {
    int maxDimension = 256,
  }) async {
    final aspect = image.width / image.height;
    int thumbW, thumbH;
    if (aspect >= 1.0) {
      thumbW = maxDimension;
      thumbH = (maxDimension / aspect).round().clamp(32, maxDimension);
    } else {
      thumbH = maxDimension;
      thumbW = (maxDimension * aspect).round().clamp(32, maxDimension);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, thumbW.toDouble(), thumbH.toDouble()),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, thumbW.toDouble(), thumbH.toDouble()),
      Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final thumbImage = await picture.toImage(thumbW, thumbH);
    final byteData = await thumbImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = byteData!.buffer.asUint8List();

    return SmartImageThumb(
      rgbaBytes: bytes,
      width: thumbW,
      height: thumbH,
    );
  }

  /// Performs fast BFS color-region flood-fill starting from [seedNorm] (0..1, 0..1).
  ///
  /// [tolerance] is between 0.05 and 0.50 (default 0.22).
  /// Returns a list of normalized Rects (0..1) covering the selected area.
  static List<Rect> floodSelect({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    required Offset seedNorm,
    double tolerance = 0.22,
    bool dilate = true,
  }) {
    if (width <= 0 || height <= 0 || rgbaBytes.length < width * height * 4) {
      return [];
    }

    final startX = (seedNorm.dx * (width - 1)).round().clamp(0, width - 1);
    final startY = (seedNorm.dy * (height - 1)).round().clamp(0, height - 1);

    final seedIdx = (startY * width + startX) * 4;
    final seedR = rgbaBytes[seedIdx];
    final seedG = rgbaBytes[seedIdx + 1];
    final seedB = rgbaBytes[seedIdx + 2];
    final seedA = rgbaBytes[seedIdx + 3];

    if (seedA < 10) return [];

    // Max color distance squared: 255^2 * 3 = 195075
    final thresholdSq = (tolerance * tolerance * 195075.0).round();

    final totalPixels = width * height;
    final visited = Uint8List(totalPixels);
    final queue = Int32List(totalPixels);
    var head = 0;
    var tail = 0;

    final startPos = startY * width + startX;
    visited[startPos] = 1;
    queue[tail++] = startPos;

    while (head < tail) {
      final pos = queue[head++];
      final cy = pos ~/ width;
      final cx = pos % width;

      // 4-connected neighbors
      for (var d = 0; d < 4; d++) {
        int nx = cx;
        int ny = cy;
        if (d == 0) {
          nx = cx - 1;
        } else if (d == 1) {
          nx = cx + 1;
        } else if (d == 2) {
          ny = cy - 1;
        } else {
          ny = cy + 1;
        }

        if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;

        final nPos = ny * width + nx;
        if (visited[nPos] == 1) continue;

        final nIdx = nPos * 4;
        final nr = rgbaBytes[nIdx];
        final ng = rgbaBytes[nIdx + 1];
        final nb = rgbaBytes[nIdx + 2];
        final na = rgbaBytes[nIdx + 3];

        if (na < 10) continue;

        final dr = nr - seedR;
        final dg = ng - seedG;
        final db = nb - seedB;
        final distSq = dr * dr + dg * dg + db * db;

        if (distSq <= thresholdSq) {
          visited[nPos] = 1;
          queue[tail++] = nPos;
        }
      }
    }

    if (tail == 0) return [];

    // Optional 1-pixel dilation to cleanly cover fabric/edge seams
    Uint8List finalMask = visited;
    if (dilate && tail > 2) {
      final dilated = Uint8List(totalPixels);
      for (var y = 0; y < height; y++) {
        final row = y * width;
        for (var x = 0; x < width; x++) {
          if (visited[row + x] == 1) {
            dilated[row + x] = 1;
            if (x > 0) dilated[row + x - 1] = 1;
            if (x < width - 1) dilated[row + x + 1] = 1;
            if (y > 0) dilated[(y - 1) * width + x] = 1;
            if (y < height - 1) dilated[(y + 1) * width + x] = 1;
          }
        }
      }
      finalMask = dilated;
    }

    // Convert binary mask to run-length horizontal Rects in normalized coords
    final rects = <Rect>[];
    final invW = 1.0 / width;
    final invH = 1.0 / height;

    for (var y = 0; y < height; y++) {
      final row = y * width;
      int? runStart;
      for (var x = 0; x < width; x++) {
        if (finalMask[row + x] == 1) {
          runStart ??= x;
        } else if (runStart != null) {
          rects.add(Rect.fromLTRB(
            runStart * invW,
            y * invH,
            x * invW,
            (y + 1) * invH,
          ));
          runStart = null;
        }
      }
      if (runStart != null) {
        rects.add(Rect.fromLTRB(
          runStart * invW,
          y * invH,
          1.0,
          (y + 1) * invH,
        ));
      }
    }

    return rects;
  }
}
