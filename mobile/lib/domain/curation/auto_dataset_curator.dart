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

class AutoDatasetCurator {
  const AutoDatasetCurator({
    this.targetFaceCount = 7,
    this.targetUpperCount = 5,
    this.targetBodyCount = 8,
    this.minVideoGapMs = 1500,
  });

  final int targetFaceCount;
  final int targetUpperCount;
  final int targetBodyCount;
  final int minVideoGapMs;

  double scoreCandidate(CurationCandidate c) {
    switch (c.category) {
      case CurationCategory.face:
        final angleWeight = c.yaw != null ? (1.0 - (c.yaw!.abs() / 180.0)) : 0.8;
        return (c.quality * 50.0) + (angleWeight * 30.0) + (c.boxArea * 20.0);

      case CurationCategory.upper:
        return (c.quality * 40.0) + (c.skinRatio * 30.0) + (c.boxArea * 30.0);

      case CurationCategory.body:
        double score = c.quality * 20.0;
        if (c.hasExposedRegion) {
          score += 100.0; // Top Tier: sensitive/exposed regions detected
        } else if (c.skinRatio > 0.4) {
          score += 50.0 + (c.skinRatio * 30.0); // High Tier: swimwear / light clothes
        } else if (c.skinRatio > 0.2) {
          score += 30.0 + (c.skinRatio * 20.0);
        }
        if (c.extent == 'full') {
          score += 20.0;
        } else if (c.extent == 'knee') {
          score += 10.0;
        }
        return score;
    }
  }

  List<CurationCandidate> deduplicateVideoFrames(List<CurationCandidate> candidates) {
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

  CurationResult curate(List<CurationCandidate> allCandidates) {
    final clean = deduplicateVideoFrames(allCandidates);

    final facePool = clean.where((c) => c.category == CurationCategory.face).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final upperPool = clean.where((c) => c.category == CurationCategory.upper).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final bodyPool = clean.where((c) => c.category == CurationCategory.body).toList()
      ..sort((a, b) => scoreCandidate(b).compareTo(scoreCandidate(a)));

    final selectedFaces = facePool.take(targetFaceCount).toList();
    final selectedUpper = upperPool.take(targetUpperCount).toList();
    final selectedBody = bodyPool.take(targetBodyCount).toList();

    return CurationResult(
      faces: selectedFaces,
      upper: selectedUpper,
      body: selectedBody,
    );
  }
}
