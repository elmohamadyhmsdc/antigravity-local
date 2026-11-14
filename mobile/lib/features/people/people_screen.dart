import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../data/repositories/identity_groups.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../ui/scaffolds/tab_root_scaffold.dart';
import '../../ui/sheets/name_sheet.dart';
import '../review/review_banner.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import 'people_actions.dart';
import 'action_sheet.dart';
import 'identity_groups_screen.dart';

enum PeopleSort { mostFaces, name, newest }

final _allIdentitiesProvider = StreamProvider.autoDispose<List<PersonSummary>>(
  (ref) => ref.watch(peopleRepositoryProvider).watchIdentities(),
);

/// S07 - everyone found in the library: a grid of cover + name + face count, an "Unsorted" card for
/// faces that belong to nobody yet, search and sort.
///
/// The same screen lists drawn characters (`kind: 'character'`): they are grouped, reviewed,
/// merged and split exactly like people, in their own list.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key, this.kind = 'all', this.initialGroupId});
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
  late String _kind = widget.kind;
  late int? _groupId = widget.initialGroupId;
  bool _selecting = false;
  final _selected = <int>{};

  void _startSelection(int id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selecting = true;
      _selected.add(id);
    });
  }

  void _toggle(int id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Future<void> _runAction(List<PersonSummary> allPeople, String action) async {
    final selectedPeople = allPeople
        .where((p) => _selected.contains(p.id))
        .toList();
    if (selectedPeople.isEmpty) return;
    await runPersonAction(context, ref, selectedPeople, action);
    if (mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  Future<void> _menu(List<PersonSummary> people) async {
    final mixed = people.map((p) => p.kind).toSet().length > 1;
    final l = AppLocalizations.of(context);
    final action = await showPeopleActionSheet(
      context,
      title: people.length == 1
          ? personName(l, people.single)
          : l.selectedCount(people.length),
      cropPath: people.length == 1 ? people.single.avatarCropPath : null,
      actions: [
        for (final action in personMenuActions(people))
          if (!mixed ||
              !{'merge', 'toCharacters', 'toPeople'}.contains(action.id))
            action,
      ],
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

  Future<void> _openReview({bool quick = false}) async {
    var kind = _kind;
    if (kind == 'all') {
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Choose type to review')),
              ListTile(
                title: const Text('People'),
                onTap: () => Navigator.pop(context, 'person'),
              ),
              ListTile(
                title: const Text('Anime characters'),
                onTap: () => Navigator.pop(context, 'character'),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      kind = selected;
    }
    final uri = Uri(
      path: Routes.review,
      queryParameters: {
        if (kind == 'character') 'kind': 'character',
        if (quick) 'view': 'quick',
      },
    );
    context.push(uri.toString());
  }

  void _showToolsSheet(
    BuildContext context,
    int review,
    String scopedKind,
    bool characters,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.manage_accounts_outlined,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.peopleAction('more'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ToolsSheetTile(
                key: const Key('manage-identity-groups'),
                icon: Icons.folder_outlined,
                title: l10n.identityGroupsTitle,
                subtitle: 'Organize people & characters into folders',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IdentityGroupsScreen(kind: scopedKind),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              _ToolsSheetTile(
                key: const Key('open-review'),
                icon: Icons.fact_check_outlined,
                title: l10n.reviewTitle,
                subtitle: 'Review doubts and merge suggestions',
                trailingBadge: review > 0 ? '$review' : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _openReview();
                },
              ),
              const SizedBox(height: 6),
              _ToolsSheetTile(
                key: const Key('test-character-photo'),
                icon: Icons.add_photo_alternate_outlined,
                title: 'Analyze photo',
                subtitle: 'Detect faces & characters from a single image',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('${Routes.analyze}?characters=$characters');
                },
              ),
              const SizedBox(height: 6),
              _ToolsSheetTile(
                key: const Key('open-bodies'),
                icon: Icons.accessibility_new,
                title: l10n.bodiesTitle,
                subtitle: 'Browse detected full-body crops and poses',
                onTap: () {
                  Navigator.pop(ctx);
                  context.push(Routes.bodies);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final characters = _kind == 'character';
    final allKinds = _kind == 'all';
    final listProvider = allKinds
        ? _allIdentitiesProvider
        : characters
        ? charactersProvider
        : peopleProvider;
    final people = ref.watch(listProvider);
    final humanUnsorted = ref.watch(unsortedCountProvider).value ?? 0;
    final characterUnsorted =
        ref.watch(characterUnsortedCountProvider).value ?? 0;
    final unsorted =
        ref
            .watch(
              characters
                  ? characterUnsortedCountProvider
                  : unsortedCountProvider,
            )
            .value ??
        0;
    final scopedKind = characters ? 'character' : 'person';
    final review =
        (ref.watch(reviewCountsByKindProvider(scopedKind)).value?.total ?? 0) +
        (allKinds
            ? (ref
                      .watch(reviewCountsByKindProvider('character'))
                      .value
                      ?.total ??
                  0)
            : 0);
    final questions =
        (ref.watch(reviewQuestionsByKindProvider(scopedKind)).value?.length ??
            0) +
        (allKinds
            ? (ref
                      .watch(reviewQuestionsByKindProvider('character'))
                      .value
                      ?.length ??
                  0)
            : 0);
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

    final selectedPeople = allPeople
        .where((p) => _selected.contains(p.id))
        .toList();
    final mixedKinds = selectedPeople.map((p) => p.kind).toSet().length > 1;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) {
          setState(() {
            _selecting = false;
            _selected.clear();
          });
        }
      },
      child: TabRootScaffold(
        title: Text(l10n.navPeople),
        onSettingsTap: () => context.push(Routes.settings),
        primaryAction: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('people-select'),
              tooltip: _selecting
                  ? l10n.cancel
                  : l10n.peopleAction('selection'),
              icon: Icon(_selecting ? Icons.close : Icons.checklist),
              onPressed: () => setState(() {
                _selecting = !_selecting;
                _selected.clear();
              }),
            ),
            if (!_selecting)
              IconButton(
                key: const Key('people-tools'),
                tooltip: l10n.peopleAction('more'),
                icon: Badge(
                  isLabelVisible: review > 0,
                  child: const Icon(Icons.more_horiz),
                ),
                onPressed: () =>
                    _showToolsSheet(context, review, scopedKind, characters),
              ),
          ],
        ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton(
                key: const Key('people-add'),
                tooltip: _kind == 'group'
                    ? l10n.identityGroupCreate
                    : l10n.createPerson,
                onPressed: () async {
                  if (_kind == 'group') {
                    final name = await NameSheet.show(
                      context: context,
                      title: l10n.identityGroupCreate,
                      hintText: l10n.identityGroupNameHint,
                    );
                    if (!mounted) return;
                    if (name != null && name.isNotEmpty) {
                      await ref
                          .read(identityGroupsRepositoryProvider)
                          .create(name);
                    }
                  } else {
                    final name = await NameSheet.show(
                      context: context,
                      title: l10n.createPerson,
                    );
                    if (!mounted) return;
                    if (name != null && name.isNotEmpty) {
                      final targetKind = _kind == 'character'
                          ? 'character'
                          : 'person';
                      final id = await peopleRepositoryFor(
                        ref,
                        targetKind,
                      ).createPerson(name: name);
                      if (context.mounted) {
                        context.push('${Routes.people}/$id');
                      }
                    }
                  }
                },
                child: const Icon(Icons.add),
              ),
        bottomNavigationBar: !_selecting
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                l10n.selectedCount(_selected.length),
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: () => setState(
                                () =>
                                    _selected.addAll(visible.map((p) => p.id)),
                              ),
                              child: Text(l10n.selectAll),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
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
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (!mixedKinds)
                              _SelectionActionButton(
                                key: const Key('people-action-merge'),
                                icon: Icons.merge,
                                label: l10n.peopleAction('merge'),
                                enabled: _selected.isNotEmpty,
                                onPressed: () => _runAction(allPeople, 'merge'),
                              ),
                            if (_selected.length == 1)
                              _SelectionActionButton(
                                key: const Key('people-action-rename'),
                                icon: Icons.edit_outlined,
                                label: l10n.rename,
                                enabled: true,
                                onPressed: () =>
                                    _runAction(allPeople, 'rename'),
                              ),
                            _SelectionActionButton(
                              key: const Key('people-action-setGroup'),
                              icon: Icons.folder_outlined,
                              label: l10n.identityGroupsTitle,
                              enabled: _selected.isNotEmpty,
                              onPressed: () =>
                                  _runAction(allPeople, 'setGroup'),
                            ),
                            _SelectionActionButton(
                              key: const Key('people-action-deletePerson'),
                              icon: Icons.delete_outline,
                              label: l10n.delete,
                              color: Theme.of(context).colorScheme.error,
                              enabled: _selected.isNotEmpty,
                              onPressed: () =>
                                  _runAction(allPeople, 'deletePerson'),
                            ),
                            _SelectionActionButton(
                              key: const Key('people-selection-actions'),
                              icon: Icons.more_horiz,
                              label: l10n.peopleAction('more'),
                              enabled: _selected.isNotEmpty,
                              onPressed: () => _menu(selectedPeople),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                        key: const Key('open-all-types'),
                        visualDensity: VisualDensity.compact,
                        labelPadding: EdgeInsets.zero,
                        label: const Text('All types'),
                        selected: allKinds,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _kind = 'all';
                          _selected.clear();
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('open-people'),
                        visualDensity: VisualDensity.compact,
                        labelPadding: EdgeInsets.zero,
                        label: Text(l10n.navPeople),
                        selected: _kind == 'person',
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _kind = 'person';
                          _selected.clear();
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('open-characters'),
                        visualDensity: VisualDensity.compact,
                        labelPadding: EdgeInsets.zero,
                        label: Text(l10n.peopleCharacters),
                        selected: characters,
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _kind = 'character';
                          _selected.clear();
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        key: const Key('open-groups'),
                        visualDensity: VisualDensity.compact,
                        labelPadding: EdgeInsets.zero,
                        label: Text(l10n.identityGroupsTitle),
                        selected: _kind == 'group',
                        showCheckmark: false,
                        onSelected: (_) => setState(() {
                          _kind = 'group';
                          _selected.clear();
                        }),
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
                      PeopleSort.mostFaces => b.faceCount.compareTo(
                        a.faceCount,
                      ),
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
                                onTap: () => _openReview(quick: true),
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
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  4,
                                  14,
                                  8,
                                ),
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
                                      onPressed: () =>
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  IdentityGroupsScreen(
                                                    kind: scopedKind,
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
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
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
                                          label: Text(
                                            l10n.peopleAction(filter),
                                          ),
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
                                (width -
                                    (horizontalPadding * 2) -
                                    totalSpacing) /
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
                                  if ((allKinds ? humanUnsorted : unsorted) >
                                          0 &&
                                      q.isEmpty &&
                                      _filter == 'all' &&
                                      groupId == null &&
                                      !_selecting)
                                    _UnsortedCard(
                                      count: allKinds
                                          ? humanUnsorted
                                          : unsorted,
                                      avatarRadius: avatarRadius,
                                      kind: scopedKind,
                                    ),
                                  if (allKinds &&
                                      characterUnsorted > 0 &&
                                      q.isEmpty &&
                                      _filter == 'all' &&
                                      groupId == null &&
                                      !_selecting)
                                    _UnsortedCard(
                                      count: characterUnsorted,
                                      avatarRadius: avatarRadius,
                                      kind: 'character',
                                    ),
                                  if (_kind == 'group')
                                    for (final g in groups)
                                      _GroupCard(
                                        group: g,
                                        avatarRadius: avatarRadius,
                                      )
                                  else
                                    for (final p in shown)
                                      _PersonCard(
                                        person: p,
                                        selecting: _selecting,
                                        selected: _selected.contains(p.id),
                                        onToggle: () => _toggle(p.id),
                                        onStartSelection: () =>
                                            _startSelection(p.id),
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
    required this.onStartSelection,
    required this.onMenu,
    this.avatarRadius = 34,
  });

  final PersonSummary person;
  final bool selecting, selected;
  final VoidCallback onToggle, onStartSelection, onMenu;
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
          HapticFeedback.mediumImpact();
          if (selecting) {
            onToggle();
          } else {
            onStartSelection();
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
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
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
                        expandable: false,
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
                              color: isSelected
                                  ? scheme.primary
                                  : scheme.surface,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(1.5),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: isSelected
                                  ? scheme.onPrimary
                                  : scheme.outline,
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
        key: Key(
          kind == 'character' ? 'unsorted-character-card' : 'unsorted-card',
        ),
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
                  kind == 'character'
                      ? '${l10n.unsortedCardTitle} · Characters'
                      : l10n.unsortedCardTitle,
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, this.avatarRadius = 34});

  final IdentityGroupSummary group;
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
        key: Key('group-${group.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('${Routes.group}/${group.id}'),
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
                  color: scheme.secondaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.folder_outlined,
                  size: avatarRadius * 0.85,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  group.name,
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
                  l10n.identityGroupMembers(group.people + group.characters),
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

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveColor = enabled
        ? (color ?? scheme.onSurface)
        : scheme.onSurface.withValues(alpha: 0.38);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed?.call();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: effectiveColor, size: 22),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                textScaler: MediaQuery.textScalerOf(
                  context,
                ).clamp(maxScaleFactor: 1.1),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: effectiveColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolsSheetTile extends StatelessWidget {
  const _ToolsSheetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingBadge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: scheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailingBadge != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    trailingBadge!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
