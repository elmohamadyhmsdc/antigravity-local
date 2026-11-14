import 'dart:math' as math;
import 'dart:typed_data';

import '../scan/scan_math.dart' show appearanceSimilarity;

enum CurationCategory { face, upper, body }

class CurationCandidate {
  const CurationCandidate({
    required this.detectionId,
    required this.mediaId,
    required this.assetId,
    required this.isVideo,
    required this.category,
    this.quality = 0.5,
    this.extent,
    this.hasExposedRegion = false,
    this.skinRatio = 0.0,
    this.timestampMs,
    this.frameNumber,
    this.yaw,
    this.pitch,
    this.boxW,
    this.boxH,
    this.refId,
    this.appearance,
    this.facePx,
    this.embedding,
  });

  final int detectionId;
  final int mediaId;
  final String assetId;
  final bool isVideo;
  final CurationCategory category;
  final double quality;
  final String? extent;
  final bool hasExposedRegion;
  final double skinRatio;
  final int? timestampMs;
  final int? frameNumber;
  final double? yaw, pitch;
  final double? boxW, boxH;

  /// The face / body row behind the detection. A face seen again in other photos (a near-duplicate,
  /// cosine >= 0.95) has one row and several detections: only one of them is worth training on.
  final int? refId;

  /// The outfit descriptor of a body, to keep the picks from being one outfit.
  final List<double>? appearance;

  /// A face's size in pixels as the PC measured it, and its identity vector: pixels are what a model
  /// learns from (the box as a share of the photo says nothing about that), and two faces with
  /// near-identical vectors are the same picture twice.
  final double? facePx;
  final Float32List? embedding;

  double get boxArea => (boxW ?? 0.3) * (boxH ?? 0.3);
}

class CurationResult {
  const CurationResult({
    required this.faces,
    required this.upper,
    required this.body,
  });

  final List<CurationCandidate> faces;
  final List<CurationCandidate> upper;
  final List<CurationCandidate> body;

  int get totalCount => faces.length + upper.length + body.length;
  List<CurationCandidate> get all => [...faces, ...upper, ...body];
}

/// Picks a training set for one identity. Not "the best N": the N best are the same sharp frontal
/// face from one sitting. Each pick is the best-scoring candidate *after* a penalty for looking like
/// what is already picked (head pose for faces, outfit for bodies, same photo / same video moment
/// for both), so the set spreads over poses, outfits and occasions.
class AutoDatasetCurator {
  const AutoDatasetCurator({
    this.targetFaceCount = 7,
    this.targetUpperCount = 5,
    this.targetBodyCount = 8,
    this.minVideoGapMs = 1500,
    this.minFaceQuality = 0.45,
    this.diversityWeight = 60.0,
    this.preferExposed = false,
    this.maxExposedShare = 0.9,
  });

  final int targetFaceCount;
  final int targetUpperCount;
  final int targetBodyCount;
  final int minVideoGapMs;

  /// Below this a face is not worth training on, even when there are few faces.
  final double minFaceQuality;

  /// How much (score points) a candidate identical to a pick loses.
  final double diversityWeight;

  /// A switch, off by default: when on, bodies with exposed regions (and skin) are ranked far above the
  /// rest. Off, an exposed body is neither preferred nor avoided: it competes on quality and variety.
  final bool preferExposed;

  /// With [preferExposed], at most this share of the body slots goes to exposed bodies (a little variety
  /// is kept). Without it there is no cap: nothing is preferred.
  final double maxExposedShare;

  double scoreCandidate(CurationCandidate c) {
    switch (c.category) {
      case CurationCategory.face:
        final angleWeight = c.yaw != null
            ? (1.0 - (c.yaw!.abs() / 180.0))
            : 0.8;
        // size: 80 px (the least we train on) .. 256 px and up; the box share only when the size is unknown
        final size = c.facePx == null
            ? c.boxArea
            : ((c.facePx! - 80) / 176).clamp(0.0, 1.0);
        return (c.quality * 50.0) + (angleWeight * 30.0) + (size * 20.0);

      case CurationCategory.upper:
        return (c.quality * 40.0) + (c.skinRatio * 30.0) + (c.boxArea * 30.0);

      case CurationCategory.body:
        double score = c.quality * 20.0;
        if (preferExposed) {
          if (c.hasExposedRegion) {
            score += 100.0; // Top Tier: sensitive/exposed regions detected
          } else if (c.skinRatio > 0.4) {
            score +=
                50.0 +
                (c.skinRatio * 30.0); // High Tier: swimwear / light clothes
          } else if (c.skinRatio > 0.2) {
            score += 30.0 + (c.skinRatio * 20.0);
          }
        }
        if (c.extent == 'full') {
          score += 20.0;
        } else if (c.extent == 'knee') {
          score += 10.0;
        }
        return score;
    }
  }

