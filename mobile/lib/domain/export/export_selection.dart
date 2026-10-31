import 'dart:math' as math;

enum ExportKind { face, body }

/// One stored detection of the chosen person, with what the choice needs to rank it.
/// Boxes are normalised to the upright original; [quality] is 0..1 (face quality, body score).
class ExportCandidate {
  const ExportCandidate({
    required this.detectionId,
    required this.kind,
    required this.mediaId,
    required this.assetId,
    required this.isVideo,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.quality,
    this.refId,
    this.timestampMs,
    this.frameNumber,
    this.yaw,
    this.pitch,
    this.imgW,
    this.imgH,
    this.durationMs,
    this.extent,
  });

  final int detectionId;
  final ExportKind kind;
  final int mediaId;
  final String assetId;
  final bool isVideo;
  final double x, y, w, h;
  final double quality;

  /// The face/body row this detection points at.
  final int? refId;
  final int? timestampMs;
  final int? frameNumber;
  final double? yaw, pitch;

  /// Original size as the media row records it (a hint: the real size is read when exporting).
  final int? imgW, imgH;
  final int? durationMs;

  /// Bodies: full | knee | upper | head.
  final String? extent;

  /// Both kinds of one frame share one decode.
  String get frameKey => '$mediaId@${timestampMs ?? -1}';

  double get boxArea => w * h;
}

class ExportSelectionOptions {
  const ExportSelectionOptions({
    this.maxPerVideo = 40,
    this.minGapMs = 1000,
    this.minFaceBoxPx = 96,
    this.minBodyHeightPx = 384,
    this.poseWeight = 1.0,
  });

  /// Rows kept per video and kind. Photos always keep one detection per kind.
  final int maxPerVideo;

  /// Two picks of one video are at least this far apart in time while enough frames remain.
  final int minGapMs;

  /// Boxes whose shorter (face) / taller (body) side is below this in the original are dropped.
  final int minFaceBoxPx;
  final int minBodyHeightPx;

  /// How much a different head pose is worth next to a different moment (1.0 = equal).
  final double poseWeight;
}

/// Weight of a body by how much of the person it shows.
double extentWeight(String? extent) => switch (extent) {
  'full' => 1.0,
  'knee' => 0.9,
  'upper' => 0.75,
  'head' => 0.0, // a head is not a body picture
  _ => 0.85,
};

bool _fits(ExportCandidate c, ExportSelectionOptions o) {
  final iw = c.imgW, ih = c.imgH;
  if (c.kind == ExportKind.body && extentWeight(c.extent) == 0) return false;
  if (iw == null || ih == null || iw <= 0 || ih <= 0) return true;
  // The record may hold the stored (not upright) size: judge by the better reading.
  final a = c.kind == ExportKind.face ? math.min(c.w * iw, c.h * ih) : c.h * ih;
  final b = c.kind == ExportKind.face ? math.min(c.w * ih, c.h * iw) : c.h * iw;
  final px = math.max(a, b);
  return px >= (c.kind == ExportKind.face ? o.minFaceBoxPx : o.minBodyHeightPx);
}

double _rank(ExportCandidate c) {
  // Quality first; among equals the larger box (more pixels) wins.
  final weight = c.kind == ExportKind.body ? extentWeight(c.extent) : 1.0;
  return c.quality * weight + c.boxArea * 0.05;
}

/// The pose distance between two faces (0 for bodies / unknown pose).
double _poseDistance(ExportCandidate a, ExportCandidate b) {
  if (a.yaw == null || b.yaw == null) return 0;
  final dy = (a.yaw! - b.yaw!).abs() / 90;
  final dp = a.pitch == null || b.pitch == null
      ? 0.0
      : (a.pitch! - b.pitch!).abs() / 60;
  return dy + dp;
}

/// Picks the detections to export. A photo contributes its best detection of each kind. A video
/// contributes up to `maxPerVideo` per kind, chosen greedily so every pick is as far as possible
/// (in time, plus head pose for faces) from the ones already picked, weighted by quality - the
/// result spreads over the whole video instead of clustering on its sharpest second.
/// Result order: media id, then time, then kind (faces first).
List<ExportCandidate> selectDiverse(
  Iterable<ExportCandidate> candidates, [
  ExportSelectionOptions options = const ExportSelectionOptions(),
]) {
  final byMedia = <(int, ExportKind), List<ExportCandidate>>{};
  for (final c in candidates) {
    if (!_fits(c, options)) continue;
    byMedia.putIfAbsent((c.mediaId, c.kind), () => []).add(c);
  }
  final picked = <ExportCandidate>[];
  for (final group in byMedia.values) {
    // One person once per frame: the best detection of a moment.
    final perFrame = <String, ExportCandidate>{};
    for (final c in group) {
      final held = perFrame[c.frameKey];
      if (held == null || _better(c, held)) perFrame[c.frameKey] = c;
    }
    final list = perFrame.values.toList();
    if (!list.first.isVideo) {
      picked.add(list.reduce((a, b) => _better(a, b) ? a : b));
    } else {
      picked.addAll(_spread(list, options));
    }
  }
  picked.sort((a, b) {
    final m = a.mediaId.compareTo(b.mediaId);
    if (m != 0) return m;
    final t = (a.timestampMs ?? 0).compareTo(b.timestampMs ?? 0);
    if (t != 0) return t;
    final k = a.kind.index.compareTo(b.kind.index);
    return k != 0 ? k : a.detectionId.compareTo(b.detectionId);
  });
  return picked;
}

bool _better(ExportCandidate a, ExportCandidate b) {
  final d = _rank(a) - _rank(b);
  return d.abs() > 1e-9 ? d > 0 : a.detectionId < b.detectionId;
}

List<ExportCandidate> _spread(
  List<ExportCandidate> all,
  ExportSelectionOptions o,
) {
  final cap = math.max(1, o.maxPerVideo);
  if (all.length <= 1) return all;
  final times = [for (final c in all) c.timestampMs ?? 0];
  final span = math.max(1, times.reduce(math.max) - times.reduce(math.min));
  final remaining = [...all]..sort((a, b) => _better(a, b) ? -1 : 1);
  final chosen = <ExportCandidate>[remaining.removeAt(0)];
  while (chosen.length < cap && remaining.isNotEmpty) {
    ExportCandidate? best;
    var bestValue = -1.0;
    for (final c in remaining) {
      var nearest = double.infinity;
      var gap = true;
      for (final s in chosen) {
        final dt = ((c.timestampMs ?? 0) - (s.timestampMs ?? 0)).abs();
        if (dt < o.minGapMs) {
          gap = false;
          break;
        }
        final d = dt / span + o.poseWeight * _poseDistance(c, s);
        if (d < nearest) nearest = d;
      }
      if (!gap) continue;
      final value = nearest * (0.4 + 0.6 * c.quality.clamp(0.0, 1.0));
      if (value > bestValue + 1e-12) {
        best = c;
        bestValue = value;
      }
    }
    if (best == null) break; // everything left is closer than the minimum gap
    chosen.add(best);
    remaining.remove(best);
  }
  return chosen;
}
