import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/api_exception.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../data/repositories/review_visual_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../people/person_detail_screen.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'review_media_viewer.dart';
import 'review_photo_tile.dart';

final reviewMatchesProvider =
    StreamProvider.autoDispose<List<ReviewMatchGroup>>(
      (ref) => ref.watch(reviewRepositoryProvider).watchMatches(),
    );

final reviewGroupsProvider = StreamProvider.autoDispose<List<ReviewGroupItem>>(
  (ref) => ref.watch(reviewRepositoryProvider).watchGroups(),
);

/// S10 - everything the PC wants a decision on, in four tabs: faces that look like a known person,
/// new groups of faces, people who may be the same, bodies matched by outfit.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final counts =
        ref.watch(reviewCountsProvider).value ?? const ReviewCounts();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            counts.total == 0
                ? l10n.reviewTitle
                : l10n.reviewTitleCount(counts.total),
          ),
          actions: [
            IconButton(
              key: const Key('review-sort-now'),
              tooltip: l10n.sortNow,
              icon: const Icon(Icons.auto_fix_high),
              onPressed: () => sortNow(context, ref),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                key: const Key('review-tab-matches'),
                text: l10n.reviewTabMatches(counts.matches),
              ),
              Tab(
                key: const Key('review-tab-groups'),
                text: l10n.reviewTabGroups(counts.groups),
              ),
              Tab(
                key: const Key('review-tab-duplicates'),
                text: l10n.reviewTabDuplicates(counts.duplicates),
              ),
              Tab(
                key: const Key('review-tab-outfits'),
                text: l10n.reviewTabOutfits(counts.bodyLinks),
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                l10n.reviewIntro,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _MatchesTab(),
                  _GroupsTab(),
                  _DuplicatesTab(),
                  _OutfitsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Runs the three grouping rounds now (also behind "Sort now" in Settings).
Future<void> sortNow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.sorting), duration: const Duration(seconds: 2)),
  );
  try {
    final run = await ref.read(groupingRunnerProvider).run();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            run.skipped
                ? l10n.sortNeedsPc
                : l10n.sortDone(run.assigned, run.newPeople, run.review.total),
          ),
        ),
      );
  } on ApiException catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(e.isGpuBusy ? l10n.gpuBusyMessage : e.message)),
      );
  }
}

// ---------------------------------------------------------------------------------------------

