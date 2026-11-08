import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_questions.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/review_visual_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import 'highlighted_photo.dart';
import 'review_media_viewer.dart';
import 'review_screen.dart';
import 'review_words.dart';

/// `/review`: the quick review, or the four tabs when Advanced details is on. `?view=all` and
/// `?view=quick` pick one regardless. Chosen once, so switching numbers on from the quick review's
/// menu does not swap the screen under the user.
class ReviewEntryScreen extends ConsumerStatefulWidget {
  const ReviewEntryScreen({super.key, this.view, this.kind = 'person'});

  final String? view;

  /// 'person' or 'character'.
  final String kind;

  @override
  ConsumerState<ReviewEntryScreen> createState() => _ReviewEntryScreenState();
}

class _ReviewEntryScreenState extends ConsumerState<ReviewEntryScreen> {
  bool? _all;

  @override
  Widget build(BuildContext context) {
    _all ??= switch (widget.view) {
      'all' => true,
      'quick' => false,
      _ => switch (ref.watch(settingsProvider)) {
        AsyncData(:final value) => value.reviewAdvanced,
        AsyncError() => false,
        _ => null,
      },
    };
    return switch (_all) {
      null => Scaffold(appBar: AppBar(), body: const LoadingBox()),
      true => ReviewScreen(kind: widget.kind),
      false => QuickReviewScreen(kind: widget.kind),
    };
  }
}

/// Opens the full four-tab review ("See all").
void openAllReview(
  BuildContext context, [
  String kind = 'person',
]) => context.push(
  '${Routes.review}?view=all${kind == 'character' ? '&kind=character' : ''}',
);

/// S10 quick review - one question at a time with the face highlighted on the whole photo, big
/// Yes / No / Not sure buttons (or swipe right / left), most useful questions first. Every answer is
/// the same correction the four tabs record; "Not sure" parks the question on this phone.
class QuickReviewScreen extends ConsumerStatefulWidget {
  const QuickReviewScreen({super.key, this.kind = 'person'});

  final String kind;

  @override
  ConsumerState<QuickReviewScreen> createState() => _QuickReviewScreenState();
}

class _QuickReviewScreenState extends ConsumerState<QuickReviewScreen> {
  var _answered = 0;
  var _sessionStart = 0;

  /// Answered here, with the evidence it was answered on: hidden until the stored plan catches
  /// up, but shown again when a parked question comes back with new evidence.
  final _done = <String, (double, int)>{};
  var _busy = false;
  var _drag = 0.0;

  /// "Are you sure?" questions: the faces the user tapped as NOT that person, per question.
  final _marked = <String, Set<int>>{};

  /// Questions where the user chose to send the removed faces to the person they look like.
  final _moveTo = <String>{};

  /// face -> the person the audit found a better home in (only for the faces that have one).
  Map<int, int> _suggestions(ReviewQuestion q, Iterable<int> faceIds) {
    if (!_moveTo.contains(q.key)) return const {};
    final wanted = faceIds.toSet();
    return {
      for (final f in q.doubtful!.faces)
        if (wanted.contains(f.faceId) && f.suggested != null)
          f.faceId: f.suggested!.id,
    };
  }

  ReviewRepository get _review => reviewRepositoryFor(ref, widget.kind);
  PeopleRepository get _people => peopleRepositoryFor(ref, widget.kind);

