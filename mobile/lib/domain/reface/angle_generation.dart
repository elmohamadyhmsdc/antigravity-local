import 'reface_preflight.dart';

/// The head directions the PC's `angles` option knows (`lora_generate.ANGLE_PROMPTS`).
String serverAngle(PoseBucket bucket) => switch (bucket) {
  PoseBucket.frontal => 'frontal',
  PoseBucket.threeQuarter => 'three_quarter',
  PoseBucket.profile => 'profile',
  PoseBucket.up => 'up',
  PoseBucket.down => 'down',
};

/// What to ask the person's LoRA for, so its references cover the target.
class AngleGenerationPlan {
  AngleGenerationPlan._(this.buckets, this.angles);

  /// An explicitly selected model supplies each observed angle. Reuse verified
  /// portraits of that model and cover the full pose range when pose is unknown.
  static AngleGenerationPlan? forModel(RefacePreflight preflight) {
    final needed = preflight.targetShare.isEmpty
        ? PoseBucket.values
        : (preflight.targetShare.keys.toList()..sort(
            (a, b) =>
                preflight.targetShare[b]!.compareTo(preflight.targetShare[a]!),
          ));
    final buckets = [
      for (final bucket in needed)
        if ((preflight.generatedCoverage[bucket] ?? 0) == 0) bucket,
    ];
    if (buckets.isEmpty) return null;
    return AngleGenerationPlan._(buckets, [
      for (final bucket in buckets) ...List.filled(3, serverAngle(bucket)),
    ]);
  }

  final List<PoseBucket> buckets;

  /// One entry per image, as the `angles` job option.
  final List<String> angles;

  int get count => angles.length;
}
