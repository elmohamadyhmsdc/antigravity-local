import 'dart:math' as math;
import 'dart:typed_data';

import '../../data/api/dtos/analyze.dart';
import '../../data/api/dtos/embedding.dart';

int _nextFrame = 0;

double _similarity(Float32List a, Float32List b) {
  var dot = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return aa > 1e-12 && bb > 1e-12
      ? (dot / math.sqrt(aa * bb)).clamp(-1.0, 1.0)
      : -1;
}

/// Short-lived detections for one Reface form; never inserted into the library.
class RefaceFaceGroup {
  RefaceFaceGroup(DetectedFace face) : samples = [face], frames = {};
  RefaceFaceGroup.copy(RefaceFaceGroup group)
    : samples = List.of(group.samples),
      frames = Set.of(group.frames);
  final List<DetectedFace> samples;
  final Set<int> frames;
  Float32List? _center;
  int get appearances => math.max(1, frames.length);
  DetectedFace get representative => samples.first;

  Float32List get center => _center ??= (() {
    final vector = Float32List(embeddingDim);
    for (final face in samples) {
      var length = 0.0;
      for (final value in face.embedding) {
        length += value * value;
      }
      if (length <= 1e-12) continue;
      final weight = face.quality.score.clamp(.05, 1) / math.sqrt(length);
      for (var i = 0; i < vector.length; i++) {
        vector[i] += face.embedding[i] * weight;
      }
    }
    return vector;
  })();

  double match(DetectedFace face) {
    final best = samples
        .map((sample) => _similarity(sample.embedding, face.embedding))
        .reduce(math.max);
    return .7 * best + .3 * _similarity(center, face.embedding);
  }

  bool cooccurs(RefaceFaceGroup other) => frames.any(other.frames.contains);

  double affinity(RefaceFaceGroup other) {
    var best = -1.0;
    for (final left in samples.take(3)) {
      for (final right in other.samples.take(3)) {
        best = math.max(best, _similarity(left.embedding, right.embedding));
      }
    }
    return .6 * _similarity(center, other.center) + .4 * best;
  }

  void absorb(RefaceFaceGroup other) {
    frames.addAll(other.frames);
    for (final face in other.samples) {
      add(face);
    }
  }

  void add(DetectedFace face) {
    final duplicate = samples.indexWhere(
      (old) => _similarity(old.embedding, face.embedding) >= .95,
    );
    if (duplicate >= 0) {
      if (face.quality.score > samples[duplicate].quality.score) {
        samples[duplicate] = face;
      }
    } else {
      samples.add(face);
    }
    samples.sort((a, b) => b.quality.score.compareTo(a.quality.score));
    if (samples.length > 20) samples.removeRange(20, samples.length);
    _center = null;
  }

  List<Map<String, dynamic>> encode() => [
    for (final face in samples)
      {
        'embedding': encodeEmbedding(face.embedding),
        'quality': face.quality.score,
        if (face.quality.pose case final pose?)
          'pose': {
            'yaw': pose.yaw,
            'pitch': pose.pitch,
            'roll': pose.roll ?? 0,
          },
      },
  ];
}

void _combine(List<RefaceFaceGroup> groups, int a, int b, Set<int>? selected) {
  final keep = math.min(a, b), remove = math.max(a, b);
  groups[keep].absorb(groups[remove]);
  groups.removeAt(remove);
  if (selected != null) {
    final adjusted = {
      for (final index in selected)
        if (index == remove) keep else if (index > remove) index - 1 else index,
    };
    selected
      ..clear()
      ..addAll(adjusted);
  }
}

bool _ambiguousMerge(List<RefaceFaceGroup> groups, int a, int b, double score) {
  for (var other = 0; other < groups.length; other++) {
    if (other == a || other == b) continue;
    final left = groups[a].affinity(groups[other]);
    final right = groups[b].affinity(groups[other]);
    if (right >= score - .06 &&
        (groups[a].cooccurs(groups[other]) || left < .4)) {
      return true;
    }
    if (left >= score - .06 &&
        (groups[b].cooccurs(groups[other]) || right < .4)) {
      return true;
    }
  }
  return false;
}

