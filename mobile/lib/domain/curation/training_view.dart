import 'dart:typed_data';

import '../../data/platform/crop_source.dart';
import '../export/crop_math.dart';
import '../geometry/outline.dart';
import 'auto_dataset_curator.dart';

/// Cut the selected occurrence from upright original pixels, including its
/// timestamp for video. The PC uses the view label to verify and caption it.
Future<({Uint8List jpeg, String view, List<double>? outline})?>
readTrainingView(CropSource source, CurationCandidate c) async {
  final x = c.boxX, y = c.boxY, w = c.boxW, h = c.boxH;
  if (c.refId == null ||
      x == null ||
      y == null ||
      w == null ||
      h == null ||
      [x, y, w, h].any((v) => !v.isFinite) ||
      w <= 0 ||
      h <= 0 ||
      x < 0 ||
      y < 0 ||
      x + w > 1.001 ||
      y + h > 1.001 ||
      (c.isVideo && (c.timestampMs == null || c.timestampMs! < 0))) {
    return null;
  }
  final frame = await source.open(
    assetId: c.assetId,
    video: c.isVideo,
    timeMs: c.timestampMs,
  );
  if (frame == null) return null;
  final face = c.category == CurationCategory.face;
  final plan = bodyCrop(
    x: x,
    y: y,
    w: w,
    h: h,
    imgW: frame.width,
    imgH: frame.height,
    longSide: face ? 1024 : 1536,
    margin: face ? 1.6 : 1.0,
  );
  if (plan == null) return null;
  final jpeg = await source.crop(
    frame,
    plan.source,
    outWidth: plan.outWidth,
    outHeight: plan.outHeight,
  );
  if (jpeg == null || jpeg.isEmpty) return null;
  final points = face ? null : decodeOutline(c.outline);
  List<double>? outline;
  if (points != null && points.length >= 3) {
    final stride = (points.length / 96).ceil();
    outline = [
      for (var i = 0; i < points.length; i += stride) ...[
        (((x + points[i].dx * w) * frame.width - plan.source.left) /
                plan.source.width)
            .clamp(0.0, 1.0),
        (((y + points[i].dy * h) * frame.height - plan.source.top) /
                plan.source.height)
            .clamp(0.0, 1.0),
      ],
    ];
  }
  return (
    jpeg: jpeg,
    view: face
        ? 'portrait'
        : c.manualBody
        ? 'confirmed_body'
        : 'body',
    outline: outline,
  );
}
