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

final _exploreCountsProvider = StreamProvider.autoDispose<Map<String, int>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        """SELECT
    (SELECT COUNT(*) FROM bodies WHERE kind = 'person' AND hidden = 0) AS bodies,
    (SELECT COUNT(*) FROM body_marks) AS marks,
    (SELECT COUNT(*) FROM equipment_objects WHERE state != 'rejected') AS equipment""",
        readsFrom: {db.bodies, db.bodyMarks, db.equipmentObjects},
      )
      .watchSingle()
      .map(
        (row) => {
          'bodies': row.read<int>('bodies'),
          'marks': row.read<int>('marks'),
          'equipment': row.read<int>('equipment'),
        },
      );
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

    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final bodyItems = [
      (
        'All bodies',
        'Browse analyzed body crops',
        Icons.photo_library_outlined,
        Routes.bodies,
        counts['bodies'],
      ),
      (
        'Poses',
        'Browse body positions',
        Icons.accessibility_new,
        '${Routes.explore}/poses',
        null,
      ),
      (
        'Outfits & colours',
        'Find similar clothing',
        Icons.checkroom_outlined,
        '${Routes.explore}/outfits',
        null,
      ),
      (
        'Group poses',
        'Explore people together',
        Icons.groups_outlined,
        '${Routes.explore}/groupPoses',
        null,
      ),
    ];
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
          _buildSectionHeader(
            'Bodies & clothing',
            Icons.accessibility_new,
            scheme,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: compact
                ? SliverList.list(
                    children: [
                      for (final item in bodyItems)
                        _ExploreRow(
                          title: item.$1,
                          subtitle: item.$2,
                          icon: item.$3,
                          count: item.$5,
                          onTap: () => context.push(item.$4),
                        ),
                    ],
                  )
                : SliverGrid.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.12,
                    children: [
                      for (var i = 0; i < bodyItems.length; i++)
                        _ExploreCard(
                          title: bodyItems[i].$1,
                          subtitle: bodyItems[i].$2,
                          icon: bodyItems[i].$3,
                          count: bodyItems[i].$5,
                          cropPath: i == 0 && crops.isNotEmpty
                              ? crops.first
                              : null,
                          onTap: () => context.push(bodyItems[i].$4),
                        ),
                    ],
                  ),
          ),
          _buildSectionHeader(
            'Regions, objects & activities',
            Icons.search,
            scheme,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.list(
              children: [
                _ExploreRow(
                  title: 'Areas',
                  subtitle: 'Compare visible body regions',
                  icon: Icons.highlight_alt,
                  onTap: () => context.push('${Routes.explore}/areas'),
                ),
                _ExploreRow(
                  title: 'Marks',
                  subtitle: 'Browse saved marks by person',
                  count: counts['marks'],
                  icon: Icons.draw_outlined,
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
                _ExploreRow(
                  title: 'Equipment',
                  subtitle: 'Browse detected objects',
                  count: counts['equipment'],
                  icon: Icons.sports_tennis_outlined,
                  onTap: () => context.push('${Routes.explore}/equipment'),
                ),
                _ExploreRow(
                  title: 'Actions',
                  subtitle: 'Find activities from your examples',
                  icon: Icons.motion_photos_on_outlined,
                  onTap: () => context.push('${Routes.explore}/actions'),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
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
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
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
                          child: CropImage(
                            path: cropPath,
                            fit: BoxFit.cover,
                            expandable: false,
                          ),
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
                      : Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, size: 28, color: scheme.primary),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (count != null && count! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
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

class _ExploreRow extends StatelessWidget {
  const _ExploreRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.count,
  });
  final String title, subtitle;
  final IconData icon;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: scheme.primary, size: 22),
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
                if (count != null && count! > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
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
      ),
    );
  }
}