  List<CurationCandidate> deduplicateVideoFrames(
    List<CurationCandidate> candidates,
  ) {
    final nonVideo = candidates.where((c) => !c.isVideo).toList();
    final videoByMedia = <int, List<CurationCandidate>>{};
    for (final c in candidates.where((c) => c.isVideo)) {
      videoByMedia.putIfAbsent(c.mediaId, () => []).add(c);
    }

    final keptVideo = <CurationCandidate>[];
    for (final list in videoByMedia.values) {
      list.sort((a, b) => (a.timestampMs ?? 0).compareTo(b.timestampMs ?? 0));
      CurationCandidate? lastKept;
      for (final item in list) {
        if (lastKept == null) {
          lastKept = item;
          keptVideo.add(item);
        } else {
          final diff = (item.timestampMs ?? 0) - (lastKept.timestampMs ?? 0);
          if (diff >= minVideoGapMs) {
            lastKept = item;
            keptVideo.add(item);
          } else if (item.quality > lastKept.quality) {
            // Replace with higher quality frame in same window
            keptVideo.removeLast();
            lastKept = item;
            keptVideo.add(item);
          }
        }
      }
    }
    return [...nonVideo, ...keptVideo];
  }

  /// One detection per stored face / body: the best-scoring one.
  List<CurationCandidate> _uniqueRows(List<CurationCandidate> pool) {
    final best = <String, CurationCandidate>{};
    final rest = <CurationCandidate>[];
    for (final c in pool) {
      final id = c.refId;
      if (id == null) {
        rest.add(c);
        continue;
      }
      final key = '${c.category == CurationCategory.face ? 'f' : 'b'}$id';
      final old = best[key];
      if (old == null || scoreCandidate(c) > scoreCandidate(old)) best[key] = c;
    }
    return [...best.values, ...rest];
  }

  /// 0 (nothing alike) .. 1 (the same picture again).
  double similarity(CurationCandidate a, CurationCandidate b) {
    var sim = 0.0;
    if (a.mediaId == b.mediaId) {
      // two moments of one video are different pictures, two crops of one photo are not
      final gap = (a.timestampMs != null && b.timestampMs != null)
          ? (a.timestampMs! - b.timestampMs!).abs()
          : 0;
      sim = a.isVideo ? (gap < 20000 ? 0.8 : 0.5) : 0.9;
    }
    if (a.category == CurationCategory.face) {
      final ea = a.embedding, eb = b.embedding;
      if (ea != null && eb != null && ea.length == eb.length) {
        var dot = 0.0, na = 0.0, nb = 0.0;
        for (var i = 0; i < ea.length; i++) {
          dot += ea[i] * eb[i];
          na += ea[i] * ea[i];
          nb += eb[i] * eb[i];
        }
        final cos = na > 0 && nb > 0 ? dot / math.sqrt(na * nb) : 0.0;
        // near-identical vectors (same expression, same light): the same picture, whoever the photo is
        if (cos >= 0.85) {
          sim = math.max(
            sim,
            ((cos - 0.85) / 0.15).clamp(0.0, 1.0) * 0.5 + 0.5,
          );
        }
      }
      if (a.yaw == null || b.yaw == null) return math.max(sim, 0.5);
      final dy = (a.yaw! - b.yaw!).abs() / 90;
      final dp = (a.pitch == null || b.pitch == null)
          ? 0.0
          : (a.pitch! - b.pitch!).abs() / 60;
      final poseSim = (1 - (dy + dp) / 0.6).clamp(0.0, 1.0);
      return math.max(sim, poseSim * 0.8);
    }
    final outfit = appearanceSimilarity(a.appearance, b.appearance);
    final outfitSim = a.appearance == null || b.appearance == null
        ? 0.3
        : (outfit >= 0.8 ? outfit : outfit * 0.5);
    return math.max(sim, outfitSim);
  }

  List<CurationCandidate> _pick(
    List<CurationCandidate> pool,
    int target, {
    double maxExposed = 1.0,
  }) {
    final remaining = _uniqueRows(pool);
    final picks = <CurationCandidate>[];
    final cap = (target * maxExposed).floor();
    var exposed = 0;
    while (picks.length < target && remaining.isNotEmpty) {
      CurationCandidate? best;
      var bestScore = double.negativeInfinity;
      for (final c in remaining) {
        if (c.hasExposedRegion && exposed >= cap) continue;
        var nearest = 0.0;
        for (final p in picks) {
          final s = similarity(c, p);
          if (s > nearest) nearest = s;
        }
        final value = scoreCandidate(c) - diversityWeight * nearest;
        if (value > bestScore) {
          bestScore = value;
          best = c;
        }
      }
      if (best == null) break;
      picks.add(best);
      remaining.remove(best);
      if (best.hasExposedRegion) exposed++;
    }
    return picks;
  }

  CurationResult curate(List<CurationCandidate> allCandidates) {
    final clean = deduplicateVideoFrames(allCandidates);

    List<CurationCandidate> of(CurationCategory category) =>
        clean.where((c) => c.category == category).toList();

    return CurationResult(
      faces: _pick(
        of(
          CurationCategory.face,
        ).where((c) => c.quality >= minFaceQuality).toList(),
        targetFaceCount,
      ),
      upper: _pick(of(CurationCategory.upper), targetUpperCount),
      body: _pick(
        of(CurationCategory.body),
        targetBodyCount,
        maxExposed: preferExposed ? maxExposedShare : 1.0,
      ),
    );
  }
}
