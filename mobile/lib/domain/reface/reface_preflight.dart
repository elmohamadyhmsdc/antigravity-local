/// Which way a face looks. Frontal is within 20 degrees both ways; a face that looks up or down by 20 or more
/// is up / down whatever its yaw; otherwise the turn decides (20-50 = 3/4 view, more = profile). Left and
/// right are one bucket: the swap does not care, and a mirrored face covers the other side.
enum PoseBucket {
  frontal('Frontal'),
  threeQuarter('3/4 view'),
  profile('Profile'),
  up('Looking up'),
  down('Looking down');

  const PoseBucket(this.label);
  final String label;

  /// The bucket for a head pose in degrees, or null when the pose is unknown.
  static PoseBucket? of(double? yaw, double? pitch) {
    if (yaw == null && pitch == null) return null;
    final y = (yaw ?? 0).abs();
    final p = pitch ?? 0;
    if (p >= 20) return PoseBucket.up;
    if (p <= -20) return PoseBucket.down;
    if (y >= 50) return PoseBucket.profile;
    if (y >= 20) return PoseBucket.threeQuarter;
    return PoseBucket.frontal;
  }
}

/// A face of the photo / video to be swapped, as the phone measured it.
class PreflightTarget {
  const PreflightTarget({this.facePx, this.yaw, this.pitch, this.weight = 1});

  final double? facePx;
  final double? yaw, pitch;

  /// How much of the result this face is: 1 for a photo face, the number of sampled frames for a video person.
  final double weight;
}

/// A face the swap will learn the identity from.
class PreflightSource {
  const PreflightSource({
    this.yaw,
    this.pitch,
    this.generated = false,
    this.facePx,
  });

  final double? yaw, pitch;

  /// Made by the person's LoRA, not photographed.
  final bool generated;
  final double? facePx;
}

/// "Before we start": what the target asks for and what the source can give, checked on the phone with no
/// PC and no GPU, so problems are found before a long job is queued - and so that the poses a LoRA would
/// have to generate (see [gaps]) are known.
class RefacePreflight {
  RefacePreflight({
    required List<PreflightTarget> targets,
    required List<PreflightSource> sources,
  }) : targetFaces = targets.length,
       sourceFaces = sources.length,
       realSources = sources.where((s) => !s.generated).length,
       generatedSources = sources.where((s) => s.generated).length {
    var total = 0.0;
    for (final t in targets) {
      final px = t.facePx;
      if (px != null) {
        if (smallestTargetPx == null || px < smallestTargetPx!) {
          smallestTargetPx = px;
        }
        if (px < tinyPx) {
          tinyTargets++;
        } else if (px < smallPx) {
          smallTargets++;
        }
      }
      final bucket = PoseBucket.of(t.yaw, t.pitch);
      if (bucket != null) {
        targetShare[bucket] = (targetShare[bucket] ?? 0) + t.weight;
        total += t.weight;
      }
    }
    if (total > 0) {
      for (final k in targetShare.keys.toList()) {
        targetShare[k] = targetShare[k]! / total;
      }
    }
    for (final s in sources) {
      final bucket = PoseBucket.of(s.yaw, s.pitch);
      if (bucket == null) continue;
      final into = s.generated ? generatedCoverage : realCoverage;
      into[bucket] = (into[bucket] ?? 0) + 1;
    }
  }

  /// Below this the face is too small to swap well; below [smallPx] it comes out soft.
  static const tinyPx = 40.0;
  static const smallPx = 64.0;

  /// A pose is a gap when it is at least this share of the target and the source has fewer real faces than
  /// [neededPerBucket] there.
  static const gapShare = 0.10;
  static const neededPerBucket = 2;

  /// Fewer source faces than this make a thin identity.
  static const minSourceFaces = 5;

  final int targetFaces, sourceFaces, realSources, generatedSources;
  double? smallestTargetPx;
  int tinyTargets = 0, smallTargets = 0;

  /// Share of the target (0..1) in each pose; only poses that occur.
  final Map<PoseBucket, double> targetShare = {};
  final Map<PoseBucket, int> realCoverage = {};
  final Map<PoseBucket, int> generatedCoverage = {};

  /// Poses the target shows (>= [gapShare]) that the real source faces cover poorly, biggest first. These are
  /// the angles to add photos for - or to generate with the person's LoRA.
  List<PoseBucket> get gaps => [
    for (final e in targetShare.entries)
      if (e.value >= gapShare && (realCoverage[e.key] ?? 0) < neededPerBucket)
        e.key,
  ]..sort((a, b) => targetShare[b]!.compareTo(targetShare[a]!));

  /// The gaps that are still open once the person's model portraits are counted: what to generate.
  List<PoseBucket> get needsGeneration => [
    for (final g in gaps)
      if ((realCoverage[g] ?? 0) + (generatedCoverage[g] ?? 0) <
          neededPerBucket)
        g,
  ];

  /// Short sentences, most important first. Empty = nothing to say.
  List<String> get warnings => [
    if (targetFaces == 0) 'No face is selected in the target.',
    if (tinyTargets > 0)
      '$tinyTargets target face${tinyTargets == 1 ? ' is' : 's are'} under ${tinyPx.round()} px: too small to swap well.',
    if (smallTargets > 0)
      '$smallTargets target face${smallTargets == 1 ? ' is' : 's are'} under ${smallPx.round()} px: the result will be soft there.',
    if (sourceFaces > 0 && realSources < minSourceFaces)
      'Only $realSources real source face${realSources == 1 ? '' : 's'}: a thin identity. $minSourceFaces or more, from different angles, work better.',
    for (final g in needsGeneration)
      '${g.label} is ${(targetShare[g]! * 100).round()}% of the target but the source has ${realCoverage[g] ?? 0} real face${(realCoverage[g] ?? 0) == 1 ? '' : 's'} like that.',
  ];

  bool get hasProblems => warnings.isNotEmpty;

  static String percent(Map<PoseBucket, double> share) => [
    for (final b in PoseBucket.values)
      if ((share[b] ?? 0) > 0) '${b.label} ${(share[b]! * 100).round()}%',
  ].join(' · ');

  static String counts(Map<PoseBucket, int> by) => [
    for (final b in PoseBucket.values)
      if ((by[b] ?? 0) > 0) '${b.label} ${by[b]}',
  ].join(' · ');
}
