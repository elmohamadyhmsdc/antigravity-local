import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../people/face_grid.dart';
import '../people/person_detail_screen.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';

final _pcScoreProvider = FutureProvider.autoDispose.family<double?, (int, int)>(
  (ref, pair) =>
      ref.watch(reviewRepositoryProvider).duplicateScore(pair.$1, pair.$2),
);

/// S11 - two people side by side: are they the same person? Merge them (one into the other) or
/// record that they are different so the PC never suggests the pair again.
class MergeScreen extends ConsumerStatefulWidget {
  const MergeScreen({super.key, required this.a, required this.b});

  final int a;
  final int b;

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen> {
  var _keepA = true; // true: B is merged into A

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = ref.watch(personProvider(widget.a)).value;
    final b = ref.watch(personProvider(widget.b)).value;
    final score = ref.watch(_pcScoreProvider((widget.a, widget.b))).value;

    if (a == null || b == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.mergeTitle)),
        body:
            ref.watch(personProvider(widget.a)).isLoading ||
                ref.watch(personProvider(widget.b)).isLoading
            ? const LoadingBox()
            : EmptyState(
                icon: Icons.person_off_outlined,
                title: l10n.personGone,
              ),
      );
    }
    final keep = _keepA ? a : b;
    final drop = _keepA ? b : a;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mergeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Side(label: 'A', person: a, highlighted: _keepA),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 40,
                ),
                child: Icon(
                  Icons.compare_arrows,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              Expanded(
                child: _Side(label: 'B', person: b, highlighted: !_keepA),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              key: const Key('merge-score'),
              leading: const Icon(Icons.insights_outlined),
              title: Text(
                score == null
                    ? l10n.mergeNotFlagged
                    : l10n.similarityPercent((score * 100).round()),
              ),
              subtitle: Text(l10n.mergeScoreHint),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const Key('merge-direction'),
            segments: [
              ButtonSegment(value: true, label: Text(l10n.keepPerson('A'))),
              ButtonSegment(value: false, label: Text(l10n.keepPerson('B'))),
            ],
            selected: {_keepA},
            onSelectionChanged: (s) => setState(() => _keepA = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('merge-confirm'),
            icon: const Icon(Icons.merge_type),
            label: Text(
              l10n.mergeInto(personName(l10n, drop), personName(l10n, keep)),
            ),
            onPressed: () => _merge(context, keep, drop),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('merge-distinct'),
            icon: const Icon(Icons.people_outline),
            label: Text(l10n.differentPeople),
            onPressed: () async {
              await ref.read(peopleRepositoryProvider).markDistinct(a.id, b.id);
              if (context.mounted) leave(context, Routes.review);
            },
          ),
          TextButton(
            onPressed: () => leave(context, Routes.review),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _merge(
    BuildContext context,
    PersonSummary keep,
    PersonSummary drop,
  ) async {
    final l10n = AppLocalizations.of(context);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirm(
      context,
      title: l10n.mergeConfirmTitle,
      body: l10n.mergeConfirmBody(
        personName(l10n, drop),
        drop.faceCount,
        personName(l10n, keep),
      ),
      confirmLabel: l10n.merge,
      cancelLabel: l10n.cancel,
    );
    if (!ok) return;
    await ref
        .read(peopleRepositoryProvider)
        .mergePeople(sourceId: drop.id, targetId: keep.id);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mergedInto(personName(l10n, keep)))),
    );
    router.pushReplacement('${Routes.people}/${keep.id}');
  }
}

class _Side extends ConsumerWidget {
  const _Side({
    required this.label,
    required this.person,
    required this.highlighted,
  });

  final String label;
  final PersonSummary person;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final faces =
        ref.watch(facesProvider(person.id)).value ?? const <FaceItem>[];
    return Card(
      color: highlighted
          ? scheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            PersonAvatar(cropPath: person.avatarCropPath, radius: 36),
            const SizedBox(height: 6),
            Text(
              personName(l10n, person),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              l10n.facesCount(person.faceCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              mainAxisSpacing: 3,
              crossAxisSpacing: 3,
              children: [
                for (final f in faces.take(6))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CropImage(path: f.cropPath, cacheWidth: 160),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
