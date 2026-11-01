/// Roadmap 7.4: the real photo-patch cutter. Cuts a rotated rectangle (a [MarkRect], in the pixels of the
/// photo as the database knows it) out of the ORIGINAL photo, turned upright so the segment axis runs left to
/// right, at most [maxOutput] px on the long side. PNG, because dart:ui has no JPEG encoder; the PC decodes
/// either by content.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import 'mark_geometry.dart';

const markPatchMaxOutput = 384;
const markPatchMinSide = 24;

/// The viewer-quality original (up to [originalMaxSide] px) is decoded once per call; null when the photo is gone.
class UiPatchCutter {
  UiPatchCutter(this._library, {this.originalMaxSide = 4096});

  final MediaLibrary _library;
  final int originalMaxSide;

  Future<Uint8List?> call(MediaRow media, MarkRect rect) async {
    final bytes = await _library.viewerImage(
      media.assetId,
      maxSide: originalMaxSide,
    );
    if (bytes == null) return null;
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      // the rectangle is in the pixels of the stored frame (media.width x height); the decoded image may be smaller
      final sx = image.width / (media.width ?? image.width);
      final sy = image.height / (media.height ?? image.height);
      final w = rect.width * sx, h = rect.height * sy;
      if (w < markPatchMinSide || h < markPatchMinSide) return null;
      final k = math.min(1.0, markPatchMaxOutput / math.max(w, h));
      final outW = math.max(1, (w * k).round()),
          outH = math.max(1, (h * k).round());
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(outW / 2, outH / 2);
      canvas.scale(k);
      canvas.rotate(-rect.angleDegrees * math.pi / 180);
      canvas.translate(-rect.cx * sx, -rect.cy * sy);
      canvas.drawImage(
        image,
        ui.Offset.zero,
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final out = await recorder.endRecording().toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}
