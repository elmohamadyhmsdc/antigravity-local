import 'dart:math' as math;

/// An integer pixel rectangle (left/top inclusive, [width] x [height]).
class PxRect {
  const PxRect(this.left, this.top, this.width, this.height);

  final int left, top, width, height;

  int get right => left + width;
  int get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is PxRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'PxRect($left, $top, $width x $height)';
}

/// What to cut from one decoded original and how large the written image is.
class CropPlan {
  const CropPlan({
    required this.source,
    required this.outWidth,
    required this.outHeight,
  });

  /// In the upright (EXIF-rotated) pixel space of the original.
  final PxRect source;
  final int outWidth, outHeight;

  /// Output pixels per source pixel (> 1 means the crop is enlarged).
  double get scale => outWidth / source.width;
}

/// Pixel size of a normalised box inside an image of [imgW] x [imgH].
({double width, double height}) boxPixels(
  double w,
  double h,
  int imgW,
  int imgH,
) => (width: w * imgW, height: h * imgH);

/// A square crop around a face box, enlarged by [margin] (1.6 = 60 % more than the face's
/// longer side), moved inside the image instead of padded. Null when the box does not fit
/// (the image is smaller than the face box itself) or the crop would have to be enlarged by
/// more than [maxUpscale] to reach [outSize].
CropPlan? faceCrop({
  required double x,
  required double y,
  required double w,
  required double h,
  required int imgW,
  required int imgH,
  required int outSize,
  double margin = 1.6,
  double maxUpscale = 2.0,
}) {
  if (imgW <= 0 || imgH <= 0 || outSize <= 0 || w <= 0 || h <= 0) return null;
  final bw = w * imgW, bh = h * imgH;
  final cx = (x + w / 2) * imgW, cy = (y + h / 2) * imgH;
  final face = math.max(bw, bh);
  final limit = math.min(imgW, imgH).toDouble();
  final side = math.min(face * margin, limit);
  if (side < face - 0.5) {
    return null; // the face itself does not fit in a square
  }
  final left = (cx - side / 2).clamp(0.0, imgW - side).toDouble();
  final top = (cy - side / 2).clamp(0.0, imgH - side).toDouble();
  final s = side.round().clamp(1, math.min(imgW, imgH)).toInt();
  final l = left.round().clamp(0, imgW - s).toInt();
  final t = top.round().clamp(0, imgH - s).toInt();
  if (outSize / s > maxUpscale) return null;
  return CropPlan(
    source: PxRect(l, t, s, s),
    outWidth: outSize,
    outHeight: outSize,
  );
}

/// The body box enlarged by [margin] on every side (1.1 = 10 %), clamped to the image. The
/// aspect ratio is kept. The long side of the output is [longSide], but the crop is never
/// enlarged: a smaller original gives a smaller image.
CropPlan? bodyCrop({
  required double x,
  required double y,
  required double w,
  required double h,
  required int imgW,
  required int imgH,
  required int longSide,
  double margin = 1.1,
}) {
  if (imgW <= 0 || imgH <= 0 || longSide <= 0 || w <= 0 || h <= 0) return null;
  final bw = w * imgW * margin, bh = h * imgH * margin;
  final cx = (x + w / 2) * imgW, cy = (y + h / 2) * imgH;
  final l = (cx - bw / 2).clamp(0.0, imgW.toDouble()).toDouble();
  final t = (cy - bh / 2).clamp(0.0, imgH.toDouble()).toDouble();
  final r = (cx + bw / 2).clamp(0.0, imgW.toDouble()).toDouble();
  final b = (cy + bh / 2).clamp(0.0, imgH.toDouble()).toDouble();
  // 1e-6: float noise (239.99999...) must not widen the crop by a pixel
  final left = (l + 1e-6).floor(), top = (t + 1e-6).floor();
  final width = math.min(imgW - left, ((r - 1e-6).ceil() - left)),
      height = math.min(imgH - top, ((b - 1e-6).ceil() - top));
  if (width < 1 || height < 1) return null;
  final scale = math.min(1.0, longSide / math.max(width, height));
  return CropPlan(
    source: PxRect(left, top, width, height),
    outWidth: math.max(1, (width * scale).round()),
    outHeight: math.max(1, (height * scale).round()),
  );
}

/// Dimensions of the upright image for a file stored as [rawW] x [rawH] with EXIF [orientation].
({int width, int height}) uprightSize(int rawW, int rawH, int orientation) =>
    orientation >= 5 && orientation <= 8
    ? (width: rawH, height: rawW)
    : (width: rawW, height: rawH);

/// The rectangle of the *stored* pixels that shows [upright] once EXIF [orientation] (1..8) is
/// applied. Region decoders cut the stored pixels; the boxes in the database are upright.
PxRect uprightToRaw(PxRect upright, int orientation, int rawW, int rawH) {
  final x0 = upright.left,
      y0 = upright.top,
      x1 = upright.right,
      y1 = upright.bottom;
  // Edge coordinates (0..W, 0..H) of the stored image for an upright point (x, y).
  (int, int) raw(int x, int y) => switch (orientation) {
    2 => (rawW - x, y),
    3 => (rawW - x, rawH - y),
    4 => (x, rawH - y),
    5 => (y, x),
    6 => (y, rawH - x),
    7 => (rawW - y, rawH - x),
    8 => (rawW - y, x),
    _ => (x, y),
  };
  final a = raw(x0, y0), b = raw(x1, y1);
  final l = math.min(a.$1, b.$1), t = math.min(a.$2, b.$2);
  return PxRect(l, t, (a.$1 - b.$1).abs(), (a.$2 - b.$2).abs());
}
