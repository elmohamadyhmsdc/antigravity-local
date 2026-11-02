import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'body_inspection_sheet.dart';
import 'body_naming.dart';
import 'pose_visuals.dart';
import '../../domain/pose/exposed_matching.dart';
import '../../domain/pose/pose_index.dart' show decodeTags;

/// Roadmap 7.5 / Phase 8, behind `body_clusters_enabled` (OFF until the user switches it on): groups of
/// photos showing the same body area, given to a person with one tap, and bridge photos offered as a
/// suggestion for the OTHER group (never applied by themselves).
class BodyAreasTab extends ConsumerStatefulWidget {
  const BodyAreasTab({super.key, this.onSimilar});
  final void Function(int bodyId, ExposedKind kind)? onSimilar;

  @override
  ConsumerState<BodyAreasTab> createState() => _BodyAreasTabState();
}

class _BodyAreasTabState extends ConsumerState<BodyAreasTab> {
  List<({BodyClusterRow cluster, List<int> bodyIds})> _clusters = const [];
  List<({int fromCluster, int toCluster, int bridges})> _bridges = const [];
  Map<int, BodyTile> _tiles = const {};
  Map<int, String> _people = const {};
  Map<int, String> _customNames = const {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(exposedClustersProvider);
    final clusters = await service.clusters();
    final bridges = await service.bridgeSuggestions();
    final preview = <int>[for (final c in clusters) ...c.bodyIds.take(6)];
    final tiles = await fetchBodyTiles(ref, preview);
    final db = ref.read(databaseProvider);
    final people = <int, String>{
      for (final p in await db.select(db.persons).get())
        p.id: p.name ?? '#${p.id}',
    };
    final customNames = <int, String>{};
    for (final c in clusters) {
      final name = await db.setting('cluster.name.${c.cluster.id}');
      if (name != null && name.trim().isNotEmpty) {
        customNames[c.cluster.id] = name.trim();
      }
    }
    if (!mounted) return;
    setState(() {
      _clusters = clusters;
      _bridges = bridges;
      _tiles = tiles;
      _people = people;
      _customNames = customNames;
      _loaded = true;
    });
  }

  Future<void> _rename(int clusterId, String currentName) async {
    final newName = await promptRenameDialog(
      context,
      title: 'Rename Area',
      initialName: currentName,
      labelText: 'Custom Area Name',
    );
    if (newName == null || !mounted) return;
    final db = ref.read(databaseProvider);
    await db.putSetting('cluster.name.$clusterId', newName.trim());
    await _load();
  }

  Future<void> _assign(int clusterId, {int? personId}) async {
    var target = personId;
    if (target == null) {
      final choice = await pickPerson(context, allowNew: false);
      target = choice?.personId;
    }
    if (target == null || !mounted) return;
    await ref.read(exposedClustersProvider).assign(clusterId, target);
    await _load();
  }

  Future<void> _inspectBody(int bodyId, String clusterType) async {
    final db = ref.read(databaseProvider);
    final bodyRow = await (db.select(
      db.bodies,
    )..where((b) => b.id.equals(bodyId))).getSingleOrNull();
    final poseRow = await (db.select(
      db.bodyPoseFeatures,
    )..where((x) => x.bodyId.equals(bodyId))).getSingleOrNull();
    final tags = poseRow == null ? const <String>[] : decodeTags(poseRow.tags);
    final bbox = bodyRow == null
        ? null
        : (
            x: bodyRow.bboxX,
            y: bodyRow.bboxY,
            w: bodyRow.bboxW,
            h: bodyRow.bboxH,
          );
    final areaKind = clusterType == 'buttocks' ? 'lower' : 'chest';

    if (!mounted) return;
    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => BodyInspectionSheet(
        bodyId: bodyId,
        cropPath: _tiles[bodyId]?.cropPath,
        kpts: bodyRow?.kpts,
        bbox: bbox,
        tags: tags,
        exposedAreas: [areaKind],
        mediaId: bodyRow?.mediaId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_clusters.isEmpty) {
      return EmptyState(icon: Icons.workspaces_outline, title: l.clustersEmpty);
    }
    final personOf = {
      for (final c in _clusters) c.cluster.id: c.cluster.personId,
    };
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (_bridges.isNotEmpty)
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    l.clusterBridgeTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final b in _bridges)
                  ListTile(
                    key: Key('bridge-${b.fromCluster}-${b.toCluster}'),
                    title: Text(l.clusterBridgeAction(b.toCluster, b.bridges)),
                    trailing: const Icon(Icons.check),
                    onTap: () =>
                        _assign(b.toCluster, personId: personOf[b.fromCluster]),
                  ),
              ],
            ),
          ),
        for (final entry in _clusters)
          Card(
            key: Key('cluster-${entry.cluster.id}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 96,
                    width: 72,
                    child: PoseDiagram(
                      area: entry.cluster.clusterType == 'buttocks'
                          ? 'lower'
                          : 'chest',
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _customNames[entry.cluster.id] ??
                              (entry.cluster.clusterType == 'buttocks'
                                  ? l.clusterTitleButtocks(entry.cluster.id)
                                  : l.clusterTitleChest(entry.cluster.id)),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: Key('rename-cluster-${entry.cluster.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Rename Area',
                        onPressed: () => _rename(
                          entry.cluster.id,
                          _customNames[entry.cluster.id] ??
                              (entry.cluster.clusterType == 'buttocks'
                                  ? l.clusterTitleButtocks(entry.cluster.id)
                                  : l.clusterTitleChest(entry.cluster.id)),
                        ),
                      ),
                    ],
                  ),
                  Text(l.categoryBodyCount(entry.bodyIds.length)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final id in entry.bodyIds.take(6))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: SizedBox(
                              width: 60,
                              child: InkWell(
                                key: Key('cluster-body-$id'),
                                borderRadius: BorderRadius.circular(6),
                                onTap: () =>
                                    _inspectBody(id, entry.cluster.clusterType),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: CropImage(
                                    path: _tiles[id]?.cropPath,
                                    placeholderIcon: Icons.accessibility_new,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (entry.bodyIds.isNotEmpty)
                    TextButton.icon(
                      key: Key('cluster-similar-${entry.cluster.id}'),
                      onPressed: () => widget.onSimilar?.call(
                        entry.bodyIds.first,
                        entry.cluster.clusterType == 'buttocks'
                            ? ExposedKind.buttocks
                            : ExposedKind.chest,
                      ),
                      icon: const Icon(Icons.image_search_outlined),
                      label: Text(
                        entry.cluster.clusterType == 'buttocks'
                            ? l.equipmentAreaLowerSimilar
                            : l.equipmentAreaChestSimilar,
                      ),
                    ),
                  if (entry.cluster.personId != null)
                    Row(
                      children: [
                        Text(
                          l.clusterBelongsTo(
                            _people[entry.cluster.personId] ??
                                '#${entry.cluster.personId}',
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.swap_horiz, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Change person',
                          onPressed: () => _assign(entry.cluster.id),
                        ),
                      ],
                    )
                  else
                    FilledButton.tonal(
                      key: Key('cluster-assign-${entry.cluster.id}'),
                      onPressed: () => _assign(entry.cluster.id),
                      child: Text(l.clusterAssign),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
