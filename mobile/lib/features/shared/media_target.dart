import 'dart:ui';
import '../../data/api/dtos/analyze.dart';
import '../../data/repositories/media_queries.dart';

/// Match only the explicitly selected face occurrence to a fresh detection.
/// A weak or ambiguous overlap is left for the user to choose.
int? matchTargetFace(AnalyzeImageResponse result, MediaDetection? target) {
  if (target == null ||
      !target.isFace ||
      result.imageW <= 0 ||
      result.imageH <= 0) {
    return null;
  }
  final source = Rect.fromLTWH(target.x, target.y, target.w, target.h);
  var best = 0.0, second = 0.0;
  int? index;
  for (var i = 0; i < result.faces.length; i++) {
    final box = result.faces[i].bbox;
    final candidate = Rect.fromLTWH(
      box.x / result.imageW,
      box.y / result.imageH,
      box.w / result.imageW,
      box.h / result.imageH,
    );
    final intersection = source.intersect(candidate);
    final area = intersection.isEmpty
        ? 0.0
        : intersection.width * intersection.height;
    final union =
        source.width * source.height +
        candidate.width * candidate.height -
        area;
    final score = union <= 0 ? 0.0 : area / union;
    if (score > best) {
      second = best;
      best = score;
      index = i;
    } else if (score > second) {
      second = score;
    }
  }
  return best >= .5 && best - second >= .05 ? index : null;
}
