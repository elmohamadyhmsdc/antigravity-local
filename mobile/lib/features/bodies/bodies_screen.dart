import 'package:drift/drift.dart' show Variable, BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../../domain/pose/body_categories.dart' show CategoryMatch;
import '../../domain/pose/exposed_matching.dart';
import '../../domain/pose/outfit_palette.dart';
import '../../domain/pose/pose_rules.dart';
import '../../domain/pose/group_poses.dart';
import '../marks/mark_tattoo.dart';
import '../shared/crop_image.dart';
import 'body_areas.dart';
import 'pose_visuals.dart';
import 'group_pose_screens.dart';
import 'equipment_screens.dart';
import '../../domain/pose/group_pose_matcher.dart';
import 'body_naming.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';

/// Roadmap Phase 4 / section 6.1: the library's bodies, filtered by Tier-A pose chips and outfit colours,
/// with "find similar pose" and "name this pose / outfit" from an example. [personId] scopes everything
/// to one person (the Poses / Outfits chips of the person page).
class BodiesScreen extends ConsumerStatefulWidget {
  const BodiesScreen({
    super.key,
    this.personId,
    this.initialSimilar,
    this.initialSimilarColours,
    this.isRoot = false,
    this.initialTab = 0,
  });

  final bool isRoot;
  final int initialTab;
  final int? personId;

  /// Deep links from the photo viewer: start on "similar pose" / "similar colours" of this body.
  final int? initialSimilar;
  final int? initialSimilarColours;

  @override
  ConsumerState<BodiesScreen> createState() => _BodiesScreenState();
}

class _BodiesScreenState extends ConsumerState<BodiesScreen> {
  String? _tag;
  OutfitColor? _color;
  int? _similarTo;
  int? _colourTwinOf; // set: ranked by outfit colours of this body
  String?
  _groupTag; // set: photos with this multi-person tag (shown by one body each)
  Map<String, int> _groupCounts = const {};
  ExposedKind?
  _exposedKind; // set: the similar search is on the exposed-region embeddings, not the pose
  List<int> _ids = const [];
  Map<int, BodyTile> _rows = const {};
  Map<String, int> _counts = const {};
  bool _preparing = true;
  bool _clustersOn = false;
  int _areasVersion = 0;
  int _categoryVersion = 0;
  bool _loading = true;
  int _generation =
      0; // a slower, older reload must never overwrite a newer one

  @override
  void initState() {
    super.initState();
    _similarTo = widget.initialSimilar;
    _colourTwinOf = widget.initialSimilarColours;
    _prepare();
  }

