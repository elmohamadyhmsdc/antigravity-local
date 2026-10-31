import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import 'people_actions.dart';
import 'action_sheet.dart';

enum PeopleSort { mostFaces, name, newest }

/// S07 - everyone found in the library: a grid of cover + name + face count, an "Unsorted" card for
/// faces that belong to nobody yet, search and sort.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  var _query = '';
  var _sort = PeopleSort.mostFaces;
  var _filter = 'all';
  bool _selecting = false;
  final _selected = <int>{};

  void _toggle(int id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Future<void> _menu(List<PersonSummary> people) async {
    final l = AppLocalizations.of(context);
    final action = await showPeopleActionSheet(
      context,
      title: people.length == 1
          ? personName(l, people.single)
          : l.selectedCount(people.length),
      cropPath: people.length == 1 ? people.single.avatarCropPath : null,
      actions: personMenuActions(people),
    );
    if (action == null || !mounted) return;
    if (action == 'select') {
      setState(() {
        _selecting = true;
        _selected.addAll(people.map((p) => p.id));
      });
      return;
    }
    await runPersonAction(context, ref, people, action);
    if (mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final people = ref.watch(peopleProvider);
    final unsorted = ref.watch(unsortedCountProvider).value ?? 0;
    final review = ref.watch(reviewCountsProvider).value?.total ?? 0;
    final allPeople = people.value ?? const <PersonSummary>[];
    final q = _query.trim().toLowerCase();
    final visible = allPeople
        .where(
          (p) =>
              (_filter == 'hidden' ? p.hidden : !p.hidden) &&
              (_filter != 'favorites' || p.favorite) &&
              (_filter != 'pinned' || p.pinned) &&
              (q.isEmpty || personName(l10n, p).toLowerCase().contains(q)),
        )
        .toList();
    _selected.removeWhere((id) => !allPeople.any((p) => p.id == id));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navPeople),
        actions: [
          IconButton(
            key: const Key('people-select'),
            tooltip: l10n.peopleAction('selection'),
            icon: Icon(_selecting ? Icons.close : Icons.checklist),
            onPressed: () => setState(() {
              _selecting = !_selecting;
              _selected.clear();
            }),
          ),
          IconButton(
            key: const Key('open-characters'),
            tooltip: l10n.charactersTitle,
            onPressed: () => context.push(Routes.characters),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
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
      bottomNavigationBar: !_selecting
          ? null
          : SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(l10n.selectedCount(_selected.length)),
                      TextButton(
                        onPressed: () => setState(
                          () => _selected.addAll(visible.map((p) => p.id)),
                        ),
                        child: Text(l10n.selectAll),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          final next = visible
                              .map((p) => p.id)
                              .where((id) => !_selected.contains(id))
                              .toSet();
                          _selected
                            ..clear()
                            ..addAll(next);
                        }),
                        child: Text(l10n.peopleAction('invert')),
                      ),
                      FilledButton(
                        key: const Key('people-selection-actions'),
                        onPressed: _selected.isEmpty
                            ? null
                            : () => _menu(
                                allPeople
                                    .where((p) => _selected.contains(p.id))
                                    .toList(),
                              ),
                        child: Text(l10n.peopleAction('more')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: people.when(
        loading: () => const LoadingBox(),
        error: (e, _) => EmptyState(
          icon: Icons.people_outline,
          title: '$e',
          actionLabel: l10n.retry,
          onAction: () => ref.invalidate(peopleProvider),
        ),
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
          final shown = [...visible];
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
          shown.sort((a, b) {
            final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
            if (pin != 0) return pin;
            return switch (_sort) {
              PeopleSort.name => personName(
                l10n,
                a,
              ).toLowerCase().compareTo(personName(l10n, b).toLowerCase()),
              PeopleSort.newest => b.createdAt.compareTo(a.createdAt),
              PeopleSort.mostFaces => b.faceCount.compareTo(a.faceCount),
            };
          });
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final filter in [
                        'all',
                        'favorites',
                        'pinned',
                        'hidden',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: Key('people-filter-$filter'),
                            label: Text(l10n.peopleAction(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() {
                              _filter = filter;
                              _selected.clear();
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const Key('people-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('people-clear-search'),
                            tooltip: l10n.clearSearch,
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close),
                          ),
                    hintText: l10n.searchPeopleHint,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child:
                    shown.isEmpty &&
                        (q.isNotEmpty || _filter != 'all' || unsorted == 0)
                    ? EmptyState(
                        icon: Icons.person_search_outlined,
                        title: q.isNotEmpty
                            ? l10n.peopleNoMatches
                            : l10n.peopleAction('noResults'),
                        actionLabel: q.isNotEmpty ? l10n.clearSearch : null,
                        onAction: q.isNotEmpty ? _clearSearch : null,
                      )
                    : GridView(
                        key: const Key('people-grid'),
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisExtent:
                              190.0 +
                              (MediaQuery.textScalerOf(context).scale(14) - 14)
                                      .clamp(0.0, 42.0)
                                      .toDouble() *
                                  3.0,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        children: [
                          if (unsorted > 0 &&
                              q.isEmpty &&
                              _filter == 'all' &&
                              !_selecting)
                            _UnsortedCard(count: unsorted),
                          for (final p in shown)
                            _PersonCard(
                              person: p,
                              selecting: _selecting,
                              selected: _selected.contains(p.id),
                              onToggle: () => _toggle(p.id),
                              onMenu: () => _menu([p]),
                            ),
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
  const _PersonCard({
    required this.person,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onMenu,
  });

  final PersonSummary person;
  final bool selecting, selected;
  final VoidCallback onToggle, onMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      key: Key('person-${person.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: selecting
          ? onToggle
          : () => context.push('${Routes.people}/${person.id}'),
      onLongPress: selecting ? onToggle : onMenu,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 96,
              width: double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PersonAvatar(cropPath: person.avatarCropPath, radius: 46),
                  if (selecting)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  if (!selecting)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Tooltip(
                        message: l10n.peopleAction('more'),
                        triggerMode: TooltipTriggerMode.manual,
                        child: GestureDetector(
                          onLongPress: onMenu,
                          child: IconButton(
                            key: Key('person-menu-${person.id}'),
                            onPressed: onMenu,
                            icon: const Icon(Icons.more_vert),
                          ),
                        ),
                      ),
                    ),
                  if (person.pinned ||
                      person.favorite ||
                      person.hidden ||
                      person.groupingLocked)
                    Positioned(
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (person.pinned)
                            const Icon(Icons.push_pin, size: 16),
                          if (person.favorite) const Icon(Icons.star, size: 16),
                          if (person.hidden)
                            const Icon(Icons.visibility_off, size: 16),
                          if (person.groupingLocked)
                            const Icon(Icons.lock, size: 16),
                        ],
                      ),
                    ),
                ],
              ),
            ),
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
              radius: 46,
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
