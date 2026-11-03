import 'dart:math' as math;
import 'dart:typed_data';

/// One face as the identity maths sees it.
class IdentityFace {
  const IdentityFace({
    required this.id,
    required this.embedding,
    required this.quality,
    this.yaw,
    this.pitch,
  });

  final int id;
  final Float32List embedding;
  final double quality;
  final double? yaw, pitch;
}

class IdentitySelection {
  const IdentitySelection({
    required this.kept,
    required this.outliers,
    required this.duplicates,
    required this.consistency,
    required this.poseCoverage,
    this.similarity = const {},
  });

  /// The faces to build from, best first (and, when a `top` was asked for, spread over head poses).
  final List<IdentityFace> kept;

  /// Faces that do not look like the rest of the person (a wrong grouping, a stranger, a heavy blur).
  final List<int> outliers;

  /// Near-identical pictures of a kept face (cosine >= the duplicate bar), best one kept.
  final List<int> duplicates;

  /// Mean similarity of the kept faces to their own average (1 = all the same look).
  final double consistency;

  /// Kept faces per 20-degree yaw/pitch cell, e.g. `0,0` frontal.
  final Map<String, int> poseCoverage;

  /// How much each usable face looks like the person's core (cosine to the anchor), by face id.
  final Map<int, double> similarity;
}

Float32List _unit(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final out = Float32List(v.length);
  if (!sum.isFinite || sum <= 1e-16) return out;
  final inv = 1.0 / math.sqrt(sum);
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] * inv;
  }
  return out;
}

double _dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// How far apart two head poses are: 0 = the same, ~1 = clearly different (90 deg of yaw, or 60 of pitch).
double poseDistance(IdentityFace a, IdentityFace b) {
  if (a.yaw == null || b.yaw == null) return 0.5;
  final dp = a.pitch == null || b.pitch == null
      ? 0.0
      : (a.pitch! - b.pitch!).abs() / 60;
  return (a.yaw! - b.yaw!).abs() / 90 + dp;
}