  Future<void> _run(ReviewQuestion q, Future<bool> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _drag = 0;
    });
    try {
      if (await action() && mounted) {
        setState(() {
          _answered++;
          _done[q.key] = (q.score, q.evidence);
        });
      }
    } catch (e) {
      if (mounted) {
        _toast(
          ScaffoldMessenger.of(context),
          AppLocalizations.of(context).peopleActionError('$e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Floats above the answer buttons so the next answer is never a tap on a snackbar.
  void _toast(
    ScaffoldMessengerState messenger,
    String text, {
    SnackBarAction? action,
  }) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          _answered - _sessionStart + 1 >= reviewSessionSize ? 16 : 160,
        ),
      ),
    );

  Future<void> _yes(ReviewQuestion q) => _run(q, () async {
    switch (q.kind) {
      case ReviewQuestionKind.match:
        final excluded = _marked[q.key] ?? const <int>{};
        await _review.answerMatchBatch(
          [for (final f in q.matchFaces) f.faceId],
          q.match!.person.id,
          excluded: excluded,
        );
      case ReviewQuestionKind.outfit:
        await _review.acceptBodyLink(q.outfit!.bodyId, q.outfit!.person.id);
      case ReviewQuestionKind.duplicate:
        return _merge(q.duplicate!);
      case ReviewQuestionKind.group:
        return false; // answered by _GroupAnswer
      case ReviewQuestionKind.doubtful:
        // the faces not tapped are confirmed (and become the trusted core), the tapped ones leave
        final item = q.doubtful!;
        final out = _marked[q.key] ?? <int>{};
        final keep = [
          for (final x in item.faces)
            if (!out.contains(x.faceId)) x.faceId,
        ];
        if (keep.isNotEmpty) {
          await _review.confirmDoubtful(keep, item.person.id);
        }
        if (out.isNotEmpty) {
          await _review.removeDoubtful(
            out,
            item.person.id,
            moveTo: _suggestions(q, out),
          );
        }
    }
    return true;
  });

  Future<void> _no(ReviewQuestion q) => _run(q, () async {
    switch (q.kind) {
      case ReviewQuestionKind.match:
        final ids = [for (final f in q.matchFaces) f.faceId];
        await _review.answerMatchBatch(
          ids,
          q.match!.person.id,
          excluded: ids.toSet(),
        );
      case ReviewQuestionKind.outfit:
        await _review.rejectBodyLink(q.outfit!.bodyId, q.outfit!.person.id);
      case ReviewQuestionKind.duplicate:
        await _people.markDistinct(q.duplicate!.a.id, q.duplicate!.b.id);
      case ReviewQuestionKind.group:
        await _review.dismissGroup(q.group!.id);
      case ReviewQuestionKind.doubtful:
        // none of these is her
        final all = [for (final x in q.doubtful!.faces) x.faceId];
        await _review.removeDoubtful(
          all,
          q.doubtful!.person.id,
          moveTo: _suggestions(q, all),
        );
    }
    return true;
  });

  /// Questions that offer "Ignore": the ones about faces (not two people, not an outfit).
  bool _ignorable(ReviewQuestion q) =>
      q.kind == ReviewQuestionKind.match ||
      q.kind == ReviewQuestionKind.group ||
      q.kind == ReviewQuestionKind.doubtful;

  /// "Ignore": not important, never ask about these faces again (in Review or in grouping).
  Future<void> _ignore(ReviewQuestion q) => _run(q, () async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final List<int> ids;
    switch (q.kind) {
      case ReviewQuestionKind.match:
        ids = await _review.ignoreFaces([
          for (final f in q.matchFaces) f.faceId,
        ]);
      case ReviewQuestionKind.group:
        ids = await _review.dismissGroup(q.group!.id);
      case ReviewQuestionKind.doubtful:
        ids = await _review.ignoreDoubtful([
          for (final x in q.doubtful!.faces) x.faceId,
        ], q.doubtful!.person.id);
      case ReviewQuestionKind.duplicate || ReviewQuestionKind.outfit:
        return false;
    }
    _toast(
      messenger,
      'Ignored ${ids.length} face${ids.length == 1 ? '' : 's'}. They will not come back.',
      action: SnackBarAction(
        label: l.peopleAction('undo'),
        onPressed: () async {
          await _review.restoreIgnored(ids);
          if (mounted) {
            setState(() {
              _answered--;
              _sessionStart = _sessionStart.clamp(0, _answered);
              _done.remove(q.key);
            });
          }
        },
      ),
    );
    return true;
  });

  Future<void> _notSure(ReviewQuestion q) => _run(q, () async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await _review.snooze(q);
    _toast(
      messenger,
      l.quickSnoozed,
      action: SnackBarAction(
        label: l.peopleAction('undo'),
        onPressed: () async {
          await _review.unsnooze(q);
          if (mounted) {
            setState(() {
              _answered--;
              _sessionStart = _sessionStart.clamp(0, _answered);
              _done.remove(q.key);
            });
          }
        },
      ),
    );
    return true;
  });

  Future<void> _group(ReviewQuestion q, String name, PersonSummary? person) =>
      _run(q, () async {
        final ids = [for (final f in q.group!.faces) f.faceId];
        if (person != null) {
          await _review.assignGroup(ids, person.id);
        } else {
          await _review.createPersonFromGroup(name: name, faceIds: ids);
        }
        await _review.forgetGroup(q.group!.id);
        return true;
      });

  /// "Same person?" Yes. Two different names need the user's choice, so that goes to Merge.
  Future<bool> _merge(ReviewDuplicateItem d) async {
    final l = AppLocalizations.of(context);
    final aName = (d.a.name ?? '').trim();
    final bName = (d.b.name ?? '').trim();
    if (aName.isNotEmpty &&
        bName.isNotEmpty &&
        aName.toLowerCase() != bName.toLowerCase()) {
      await context.push('${Routes.merge}/${d.a.id}/${d.b.id}');
      return false; // the stream drops the pair if it was merged there
    }
    final keepA =
        d.a.faceCount > d.b.faceCount ||
        (d.a.faceCount == d.b.faceCount && aName.isNotEmpty) ||
        (d.a.faceCount == d.b.faceCount && bName.isEmpty);
    final keep = keepA ? d.a : d.b;
    final drop = keepA ? d.b : d.a;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _people.mergePeople(sourceId: drop.id, targetId: keep.id);
    } on MergeBlockedException catch (e) {
      _toast(messenger, e.message);
      return false;
    }
    // an unnamed person takes the other one's name (PeopleRepository.mergePeople)
    final shown = !keep.isNamed && drop.isNamed ? drop : keep;
    _toast(messenger, l.mergedInto(personName(l, shown)));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final questions = ref.watch(reviewQuestionsByKindProvider(widget.kind));
    final advanced = ref.watch(reviewAdvancedProvider);
    final sorting = ref.watch(manualSortRunningProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.quickReviewTitle),
        actions: [
          IconButton(
            key: const Key('review-sort-now'),
            tooltip: sorting ? l.sorting : l.sortNow,
            icon: sorting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            onPressed: sorting ? null : () => sortNow(context, ref),
          ),
          TextButton(
            key: const Key('quick-see-all'),
            onPressed: () => openAllReview(context, widget.kind),
            child: Text(l.quickSeeAll),
          ),
          PopupMenuButton<String>(
            key: const Key('quick-menu'),
            onSelected: (v) {
              if (v == 'advanced') {
                ref.read(appSettingsProvider).setReviewAdvanced(!advanced);
              }
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                key: const Key('quick-advanced'),
                value: 'advanced',
                checked: advanced,
                child: Text(l.reviewAdvancedTitle),
              ),
            ],
          ),
        ],
      ),
      body: questions.when(
        loading: () => const LoadingBox(),
        error: (_, _) => RetryState(
          onRetry: () =>
              ref.invalidate(reviewQuestionsByKindProvider(widget.kind)),
        ),
        data: (all) {
          final open = [
            for (final q in all)
              if (_done[q.key] != (q.score, q.evidence)) q,
          ];
          if (open.isEmpty) {
            final left =
                ref
                    .watch(reviewCountsByKindProvider(widget.kind))
                    .value
                    ?.rawTotal ??
                0;
            return EmptyState(
              key: const Key('quick-all-done'),
              icon: Icons.task_alt,
              title: l.quickAllDone,
              body: left > 0 ? l.reviewDeferred(left) : l.quickAllDoneBody,
              actionLabel: left > 0 ? l.quickSeeAll : null,
              onAction: left > 0
                  ? () => openAllReview(context, widget.kind)
                  : null,
            );
          }
          final sessionAnswered = _answered - _sessionStart;
          if (sessionAnswered >= reviewSessionSize) {
            return EmptyState(
              key: const Key('quick-session-done'),
              icon: Icons.task_alt,
              title: l.reviewSessionDone,
              body: l.reviewSessionRemaining(open.length),
              actionLabel: l.reviewNextSession,
              onAction: () => setState(() => _sessionStart = _answered),
            );
          }
          final q = open.first;
          final total =
              sessionAnswered +
              open.length.clamp(0, reviewSessionSize - sessionAnswered);
          return _QuestionView(
            key: ValueKey(q.key),
            question: q,
            kind: widget.kind,
            position: sessionAnswered + 1,
            total: total,
            advanced: advanced,
            busy: _busy,
            drag: _drag,
            marked: _marked[q.key] ?? const <int>{},
            moveToSuggested: _moveTo.contains(q.key),
            onToggleMove: () => setState(() {
              if (!_moveTo.remove(q.key)) _moveTo.add(q.key);
            }),
            onToggle: (faceId) => setState(() {
              final set = _marked.putIfAbsent(q.key, () => <int>{});
              if (!set.remove(faceId)) set.add(faceId);
            }),
            onDrag:
                q.isMatchBatch ||
                    q.kind == ReviewQuestionKind.group ||
                    q.kind == ReviewQuestionKind.doubtful
                ? null
                : (dx) => setState(() => _drag += dx),
            onDragEnd: (velocity) {
              if (_drag > 120 || velocity > 800) {
                _yes(q);
              } else if (_drag < -120 || velocity < -800) {
                _no(q);
              } else {
                setState(() => _drag = 0);
              }
            },
            onYes: () => _yes(q),
            onNo: () => _no(q),
            onNotSure: () => _notSure(q),
            onIgnore: _ignorable(q) ? () => _ignore(q) : null,
            onGroup: (name, person) => _group(q, name, person),
          );
        },
      ),
    );
  }
}

