import 'dart:math' as math;
import 'dart:typed_data';

import '../../data/api/dtos/embedding.dart';

/// The PC's rules for "is this the same face / the same body again?", ported 1:1 from
/// library_scanner.py (`ScanOptions`) and person_linking.py so the phone and the PC agree.

/// A detection this similar (cosine >= 0.95, i.e. distance <= 0.05) to a face already in the library
/// is the same face seen again: it is linked, not stored twice. (`duplicate_distance`)
const duplicateCosine = 0.95;

/// Inside one file a near-identical face is the same face (`video_similar_distance` 0.08).
const sameFileCosine = 0.92;

/// Boxes overlapping this much (IoU) are the same detection when a file is scanned again.
const sameBoxIou = 0.5;

/// A faceless body whose outfit is this similar to one already kept in the file adds nothing.
const sameOutfitSimilarity = 0.9;

/// At most this many faceless bodies are kept per file (`max_bodies_per_media`).
const maxFacelessBodiesPerMedia = 40;

/// Intersection over union of two normalised boxes (x, y, w, h).
double iou(
  ({double x, double y, double w, double h}) a,
  ({double x, double y, double w, double h}) b,
) {
  final ix = math.max(0.0, math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x));
  final iy = math.max(0.0, math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y));
  final inter = ix * iy;
  final union = a.w * a.h + b.w * b.h - inter;
  return union > 0 ? inter / union : 0.0;
}

/// Dot product of two unit vectors.
double cosine(Float32List a, Float32List b) {
  var dot = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
  }
  return dot;
}

const _regionLen = 40; // person_linking.REGION_LEN
const _regionWeights = [0.6, 0.4]; // torso, legs

/// person_linking.appearance_similarity: weighted Bhattacharyya coefficient over the outfit regions
/// both bodies show (0..1).
double appearanceSimilarity(List<double>? a, List<double>? b) {
  if (a == null || b == null) return 0.0;
  var total = 0.0, weight = 0.0;
  for (var r = 0; r < _regionWeights.length; r++) {
    final from = r * _regionLen, to = (r + 1) * _regionLen;
    if (b.length < to || a.length < to) continue;
    var anyA = false, anyB = false;
    var dot = 0.0;
    for (var i = from; i < to; i++) {
      if (a[i] != 0) anyA = true;
      if (b[i] != 0) anyB = true;
      dot += a[i] * b[i];
    }
    if (anyA && anyB) {
      total += _regionWeights[r] * dot;
      weight += _regionWeights[r];
    }
  }
  return weight > 0 ? total / weight : 0.0;
}

/// 80 floats as the BLOB stored in `bodies.appearance`.
Uint8List appearanceToBlob(List<double> values) => packFloat32(values);

List<double> appearanceFromBlob(Uint8List blob) {
  final view = ByteData.sublistView(blob);
  return [
    for (var i = 0; i + 4 <= blob.length; i += 4)
      view.getFloat32(i, Endian.little),
  ];
}

({double x, double y, double w, double h}) clampBox(
  double x,
  double y,
  double w,
  double h,
) {
  final cx = x.clamp(0.0, 1.0).toDouble();
  final cy = y.clamp(0.0, 1.0).toDouble();
  return (
    x: cx,
    y: cy,
    w: math.min(w, 1.0 - cx).clamp(0.0, 1.0).toDouble(),
    h: math.min(h, 1.0 - cy).clamp(0.0, 1.0).toDouble(),
  );
}
