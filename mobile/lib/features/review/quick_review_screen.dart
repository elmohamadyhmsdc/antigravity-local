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
  const ReviewEntryScreen({super.key, this.view});

  final String? view;

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
      true => const ReviewScreen(),
      false => const QuickReviewScreen(),
    };
  }
}

/// Opens the full four-tab review ("See all").
void openAllReview(BuildContext context) =>
    context.push('${Routes.review}?view=all');

/// S10 quick review - one question at a time with the face highlighted on the whole photo, big
/// Yes / No / Not sure buttons (or swipe right / left), most useful questions first. Every answer is
/// the same correction the four tabs record; "Not sure" parks the question on this phone.
class QuickReviewScreen extends ConsumerStatefulWidget {
  const QuickReviewScreen({super.key});

  @override
  ConsumerState<QuickReviewScreen> createState() => _QuickReviewScreenState();
}

class _QuickReviewScreenState extends ConsumerState<QuickReviewScreen> {
  var _answered = 0;

  /// Answered here, with the evidence it was answered on: hidden until the stored plan catches
  /// up, but shown again when a parked question comes back with new evidence.
  final _done = <String, (double, int)>{};
  var _busy = false;
  var _drag = 0.0;

  ReviewRepository get _review => ref.read(reviewRepositoryProvider);
  PeopleRepository get _people => ref.read(peopleRepositoryProvider);

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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 160),
      ),
    );

  Future<void> _yes(ReviewQuestion q) => _run(q, () async {
    switch (q.kind) {
      case ReviewQuestionKind.match:
        await _review.acceptMatches([q.face!.faceId], q.match!.person.id);
      case ReviewQuestionKind.outfit:
        await _review.acceptBodyLink(q.outfit!.bodyId, q.outfit!.person.id);
      case ReviewQuestionKind.duplicate:
        return _merge(q.duplicate!);
      case ReviewQuestionKind.group:
        return false; // answered by _GroupAnswer
    }
    return true;
  });

  Future<void> _no(ReviewQuestion q) => _run(q, () async {
    switch (q.kind) {
      case ReviewQuestionKind.match:
        await _review.rejectMatches([q.face!.faceId], q.match!.person.id);
      case ReviewQuestionKind.outfit:
        await _review.rejectBodyLink(q.outfit!.bodyId, q.outfit!.person.id);
      case ReviewQuestionKind.duplicate:
        await _people.markDistinct(q.duplicate!.a.id, q.duplicate!.b.id);
      case ReviewQuestionKind.group:
        await _review.dismissGroup(q.group!.id);
    }
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
          await _review.unsnooze(q.key);
          if (mounted) {
            setState(() {
              _answered--;
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
          await _people.assignFaces(ids, person.id);
        } else {
          await _people.createPerson(name: name, faceIds: ids);
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
    await _people.mergePeople(sourceId: drop.id, targetId: keep.id);
    // an unnamed person takes the other one's name (PeopleRepository.mergePeople)
    final shown = !keep.isNamed && drop.isNamed ? drop : keep;
    _toast(messenger, l.mergedInto(personName(l, shown)));
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final questions = ref.watch(reviewQuestionsProvider);
    final advanced = ref.watch(reviewAdvancedProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.quickReviewTitle),
        actions: [
          IconButton(
            key: const Key('review-sort-now'),
            tooltip: l.sortNow,
            icon: const Icon(Icons.auto_fix_high),
            onPressed: () => sortNow(context, ref),
          ),
          TextButton(
            key: const Key('quick-see-all'),
            onPressed: () => openAllReview(context),
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
        error: (_, _) =>
            RetryState(onRetry: () => ref.invalidate(reviewQuestionsProvider)),
        data: (all) {
          final open = [
            for (final q in all)
              if (_done[q.key] != (q.score, q.evidence)) q,
          ];
          if (open.isEmpty) {
            final left = ref.watch(reviewCountsProvider).value?.total ?? 0;
            return EmptyState(
              key: const Key('quick-all-done'),
              icon: Icons.task_alt,
              title: l.quickAllDone,
              body: left > 0 ? l.quickAllDoneSnoozed(left) : l.quickAllDoneBody,
              actionLabel: left > 0 ? l.quickSeeAll : null,
              onAction: left > 0 ? () => openAllReview(context) : null,
            );
          }
          final q = open.first;
          final total = _answered + open.length;
          return _QuestionView(
            key: ValueKey(q.key),
            question: q,
            position: _answered + 1,
            total: total,
            advanced: advanced,
            busy: _busy,
            drag: _drag,
            onDrag: q.kind == ReviewQuestionKind.group
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
  });

  final ReviewQuestion question;
  final int position, total;
  final bool advanced, busy;
  final double drag;
  final ValueChanged<double>? onDrag;
  final ValueChanged<double> onDragEnd;
  final VoidCallback onYes, onNo, onNotSure;
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
        l.reviewMatchQuestion(personName(l, q.match!.person)),
        likelihood,
        q.match!.person,
      ),
      ReviewQuestionKind.outfit => (
        l.reviewMatchQuestion(personName(l, q.outfit!.person)),
        '${q.outfit!.method == 'appearance' ? l.quickByClothes : l.quickByWeakFace} · $likelihood',
        q.outfit!.person,
      ),
      ReviewQuestionKind.duplicate => (l.quickSamePerson, likelihood, null),
      ReviewQuestionKind.group => (
        l.quickWhoIsThis,
        l.quickGroupFaces(q.group!.faces.length),
        null,
      ),
    };

    final media = switch (q.kind) {
      ReviewQuestionKind.match => _Photo(kind: 'f', id: q.face!.faceId),
      ReviewQuestionKind.outfit => _Photo(kind: 'b', id: q.outfit!.bodyId),
      ReviewQuestionKind.duplicate => _Pair(item: q.duplicate!),
      ReviewQuestionKind.group => _Group(item: q.group!),
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
                    busy: busy,
                    onSave: onGroup,
                    onNo: onNo,
                    onNotSure: onNotSure,
                  )
                : _YesNoBar(
                    busy: busy,
                    onYes: onYes,
                    onNo: onNo,
                    onNotSure: onNotSure,
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
  });

  final bool busy;
  final VoidCallback onYes, onNo, onNotSure;

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
      ],
    );
  }
}

/// "Who is this?": one field that names a new person or, picked from the suggestions, adds the
/// faces to someone who already exists.
class _GroupAnswer extends ConsumerStatefulWidget {
  const _GroupAnswer({
    required this.busy,
    required this.onSave,
    required this.onNo,
    required this.onNotSure,
  });

  final bool busy;
  final void Function(String name, PersonSummary? person) onSave;
  final VoidCallback onNo, onNotSure;

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
          in ref.watch(peopleProvider).value ?? const <PersonSummary>[])
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