class _QuestionView extends ConsumerWidget {
  const _QuestionView({
    super.key,
    required this.question,
    required this.kind,
    required this.position,
    required this.total,
    required this.advanced,
    required this.busy,
    required this.drag,
    required this.onDrag,
    required this.onDragEnd,
    required this.onYes,
    required this.onNo,
    required this.onNotSure,
    required this.onGroup,
    this.onIgnore,
    required this.marked,
    required this.onToggle,
    required this.moveToSuggested,
    required this.onToggleMove,
  });

  /// "Move to the person they look like" is on for this question.
  final bool moveToSuggested;
  final VoidCallback onToggleMove;

  /// Faces of an "are you sure?" question the user tapped as not that person.
  final Set<int> marked;
  final ValueChanged<int> onToggle;

  final ReviewQuestion question;
  final String kind;
  final int position, total;
  final bool advanced, busy;
  final double drag;
  final ValueChanged<double>? onDrag;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onYes, onNo, onNotSure;

  /// "Ignore" (null where the question does not offer it).
  final VoidCallback? onIgnore;
  final void Function(String name, PersonSummary? person) onGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final q = question;
    final likelihood = scoreLabel(
      l,
      advanced: advanced,
      kind: q.kind,
      score: q.score,
      method: q.outfit?.method,
    );
    final (title, subtitle, person) = switch (q.kind) {
      ReviewQuestionKind.match => (
        q.isMatchBatch
            ? l.reviewBatchQuestion(
                personName(l, q.match!.person),
                q.matchFaces.length,
              )
            : l.reviewMatchQuestion(personName(l, q.match!.person)),
        likelihood,
        q.match!.person,
      ),
      ReviewQuestionKind.outfit => (
        l.reviewMatchQuestion(personName(l, q.outfit!.person)),
        '${switch (q.outfit!.method) {
          'appearance' => l.quickByClothes,
          'event_outfit' => l.quickByEventOutfit,
          'cluster' => l.quickByCluster,
          'tattoo' => l.quickByTattoo,
          _ => l.quickByWeakFace,
        }} · $likelihood',
        q.outfit!.person,
      ),
      ReviewQuestionKind.duplicate => (l.quickSamePerson, likelihood, null),
      ReviewQuestionKind.group => (
        l.quickWhoIsThis,
        l.quickGroupFaces(q.group!.faces.length),
        null,
      ),
      ReviewQuestionKind.doubtful => (
        'Are you sure these are ${personName(l, q.doubtful!.person)}?',
        '${q.doubtful!.remaining} of her faces look different from the rest',
        q.doubtful!.person,
      ),
    };

    final media = switch (q.kind) {
      ReviewQuestionKind.match =>
        q.isMatchBatch
            ? _Doubtful(
                item: ReviewDoubtfulItem(
                  person: q.match!.person,
                  faces: [
                    for (final f in q.matchFaces)
                      ReviewDoubtfulFace(
                        faceId: f.faceId,
                        cropPath: f.cropPath,
                        score: f.score,
                      ),
                  ],
                  remaining: q.matchFaces.length,
                ),
                marked: marked,
                onToggle: onToggle,
              )
            : _Photo(kind: 'f', id: q.face!.faceId),
      ReviewQuestionKind.outfit => _Photo(kind: 'b', id: q.outfit!.bodyId),
      ReviewQuestionKind.duplicate => _Pair(item: q.duplicate!),
      ReviewQuestionKind.group => _Group(item: q.group!),
      ReviewQuestionKind.doubtful => _Doubtful(
        item: q.doubtful!,
        marked: marked,
        onToggle: onToggle,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              Text(
                l.quickReviewProgress(position, total),
                key: const Key('quick-progress'),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (position - 1) / total,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              if (person != null) ...[
                PersonAvatar(cropPath: person.avatarCropPath, radius: 22),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      key: const Key('quick-question'),
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      subtitle,
                      key: const Key('quick-likelihood'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            key: const Key('quick-card'),
            onHorizontalDragUpdate: onDrag == null || busy
                ? null
                : (d) => onDrag!(d.delta.dx),
            onHorizontalDragEnd: onDrag == null || busy
                ? null
                : (d) => onDragEnd(d.primaryVelocity ?? 0),
            child: Transform.translate(
              offset: Offset(drag, 0),
              child: Transform.rotate(
                angle: drag / 1500,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: media,
                      ),
                    ),
                    if (drag.abs() > 24)
                      Positioned(
                        top: 24,
                        left: drag > 0 ? 24 : null,
                        right: drag < 0 ? 24 : null,
                        child: _SwipeStamp(yes: drag > 0),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: q.kind == ReviewQuestionKind.group
                ? _GroupAnswer(
                    kind: kind,
                    busy: busy,
                    onSave: onGroup,
                    onNo: onNo,
                    onNotSure: onNotSure,
                    onIgnore: onIgnore,
                  )
                : q.kind == ReviewQuestionKind.doubtful || q.isMatchBatch
                ? _DoubtfulBar(
                    name: personName(
                      l,
                      q.isMatchBatch ? q.match!.person : q.doubtful!.person,
                    ),
                    total: q.isMatchBatch
                        ? q.matchFaces.length
                        : q.doubtful!.faces.length,
                    marked: marked.length,
                    suggestions: [
                      for (final f
                          in q.doubtful?.faces ?? <ReviewDoubtfulFace>[])
                        if (f.suggested != null) f,
                    ].length,
                    move: moveToSuggested,
                    onMove: onToggleMove,
                    busy: busy,
                    onYes: onYes,
                    onNo: onNo,
                    onNotSure: onNotSure,
                    onIgnore: onIgnore,
                  )
                : _YesNoBar(
                    busy: busy,
                    onYes: onYes,
                    onNo: onNo,
                    onNotSure: onNotSure,
                    onIgnore: onIgnore,
                  ),
          ),
        ),
      ],
    );
  }
}

