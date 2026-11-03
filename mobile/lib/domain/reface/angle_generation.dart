import 'reface_preflight.dart';

/// The head directions the PC's `angles` option knows (`lora_generate.ANGLE_PROMPTS`).
String serverAngle(PoseBucket bucket) => switch (bucket) {
  PoseBucket.frontal => 'frontal',
  PoseBucket.threeQuarter => 'three_quarter',
  PoseBucket.profile => 'profile',
  PoseBucket.up => 'up',
  PoseBucket.down => 'down',
};

/// What to ask the person's LoRA for, so the source covers what the target shows: [perAngle] portraits for
/// each open gap (biggest share first), at most [maxImages] in all - a generation costs tens of seconds each
/// on a 6 GB card, and the PC's identity weighs generated faces below photographed ones anyway.
class AngleGenerationPlan {
  AngleGenerationPlan._(this.buckets, this.angles);

  /// Null when nothing is missing.
  static AngleGenerationPlan? of(
    RefacePreflight preflight, {
    int perAngle = 3,
    int maxImages = 10,
  }) {
    final buckets = <PoseBucket>[];
    final angles = <String>[];
    for (final bucket in preflight.needsGeneration) {
      if (angles.length >= maxImages) break;
      final have =
          (preflight.realCoverage[bucket] ?? 0) +
          (preflight.generatedCoverage[bucket] ?? 0);
      // enough to reach the bar, but at least a couple of tries: not every portrait lands in its pose
      final want = (perAngle - have).clamp(2, perAngle);
      final room = maxImages - angles.length;
      final count = want < room ? want : room;
      buckets.add(bucket);
      angles.addAll(List.filled(count, serverAngle(bucket)));
    }
    return angles.isEmpty ? null : AngleGenerationPlan._(buckets, angles);
  }

  final List<PoseBucket> buckets;

  /// One entry per image, as the `angles` job option.
  final List<String> angles;

  int get count => angles.length;

  String get summary => buckets.map((b) => b.label).join(', ');
}
