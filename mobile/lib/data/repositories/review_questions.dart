import 'review_repository.dart';

/// The four kinds of quick-review question, one per tab of the full Review screen.
enum ReviewQuestionKind { match, group, duplicate, outfit }

/// What the quick review shows instead of a percentage.
enum Likelihood { veryLikely, likely, maybe }

/// Turns a PC score into words. Cut points sit between the "suggest" and "auto" thresholds of the
/// balanced `person_linking.GroupingParams` (match 0.25-0.40, merge 0.40-0.60, outfit 0.78-0.86),
/// so "Very likely" means "almost good enough to have been decided without asking".
Likelihood likelihoodOf(
  ReviewQuestionKind kind,
  double score, {
  String? method,
}) {
  final (high, mid) = switch (kind) {
    ReviewQuestionKind.match => (0.40, 0.32),
    ReviewQuestionKind.duplicate => (0.55, 0.47),
    ReviewQuestionKind.outfit when method == 'weak_face' => (0.40, 0.32),
    ReviewQuestionKind.outfit => (0.84, 0.80),
    ReviewQuestionKind.group => (0.55, 0.45),
  };
  if (score >= high) return Likelihood.veryLikely;
  if (score >= mid) return Likelihood.likely;
  return Likelihood.maybe;
}

/// One decision of the quick review. Exactly one of [match], [group], [duplicate], [outfit] is set.
class ReviewQuestion {
  ReviewQuestion.match(ReviewMatchGroup this.match, ReviewMatchFace this.face)
    : kind = ReviewQuestionKind.match,
      key = 'm:${face.faceId}:${match.person.id}',
      score = face.score,
      evidence = 1,
      impact = 1,
      group = null,
      duplicate = null,
      outfit = null;

  ReviewQuestion.group(ReviewGroupItem this.group)
    : kind = ReviewQuestionKind.group,
      key =
          'g:${group.faces.map((f) => f.faceId).reduce((a, b) => a < b ? a : b)}',
      score = group.cohesion,
      evidence = group.faces.length,
      impact = group.faces.length,
      match = null,
      face = null,
      duplicate = null,
      outfit = null;

  ReviewQuestion.duplicate(ReviewDuplicateItem this.duplicate)
    : kind = ReviewQuestionKind.duplicate,
      key = 'd:${duplicate.a.id}:${duplicate.b.id}',
      score = duplicate.score,
      evidence = 1,
      // a merge sorts every face of the smaller person at once
      impact = duplicate.a.faceCount < duplicate.b.faceCount
          ? duplicate.a.faceCount
          : duplicate.b.faceCount,
      match = null,
      face = null,
      group = null,
      outfit = null;

  ReviewQuestion.outfit(ReviewBodyLinkItem this.outfit)
    : kind = ReviewQuestionKind.outfit,
      key = 'o:${outfit.bodyId}:${outfit.person.id}',
      score = outfit.confidence,
      evidence = 1,
      impact = 1,
      match = null,
      face = null,
      group = null,
      duplicate = null;

  final ReviewQuestionKind kind;

  /// Stable across grouping runs (review_groups ids are not), see `ReviewSnoozes`.
  final String key;
  final double score;

  /// Faces behind a new-group question; "Not sure" waits until this or [score] grows. Other
  /// questions reopen on a higher score only: a person's own face count changes with every answer,
  /// while the score is the PC's view after it has seen those faces.
  final int evidence;

  /// Faces one answer sorts.
  final int impact;

  final ReviewMatchGroup? match;
  final ReviewMatchFace? face;
  final ReviewGroupItem? group;
  final ReviewDuplicateItem? duplicate;
  final ReviewBodyLinkItem? outfit;

  Likelihood get likelihood =>
      likelihoodOf(kind, score, method: outfit?.method);
}

/// A "Not sure" answer as stored.
class ReviewSnooze {
  const ReviewSnooze({required this.score, required this.evidence});

  final double score;
  final int evidence;

  /// Smaller score changes are noise from re-running the same grouping.
  static const scoreStep = 0.02;

  bool stillHolds(ReviewQuestion q) =>
      q.score < score + scoreStep && q.evidence <= evidence;
}

/// Every open question minus the snoozed ones, highest impact first, then the most certain
/// (the easiest to answer) first.
List<ReviewQuestion> buildQuestions({
  required List<ReviewMatchGroup> matches,
  required List<ReviewGroupItem> groups,
  required List<ReviewDuplicateItem> duplicates,
  required List<ReviewBodyLinkItem> outfits,
  Map<String, ReviewSnooze> snoozes = const {},
}) {
  final all = [
    for (final d in duplicates) ReviewQuestion.duplicate(d),
    for (final g in groups) ReviewQuestion.group(g),
    for (final m in matches)
      for (final f in m.faces) ReviewQuestion.match(m, f),
    for (final o in outfits) ReviewQuestion.outfit(o),
  ];
  final open = [
    for (final q in all)
      if (!(snoozes[q.key]?.stillHolds(q) ?? false)) q,
  ];
  final order = {for (var i = 0; i < open.length; i++) open[i]: i};
  open.sort((a, b) {
    final impact = b.impact.compareTo(a.impact);
    if (impact != 0) return impact;
    final sure = a.likelihood.index.compareTo(b.likelihood.index);
    if (sure != 0) return sure;
    return order[a]!.compareTo(order[b]!);
  });
  return open;
}