  /// Descriptors are built lazily the first time the screen opens (and after scans).
  Future<void> _prepare() async {
    final poses = ref.read(poseIndexProvider);
    await poses.rebuild();
    final clustersOn = await ref.read(exposedClustersProvider).enabled;
    if (!mounted) return;
    setState(() {
      _preparing = false;
      _clustersOn = clustersOn;
    });
    await _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() => _loading = true);
    final poses = ref.read(poseIndexProvider);
    final counts = await poses.tagCounts(personId: widget.personId);
    final List<int> ids;
    var groupCounts = _groupCounts;
    if (widget.personId == null) {
      groupCounts = await GroupPhotos(ref.read(databaseProvider)).counts();
    }
    if (_groupTag != null) {
      ids = await _photoRepresentatives(_groupTag!);
    } else if (_colourTwinOf != null) {
      final draft = await ref
          .read(bodyCategoriesProvider)
          .draftOutfit(
            _colourTwinOf!,
            threshold: 0.75,
            personId: widget.personId,
          );
      ids = [
        for (final m in draft?.matches ?? const <CategoryMatch>[])
          if (m.bodyId != _colourTwinOf) m.bodyId,
      ];
    } else if (_similarTo != null && _exposedKind != null) {
      ids = [
        for (final r
            in await ref
                .read(exposedMatcherProvider)
                .findSimilar(_similarTo!, _exposedKind!))
          r.bodyId,
      ];
    } else if (_similarTo != null) {
      ids = [
        for (final r in await poses.findSimilar(
          _similarTo!,
          personId: widget.personId,
        ))
          r.bodyId,
      ];
    } else if (_tag != null) {
      ids = await poses.bodiesWithTag(_tag!, personId: widget.personId);
    } else if (_color != null) {
      ids = await poses.bodiesWithColor(_color!, personId: widget.personId);
    } else {
      ids = await _allBodies();
    }
    final rows = await _fetch(
      {...ids.take(400), ?_similarTo, ?_colourTwinOf}.toList(),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _counts = counts;
      _groupCounts = groupCounts;
      _ids = ids.where(rows.containsKey).take(400).toList();
      _rows = rows;
      _loading = false;
    });
  }

  Future<List<int>> _allBodies() async {
    final db = ref.read(databaseProvider);
    final person = widget.personId;
    final rows = await db
        .customSelect(
          '''SELECT b.id FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
             WHERE b.kind = 'person' ${person == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}
             ORDER BY b.id DESC LIMIT 400''',
          variables: [if (person != null) Variable.withInt(person)],
          readsFrom: {db.bodies, db.faces},
        )
        .get();
    return [for (final r in rows) r.read<int>('id')];
  }

  Future<Map<int, BodyTile>> _fetch(List<int> ids) => fetchBodyTiles(ref, ids);

  /// One body per photo that has the multi-person [tag] (the grid shows bodies; "open the photo" is an action).
  Future<List<int>> _photoRepresentatives(String tag) async {
    final photos = await GroupPhotos(
      ref.read(databaseProvider),
    ).photosWith(tag);
    if (photos.isEmpty) return const [];
    final db = ref.read(databaseProvider);
    final rows = await db
        .customSelect(
          "SELECT MIN(id) AS id FROM bodies WHERE kind = 'person' AND frame_number IS NULL AND media_id IN (${photos.take(400).join(',')}) GROUP BY media_id ORDER BY media_id DESC",
          readsFrom: {db.bodies},
        )
        .get();
    return [for (final r in rows) r.read<int>('id')];
  }

  void _filter({
    String? tag,
    OutfitColor? color,
    int? similar,
    ExposedKind? exposed,
    int? colours,
    String? group,
  }) {
    setState(() {
      _tag = tag;
      _color = color;
      _similarTo = similar;
      _exposedKind = exposed;
      _colourTwinOf = colours;
      _groupTag = group;
    });
    _reload();
  }

  String _tagLabel(AppLocalizations l, String tag) => switch (tag) {
    PoseTag.lying => l.poseTagLying,
    PoseTag.standing => l.poseTagStanding,
    PoseTag.sitting => l.poseTagSitting,
    PoseTag.armsUp => l.poseTagArmsUp,
    PoseTag.oneArmUp => l.poseTagOneArmUp,
    PoseTag.armsSpread => l.poseTagArmsSpread,
    PoseTag.handsOnHips => l.poseTagHandsOnHips,
    PoseTag.frontal => l.poseTagFrontal,
    PoseTag.profile => l.poseTagProfile,
    PoseTag.back => l.poseTagBack,
    _ => tag,
  };

  String _groupLabel(AppLocalizations l, String tag) => switch (tag) {
    GroupTag.group => l.groupTagGroup,
    GroupTag.lineup => l.groupTagLineup,
    GroupTag.allFacing => l.groupTagAllFacing,
    _ => tag,
  };

  String _colorLabel(AppLocalizations l, OutfitColor c) => switch (c) {
    OutfitColor.white => l.outfitColorWhite,
    OutfitColor.lightGrey => l.outfitColorLightGrey,
    OutfitColor.darkGrey => l.outfitColorDarkGrey,
    OutfitColor.black => l.outfitColorBlack,
    OutfitColor.red => l.outfitColorRed,
    OutfitColor.orange => l.outfitColorOrange,
    OutfitColor.yellow => l.outfitColorYellow,
    OutfitColor.green => l.outfitColorGreen,
    OutfitColor.cyan => l.outfitColorCyan,
    OutfitColor.blue => l.outfitColorBlue,
    OutfitColor.purple => l.outfitColorPurple,
    OutfitColor.pink => l.outfitColorPink,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // the Areas tab exists only while the (experimental) grouping switch is on
    final areas = _clustersOn && widget.personId == null;
    return DefaultTabController(
      length: areas ? 6 : 5,
      initialIndex: widget.initialTab.clamp(0, areas ? 5 : 4),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isRoot ? 'Discover' : l.bodiesTitle),
          automaticallyImplyLeading: !widget.isRoot,
          leading: widget.isRoot
              ? null
              : BackButton(onPressed: () => leave(context, Routes.library)),
          actions: [
            if (widget.personId == null)
              PopupMenuButton<String>(
                key: const Key('bodies-menu'),
                onSelected: (value) async {
                  if (value == 'clusters') {
                    await _toggleClusters();
                  } else if (value == 'marks') {
                    final person = await pickPerson(context, allowNew: false);
                    if (person?.personId != null && context.mounted) {
                      context.push(
                        '${Routes.marks}?personId=${person!.personId}',
                      );
                    }
                  }
                },
                itemBuilder: (_) => [
                  if (widget.isRoot)
                    const PopupMenuItem<String>(
                      value: 'marks',
                      child: Text('Marks'),
                    ),
                  CheckedPopupMenuItem<String>(
                    key: const Key('clusters-toggle'),
                    value: 'clusters',
                    checked: _clustersOn,
                    child: Text(l.clustersToggle),
                  ),
                ],
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(key: const Key('bodies-tab-all'), text: l.bodiesTabAll),
              Tab(key: const Key('bodies-tab-poses'), text: l.bodiesTabPoses),
              Tab(
                key: const Key('bodies-tab-outfits'),
                text: l.bodiesTabOutfits,
              ),
              Tab(key: const Key('bodies-tab-groups'), text: l.groupPoseTab),
              Tab(
                key: const Key('bodies-tab-equipment'),
                text: l.bodiesTabEquipment,
              ),
              if (areas)
                Tab(key: const Key('bodies-tab-areas'), text: l.bodiesTabAreas),
            ],
          ),
        ),
        body: Builder(
          builder: (tabContext) => TabBarView(
            children: [
              _allTab(l),
              _CategoryList(
                key: ValueKey('poses-$_categoryVersion'),
                pose: true,
                personId: widget.personId,
                counts: _counts,
                onTag: (tag) {
                  _filter(tag: tag);
                  DefaultTabController.of(tabContext).animateTo(0);
                },
              ),
              _CategoryList(
                key: ValueKey('outfits-$_categoryVersion'),
                pose: false,
                personId: widget.personId,
              ),
              GroupPosesTab(personId: widget.personId),
              EquipmentTab(personId: widget.personId),
              if (areas)
                BodyAreasTab(
                  key: ValueKey('areas-$_areasVersion'),
                  onSimilar: (id, kind) {
                    _filter(similar: id, exposed: kind);
                    DefaultTabController.of(tabContext).animateTo(0);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Switches the experimental grouping on (and builds the groups) or off. Off keeps the clusters but hides
  /// the tab and stops queueing suggestions.
  Future<void> _toggleClusters() async {
    final service = ref.read(exposedClustersProvider);
    final on = !_clustersOn;
    await service.setEnabled(on);
    if (on) {
      setState(() => _loading = true);
      await service.rebuild(ExposedKind.chest);
      await service.rebuild(ExposedKind.buttocks);
    }
    if (!mounted) return;
    setState(() {
      _clustersOn = on;
      _loading = false;
      _areasVersion++;
    });
  }

  Widget _allTab(AppLocalizations l) {
    return Column(
      children: [
        if (_preparing || _loading) const LinearProgressIndicator(),
        SizedBox(
          // not a lazy ListView: the chip count is small and every chip must exist (and be testable)
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                if (_similarTo != null ||
                    _colourTwinOf != null ||
                    _groupTag != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      key: const Key('bodies-similar-chip'),
                      label: Text(
                        _groupTag != null
                            ? _groupLabel(l, _groupTag!)
                            : _colourTwinOf != null
                            ? l.bodiesSimilarColoursTitle
                            : _exposedKind == null
                            ? l.bodiesSimilarTitle
                            : _exposedKind == ExposedKind.chest
                            ? l.equipmentAreaChestSimilar
                            : l.equipmentAreaLowerSimilar,
                      ),
                      onDeleted: () => _filter(),
                      deleteButtonTooltipMessage: l.bodiesClearFilter,
                    ),
                  ),
                if (widget.personId == null)
                  for (final tag in GroupTag.all)
                    if ((_groupCounts[tag] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          key: Key('group-chip-$tag'),
                          label: Text(
                            '${_groupLabel(l, tag)} · ${_groupCounts[tag]}',
                          ),
                          selected: _groupTag == tag,
                          onSelected: (on) => _filter(group: on ? tag : null),
                        ),
                      ),
                for (final tag in PoseTag.all)
                  if ((_counts[tag] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: Key('pose-chip-$tag'),
                        label: Text('${_tagLabel(l, tag)} · ${_counts[tag]}'),
                        selected: _tag == tag,
                        onSelected: (on) => _filter(tag: on ? tag : null),
                      ),
                    ),
                for (final color in OutfitColor.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('color-chip-${color.name}'),
                      label: Text(_colorLabel(l, color)),
                      selected: _color == color,
                      onSelected: (on) => _filter(color: on ? color : null),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_similarTo != null || _colourTwinOf != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  height: 84,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CropImage(
                      path: _rows[_similarTo ?? _colourTwinOf]?.cropPath,
                      fit: BoxFit.contain,
                      placeholderIcon: Icons.accessibility_new,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.groupPoseReference,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        _colourTwinOf != null
                            ? l.bodyActionSimilarColours
                            : _exposedKind == null
                            ? l.bodyActionSimilarPose
                            : _exposedKind == ExposedKind.chest
                            ? l.equipmentAreaChest
                            : l.equipmentAreaLower,
                      ),
                    ],
                  ),
                ),
                if (_exposedKind != null)
                  SizedBox(
                    width: 48,
                    height: 72,
                    child: PoseDiagram(
                      area: _exposedKind == ExposedKind.chest
                          ? 'chest'
                          : 'lower',
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _ids.isEmpty && !_loading && !_preparing
              ? EmptyState(
                  icon: Icons.accessibility_new,
                  title:
                      _tag != null ||
                          _color != null ||
                          _similarTo != null ||
                          _colourTwinOf != null ||
                          _groupTag != null
                      ? l.bodiesNothingMatches
                      : l.bodiesEmpty,
                )
              : _grid(_ids, (id) => _openActions(id)),
        ),
      ],
    );
  }

  Widget _grid(List<int> ids, void Function(int id) onTap) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.62,
      ),
      itemCount: ids.length,
      itemBuilder: (context, i) {
        final row = _rows[ids[i]];
        return InkWell(
          key: Key('body-${ids[i]}'),
          onTap: () => onTap(ids[i]),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CropImage(
              path: row?.cropPath,
              placeholderIcon: Icons.accessibility_new,
              cacheWidth: 240,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openActions(int bodyId) async {
    final l = AppLocalizations.of(context);
    final mediaId = _rows[bodyId]?.mediaId;
    final exposedKinds = await ref.read(exposedMatcherProvider).kindsOf(bodyId);
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        height: 88,
                        child: CropImage(
                          path: _rows[bodyId]?.cropPath,
                          fit: BoxFit.contain,
                          placeholderIcon: Icons.accessibility_new,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          l.bodiesSelectedExample,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                if (mediaId != null) ...[
                  ListTile(
                    key: const Key('action-group-pose'),
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(l.groupPoseName),
                    onTap: () => Navigator.pop(context, 'group-pose'),
                  ),
                  ListTile(
                    key: const Key('action-equipment'),
                    leading: const Icon(Icons.sports_tennis_outlined),
                    title: Text(l.bodiesTabEquipment),
                    onTap: () => Navigator.pop(context, 'equipment'),
                  ),
                ],
                ListTile(
                  key: const Key('action-similar'),
                  leading: const Icon(Icons.compare_outlined),
                  title: Text(l.bodyActionSimilarPose),
                  onTap: () => Navigator.pop(context, 'similar'),
                ),
                for (final kind in exposedKinds)
                  ListTile(
                    key: Key('action-similar-${kind.name}'),
                    leading: const Icon(Icons.image_search_outlined),
                    title: Text(
                      kind == ExposedKind.chest
                          ? l.equipmentAreaChestSimilar
                          : l.equipmentAreaLowerSimilar,
                    ),
                    subtitle: Text(
                      kind == ExposedKind.chest
                          ? l.equipmentAreaChest
                          : l.equipmentAreaLower,
                    ),
                    trailing: SizedBox(
                      width: 44,
                      height: 56,
                      child: PoseDiagram(
                        area: kind == ExposedKind.chest ? 'chest' : 'lower',
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'exposed-${kind.name}'),
                  ),
                ListTile(
                  key: const Key('action-similar-colours'),
                  leading: const Icon(Icons.palette_outlined),
                  title: Text(l.bodyActionSimilarColours),
                  onTap: () => Navigator.pop(context, 'colours'),
                ),
                ListTile(
                  key: const Key('action-name-pose'),
                  leading: const Icon(Icons.accessibility_new),
                  title: Text(l.bodyActionNamePose),
                  onTap: () => Navigator.pop(context, 'pose'),
                ),
                ListTile(
                  key: const Key('action-mark-tattoo'),
                  leading: const Icon(Icons.draw_outlined),
                  title: Text(l.bodyActionMarkTattoo),
                  onTap: () => Navigator.pop(context, 'mark'),
                ),
                ListTile(
                  key: const Key('action-name-outfit'),
                  leading: const Icon(Icons.checkroom_outlined),
                  title: Text(l.bodyActionNameOutfit),
                  onTap: () => Navigator.pop(context, 'outfit'),
                ),
                if (mediaId != null)
                  ListTile(
                    key: const Key('action-open-photo'),
                    leading: const Icon(Icons.photo_outlined),
                    title: Text(l.bodyActionOpenPhoto),
                    onTap: () => Navigator.pop(context, 'photo'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice.startsWith('exposed-')) {
      _filter(
        similar: bodyId,
        exposed: ExposedKind.values.byName(choice.substring(8)),
      );
      return;
    }
    switch (choice) {
      case 'group-pose':
        if (mediaId != null) await nameGroupPose(context, ref, mediaId);
      case 'equipment':
        if (mediaId != null) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => EquipmentPhotoScreen(mediaId: mediaId),
            ),
          );
        }
      case 'similar':
        _filter(similar: bodyId);
      case 'mark':
        await showMarkTattoo(context, ref, bodyId);
      case 'colours':
        _filter(colours: bodyId);
      case 'pose':
        if (await nameBodyPose(context, ref, bodyId)) {
          setState(() => _categoryVersion++);
        }
      case 'outfit':
        if (await nameBodyOutfit(
          context,
          ref,
          bodyId,
          personId: widget.personId,
        )) {
          setState(() => _categoryVersion++);
        }
      case 'photo':
        context.push('${Routes.media}/$mediaId');
    }
  }
}

/// The saved pose or outfit groups; tap one to see its bodies, long-press a body to take it out.
class _CategoryList extends ConsumerStatefulWidget {
  const _CategoryList({
    super.key,
    required this.pose,
    this.personId,
    this.counts = const {},
    this.onTag,
  });
  final Map<String, int> counts;
  final void Function(String)? onTag;

  final bool pose;
  final int? personId;

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList> {
  List<({int id, String name, int count, String? cropPath})> _items = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final categories = ref.read(bodyCategoriesProvider);
    final items = <({int id, String name, int count, String? cropPath})>[];
    if (widget.pose) {
      for (final c in await (db.select(
        db.poseCategories,
      )..where((c) => c.kind.equals(groupPoseKind).not())).get()) {
        items.add((
          id: c.id,
          name: c.name,
          count: (await categories.bodiesInPose(c.id)).length,
          cropPath: c.exemplarBodyId == null
              ? null
              : (await fetchBodyTiles(ref, [
                  c.exemplarBodyId!,
                ]))[c.exemplarBodyId]?.cropPath,
        ));
      }
    } else {
      for (final c in await db.select(db.outfitCategories).get()) {
        if (widget.personId != null &&
            c.personId != null &&
            c.personId != widget.personId) {
          continue;
        }
        items.add((
          id: c.id,
          name: c.name,
          count: (await categories.bodiesInOutfit(c.id)).length,
          cropPath: c.exemplarBodyId == null
              ? null
              : (await fetchBodyTiles(ref, [
                  c.exemplarBodyId!,
                ]))[c.exemplarBodyId]?.cropPath,
        ));
      }
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_items.isNotEmpty && widget.pose)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.poseSavedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        for (final item in _items)
          ListTile(
            key: Key('category-${widget.pose ? 'pose' : 'outfit'}-${item.id}'),
            leading: SizedBox(
              width: 56,
              height: 72,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CropImage(
                  path: item.cropPath,
                  fit: BoxFit.contain,
                  placeholderIcon: widget.pose
                      ? Icons.accessibility_new
                      : Icons.checkroom_outlined,
                ),
              ),
            ),
            title: Text(item.name),
            subtitle: Text(l.categoryBodyCount(item.count)),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _CategoryBodies(
                    pose: widget.pose,
                    id: item.id,
                    name: item.name,
                  ),
                ),
              );
              if (mounted) _load();
            },
          ),

        if (widget.pose) ...[
          Text(l.poseBrowseHint),
          for (final section in [
            (l.posePostureTitle, PoseTag.posture),
            (l.poseArmsTitle, PoseTag.arms),
            (l.poseDirectionTitle, PoseTag.orientation),
          ]) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                section.$1,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in section.$2)
                  SizedBox(
                    width: 140,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        key: Key('pose-visual-$tag'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: (widget.counts[tag] ?? 0) == 0
                            ? null
                            : () => widget.onTag?.call(tag),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 72,
                                width: 104,
                                child: PoseDiagram(tag: tag),
                              ),
                              Text(
                                poseLabel(l, tag),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                l.categoryBodyCount(widget.counts[tag] ?? 0),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l.categoryNone),
          ),
      ],
    );
  }
}

