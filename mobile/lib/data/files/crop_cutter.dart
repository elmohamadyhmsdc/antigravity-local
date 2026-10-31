import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../media/media_library.dart';
import '../platform/video_frames.dart';
import 'crop_cache.dart';

/// Decodes [source] with the engine, draws the crop at its preview size and encodes a JPEG.
Future<Uint8List?> cutCrop(
  Uint8List source,
  CropKind kind,
  ({double x, double y, double w, double h}) box,
) async {
  final codec = await ui.instantiateImageCodec(source);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  ui.Image? out;
  try {
    final r = cropPixels(kind, box, image.width, image.height);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(
        r.left.toDouble(),
        r.top.toDouble(),
        r.width.toDouble(),
        r.height.toDouble(),
      ),
      Rect.fromLTWH(0, 0, r.outWidth.toDouble(), r.outHeight.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    out = await picture.toImage(r.outWidth, r.outHeight);
    picture.dispose();
    final png = await out.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return await FlutterImageCompress.compressWithList(
      png.buffer.asUint8List(),
      minWidth: r.outWidth,
      minHeight: r.outHeight,
      quality: 85,
      format: CompressFormat.jpeg,
    );
  } finally {
    image.dispose();
    out?.dispose();
  }
}

/// Originals as the scan analysed them: photos through the same upright preview the Review viewer
/// draws its boxes on, video frames through the scan's own decoder (it reopens per video, so a
/// running scan only pays one reopen).
OriginalLoader originalLoader(MediaLibrary media, LocalVideoFrames? frames) =>
    (assetId, video, timestampMs) async {
      if (!video) return media.viewerImage(assetId, maxSide: 2048);
      if (frames == null) return null;
      final out = await frames.frames(assetId, [timestampMs ?? 0]);
      return out.isEmpty ? null : out.first;
    };
