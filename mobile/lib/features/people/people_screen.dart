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
import 'identity_groups_screen.dart';

enum PeopleSort { mostFaces, name, newest }

/// S07 - everyone found in the library: a grid of cover + name + face count, an "Unsorted" card for
/// faces that belong to nobody yet, search and sort.
///
/// The same screen lists drawn characters (`kind: 'character'`): they are grouped, reviewed,
/// merged and split exactly like people, in their own list.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key, this.kind = 'person', this.initialGroupId});
  final int? initialGroupId;

  final String kind;

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _search = TextEditingController();
  var _query = '';
  var _sort = PeopleSort.mostFaces;
  var _filter = 'all';
  late int? _groupId = widget.initialGroupId;
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
    final characters = widget.kind == 'character';
    final listProvider = characters ? charactersProvider : peopleProvider;
    final people = ref.watch(listProvider);
    final unsorted =
        ref
            .watch(
              characters
                  ? characterUnsortedCountProvider
                  : unsortedCountProvider,
            )
            .value ??
        0;
    final review =
        ref.watch(reviewCountsByKindProvider(widget.kind)).value?.total ?? 0;
    final questions =
        ref.watch(reviewQuestionsByKindProvider(widget.kind)).value?.length ??
        0;
    final charactersCount = ref.watch(charactersProvider).value?.length ?? 0;
    final reviewRoute = characters
        ? '${Routes.review}?kind=character'
        : Routes.review;
    final groupsState = ref.watch(identityGroupsProvider);
    final groups = groupsState.value ?? const [];
    final groupId =
        _groupId != null &&
            _groupId! > 0 &&
            groupsState.hasValue &&
            !groups.any((g) => g.id == _groupId)
        ? null
        : _groupId;
    final allPeople = people.value ?? const <PersonSummary>[];
    final q = _query.trim().toLowerCase();
    final visible = allPeople
        .where(
          (p) =>
              (_filter == 'hidden' ? p.hidden : !p.hidden) &&
              (_filter != 'favorites' || p.favorite) &&
              (_filter != 'pinned' || p.pinned) &&
              (groupId == null ||
                  (groupId == -1 ? p.groupId == null : p.groupId == groupId)) &&
              (q.isEmpty ||
                  personName(l10n, p).toLowerCase().contains(q) ||
                  (p.groupName?.toLowerCase().contains(q) ?? false)),
        )
        .toList();
    _selected.removeWhere((id) => !allPeople.any((p) => p.id == id));

    return Scaffold(
      appBar: AppBar(
        title: Text(characters ? l10n.peopleCharacters : l10n.navPeople),
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
          PopupMenuButton<String>(
            key: const Key('people-tools'),
            tooltip: l10n.peopleAction('more'),
            icon: Badge(
              isLabelVisible: review > 0,
              child: const Icon(Icons.more_horiz),
            ),
            onSelected: (value) {
              if (value == 'groups') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => IdentityGroupsScreen(kind: widget.kind),
                  ),
                );
              } else {
                context.push(
                  value == 'review'
                      ? reviewRoute
                      : value == 'test'
                      ? '${Routes.analyze}?characters=true'
                      : Routes.bodies,
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                key: const Key('manage-identity-groups'),
                value: 'groups',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(l10n.identityGroupsTitle),
                ),
              ),
              PopupMenuItem(
                key: const Key('open-review'),
                value: 'review',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(l10n.reviewTitle),
                  trailing: review > 0 ? Text('$review') : null,
                ),
              ),
              if (characters)
                PopupMenuItem(
                  key: const Key('test-character-photo'),
                  value: 'test',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.add_photo_alternate_outlined),
                    title: Text(l10n.charactersTestPhoto),
                  ),
                ),
              if (!characters)
                PopupMenuItem(
                  key: const Key('open-bodies'),
                  value: 'bodies',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.accessibility_new),
                    title: Text(l10n.bodiesTitle),
                  ),
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const Key('open-people'),
                      label: Text(l10n.navPeople),
                      avatar: const Icon(Icons.people_outline, size: 18),
                      selected: !characters,
                      showCheckmark: false,
                      onSelected: (_) {
                        if (characters) leave(context, Routes.people);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      key: const Key('open-characters'),
                      label: Text(
                        charactersCount > 0
                            ? '${l10n.peopleCharacters} · $charactersCount'
                            : l10n.peopleCharacters,
                      ),
                      avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
                      selected: characters,
                      showCheckmark: false,
                      onSelected: (_) {
                        if (!characters) context.push(Routes.characters);
                      },
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: people.when(
              loading: () => const LoadingBox(),
              error: (e, _) => EmptyState(
                icon: Icons.people_outline,
                title: '$e',
                actionLabel: l10n.retry,
                onAction: () => ref.invalidate(listProvider),
              ),
              data: (all) {
                if (all.isEmpty && unsorted == 0) {
                  return EmptyState(
                    icon: characters
                        ? Icons.auto_awesome_outlined
                        : Icons.groups_outlined,
                    title: characters
                        ? l10n.charactersEmpty
                        : l10n.noPeopleTitle,
                    body: characters
                        ? l10n.charactersEmptyHint
                        : l10n.noPeopleBody,
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
                      (a, b) => personName(l10n, a).toLowerCase().compareTo(
                        personName(l10n, b).toLowerCase(),
                      ),
                    );
                  case PeopleSort.newest:
                    shown.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                }
                shown.sort((a, b) {
                  final pin = (b.pinned ? 1 : 0).compareTo(a.pinned ? 1 : 0);
                  if (pin != 0) return pin;
                  return switch (_sort) {
                    PeopleSort.name =>
                      personName(l10n, a).toLowerCase().compareTo(
                        personName(l10n, b).toLowerCase(),
                      ),
                    PeopleSort.newest => b.createdAt.compareTo(a.createdAt),
                    PeopleSort.mostFaces => b.faceCount.compareTo(a.faceCount),
                  };
                });
                return CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          if (questions > 0 && !_selecting)
                            ReviewBanner(
                              key: const Key('people-review-banner'),
                              icon: Icons.swipe_outlined,
                              title: l10n.peopleReviewBanner(questions),
                              body: l10n.peopleReviewBannerBody,
                              onTap: () => context.push(
                                '$reviewRoute${characters ? '&' : '?'}view=quick',
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                            child: TextField(
                              key: const Key('people-search'),
                              controller: _search,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_query.isNotEmpty)
                                      IconButton(
                                        key: const Key('people-clear-search'),
                                        tooltip: l10n.clearSearch,
                                        onPressed: _clearSearch,
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    PopupMenuButton<PeopleSort>(
                                      key: const Key('people-sort'),
                                      tooltip: l10n.sortBy,
                                      icon: const Icon(Icons.sort),
                                      initialValue: _sort,
                                      onSelected: (v) =>
                                          setState(() => _sort = v),
                                      itemBuilder: (context) => [
                                        CheckedPopupMenuItem(
                                          value: PeopleSort.mostFaces,
                                          checked:
                                              _sort == PeopleSort.mostFaces,
                                          child: Text(l10n.sortMostFaces),
                                        ),
                                        CheckedPopupMenuItem(
                                          value: PeopleSort.name,
                                          checked: _sort == PeopleSort.name,
                                          child: Text(l10n.sortName),
                                        ),
                                        CheckedPopupMenuItem(
                                          value: PeopleSort.newest,
                                          checked: _sort == PeopleSort.newest,
                                          child: Text(l10n.sortNewest),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                hintText: characters
                                    ? l10n.peopleSearchCharacters
                                    : l10n.searchPeopleHint,
                                filled: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          if (groups.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      key: ValueKey(
                                        'people-group-filter-$groupId',
                                      ),
                                      initialValue: groupId ?? 0,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: l10n.identityGroupsTitle,
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: 0,
                                          child: Text(l10n.identityGroupAll),
                                        ),
                                        DropdownMenuItem(
                                          value: -1,
                                          child: Text(
                                            l10n.identityGroupUngrouped,
                                          ),
                                        ),
                                        for (final group in groups)
                                          DropdownMenuItem(
                                            value: group.id,
                                            child: Text(
                                              group.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                      onChanged: (id) => setState(() {
                                        _groupId = id == 0 ? null : id;
                                        _selected.clear();
                                      }),
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('people-manage-groups'),
                                    tooltip: l10n.identityGroupsTitle,
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => IdentityGroupsScreen(
                                          kind: widget.kind,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.create_new_folder_outlined,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shown.isEmpty &&
                        (q.isNotEmpty ||
                            _filter != 'all' ||
                            groupId != null ||
                            unsorted == 0))
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.person_search_outlined,
                          title: q.isNotEmpty
                              ? l10n.peopleNoMatches
                              : l10n.peopleAction('noResults'),
                          actionLabel: q.isNotEmpty
                              ? l10n.clearSearch
                              : l10n.clearFilters,
                          onAction: q.isNotEmpty
                              ? _clearSearch
                              : () => setState(() {
                                  _filter = 'all';
                                  _groupId = null;
                                }),
                        ),
                      )
                    else
                      SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.crossAxisExtent;
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
                              64.0 +
                              (avatarRadius * 2) +
                              textScaleDelta * 2.5 +
                              (shown.any((p) => p.groupName != null)
                                  ? 22 + textScaleDelta
                                  : 0);

                          return SliverPadding(
                            padding: const EdgeInsets.fromLTRB(
                              horizontalPadding,
                              2,
                              horizontalPadding,
                              24,
                            ),
                            sliver: SliverGrid(
                              key: const Key('people-grid'),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: crossAxisSpacing,
                                    mainAxisSpacing: mainAxisSpacing,
                                    mainAxisExtent: mainAxisExtent,
                                  ),
                              delegate: SliverChildListDelegate([
                                if (unsorted > 0 &&
                                    q.isEmpty &&
                                    _filter == 'all' &&
                                    groupId == null &&
                                    !_selecting)
                                  _UnsortedCard(
                                    count: unsorted,
                                    avatarRadius: avatarRadius,
                                    kind: widget.kind,
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
                              ]),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ],
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
              if (person.groupName != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    person.groupName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.primary),
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
  const _UnsortedCard({
    required this.count,
    this.avatarRadius = 34,
    this.kind = 'person',
  });

  final int count;
  final double avatarRadius;
  final String kind;

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
        onTap: () => context.push(
          kind == 'character'
              ? '${Routes.unsorted}?kind=character'
              : Routes.unsorted,
        ),
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