class _SwipeStamp extends StatelessWidget {
  const _SwipeStamp({required this.yes});

  final bool yes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = yes ? Colors.green.shade600 : Colors.red.shade600;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .9),
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          yes ? l.quickYes : l.quickNo,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _YesNoBar extends StatelessWidget {
  const _YesNoBar({
    required this.busy,
    required this.onYes,
    required this.onNo,
    required this.onNotSure,
    this.onIgnore,
  });

  final bool busy;
  final VoidCallback onYes, onNo, onNotSure;
  final VoidCallback? onIgnore;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const size = Size.fromHeight(56);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l.quickSwipeHint,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('quick-no'),
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: busy ? null : onNo,
                icon: const Icon(Icons.close),
                label: Text(l.quickNo),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                key: const Key('quick-unsure'),
                style: TextButton.styleFrom(minimumSize: size),
                onPressed: busy ? null : onNotSure,
                child: Text(l.quickNotSure, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                key: const Key('quick-yes'),
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: busy ? null : onYes,
                icon: const Icon(Icons.check),
                label: Text(l.quickYes),
              ),
            ),
          ],
        ),
        if (onIgnore != null)
          TextButton.icon(
            key: const Key('quick-ignore'),
            onPressed: busy ? null : onIgnore,
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Ignore - not important, never show again'),
          ),
      ],
    );
  }
}

