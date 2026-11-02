import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router.dart';
import '../../providers.dart';
import '../../ui/scaffolds/tab_root_scaffold.dart';
import '../bodies/pose_visuals.dart';
import '../library/scan_invite_strip.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import '../video_actions/video_actions_screen.dart';

final _exploreCropsProvider = StreamProvider.autoDispose<List<String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT crop_path FROM bodies WHERE crop_path IS NOT NULL AND kind = 'person' ORDER BY id DESC LIMIT 6",
        readsFrom: {db.bodies},
      )
      .watch()
      .map((rows) => [for (final row in rows) row.read<String>('crop_path')]);
});

final _exploreCountsProvider = FutureProvider.autoDispose<Map<String, int>>((
  ref,
) async {
  final db = ref.watch(databaseProvider);
  final bodyCount =
      (await db
              .customSelect(
                "SELECT COUNT(*) AS c FROM bodies WHERE (ownership IS NULL OR ownership != 'none') AND (hidden IS NULL OR hidden = 0)",
                readsFrom: {db.bodies},
              )
              .getSingle())
          .read<int>('c');

  final marksCount =
      (await db
              .customSelect(
                'SELECT COUNT(*) AS c FROM body_marks',
                readsFrom: {db.bodyMarks},
              )
              .getSingle())
          .read<int>('c');

  final equipmentCount =
      (await db
              .customSelect(
                'SELECT COUNT(*) AS c FROM equipment_objects',
                readsFrom: {db.equipmentObjects},
              )
              .getSingle())
          .read<int>('c');

  return {
    'bodies': bodyCount,
    'marks': marksCount,
    'equipment': equipmentCount,
  };
});

/// E1 / P7 — ExploreScreen: Hub for visual feature browsing
/// 3 main sections: Bodies, Objects, Motion.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crops = ref.watch(_exploreCropsProvider).value ?? const <String>[];
    final counts = ref.watch(_exploreCountsProvider).value ?? const {};
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TabRootScaffold(
      title: const Text('Explore'),
      body: CustomScrollView(
        slivers: [
          if (crops.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: ScanInviteStrip(),
              ),
            ),

          // Section 1: Bodies
          _buildSectionHeader('Bodies', Icons.accessibility_new, scheme),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid.count(
              crossAxisCount: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1
                  : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1.35
                  : 1.12,
              children: [
                _ExploreCard(
                  title: 'All bodies',
                  subtitle: 'Browse analyzed body crops',
                  count: counts['bodies'],
                  icon: Icons.photo_library_outlined,
                  cropPath: crops.isNotEmpty ? crops.first : null,
                  onTap: () => context.push(Routes.bodies),
                ),
                _ExploreCard(
                  title: 'Poses',
                  subtitle: 'Browse body positions',
                  icon: Icons.accessibility_new,
                  cropPath: crops.length > 1 ? crops[1] : null,
                  onTap: () => context.push('${Routes.explore}/poses'),
                ),
                _ExploreCard(
                  title: 'Outfits & colours',
                  subtitle: 'Find similar clothing',
                  icon: Icons.checkroom_outlined,
                  cropPath: crops.length > 2 ? crops[2] : null,
                  onTap: () => context.push('${Routes.explore}/outfits'),
                ),
                _ExploreCard(
                  title: 'Group poses',
                  subtitle: 'Explore people together',
                  icon: Icons.groups_outlined,
                  cropPath: crops.length > 3 ? crops[3] : null,
                  onTap: () => context.push('${Routes.explore}/groupPoses'),
                ),
                _ExploreCard(
                  title: 'Areas',
                  subtitle: 'Exposed region clusters',
                  icon: Icons.bubble_chart_outlined,
                  cropPath: crops.length > 4 ? crops[4] : null,
                  onTap: () => context.push('${Routes.explore}/areas'),
                ),
                _ExploreCard(
                  title: 'Marks',
                  subtitle: 'Browse saved marks by person',
                  count: counts['marks'],
                  icon: Icons.draw_outlined,
                  cropPath: crops.length > 5 ? crops[5] : null,
                  onTap: () async {
                    final person = await pickPerson(
                      context,
                      allowNew: false,
                      kind: 'all',
                    );
                    if (person?.personId != null && context.mounted) {
                      context.push(
                        '${Routes.marks}?personId=${person!.personId}',
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          // Section 2: Objects
          _buildSectionHeader('Objects', Icons.sports_tennis_outlined, scheme),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid.count(
              crossAxisCount: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1
                  : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1.35
                  : 1.12,
              children: [
                _ExploreCard(
                  title: 'Equipment',
                  subtitle: 'Browse detected objects',
                  count: counts['equipment'],
                  icon: Icons.sports_tennis_outlined,
                  onTap: () => context.push('${Routes.explore}/equipment'),
                ),
              ],
            ),
          ),

          // Section 3: Motion
          _buildSectionHeader(
            'Motion',
            Icons.motion_photos_on_outlined,
            scheme,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverGrid.count(
              crossAxisCount: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1
                  : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 22
                  ? 1.35
                  : 1.12,
              children: [
                _ExploreCard(
                  title: 'Actions',
                  subtitle: 'Find activities from your examples',
                  icon: Icons.motion_photos_on_outlined,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const VideoActionsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme scheme) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.cropPath,
    this.count,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String? cropPath;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: cropPath != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CropImage(path: cropPath, fit: BoxFit.cover),
                        )
                      : title == 'Group poses'
                      ? const SizedBox(
                          width: 100,
                          child: Row(
                            children: [
                              Expanded(child: PoseDiagram(tag: 'standing')),
                              Expanded(child: PoseDiagram(tag: 'standing')),
                            ],
                          ),
                        )
                      : title == 'Poses' || title == 'All bodies'
                      ? const SizedBox(
                          width: 70,
                          child: PoseDiagram(tag: 'standing'),
                        )
                      : Icon(icon, size: 42, color: scheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (count != null && count! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
