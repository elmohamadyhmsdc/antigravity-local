import 'review_repository.dart';

/// A visible batch, never an implicit acceptance of unseen matches.
const reviewBatchSize = 24;
const reviewSessionSize = 20;

/// The kinds of quick-review question, one per tab of the full Review screen.
enum ReviewQuestionKind { match, group, duplicate, outfit, doubtful }

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
    ReviewQuestionKind.outfit when method == 'event_outfit' => (0.90, 0.85),
    ReviewQuestionKind.outfit when method == 'cluster' => (0.90, 0.80),
    ReviewQuestionKind.outfit when method == 'tattoo' => (0.90, 0.75),
    ReviewQuestionKind.outfit => (0.84, 0.80),
    ReviewQuestionKind.group => (0.55, 0.45),
    // the average look of the doubted faces: the closer to the person, the likelier they are hers
    ReviewQuestionKind.doubtful => (0.50, 0.40),
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
      outfit = null,
      doubtful = null;

  ReviewQuestion.matchBatch(ReviewMatchGroup batch)
    : kind = ReviewQuestionKind.match,
      key =
          'mb:${batch.person.id}:${batch.faces.map((f) => f.faceId).join(',')}',
      score = batch.faces.map((f) => f.score).reduce((a, b) => a < b ? a : b),
      evidence = batch.faces.length,
      impact = batch.faces.length,
      match = batch,
      face = batch.faces.first,
      group = null,
      duplicate = null,
      outfit = null,
      doubtful = null;

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
      outfit = null,
      doubtful = null;

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
      outfit = null,
      doubtful = null;

  ReviewQuestion.outfit(ReviewBodyLinkItem this.outfit)
    : kind = ReviewQuestionKind.outfit,
      key = 'o:${outfit.bodyId}:${outfit.person.id}',
      score = outfit.confidence,
      evidence = 1,
      impact = 1,
      match = null,
      face = null,
      group = null,
      duplicate = null,
      doubtful = null;

  ReviewQuestion.doubtful(ReviewDoubtfulItem this.doubtful)
    : kind = ReviewQuestionKind.doubtful,
      key = 'x:${doubtful.person.id}:${doubtful.faces.first.faceId}',
      score = doubtful.averageScore,
      // "Not sure" reopens when the person has more doubtful faces than when it was parked
      evidence = doubtful.remaining,
      // one answer settles the whole batch
      impact = doubtful.faces.length,
      match = null,
      face = null,
      group = null,
      duplicate = null,
      outfit = null;

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
  final ReviewDoubtfulItem? doubtful;

  List<ReviewMatchFace> get matchFaces => kind != ReviewQuestionKind.match
      ? const []
      : key.startsWith('mb:')
      ? match!.faces
      : [face!];

  bool get isMatchBatch => matchFaces.length > 1;

  /// Low-evidence hypotheses remain in detailed review, without creating work
  /// in the daily queue. Existing identity errors always remain actionable.
  bool get actionable =>
      kind == ReviewQuestionKind.doubtful ||
      (likelihood != Likelihood.maybe &&
          (kind != ReviewQuestionKind.match ||
              matchFaces.every((f) => f.margin >= 0.05 && f.quality >= 0.45)));

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
  List<ReviewDoubtfulItem> doubtful = const [],
  Map<String, ReviewSnooze> snoozes = const {},
  bool includeDeferred = false,
}) {
  final matchQuestions = <ReviewQuestion>[];
  for (final m in matches) {
    // Stable ID order prevents score jitter from reshuffling every batch.
    final faces = [...m.faces]..sort((a, b) => a.faceId.compareTo(b.faceId));
    for (final likelihood in Likelihood.values) {
      final eligible = faces.where((f) {
        final q = ReviewQuestion.match(m, f);
        return q.likelihood == likelihood &&
            (includeDeferred || q.actionable) &&
            !(snoozes[q.key]?.stillHolds(q) ?? false);
      }).toList();
      for (var i = 0; i < eligible.length; i += reviewBatchSize) {
        final chunk = eligible.skip(i).take(reviewBatchSize).toList();
        matchQuestions.add(
          chunk.length == 1
              ? ReviewQuestion.match(m, chunk.single)
              : ReviewQuestion.matchBatch(
                  ReviewMatchGroup(person: m.person, faces: chunk),
                ),
        );
      }
    }
  }
  final all = [
    for (final d in duplicates) ReviewQuestion.duplicate(d),
    for (final g in groups) ReviewQuestion.group(g),
    ...matchQuestions,
    for (final o in outfits) ReviewQuestion.outfit(o),
    for (final x in doubtful) ReviewQuestion.doubtful(x),
  ];
  final open = [
    for (final q in all)
      if ((includeDeferred || q.actionable) &&
          !(snoozes[q.key]?.stillHolds(q) ?? false))
        q,
  ];
  final order = {for (var i = 0; i < open.length; i++) open[i]: i};
  open.sort((a, b) {
    // Repair existing contamination before adding more content to identities.
    final repair = (b.kind == ReviewQuestionKind.doubtful ? 1 : 0).compareTo(
      a.kind == ReviewQuestionKind.doubtful ? 1 : 0,
    );
    if (repair != 0) return repair;
    final impact = b.impact.compareTo(a.impact);
    if (impact != 0) return impact;
    final sure = a.likelihood.index.compareTo(b.likelihood.index);
    if (sure != 0) return sure;
    final score = a.kind == ReviewQuestionKind.doubtful && b.kind == a.kind
        ? a.score.compareTo(b.score)
        : b.score.compareTo(a.score);
    if (score != 0) return score;
    return order[a]!.compareTo(order[b]!);
  });
  return open;
}
