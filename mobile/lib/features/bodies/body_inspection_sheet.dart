import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'pose_visuals.dart';

/// Interactive modal sheet to inspect a body's pose skeleton, active areas, and launch actions.
class BodyInspectionSheet extends StatefulWidget {
  const BodyInspectionSheet({
    super.key,
    required this.bodyId,
    this.mediaId,
    this.cropPath,
    this.kpts,
    this.bbox,
    this.tags = const [],
    this.exposedAreas = const [],
  });

  final int bodyId;
  final int? mediaId;
  final String? cropPath;
  final String? kpts;
  final ({double x, double y, double w, double h})? bbox;
  final List<String> tags;
  final List<String> exposedAreas;

  @override
  State<BodyInspectionSheet> createState() => _BodyInspectionSheetState();
}

class _BodyInspectionSheetState extends State<BodyInspectionSheet> {
  bool _showSkeleton = false;
  bool _showArea = false;
  late final String _selectedArea = widget.exposedAreas.firstOrNull ?? 'chest';

  String _formatTag(AppLocalizations l, String tag) {
    return switch (tag.toLowerCase()) {
      'standing' => l.poseTagStanding,
      'sitting' => l.poseTagSitting,
      'lying' => l.poseTagLying,
      'bent' => 'Bent',
      'frontal' => l.poseTagFrontal,
      'profile' => l.poseTagProfile,
      'back' => l.poseTagBack,
      'arms_up' => l.poseTagArmsUp,
      'one_arm_up' => l.poseTagOneArmUp,
      'arms_spread' => l.poseTagArmsSpread,
      'hands_on_hips' => l.poseTagHandsOnHips,
      _ => tag,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ConstrainedBox(
        key: const Key('body-inspection-sheet'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Drag Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 2. Inspection Preview Box
              Center(
                child: Container(
                  width: 140,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: scheme.surfaceContainerHighest,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: BodyCropAnnotatedView(
                    cropPath: widget.cropPath,
                    kpts: widget.kpts,
                    bbox: widget.bbox,
                    showSkeleton: _showSkeleton,
                    showArea: _showArea,
                    area: _selectedArea,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 3. Inspection Toggles Row
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilterChip(
                    key: const Key('toggle-skeleton-btn'),
                    selected: _showSkeleton,
                    label: const Text('Skeleton'),
                    avatar: const Icon(Icons.accessibility_new, size: 18),
                    onSelected: (val) => setState(() => _showSkeleton = val),
                  ),
                  FilterChip(
                    key: const Key('toggle-area-btn'),
                    selected: _showArea,
                    label: const Text('Area'),
                    avatar: const Icon(Icons.highlight_alt, size: 18),
                    onSelected: (val) => setState(() => _showArea = val),
                  ),
                ],
              ),

              // 4. Detected Tags / Badges
              if (widget.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final tag in widget.tags)
                      Chip(
                        label: Text(
                          _formatTag(l, tag),
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: scheme.secondaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                  ],
                ),
              ],

              const SizedBox(height: 8),
              const Divider(),

              // 5. Actions List
              if (widget.mediaId != null) ...[
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
              for (final kind in widget.exposedAreas)
                ListTile(
                  key: Key('action-similar-$kind'),
                  leading: const Icon(Icons.image_search_outlined),
                  title: Text(
                    kind == 'chest'
                        ? l.equipmentAreaChestSimilar
                        : l.equipmentAreaLowerSimilar,
                  ),
                  subtitle: Text(
                    kind == 'chest'
                        ? l.equipmentAreaChest
                        : l.equipmentAreaLower,
                  ),
                  onTap: () => Navigator.pop(context, 'exposed-$kind'),
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
                key: const Key('action-name-outfit'),
                leading: const Icon(Icons.checkroom_outlined),
                title: Text(l.bodyActionNameOutfit),
                onTap: () => Navigator.pop(context, 'outfit'),
              ),
              ListTile(
                key: const Key('action-mark-tattoo'),
                leading: const Icon(Icons.draw_outlined),
                title: Text(l.bodyActionMarkTattoo),
                onTap: () => Navigator.pop(context, 'mark'),
              ),
              if (widget.mediaId != null)
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
    );
  }
}
