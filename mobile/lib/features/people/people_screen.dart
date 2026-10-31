import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../review/review_banner.dart';
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
    final questions = ref.watch(reviewQuestionsProvider).value?.length ?? 0;
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
              if (questions > 0 && !_selecting)
                ReviewBanner(
                  key: const Key('people-review-banner'),
                  icon: Icons.swipe_outlined,
                  title: l10n.peopleReviewBanner(questions),
                  body: l10n.peopleReviewBannerBody,
                  onTap: () => context.push('${Routes.review}?view=quick'),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
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
                            avatar: switch (filter) {
                              'favorites' => const Icon(
                                Icons.star_rounded,
                                size: 16,
                              ),
                              'pinned' => const Icon(
                                Icons.push_pin_rounded,
                                size: 16,
                              ),
                              'hidden' => const Icon(
                                Icons.visibility_off_rounded,
                                size: 16,
                              ),
                              _ => null,
                            },
                            label: Text(l10n.peopleAction(filter)),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() {
                              _filter = filter;
                              _selected.clear();
                            }),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: TextField(
                  key: const Key('people-search'),
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            key: const Key('people-clear-search'),
                            tooltip: l10n.clearSearch,
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    hintText: l10n.searchPeopleHint,
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          // Responsive column count: 3 on normal phones (< 480dp width),
                          // 4 on wider screens / landscape (480dp - 720dp),
                          // 5+ on tablets / desktop (>= 720dp).
                          final crossAxisCount = width < 480
                              ? 3
                              : width < 720
                              ? 4
                              : (width / 140).floor().clamp(4, 8);
                          const crossAxisSpacing = 8.0;
                          const mainAxisSpacing = 10.0;
                          const horizontalPadding = 12.0;

                          final totalSpacing =
                              (crossAxisCount - 1) * crossAxisSpacing;
                          final cardWidth =
                              (width - (horizontalPadding * 2) - totalSpacing) /
                              crossAxisCount;
                          final avatarRadius = (cardWidth * 0.28).clamp(
                            30.0,
                            42.0,
                          );

                          final textScaler = MediaQuery.textScalerOf(context);
                          final textScaleDelta = (textScaler.scale(14) - 14)
                              .clamp(0.0, 30.0);
                          final mainAxisExtent =
                              60.0 + (avatarRadius * 2) + textScaleDelta * 2.5;

                          return GridView(
                            key: const Key('people-grid'),
                            padding: const EdgeInsets.fromLTRB(
                              horizontalPadding,
                              2,
                              horizontalPadding,
                              24,
                            ),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: crossAxisSpacing,
                                  mainAxisSpacing: mainAxisSpacing,
                                  mainAxisExtent: mainAxisExtent,
                                ),
                            children: [
                              if (unsorted > 0 &&
                                  q.isEmpty &&
                                  _filter == 'all' &&
                                  !_selecting)
                                _UnsortedCard(
                                  count: unsorted,
                                  avatarRadius: avatarRadius,
                                ),
                              for (final p in shown)
                                _PersonCard(
                                  person: p,
                                  selecting: _selecting,
                                  selected: _selected.contains(p.id),
                                  onToggle: () => _toggle(p.id),
                                  onMenu: () => _menu([p]),
                                  avatarRadius: avatarRadius,
                                ),
                            ],
                          );
                        },
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
    this.avatarRadius = 34,
  });

  final PersonSummary person;
  final bool selecting, selected;
  final VoidCallback onToggle, onMenu;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final isSelected = selecting && selected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('person-${person.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: selecting
            ? onToggle
            : () => context.push('${Routes.people}/${person.id}'),
        onLongPress: () {
          HapticFeedback.selectionClick();
          if (selecting) {
            onToggle();
          } else {
            onMenu();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.35),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: avatarRadius * 2 + 4,
                width: avatarRadius * 2 + 4,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: PersonAvatar(
                        cropPath: person.avatarCropPath,
                        radius: avatarRadius,
                      ),
                    ),
                    if (selecting)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: AnimatedScale(
                          scale: 1.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.surface,
                            ),
                            child: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 22,
                              color: selected ? scheme.primary : scheme.outline,
                            ),
                          ),
                        ),
                      ),
                    if (person.pinned ||
                        person.favorite ||
                        person.hidden ||
                        person.groupingLocked)
                      Positioned(
                        bottom: -3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.95,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.surface,
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (person.favorite) ...[
                                Icon(
                                  Icons.star_rounded,
                                  size: 12,
                                  color: Colors.amber.shade700,
                                ),
                                if (person.pinned ||
                                    person.hidden ||
                                    person.groupingLocked)
                                  const SizedBox(width: 2),
                              ],
                              if (person.pinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 11,
                                  color: scheme.primary,
                                ),
                                if (person.hidden || person.groupingLocked)
                                  const SizedBox(width: 2),
                              ],
                              if (person.hidden) ...[
                                Icon(
                                  Icons.visibility_off_rounded,
                                  size: 11,
                                  color: scheme.outline,
                                ),
                                if (person.groupingLocked)
                                  const SizedBox(width: 2),
                              ],
                              if (person.groupingLocked)
                                Icon(
                                  Icons.lock_rounded,
                                  size: 11,
                                  color: scheme.secondary,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  personName(l10n, person),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  l10n.facesCount(person.faceCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnsortedCard extends StatelessWidget {
  const _UnsortedCard({required this.count, this.avatarRadius = 34});

  final int count;
  final double avatarRadius;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('unsorted-card'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Routes.unsorted),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: avatarRadius * 2,
                height: avatarRadius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.tertiaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.help_outline_rounded,
                  size: avatarRadius * 0.85,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  l10n.unsortedCardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  l10n.facesCount(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
