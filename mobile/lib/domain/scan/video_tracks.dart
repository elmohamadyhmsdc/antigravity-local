import 'dart:typed_data';

import 'scan_math.dart';

/// Phone-only video tracking. A person who stays in a video for minutes used to become one face
/// row (and one review item) per sampled frame. A track is that continuous appearance: a few
/// varied views are kept as rows, every other frame is only a detection pointing at one of them.

/// A face continues a track of the same video when it is this similar to one of its views...
const trackIdentityCosine = 0.65;

/// ...or when it is at least this similar and sits where the track was a moment ago.
const trackMotionCosine = 0.40;
const trackMotionIou = 0.3;
const trackMotionGapMs = 4000;

/// A track keeps at most this many face rows: each a view unlike the others or clearly sharper.
const maxFacesPerTrack = 5;
const trackDiverseCosine = 0.85;
const trackUpgradeQuality = 0.15;

/// Faceless bodies continue a track by outfit; bodies with a face follow the face's track.
const maxBodiesPerTrack = 3;
const trackMotionOutfit = 0.7;
const trackDiverseOutfit = 0.95;

typedef NormBox = ({double x, double y, double w, double h});

class TrackView<V> {
  TrackView({
    required this.id,
    required this.value,
    this.quality = 0,
    this.replaceable = false,
  });

  final int id;
  V value;
  double quality;

  /// Untouched by the user (unsorted, no corrections or references), so it may be replaced.
  bool replaceable;
}

class Track<V> {
  Track(this.id, {this.faceTrack});

  final int id;
  final views = <TrackView<V>>[];

  /// For a body track: the face track its bodies belong to (null = faceless).
  int? faceTrack;
  NormBox? lastBox;
  int? lastTimestampMs;

  bool isNear(NormBox box, int? timestampMs) =>
      lastBox != null &&
      (timestampMs == null ||
          lastTimestampMs == null ||
          (timestampMs - lastTimestampMs!).abs() <= trackMotionGapMs) &&
      iou(box, lastBox!) >= trackMotionIou;

  (TrackView<V>?, double) closest(V value, double Function(V, V) similarity) {
    TrackView<V>? best;
    var score = -1.0;
    for (final v in views) {
      final s = similarity(v.value, value);
      if (s > score) {
        score = s;
        best = v;
      }
    }
    return (best, score);
  }
}

/// Greedy one-to-one assignment of one frame's detections to tracks (a person is in a frame
/// once). Entry i is the track for detection i, or null for a new track.
List<Track<V>?> assignTracks<V>({
  required List<V> values,
  required List<NormBox> boxes,
  required int? timestampMs,
  required Iterable<Track<V>> tracks,
  required double Function(V, V) similarity,
  required double identity,
  required double motion,
}) {
  final pairs = <(double, int, Track<V>)>[];
  for (var i = 0; i < values.length; i++) {
    for (final t in tracks) {
      if (t.views.isEmpty) continue;
      final (_, sim) = t.closest(values[i], similarity);
      final near = t.isNear(boxes[i], timestampMs);
      if (sim >= identity || (near && sim >= motion)) {
        pairs.add((sim + (near ? 0.2 : 0), i, t));
      }
    }
  }
  pairs.sort((a, b) => b.$1.compareTo(a.$1));
  final out = List<Track<V>?>.filled(values.length, null);
  final used = <int>{};
  for (final (_, i, t) in pairs) {
    if (out[i] != null || used.contains(t.id)) continue;
    out[i] = t;
    used.add(t.id);
  }
  return out;
}

sealed class TrackPlacement<V> {
  const TrackPlacement();
}

/// Store the detection as a new view of the track.
class InsertView<V> extends TrackPlacement<V> {
  const InsertView();
}

/// Overwrite this weaker, untouched view with the detection.
class ReplaceView<V> extends TrackPlacement<V> {
  const ReplaceView(this.view);
  final TrackView<V> view;
}

/// The track already shows this: the detection only points at the view.
class LinkView<V> extends TrackPlacement<V> {
  const LinkView(this.view);
  final TrackView<V> view;
}

TrackPlacement<V> placeInTrack<V>(
  Track<V> track,
  V value,
  double quality, {
  required double Function(V, V) similarity,
  required int maxViews,
  required double diverse,
}) {
  final (closest, sim) = track.closest(value, similarity);
  if (closest == null) return const InsertView();
  var best = closest.quality;
  TrackView<V>? weakest;
  for (final v in track.views) {
    if (v.quality > best) best = v.quality;
    if (v.replaceable && (weakest == null || v.quality < weakest.quality)) {
      weakest = v;
    }
  }
  final upgrade = quality > best + trackUpgradeQuality;
  if (track.views.length < maxViews && (sim < diverse || upgrade)) {
    return const InsertView();
  }
  if (weakest != null && quality > weakest.quality + trackUpgradeQuality) {
    return ReplaceView(weakest);
  }
  return LinkView(closest);
}

double faceSimilarity(Float32List a, Float32List b) => cosine(a, b);

double outfitSimilarity(List<double>? a, List<double>? b) =>
    appearanceSimilarity(a, b);
