import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import '../shared/empty_state.dart';
import '../shared/person_picker.dart';
import 'body_naming.dart';
import 'pose_visuals.dart';
import '../../domain/pose/exposed_matching.dart';

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
    if (!mounted) return;
    setState(() {
      _clusters = clusters;
      _bridges = bridges;
      _tiles = tiles;
      _people = people;
      _loaded = true;
    });
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
                  Text(
                    entry.cluster.clusterType == 'buttocks'
                        ? l.clusterTitleButtocks(entry.cluster.id)
                        : l.clusterTitleChest(entry.cluster.id),
                    style: Theme.of(context).textTheme.titleMedium,
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
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CropImage(
                                  path: _tiles[id]?.cropPath,
                                  placeholderIcon: Icons.accessibility_new,
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
                    Text(
                      l.clusterBelongsTo(
                        _people[entry.cluster.personId] ??
                            '#${entry.cluster.personId}',
                      ),
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
