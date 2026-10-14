import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/api/api_exception.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../people/person_detail_screen.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';

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
        body: const TabBarView(
          children: [
            _MatchesTab(),
            _GroupsTab(),
            _DuplicatesTab(),
            _OutfitsTab(),
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
      error: (e, _) => Center(child: Text('$e')),
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
          padding: const EdgeInsets.all(12),
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
            for (final g in items) _MatchCard(group: g),
          ],
        );
      },
    );
  }
}

class _MatchCard extends ConsumerStatefulWidget {
  const _MatchCard({required this.group});

  final ReviewMatchGroup group;

  @override
  ConsumerState<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends ConsumerState<_MatchCard> {
  final _off = <int>{};

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
        padding: const EdgeInsets.all(12),
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
                      l10n.matchCardTitle(
                        personName(l10n, g.person),
                        g.faces.length,
                      ),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in g.faces)
                  GestureDetector(
                    key: Key('match-face-${f.faceId}'),
                    onTap: () => setState(() {
                      if (!_off.remove(f.faceId)) _off.add(f.faceId);
                    }),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CropImage(path: f.cropPath, cacheWidth: 200),
                            if (_off.contains(f.faceId))
                              const ColoredBox(color: Colors.black54),
                            Positioned(
                              right: 3,
                              top: 3,
                              child: Icon(
                                _off.contains(f.faceId)
                                    ? Icons.radio_button_unchecked
                                    : Icons.check_circle,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  key: Key('match-accept-${g.person.id}'),
                  onPressed: chosen.isEmpty
                      ? null
                      : () => repo.acceptMatches(chosen, g.person.id),
                  child: Text(l10n.addFacesTo(chosen.length)),
                ),
                const SizedBox(width: 8),
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
      error: (e, _) => Center(child: Text('$e')),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewGroupsEmpty,
          );
        }
        return ListView(
          key: const Key('review-groups'),
          padding: const EdgeInsets.all(12),
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
            for (final g in items) _GroupCard(group: g),
          ],
        );
      },
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});

  final ReviewGroupItem group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = widget.group;
    final ids = [for (final f in g.faces) f.faceId];
    return Card(
      key: Key('group-card-${g.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.groupCardTitle(g.faces.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final f in g.faces.take(14))
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CropImage(path: f.cropPath, cacheWidth: 180),
                    ),
                  ),
                if (g.faces.length > 14)
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: Center(child: Text('+${g.faces.length - 14}')),
                  ),
              ],
            ),
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
                  onPressed: () async {
                    await ref
                        .read(peopleRepositoryProvider)
                        .createPerson(name: _name.text, faceIds: ids);
                    await ref.read(reviewRepositoryProvider).forgetGroup(g.id);
                  },
                  child: Text(l10n.createPerson),
                ),
                OutlinedButton(
                  key: Key('group-add-${g.id}'),
                  onPressed: () async {
                    final choice = await pickPerson(
                      context,
                      allowNew: false,
                      title: l10n.addToPerson,
                    );
                    if (choice?.personId == null) return;
                    await ref
                        .read(peopleRepositoryProvider)
                        .assignFaces(ids, choice!.personId!);
                    await ref.read(reviewRepositoryProvider).forgetGroup(g.id);
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
      error: (e, _) => Center(child: Text('$e')),
      data: (pairs) {
        if (pairs.isEmpty) {
          return EmptyState(
            icon: Icons.task_alt,
            title: l10n.reviewDuplicatesEmpty,
          );
        }
        return ListView(
          key: const Key('review-duplicates'),
          padding: const EdgeInsets.all(12),
          children: [
            for (final d in pairs)
              Card(
                key: Key('dup-card-${d.a.id}-${d.b.id}'),
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
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

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person});

  final PersonSummary person;

  @override
  Widget build(BuildContext context) {
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
      error: (e, _) => Center(child: Text('$e')),
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
          padding: const EdgeInsets.all(12),
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
            for (final l in links)
              Card(
                key: Key('outfit-card-${l.bodyId}'),
                child: ListTile(
                  leading: SizedBox(
                    width: 48,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        onTap: l.mediaId == null
                            ? null
                            : () =>
                                  context.push('${Routes.media}/${l.mediaId}'),
                        child: CropImage(
                          path: l.cropPath,
                          placeholderIcon: Icons.accessibility_new,
                        ),
                      ),
                    ),
                  ),
                  title: Text(l10n.bodyLinkTitle(personName(l10n, l.person))),
                  subtitle: Text(
                    l10n.bodyLinkDetail(
                      l.method == 'appearance'
                          ? l10n.linkOutfit
                          : l10n.linkWeakFace,
                      (l.confidence * 100).round(),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('outfit-accept-${l.bodyId}'),
                        tooltip: l10n.accept,
                        icon: const Icon(Icons.check),
                        onPressed: () =>
                            repo.acceptBodyLink(l.bodyId, l.person.id),
                      ),
                      IconButton(
                        key: Key('outfit-reject-${l.bodyId}'),
                        tooltip: l10n.reject,
                        icon: const Icon(Icons.close),
                        onPressed: () =>
                            repo.rejectBodyLink(l.bodyId, l.person.id),
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