class _MatchesTab extends ConsumerWidget {
  const _MatchesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(reviewMatchesProvider);
    return groups.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          RetryState(onRetry: () => ref.invalidate(reviewMatchesProvider)),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewMatchesEmpty,
          );
        }
        final total = items.fold<int>(0, (sum, g) => sum + g.faces.length);
        return ListView(
          key: const Key('review-matches'),
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.tonalIcon(
              key: const Key('accept-all-matches'),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.acceptAllMatches(total)),
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: l10n.acceptAllMatches(total),
                  body: l10n.acceptAllMatchesBody,
                  confirmLabel: l10n.accept,
                  cancelLabel: l10n.cancel,
                );
                if (!ok) return;
                final repo = ref.read(reviewRepositoryProvider);
                for (final g in items) {
                  await repo.acceptMatches([
                    for (final f in g.faces) f.faceId,
                  ], g.person.id);
                }
              },
            ),
            const SizedBox(height: 8),
            for (final g in items)
              _MatchCard(key: ValueKey(g.person.id), group: g),
          ],
        );
      },
    );
  }
}

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({super.key, required this.group});

  final ReviewMatchGroup group;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  final _off = <int>{};

  void _openPhotos([int index = 0]) {
    final g = widget.group;
    openReviewMedia(
      context,
      [for (final f in g.faces) ReviewTarget('f', f.faceId)],
      initialTarget: index,
      title: AppLocalizations.of(
        context,
      ).reviewMatchQuestion(personName(AppLocalizations.of(context), g.person)),
      selectedFaceIds: g.faces
          .map((f) => f.faceId)
          .where((id) => !_off.contains(id))
          .toSet(),
      onSelectionChanged: (selected) {
        if (mounted) {
          setState(() {
            _off
              ..clear()
              ..addAll(
                g.faces
                    .map((f) => f.faceId)
                    .where((id) => !selected.contains(id)),
              );
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = widget.group;
    final chosen = [
      for (final f in g.faces)
        if (!_off.contains(f.faceId)) f.faceId,
    ];
    final repo = ref.read(reviewRepositoryProvider);
    return Card(
      key: Key('match-card-${g.person.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => context.push('${Routes.people}/${g.person.id}'),
              child: Row(
                children: [
                  PersonAvatar(cropPath: g.person.avatarCropPath, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.reviewMatchQuestion(personName(l10n, g.person)),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => reviewPersonPhotos(
                context,
                ref,
                g.person.id,
                personName(l10n, g.person),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.reviewReferencePhotos),
            ),
            Text(
              l10n.reviewMatchHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: g.faces.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = g.faces[i];
                  return ReviewPhotoTile(
                    photoKey: Key('match-face-${f.faceId}'),
                    selectionKey: Key('match-select-${f.faceId}'),
                    cropPath: f.cropPath,
                    selected: !_off.contains(f.faceId),
                    onOpen: () => _openPhotos(i),
                    onSelect: () => setState(() {
                      if (!_off.remove(f.faceId)) _off.add(f.faceId);
                    }),
                  );
                },
              ),
            ),
            TextButton.icon(
              key: Key('match-view-all-${g.person.id}'),
              icon: const Icon(Icons.fullscreen),
              label: Text(l10n.reviewViewAll(g.faces.length)),
              onPressed: _openPhotos,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: Key('match-accept-${g.person.id}'),
                  onPressed: chosen.isEmpty
                      ? null
                      : () => repo.acceptMatches(chosen, g.person.id),
                  child: Text(l10n.addFacesTo(chosen.length)),
                ),
                OutlinedButton(
                  key: Key('match-reject-${g.person.id}'),
                  onPressed: chosen.isEmpty
                      ? null
                      : () => repo.rejectMatches(chosen, g.person.id),
                  child: Text(l10n.notThem(chosen.length)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------

class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final groups = ref.watch(reviewGroupsProvider);
    return groups.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          RetryState(onRetry: () => ref.invalidate(reviewGroupsProvider)),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewGroupsEmpty,
          );
        }
        return ListView(
          key: const Key('review-groups'),
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.tonalIcon(
              key: const Key('create-all-groups'),
              icon: const Icon(Icons.group_add_outlined),
              label: Text(l10n.createAllGroups(items.length)),
              onPressed: () async {
                final people = ref.read(peopleRepositoryProvider);
                final review = ref.read(reviewRepositoryProvider);
                for (final g in items) {
                  await people.createPerson(
                    faceIds: [for (final f in g.faces) f.faceId],
                  );
                  await review.forgetGroup(g.id);
                }
              },
            ),
            const SizedBox(height: 8),
            for (final g in items) _GroupCard(key: ValueKey(g.id), group: g),
          ],
        );
      },
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({super.key, required this.group});

  final ReviewGroupItem group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  final _name = TextEditingController();
  final _off = <int>{};

  void _openPhotos([int index = 0]) {
    final g = widget.group;
    openReviewMedia(
      context,
      [for (final f in g.faces) ReviewTarget('f', f.faceId)],
      initialTarget: index,
      title: AppLocalizations.of(context).reviewGroupQuestion,
      selectedFaceIds: g.faces
          .map((f) => f.faceId)
          .where((id) => !_off.contains(id))
          .toSet(),
      onSelectionChanged: (selected) {
        if (mounted) {
          setState(() {
            _off
              ..clear()
              ..addAll(
                g.faces
                    .map((f) => f.faceId)
                    .where((id) => !selected.contains(id)),
              );
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = widget.group;
    final ids = [
      for (final f in g.faces)
        if (!_off.contains(f.faceId)) f.faceId,
    ];
    return Card(
      key: Key('group-card-${g.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reviewGroupQuestion,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.reviewGroupHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: g.faces.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = g.faces[i];
                  return ReviewPhotoTile(
                    photoKey: Key('group-face-${f.faceId}'),
                    selectionKey: Key('group-select-${f.faceId}'),
                    cropPath: f.cropPath,
                    selected: !_off.contains(f.faceId),
                    onSelect: () => setState(() {
                      if (!_off.remove(f.faceId)) _off.add(f.faceId);
                    }),
                    onOpen: () => _openPhotos(i),
                  );
                },
              ),
            ),
            TextButton.icon(
              key: Key('group-view-all-${g.id}'),
              icon: const Icon(Icons.fullscreen),
              label: Text(l10n.reviewViewAll(g.faces.length)),
              onPressed: _openPhotos,
            ),
            Text(l10n.selectedCount(ids.length)),
            const SizedBox(height: 10),
            TextField(
              key: Key('group-name-${g.id}'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                labelText: l10n.personNameLabel,
                hintText: l10n.personNameOptional,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(
                  key: Key('group-create-${g.id}'),
                  onPressed: ids.isEmpty
                      ? null
                      : () async {
                          await ref
                              .read(peopleRepositoryProvider)
                              .createPerson(name: _name.text, faceIds: ids);
                          await ref
                              .read(reviewRepositoryProvider)
                              .forgetGroup(g.id);
                        },
                  child: Text(l10n.createPerson),
                ),
                OutlinedButton(
                  key: Key('group-add-${g.id}'),
                  onPressed: ids.isEmpty
                      ? null
                      : () async {
                          final choice = await pickPerson(
                            context,
                            allowNew: false,
                            title: l10n.addToPerson,
                          );
                          if (choice?.personId == null) return;
                          await ref
                              .read(peopleRepositoryProvider)
                              .assignFaces(ids, choice!.personId!);
                          await ref
                              .read(reviewRepositoryProvider)
                              .forgetGroup(g.id);
                        },
                  child: Text(l10n.addToPerson),
                ),
                TextButton(
                  key: Key('group-dismiss-${g.id}'),
                  onPressed: () =>
                      ref.read(reviewRepositoryProvider).dismissGroup(g.id),
                  child: Text(l10n.notAPerson),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------

class _DuplicatesTab extends ConsumerWidget {
  const _DuplicatesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(reviewDuplicatesProvider);
    return items.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          RetryState(onRetry: () => ref.invalidate(reviewDuplicatesProvider)),
      data: (pairs) {
        if (pairs.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewDuplicatesEmpty,
          );
        }
        return ListView(
          key: const Key('review-duplicates'),
          padding: const EdgeInsets.all(20),
          children: [
            for (final d in pairs)
              Card(
                key: Key('dup-card-${d.a.id}-${d.b.id}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _PersonChip(person: d.a)),
                          const Icon(Icons.compare_arrows),
                          Expanded(child: _PersonChip(person: d.b)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(l10n.similarityPercent((d.score * 100).round())),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            key: Key('dup-compare-${d.a.id}-${d.b.id}'),
                            onPressed: () => context.push(
                              '${Routes.merge}/${d.a.id}/${d.b.id}',
                            ),
                            child: Text(l10n.compare),
                          ),
                          OutlinedButton(
                            key: Key('dup-distinct-${d.a.id}-${d.b.id}'),
                            onPressed: () => ref
                                .read(peopleRepositoryProvider)
                                .markDistinct(d.a.id, d.b.id),
                            child: Text(l10n.differentPeople),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PersonChip extends ConsumerWidget {
  const _PersonChip({required this.person});

  final PersonSummary person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        PersonAvatar(cropPath: person.avatarCropPath, radius: 30),
        const SizedBox(height: 4),
        Text(
          personName(l10n, person),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          l10n.facesCount(person.faceCount),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () => reviewPersonPhotos(
            context,
            ref,
            person.id,
            personName(l10n, person),
          ),
          child: Text(l10n.reviewViewAll(person.faceCount)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------

class _OutfitsTab extends ConsumerWidget {
  const _OutfitsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final items = ref.watch(reviewBodyLinksProvider);
    return items.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          RetryState(onRetry: () => ref.invalidate(reviewBodyLinksProvider)),
      data: (links) {
        if (links.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewOutfitsEmpty,
          );
        }
        final repo = ref.read(reviewRepositoryProvider);
        return ListView(
          key: const Key('review-outfits'),
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.tonalIcon(
              key: const Key('accept-all-outfits'),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.acceptAllOutfits(links.length)),
              onPressed: () async {
                for (final l in links) {
                  await repo.acceptBodyLink(l.bodyId, l.person.id);
                }
              },
            ),
            const SizedBox(height: 8),
            for (final l in links) _OutfitCard(link: l),
          ],
        );
      },
    );
  }
}

class _OutfitCard extends ConsumerWidget {
  const _OutfitCard({required this.link});
  final ReviewBodyLinkItem link;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final name = personName(l, link.person);
    final repo = ref.read(reviewRepositoryProvider);
    void view() => openReviewMedia(
      context,
      [ReviewTarget('b', link.bodyId)],
      title: l.reviewOutfitQuestion(name),
      personName: name,
      onBodyDecision: (yes) => yes
          ? repo.acceptBodyLink(link.bodyId, link.person.id)
          : repo.rejectBodyLink(link.bodyId, link.person.id),
    );
    return Card(
      key: Key('outfit-card-${link.bodyId}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.reviewOutfitQuestion(name),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l.reviewOutfitHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                InkWell(
                  onTap: view,
                  child: SizedBox(
                    width: 96,
                    height: 128,
                    child: CropImage(
                      path: link.cropPath,
                      placeholderIcon: Icons.accessibility_new,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.compare_arrows),
                ),
                Expanded(
                  child: Column(
                    children: [
                      PersonAvatar(
                        cropPath: link.person.avatarCropPath,
                        radius: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(name),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              l.bodyLinkDetail(
                link.method == 'appearance' ? l.linkOutfit : l.linkWeakFace,
                (link.confidence * 100).round(),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: Key('outfit-view-${link.bodyId}'),
                  onPressed: view,
                  icon: const Icon(Icons.fullscreen),
                  label: Text(l.reviewFullPhoto),
                ),
                TextButton(
                  onPressed: () =>
                      reviewPersonPhotos(context, ref, link.person.id, name),
                  child: Text(l.reviewReferencePhotos),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: Key('outfit-accept-${link.bodyId}'),
                  onPressed: () =>
                      repo.acceptBodyLink(link.bodyId, link.person.id),
                  child: Text(l.reviewYesPerson(name)),
                ),
                OutlinedButton(
                  key: Key('outfit-reject-${link.bodyId}'),
                  onPressed: () =>
                      repo.rejectBodyLink(link.bodyId, link.person.id),
                  child: Text(l.reviewNotPerson),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