class _CategoryBodies extends ConsumerStatefulWidget {
  const _CategoryBodies({
    required this.pose,
    required this.id,
    required this.name,
  });

  final bool pose;
  final int id;
  final String name;

  @override
  ConsumerState<_CategoryBodies> createState() => _CategoryBodiesState();
}

class _CategoryBodiesState extends ConsumerState<_CategoryBodies> {
  List<int> _ids = const [];
  Map<int, BodyTile> _rows = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final categories = ref.read(bodyCategoriesProvider);
    final ids = widget.pose
        ? await categories.bodiesInPose(widget.id)
        : await categories.bodiesInOutfit(widget.id);
    final db = ref.read(databaseProvider);
    final shown = ids.take(400).toList();
    final rows = shown.isEmpty
        ? <int, BodyTile>{}
        : {
            for (final r
                in await db
                    .customSelect(
                      'SELECT id, crop_path, media_id FROM bodies WHERE id IN (${List.filled(shown.length, '?').join(',')})',
                      variables: [for (final id in shown) Variable.withInt(id)],
                      readsFrom: {db.bodies},
                    )
                    .get())
              r.read<int>('id'): (
                id: r.read<int>('id'),
                cropPath: r.readNullable<String>('crop_path'),
                mediaId: r.readNullable<int>('media_id'),
              ),
          };
    if (mounted) {
      setState(() {
        _ids = shown;
        _rows = rows;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final categories = ref.read(bodyCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          IconButton(
            key: const Key('category-delete'),
            tooltip: l.categoryDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (widget.pose) {
                await categories.deletePose(widget.id);
              } else {
                await categories.deleteOutfit(widget.id);
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 0.62,
        ),
        itemCount: _ids.length,
        itemBuilder: (context, i) {
          final id = _ids[i];
          return InkWell(
            key: Key('category-body-$id'),
            onTap: () {
              final media = _rows[id]?.mediaId;
              if (media != null) context.push('${Routes.media}/$media');
            },
            onLongPress: () async {
              if (widget.pose) {
                await categories.setPoseState(widget.id, id, 'rejected');
              } else {
                await categories.setOutfitState(widget.id, id, 'rejected');
              }
              await _load();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CropImage(
                path: _rows[id]?.cropPath,
                placeholderIcon: Icons.accessibility_new,
              ),
            ),
          );
        },
      ),
    );
  }
}