/// Which faces really are this person, and which of them are worth building from.
///
/// The same idea the PC applies to a Reface source (`identity.select_identity_faces`): the *medoid* (the face
/// most like all the others) is the anchor; a face far below the person's own spread of similarity to it
/// is an outlier. A minority of wrong faces therefore cannot drag a model, a LoRA anchor or a swap source
/// toward someone else. Never trims a small set, and never throws away more than [maxTrim] of the faces
/// (that would mean the medoid is the odd one out, not the faces).
///
/// [trusted]: faces the user vouched for. With at least [minTrusted] of them the anchor is *their* average
/// (not a guess at the majority), the spread is theirs, and none of them is ever an outlier - so a person
/// who is mostly wrong faces can still be audited once a few right ones are confirmed.
///
/// [floor]: the similarity below which a face is out whatever the spread. [top]: return that many, picked
/// one at a time as the best quality plus how far the head pose is from the ones already picked.
IdentitySelection selectIdentity(
  List<IdentityFace> faces, {
  int? top,
  double floor = 0.4,
  int minToTrim = 5,
  double maxTrim = 0.4,
  bool dedupe = true,
  double duplicateCosine = 0.95,
  int medoidSample = 150,
  Set<int>? trusted,
  int minTrusted = 3,
}) {
  final outliers = <int>[];
  final usable = <(IdentityFace, Float32List)>[];
  for (final f in faces) {
    final u = _unit(f.embedding);
    final ok = f.quality.isFinite && u.any((x) => x != 0);
    if (ok) {
      usable.add((f, u));
    } else {
      outliers.add(f.id);
    }
  }
  usable.sort((a, b) => b.$1.quality.compareTo(a.$1.quality));

  var consistency = 0.0;
  var pool = usable;
  final similarity = <int, double>{};
  final vouched = [
    for (final f in usable)
      if (trusted != null && trusted.contains(f.$1.id)) f,
  ];
  if (usable.length >= minToTrim || vouched.length >= minTrusted) {
    Float32List anchor;
    List<double> basis; // the similarities that define "this person's spread"
    final byTrust = vouched.length >= minTrusted;
    if (byTrust) {
      final sum = Float32List(vouched.first.$2.length);
      for (final f in vouched) {
        for (var i = 0; i < sum.length; i++) {
          sum[i] += f.$2[i];
        }
      }
      anchor = _unit(sum);
      basis = [for (final f in vouched) _dot(f.$2, anchor)];
    } else {
      // the medoid among the best-quality sample (O(sample^2)), everyone judged against it
      final sample = usable.take(medoidSample).toList();
      anchor = sample.first.$2;
      var best = double.negativeInfinity;
      for (final a in sample) {
        final m = _median([for (final b in sample) _dot(a.$2, b.$2)]);
        if (m > best) {
          best = m;
          anchor = a.$2;
        }
      }
      basis = [for (final f in usable) _dot(f.$2, anchor)];
    }
    final sims = [for (final f in usable) _dot(f.$2, anchor)];
    for (var i = 0; i < usable.length; i++) {
      similarity[usable[i].$1.id] = sims[i];
    }
    final median = _median(basis);
    final mad = _median([for (final s in basis) (s - median).abs()]);
    final threshold = math.max(floor, median - math.max(3 * mad, 0.1));
    bool isTrusted(int i) => trusted != null && trusted.contains(usable[i].$1.id);
    final dropIds = [
      for (var i = 0; i < usable.length; i++)
        if (sims[i] < threshold && !isTrusted(i)) usable[i].$1.id,
    ];
    if (dropIds.length <= usable.length * maxTrim) {
      outliers.addAll(dropIds);
      pool = [
        for (var i = 0; i < usable.length; i++)
          if (sims[i] >= threshold || isTrusted(i)) usable[i],
      ];
    }
  }

  final duplicates = <int>[];
  var kept = pool;
  if (dedupe) {
    kept = [];
    for (final f in pool) {
      var dup = false;
      for (final k in kept) {
        if (_dot(f.$2, k.$2) >= duplicateCosine) {
          dup = true;
          break;
        }
      }
      if (dup) {
        duplicates.add(f.$1.id);
      } else {
        kept.add(f);
      }
    }
  }

  if (kept.isNotEmpty) {
    final mean = Float32List(kept.first.$2.length);
    for (final f in kept) {
      for (var i = 0; i < mean.length; i++) {
        mean[i] += f.$2[i] * f.$1.quality;
      }
    }
    final centre = _unit(mean);
    consistency =
        kept.map((f) => _dot(f.$2, centre)).reduce((a, b) => a + b) /
        kept.length;
  }

  var ordered = [for (final f in kept) f.$1];
  if (top != null && ordered.length > top) {
    final picked = <IdentityFace>[ordered.first];
    final rest = ordered.skip(1).toList();
    while (picked.length < top && rest.isNotEmpty) {
      IdentityFace? choice;
      var value = double.negativeInfinity;
      for (final f in rest) {
        var nearest = double.infinity;
        for (final p in picked) {
          final d = poseDistance(f, p);
          if (d < nearest) nearest = d;
        }
        final v = f.quality + nearest.clamp(0.0, 1.0);
        if (v > value) {
          value = v;
          choice = f;
        }
      }
      picked.add(choice!);
      rest.remove(choice);
    }
    ordered = picked;
  } else if (top != null) {
    ordered = ordered.take(top).toList();
  }

  final coverage = <String, int>{};
  for (final f in ordered) {
    final key =
        '${((f.yaw ?? 0) / 20).round()},${((f.pitch ?? 0) / 20).round()}';
    coverage[key] = (coverage[key] ?? 0) + 1;
  }
  return IdentitySelection(
    kept: ordered,
    outliers: outliers,
    duplicates: duplicates,
    consistency: consistency,
    poseCoverage: coverage,
    similarity: similarity,
  );
}
