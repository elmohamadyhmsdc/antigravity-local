import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router.dart';
import '../../providers.dart';
import '../shared/crop_image.dart';
import '../shared/person_picker.dart';
import 'pose_visuals.dart';
import '../video_actions/video_actions_screen.dart';

final _discoverCrops = StreamProvider.autoDispose<List<String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT crop_path FROM bodies WHERE crop_path IS NOT NULL AND kind = 'person' ORDER BY id DESC LIMIT 3",
        readsFrom: {db.bodies},
      )
      .watch()
      .map((rows) => [for (final row in rows) row.read<String>('crop_path')]);
});

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crops = ref.watch(_discoverCrops).value ?? const <String>[];
    final categories = <(String, String, IconData, int)>[
      ('Poses', 'Browse body positions', Icons.accessibility_new, 1),
      (
        'Outfits & colours',
        'Find similar clothing',
        Icons.checkroom_outlined,
        2,
      ),
      ('Group poses', 'Explore people together', Icons.groups_outlined, 3),
      ('Equipment', 'Browse detected objects', Icons.sports_tennis_outlined, 4),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Activity',
            icon: const Icon(Icons.pending_actions_outlined),
            onPressed: () => context.push(Routes.jobs),
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(20),
        crossAxisCount: MediaQuery.textScalerOf(context).scale(14) > 22 ? 1 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: MediaQuery.textScalerOf(context).scale(14) > 22
            ? 1.35
            : 1.12,
        children: [
          for (final item in categories)
            _DiscoverTile(
              title: item.$1,
              subtitle: item.$2,
              icon: item.$3,
              cropPath: item.$4 <= 2 && crops.length >= item.$4
                  ? crops[item.$4 - 1]
                  : null,
              onTap: () => context.push('${Routes.bodies}?tab=${item.$4}'),
            ),
          _DiscoverTile(
            title: 'Actions',
            subtitle: 'Find activities from your examples',
            icon: Icons.motion_photos_on_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const VideoActionsScreen(),
              ),
            ),
          ),
          _DiscoverTile(
            title: 'Marks',
            subtitle: 'Browse saved marks by person',
            icon: Icons.draw_outlined,
            onTap: () async {
              final person = await pickPerson(
                context,
                allowNew: false,
                kind: 'all',
              );
              if (person?.personId != null && context.mounted) {
                context.push('${Routes.marks}?personId=${person!.personId}');
              }
            },
          ),
          _DiscoverTile(
            title: 'All bodies',
            subtitle: 'Browse analyzed body crops',
            icon: Icons.photo_library_outlined,
            cropPath: crops.isEmpty ? null : crops.first,
            onTap: () => context.push(Routes.bodies),
          ),
        ],
      ),
    );
  }
}

class _DiscoverTile extends StatelessWidget {
  const _DiscoverTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.cropPath,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String? cropPath;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
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
                        borderRadius: BorderRadius.circular(8),
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
                    : Icon(icon, size: 42),
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}
