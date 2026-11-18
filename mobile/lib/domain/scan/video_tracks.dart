import 'dart:typed_data';

import 'scan_math.dart';
import 'track_assignment.dart';

/// Phone-only video tracking. A person who stays in a video for minutes used to become one face
/// row (and one review item) per sampled frame. A track is that continuous appearance: a few
/// varied views are kept as rows, every other frame is only a detection pointing at one of them.

/// A face continues a track of the same video when it is this similar to one of its views...
const trackIdentityCosine = 0.65;

/// ...or when it is at least this similar and sits where the track was a moment ago.
const trackMotionCosine = 0.40;
const trackMotionIou = 0.3;
const trackMotionGapMs = 4000;
const trackAssignmentMargin = 0.03;

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

  bool isRecent(int? timestampMs) {
    if (lastBox == null) return false;
    // Legacy rows without timestamps can only use spatial continuity.
    if (timestampMs == null && lastTimestampMs == null) return true;
    if (timestampMs == null || lastTimestampMs == null) return false;
    final gap = timestampMs - lastTimestampMs!;
    return gap > 0 && gap <= trackMotionGapMs;
  }

  bool isNear(NormBox box, int? timestampMs) =>
      isRecent(timestampMs) && iou(box, lastBox!) >= trackMotionIou;

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

/// Jointly assign a frame, with an unmatched option and an ambiguity margin.
/// A reappearance after a gap starts a new track; identity grouping can still
/// connect its faces later. Clothing requires spatial continuity as well.
List<Track<V>?> assignTracks<V>({
  required List<V> values,
  required List<NormBox> boxes,
  required int? timestampMs,
  required Iterable<Track<V>> tracks,
  required double Function(V, V) similarity,
  required double identity,
  required double motion,
  bool requireMotion = false,
}) {
  final out = List<Track<V>?>.filled(values.length, null);
  if (values.isEmpty) return out;
  final active =
      tracks
          .where((t) => t.views.isNotEmpty && t.isRecent(timestampMs))
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (active.isEmpty) return out;
  final weights = List.generate(
    values.length,
    (_) => List<double>.filled(active.length, 0),
  );
  for (var i = 0; i < values.length; i++) {
    for (var j = 0; j < active.length; j++) {
      final t = active[j];
      final (_, sim) = t.closest(values[i], similarity);
      final near = t.isNear(boxes[i], timestampMs);
      if (!sim.isFinite || ((requireMotion || timestampMs == null) && !near)) {
        continue;
      }
      if (sim >= identity || (near && sim >= motion)) {
        weights[i][j] = sim + (near ? 0.2 : 0);
      }
    }
  }
  final best = maximumTrackAssignment(weights);
  for (var i = 0; i < values.length; i++) {
    final j = best.columns[i];
    if (j == null) continue;
    if (weights[i].where((w) => w > 0).length > 1 ||
        weights.where((row) => row[j] > 0).length > 1) {
      final alternative = maximumTrackAssignment(weights, forbidden: (i, j));
      if (best.score - alternative.score <= trackAssignmentMargin) continue;
    }
    out[i] = active[j];
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

/// A motion match can retain a distinct view. Linking it to a saved crop once
/// the track is full needs either a strong match or support from two views.
bool supportsFaceCompaction<V>(
  Track<V> track,
  V value,
  double Function(V, V) similarity,
) {
  var supporting = 0;
  for (final view in track.views) {
    final score = similarity(view.value, value);
    if (score >= trackIdentityCosine) return true;
    if (score >= trackMotionCosine && ++supporting == 2) return true;
  }
  return false;
}

double outfitSimilarity(List<double>? a, List<double>? b) =>
    appearanceSimilarity(a, b);