/// "Who is this?": one field that names a new person or, picked from the suggestions, adds the
/// faces to someone who already exists.
class _GroupAnswer extends ConsumerStatefulWidget {
  const _GroupAnswer({
    required this.kind,
    required this.busy,
    required this.onSave,
    required this.onNo,
    required this.onNotSure,
    this.onIgnore,
  });

  final String kind;
  final bool busy;
  final void Function(String name, PersonSummary? person) onSave;
  final VoidCallback onNo, onNotSure;
  final VoidCallback? onIgnore;

  @override
  ConsumerState<_GroupAnswer> createState() => _GroupAnswerState();
}

class _GroupAnswerState extends ConsumerState<_GroupAnswer> {
  final _name = TextEditingController();
  final _focus = FocusNode();
  PersonSummary? _picked;

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final people = [
      for (final p
          in ref
                  .watch(
                    widget.kind == 'character'
                        ? charactersProvider
                        : peopleProvider,
                  )
                  .value ??
              const <PersonSummary>[])
        if (!p.hidden && p.isNamed) p,
    ];
    // typing an existing name exactly is the same as picking that person
    final typed = _name.text.trim().toLowerCase();
    final exact = [
      for (final p in people)
        if (personName(l, p).toLowerCase() == typed) p,
    ];
    final picked =
        _picked != null && _name.text.trim() == personName(l, _picked!)
        ? _picked
        : exact.length == 1
        ? exact.single
        : null;
    const size = Size.fromHeight(56);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RawAutocomplete<PersonSummary>(
          textEditingController: _name,
          focusNode: _focus,
          displayStringForOption: (p) => personName(l, p),
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return const Iterable<PersonSummary>.empty();
            return people
                .where((p) => personName(l, p).toLowerCase().contains(q))
                .take(6);
          },
          onSelected: (p) => setState(() => _picked = p),
          fieldViewBuilder: (context, controller, focus, onSubmit) => TextField(
            key: const Key('quick-group-name'),
            controller: controller,
            focusNode: focus,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: l.personNameLabel,
              hintText: l.quickWhoHint,
              prefixIcon: picked == null
                  ? const Icon(Icons.person_add_alt_1)
                  : Padding(
                      padding: const EdgeInsets.all(8),
                      child: PersonAvatar(
                        cropPath: picked.avatarCropPath,
                        radius: 14,
                      ),
                    ),
              helperText: picked == null
                  ? l.quickNewPersonHelper
                  : l.quickAddToHelper(personName(l, picked)),
            ),
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.bottomLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final p in options)
                      ListTile(
                        key: Key('quick-group-option-${p.id}'),
                        leading: PersonAvatar(
                          cropPath: p.avatarCropPath,
                          radius: 18,
                        ),
                        title: Text(personName(l, p)),
                        subtitle: Text(l.facesCount(p.faceCount)),
                        onTap: () => onSelected(p),
                      ),
                  ],
                ),
              ),
            ),
          ),
          optionsViewOpenDirection: OptionsViewOpenDirection.up,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('quick-no'),
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: widget.busy ? null : widget.onNo,
                child: Text(l.notAPerson, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                key: const Key('quick-unsure'),
                style: TextButton.styleFrom(minimumSize: size),
                onPressed: widget.busy ? null : widget.onNotSure,
                child: Text(l.quickNotSure, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('quick-yes'),
                style: FilledButton.styleFrom(minimumSize: size),
                onPressed: widget.busy
                    ? null
                    : () => widget.onSave(_name.text.trim(), picked),
                child: Text(l.save),
              ),
            ),
          ],
        ),
        if (widget.onIgnore != null)
          TextButton.icon(
            key: const Key('quick-ignore'),
            onPressed: widget.busy ? null : widget.onIgnore,
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Ignore - not important, never show again'),
          ),
      ],
    );
  }
}

