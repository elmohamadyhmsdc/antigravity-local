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
import 'body_inspection_sheet.dart';
import 'pose_visuals.dart';
import 'discovery_widgets.dart';
import 'body_comparison_sheet.dart';
import 'group_pose_screens.dart';
import 'equipment_screens.dart';
import '../../domain/pose/group_pose_matcher.dart';
import '../../domain/pose/pose_index.dart' show decodeTags, poseRulesVersion;
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
  bool _failed = false;
  Map<int, ({double similarity, double? coverage})> _matches = const {};
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
    try {
      final poses = ref.read(poseIndexProvider);
      await poses.rebuild();
      final db = ref.read(databaseProvider);
      if (await db.setting('pose.matches.version') != '$poseRulesVersion') {
        await ref.read(bodyCategoriesProvider).rescoreAllPoses();
        await db.putSetting('pose.matches.version', '$poseRulesVersion');
        if (mounted) setState(() => _categoryVersion++);
      }
      final clusters = ref.read(exposedClustersProvider);
      final clustersOn = await clusters.enabled;
      if (clustersOn && await db.setting('areas.matches.version') != '2') {
        await clusters.rebuild(ExposedKind.chest);
        await clusters.rebuild(ExposedKind.buttocks);
        await db.putSetting('areas.matches.version', '2');
        if (mounted) setState(() => _areasVersion++);
      }
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _clustersOn = clustersOn;
      });
      await _reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _preparing = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _reload() async {
    try {
      final generation = ++_generation;
      setState(() => _loading = true);
      final poses = ref.read(poseIndexProvider);
      final counts = await poses.tagCounts(personId: widget.personId);
      final List<int> ids;
      final matches = <int, ({double similarity, double? coverage})>{};
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
        for (final m in draft?.matches ?? const <CategoryMatch>[]) {
          matches[m.bodyId] = (similarity: m.similarity, coverage: null);
        }
        ids = [
          for (final m in draft?.matches ?? const <CategoryMatch>[])
            if (m.bodyId != _colourTwinOf) m.bodyId,
        ];
      } else if (_similarTo != null && _exposedKind != null) {
        final ranked = await ref
            .read(exposedMatcherProvider)
            .findSimilar(_similarTo!, _exposedKind!, personId: widget.personId);
        for (final r in ranked) {
          matches[r.bodyId] = (similarity: r.similarity, coverage: null);
        }
        ids = [for (final r in ranked) r.bodyId];
      } else if (_similarTo != null) {
        final ranked = await poses.findSimilar(
          _similarTo!,
          personId: widget.personId,
        );
        for (final r in ranked) {
          matches[r.bodyId] = (similarity: r.similarity, coverage: r.coverage);
        }
        ids = [for (final r in ranked) r.bodyId];
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
        _matches = matches;
        _failed = false;
        _counts = counts;
        _groupCounts = groupCounts;
        _ids = ids.where(rows.containsKey).take(400).toList();
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _preparing = false;
          _loading = false;
        });
      }
    }
  }

  Future<List<int>> _allBodies() async {
    final db = ref.read(databaseProvider);
    final person = widget.personId;
    final rows = await db
        .customSelect(
          '''SELECT b.id FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
             WHERE b.kind = 'person' AND b.hidden = 0 ${person == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}
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
          "SELECT MIN(id) AS id FROM bodies WHERE kind = 'person' AND hidden = 0 AND frame_number IS NULL AND media_id IN (${photos.take(400).join(',')}) GROUP BY media_id ORDER BY media_id DESC",
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
    PoseTag.bent => l.discoveryBent,
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
    // Keep destination tabs stable while their data prepares.
    final areas = widget.personId == null;
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
                onChooseExample: () {
                  _filter();
                  DefaultTabController.of(tabContext).animateTo(0);
                },
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
                onChooseExample: () {
                  _filter();
                  DefaultTabController.of(tabContext).animateTo(0);
                },
                personId: widget.personId,
              ),
              GroupPosesTab(personId: widget.personId),
              EquipmentTab(personId: widget.personId),
              if (areas)
                if (!_clustersOn)
                  EmptyState(
                    icon: Icons.highlight_alt,
                    title: l.bodiesTabAreas,
                    body: l.discoveryAreaPrecision,
                    actionLabel: l.clustersToggle,
                    onAction: _preparing || _loading ? null : _toggleClusters,
                  )
                else
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
    if (_failed) {
      return EmptyState(
        icon: Icons.refresh,
        title: l.bodiesLoadFailed,
        actionLabel: l.bodiesRetry,
        onAction: _prepare,
      );
    }
    final reference = _similarTo ?? _colourTwinOf;
    final filtered =
        reference != null ||
        _tag != null ||
        _color != null ||
        _groupTag != null;
    return RefreshIndicator(
      onRefresh: _prepare,
      child: CustomScrollView(
        key: const PageStorageKey('body-results'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_preparing || _loading) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: DiscoveryIntro(
                    title: reference == null
                        ? l.bodiesTabAll
                        : l.discoveryCompare,
                    description: reference == null
                        ? l.discoveryAllIntro
                        : _exposedKind != null
                        ? l.discoveryAreaPrecision
                        : _colourTwinOf != null
                        ? l.discoveryOutfitIntro
                        : l.discoveryPosePrecision,
                    icon: reference == null
                        ? Icons.photo_library_outlined
                        : Icons.compare_outlined,
                    count: _loading ? null : _ids.length,
                  ),
                ),
                if (reference != null || _groupTag != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
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
                  ),
                if (reference != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          height: 88,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CropImage(
                              path: _rows[reference]?.cropPath,
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
                                l.discoveryCompareHint,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ExpansionTile(
                  key: const Key('bodies-filters'),
                  initiallyExpanded: reference == null,
                  title: Text(l.discoveryBrowse),
                  leading: const Icon(Icons.tune),
                  children: [
                    _filterRow([
                      if (widget.personId == null)
                        for (final tag in GroupTag.all)
                          if ((_groupCounts[tag] ?? 0) > 0)
                            FilterChip(
                              key: Key('group-chip-$tag'),
                              label: Text(
                                '${_groupLabel(l, tag)} · ${_groupCounts[tag]}',
                              ),
                              selected: _groupTag == tag,
                              onSelected: (on) =>
                                  _filter(group: on ? tag : null),
                            ),
                      for (final tag in PoseTag.all)
                        if ((_counts[tag] ?? 0) > 0)
                          FilterChip(
                            key: Key('pose-chip-$tag'),
                            label: Text(
                              '${_tagLabel(l, tag)} · ${_counts[tag]}',
                            ),
                            selected: _tag == tag,
                            onSelected: (on) => _filter(tag: on ? tag : null),
                          ),
                    ]),
                    _filterRow([
                      for (final color in OutfitColor.values)
                        FilterChip(
                          key: Key('color-chip-${color.name}'),
                          label: Text(_colorLabel(l, color)),
                          selected: _color == color,
                          onSelected: (on) => _filter(color: on ? color : null),
                        ),
                    ]),
                  ],
                ),
                if (filtered && reference == null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => _filter(),
                      icon: const Icon(Icons.close),
                      label: Text(l.bodiesClearFilter),
                    ),
                  ),
              ],
            ),
          ),
          if (_ids.isEmpty && !_loading && !_preparing)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.accessibility_new,
                title: filtered ? l.bodiesNothingMatches : l.bodiesEmpty,
              ),
            )
          else
            _grid(
              _ids,
              (id) => reference == null ? _openActions(id) : _compare(id),
            ),
        ],
      ),
    );
  }

  Widget _filterRow(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        for (final child in children)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: child,
          ),
      ],
    ),
  );

  Widget _grid(List<int> ids, void Function(int id) onTap) => SliverPadding(
    padding: const EdgeInsets.all(12),
    sliver: SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: _matches.isEmpty ? .68 : .58,
      ),
      itemCount: ids.length,
      itemBuilder: (context, i) {
        final id = ids[i];
        final score = _matches[id];
        return Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: Key('body-$id'),
            onTap: () => onTap(id),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CropImage(
                    path: _rows[id]?.cropPath,
                    fit: BoxFit.contain,
                    expandable: false,
                    placeholderIcon: Icons.accessibility_new,
                    cacheWidth: 384,
                  ),
                ),
                if (score != null)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      AppLocalizations.of(
                        context,
                      ).discoverySimilarity((score.similarity * 100).round()),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Future<void> _compare(int id) async {
    final l = AppLocalizations.of(context);
    final score = _matches[id];
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BodyComparisonSheet(
        referenceId: (_similarTo ?? _colourTwinOf)!,
        candidateId: id,
        showPose: _colourTwinOf == null,
        title: _colourTwinOf != null
            ? l.bodiesSimilarColoursTitle
            : _exposedKind != null
            ? l.bodiesTabAreas
            : l.bodiesSimilarTitle,
        similarity: score?.similarity,
        coverage: score?.coverage,
        area: _exposedKind?.name,
      ),
    );
    if (action == 'inspect' && mounted) await _openActions(id);
  }

  Future<void> _openActions(int bodyId) async {
    final mediaId = _rows[bodyId]?.mediaId;
    final exposedKinds = await ref.read(exposedMatcherProvider).kindsOf(bodyId);
    final db = ref.read(databaseProvider);
    final bodyRow = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(bodyId))).getSingleOrNull();
    final poseRow = await (db.select(
      db.bodyPoseFeatures,
    )..where((x) => x.bodyId.equals(bodyId))).getSingleOrNull();
    final mediaRow = await (db.select(
      db.media,
    )..where((m) => m.id.equals(mediaId ?? -1))).getSingleOrNull();
    final tags = poseRow == null ? const <String>[] : decodeTags(poseRow.tags);
    final bbox = bodyRow == null
        ? null
        : (
            x: bodyRow.bboxX,
            y: bodyRow.bboxY,
            w: bodyRow.bboxW,
            h: bodyRow.bboxH,
          );

    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BodyInspectionSheet(
        bodyId: bodyId,
        mediaId: mediaId,
        cropPath: _rows[bodyId]?.cropPath,
        kpts: bodyRow?.kpts,
        bbox: bbox,
        imageSize: mediaRow?.width == null || mediaRow?.height == null
            ? null
            : Size(mediaRow!.width!.toDouble(), mediaRow.height!.toDouble()),
        tags: tags,
        exposedAreas: [for (final k in exposedKinds) k.name],
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
    this.onChooseExample,
  });
  final Map<String, int> counts;
  final void Function(String)? onTag;
  final VoidCallback? onChooseExample;

  final bool pose;
  final int? personId;

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList>
    with AutomaticKeepAliveClientMixin {
  String _search = '';
  @override
  bool get wantKeepAlive => true;
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
    super.build(context);
    final l = AppLocalizations.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      key: PageStorageKey(widget.pose ? 'saved-poses' : 'saved-outfits'),
      padding: const EdgeInsets.all(16),
      children: [
        DiscoveryIntro(
          title: widget.pose ? l.bodiesTabPoses : l.bodiesTabOutfits,
          description: widget.pose
              ? l.discoveryPoseIntro
              : l.discoveryOutfitIntro,
          icon: widget.pose
              ? Icons.accessibility_new
              : Icons.checkroom_outlined,
          count: _items.isEmpty ? null : _items.length,
        ),
        if (_items.isNotEmpty)
          DiscoverySearch(
            key: ValueKey('saved-search-${widget.pose}'),
            hint: l.discoverySearchSaved,
            onChanged: (value) => setState(() => _search = value),
          ),
        if (_search.isNotEmpty &&
            !_items.any((item) => item.name.toLowerCase().contains(_search)))
          Text(l.discoveryNoSearch),

        if (_items.isNotEmpty && widget.pose)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l.poseSavedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        for (final item in _items.where(
          (item) => item.name.toLowerCase().contains(_search),
        ))
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
            trailing: IconButton(
              key: Key('rename-${widget.pose ? 'pose' : 'outfit'}-${item.id}'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename',
              onPressed: () async {
                final newName = await promptRenameDialog(
                  context,
                  title: widget.pose ? 'Rename Pose' : 'Rename Outfit',
                  initialName: item.name,
                );
                if (newName == null || !context.mounted) return;
                final db = ref.read(databaseProvider);
                if (widget.pose) {
                  await renamePoseCategory(db, item.id, newName);
                } else {
                  await renameOutfitCategory(db, item.id, newName);
                }
                await _load();
              },
            ),
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
        if (widget.onChooseExample != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: FilledButton.tonalIcon(
              key: Key('choose-${widget.pose ? 'pose' : 'outfit'}-example'),
              onPressed: widget.onChooseExample,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l.groupPoseChooseExample),
            ),
          ),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CropImage(
                    path: _rows[id]?.cropPath,
                    expandable: false,
                    placeholderIcon: Icons.accessibility_new,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    key: Key('category-remove-$id'),
                    tooltip: l.discoveryRemoveMatch,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () async {
                      if (widget.pose) {
                        await categories.setPoseState(
                          widget.id,
                          id,
                          'rejected',
                        );
                      } else {
                        await categories.setOutfitState(
                          widget.id,
                          id,
                          'rejected',
                        );
                      }
                      await _load();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