/// The balanced project identity threshold is 0.40. Match a quality-weighted
/// multi-pose identity rather than demanding 0.55 against a single snapshot.
/// Recorded co-occurrences are hard cannot-link constraints across later scans.
void mergeRefaceFaces(
  List<RefaceFaceGroup> groups,
  List<DetectedFace> faces, {
  Set<int>? selected,
}) {
  final frame = ++_nextFrame;
  final pending = List.of(faces);
  if (groups.isNotEmpty) {
    final certainty = {
      for (final face in pending)
        face: groups.map((group) => group.match(face)).reduce(math.max),
    };
    pending.sort((a, b) => certainty[b]!.compareTo(certainty[a]!));
  }
  while (pending.isNotEmpty) {
    // Process the most certain face first instead of letting detector order
    // decide which person claims a track when two detections compete.
    final face = pending.removeAt(0);
    final matches = <({int index, double score})>[];
    for (var i = 0; i < groups.length; i++) {
      matches.add((index: i, score: groups[i].match(face)));
    }
    matches.sort((a, b) => b.score.compareTo(a.score));
    // A later clear view can bridge two pose fragments of the same identity.
    // It cannot bridge people seen together, even if they look very similar.
    if (matches.length >= 2 &&
        matches[0].score >= .5 &&
        matches[1].score >= .5 &&
        matches[0].score - matches[1].score < .06) {
      final a = groups[matches[0].index], b = groups[matches[1].index];
      if (!a.frames.contains(frame) &&
          !b.frames.contains(frame) &&
          !a.cooccurs(b) &&
          a.affinity(b) >= .4 &&
          !_ambiguousMerge(
            groups,
            matches[0].index,
            matches[1].index,
            a.affinity(b),
          )) {
        _combine(groups, matches[0].index, matches[1].index, selected);
        pending.insert(0, face);
        continue;
      }
    }
    if (matches.isNotEmpty &&
        matches.first.score >= .4 &&
        !groups[matches.first.index].frames.contains(frame) &&
        (matches.length == 1 ||
            matches.first.score - matches[1].score >= .06)) {
      groups[matches.first.index]
        ..add(face)
        ..frames.add(frame);
    } else if (groups.length < 32) {
      groups.add(RefaceFaceGroup(face)..frames.add(frame));
    }
  }
  // Consolidate repeated, consistent fragments after the frame is assigned.
  // Single weak links are insufficient; appearance counts and co-occurrences
  // survive representative deduplication and bounded sample retention.
  var merged = true;
  while (merged) {
    merged = false;
    for (var i = 0; i < groups.length && !merged; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        if (groups[i].cooccurs(groups[j])) continue;
        final affinity = groups[i].affinity(groups[j]);
        if (affinity >= .62 ||
            (affinity >= .48 &&
                groups[i].frames.length >= 2 &&
                groups[j].frames.length >= 2)) {
          if (_ambiguousMerge(groups, i, j, affinity)) continue;
          _combine(groups, i, j, selected);
          merged = true;
          break;
        }
      }
    }
  }
}

/// Keep all displayed people represented within the existing API's 32-reference
/// limit. With a few people, include extra poses for more reliable matching.
Map<String, dynamic> encodeVideoTargetSelection(
  List<RefaceFaceGroup> groups,
  Set<int> selected,
) {
  final embeddings = <String>[];
  final picks = <int>[];
  final perPerson = groups.isEmpty ? 1 : (32 ~/ groups.length).clamp(1, 3);
  for (var i = 0; i < groups.length; i++) {
    for (final face in groups[i].samples.take(perPerson)) {
      if (selected.contains(i)) picks.add(embeddings.length);
      embeddings.add(encodeEmbedding(face.embedding));
    }
  }
  return {'target_embeddings': embeddings, 'target_indices': picks};
}