/// The whole photo with the face (or body) highlighted; tap for every photo of it, videos included.
class _Photo extends StatelessWidget {
  const _Photo({required this.kind, required this.id});

  final String kind;
  final int id;

  @override
  Widget build(BuildContext context) => InkWell(
    key: Key('quick-photo-$kind-$id'),
    onTap: () => openReviewMedia(context, [ReviewTarget(kind, id)]),
    child: HighlightedPhoto(kind: kind, id: id),
  );
}

class _Pair extends ConsumerWidget {
  const _Pair({required this.item});

  final ReviewDuplicateItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    Widget side(PersonSummary p) => Expanded(
      child: InkWell(
        key: Key('quick-pair-${p.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => reviewPersonPhotos(context, ref, p.id, personName(l, p)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CropImage(path: p.avatarCropPath, cacheWidth: 600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              personName(l, p),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              l.facesCount(p.faceCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [side(item.a), const SizedBox(width: 12), side(item.b)],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.item});

  final ReviewGroupItem item;

  @override
  Widget build(BuildContext context) {
    final best = item.faces.reduce((a, b) => b.quality > a.quality ? b : a);
    return Column(
      children: [
        Expanded(
          child: _Photo(kind: 'f', id: best.faceId),
        ),
        if (item.faces.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 64,
            child: ListView.separated(
              key: const Key('quick-group-faces'),
              scrollDirection: Axis.horizontal,
              itemCount: item.faces.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, i) => InkWell(
                onTap: () => openReviewMedia(context, [
                  for (final f in item.faces) ReviewTarget('f', f.faceId),
                ], initialTarget: i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    child: CropImage(path: item.faces[i].cropPath),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Tap the faces that are NOT her": a grid of the person's most doubtful faces (worst first). A
/// tapped face is marked for removal; long-press opens it in its photo. A caption shows the other
/// person a face looks more like, when there is one.
class _Doubtful extends StatelessWidget {
  const _Doubtful({
    required this.item,
    required this.marked,
    required this.onToggle,
  });

  final ReviewDoubtfulItem item;
  final Set<int> marked;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final name = personName(l, item.person);
    return Column(
      children: [
        Text(
          'Tap the ones that are NOT $name. Long-press to see the photo.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            key: const Key('quick-doubtful-faces'),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: item.faces.length,
            itemBuilder: (context, i) {
              final face = item.faces[i];
              final out = marked.contains(face.faceId);
              return InkWell(
                key: Key('quick-doubtful-${face.faceId}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onToggle(face.faceId),
                onLongPress: () => openReviewMedia(context, [
                  for (final f in item.faces) ReviewTarget('f', f.faceId),
                ], initialTarget: i),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CropImage(path: face.cropPath),
                    ),
                    if (out)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: .45),
                          border: Border.all(color: Colors.red, width: 3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    if (face.suggested != null)
                      Positioned(
                        left: 2,
                        right: 2,
                        bottom: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '→ ${personName(l, face.suggested!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DoubtfulBar extends StatelessWidget {
  const _DoubtfulBar({
    required this.name,
    required this.total,
    required this.marked,
    required this.suggestions,
    required this.move,
    required this.onMove,
    required this.busy,
    required this.onYes,
    required this.onNo,
    required this.onNotSure,
    this.onIgnore,
  });

  /// Faces of this batch the audit found a better home for, and whether the user chose to send the
  /// removed ones there.
  final int suggestions;
  final bool move;
  final VoidCallback onMove;

  final VoidCallback? onIgnore;
  final String name;
  final int total, marked;
  final bool busy;
  final VoidCallback onYes, onNo, onNotSure;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const size = Size.fromHeight(52);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (suggestions > 0)
          CheckboxListTile(
            key: const Key('quick-doubtful-move'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: move,
            onChanged: busy ? null : (_) => onMove(),
            title: Text(
              'Move the removed faces to the person they look like ($suggestions have one)',
            ),
          ),
        FilledButton.icon(
          key: const Key('quick-yes'),
          style: FilledButton.styleFrom(minimumSize: size),
          onPressed: busy ? null : onYes,
          icon: Icon(marked == 0 ? Icons.check : Icons.rule),
          label: Text(
            marked == 0
                ? 'Yes, all $total are $name'
                : 'Remove $marked, keep ${total - marked}',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('quick-no'),
                style: OutlinedButton.styleFrom(minimumSize: size),
                onPressed: busy ? null : onNo,
                child: Text('None are $name', textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                key: const Key('quick-unsure'),
                style: TextButton.styleFrom(minimumSize: size),
                onPressed: busy ? null : onNotSure,
                child: Text(l.quickNotSure, textAlign: TextAlign.center),
              ),
            ),
          ],
        ),
        if (onIgnore != null)
          TextButton.icon(
            key: const Key('quick-ignore'),
            onPressed: busy ? null : onIgnore,
            icon: const Icon(Icons.visibility_off_outlined, size: 18),
            label: const Text('Ignore these faces - not important'),
          ),
      ],
    );
  }
}
