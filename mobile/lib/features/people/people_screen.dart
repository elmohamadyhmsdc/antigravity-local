import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';

enum PeopleSort { mostFaces, name, newest }

/// S07 - everyone found in the library: a grid of cover + name + face count, an "Unsorted" card for
/// faces that belong to nobody yet, search and sort.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  var _query = '';
  var _sort = PeopleSort.mostFaces;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final people = ref.watch(peopleProvider);
    final unsorted = ref.watch(unsortedCountProvider).value ?? 0;
    final review = ref.watch(reviewCountsProvider).value?.total ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navPeople),
        actions: [
          IconButton(
            key: const Key('open-review'),
            tooltip: l10n.reviewTitle,
            onPressed: () => context.push(Routes.review),
            icon: Badge(
              isLabelVisible: review > 0,
              label: Text('$review'),
              child: const Icon(Icons.fact_check_outlined),
            ),
          ),
          PopupMenuButton<PeopleSort>(
            key: const Key('people-sort'),
            tooltip: l10n.sortBy,
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: PeopleSort.mostFaces,
                child: Text(l10n.sortMostFaces),
              ),
              PopupMenuItem(value: PeopleSort.name, child: Text(l10n.sortName)),
              PopupMenuItem(
                value: PeopleSort.newest,
                child: Text(l10n.sortNewest),
              ),
            ],
          ),
        ],
      ),
      body: people.when(
        loading: () => const LoadingBox(),
        error: (e, _) => Center(child: Text('$e')),
        data: (all) {
          if (all.isEmpty && unsorted == 0) {
            return EmptyState(
              icon: Icons.groups_outlined,
              title: l10n.noPeopleTitle,
              body: l10n.noPeopleBody,
              actionLabel: l10n.scanLibrary,
              onAction: () => context.push(Routes.sources),
            );
          }
          final q = _query.trim().toLowerCase();
          final shown = [
            for (final p in all)
              if (q.isEmpty || personName(l10n, p).toLowerCase().contains(q)) p,
          ];
          switch (_sort) {
            case PeopleSort.mostFaces:
              break; // the query already orders by face count
            case PeopleSort.name:
              shown.sort(
                (a, b) => personName(
                  l10n,
                  a,
                ).toLowerCase().compareTo(personName(l10n, b).toLowerCase()),
              );
            case PeopleSort.newest:
              shown.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const Key('people-search'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.searchPeopleHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: GridView(
                  key: const Key('people-grid'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    childAspectRatio: 0.82,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  children: [
                    if (unsorted > 0 && q.isEmpty)
                      _UnsortedCard(count: unsorted),
                    for (final p in shown) _PersonCard(person: p),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final PersonSummary person;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      key: Key('person-${person.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('${Routes.people}/${person.id}'),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PersonAvatar(cropPath: person.avatarCropPath, radius: 38),
            const SizedBox(height: 8),
            Text(
              personName(l10n, person),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall,
            ),
            Text(l10n.facesCount(person.faceCount), style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _UnsortedCard extends StatelessWidget {
  const _UnsortedCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      key: const Key('unsorted-card'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(Routes.unsorted),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: scheme.tertiaryContainer,
              child: Icon(
                Icons.help_outline,
                size: 34,
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(l10n.unsortedCardTitle, style: text.titleSmall),
            Text(l10n.facesCount(count), style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}
