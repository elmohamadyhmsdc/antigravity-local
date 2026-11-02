import 'package:flutter/material.dart';

import '../../ui/scaffolds/sheet_scaffold.dart';

/// Active layer state for the media viewer.
class ViewerLayers {
  const ViewerLayers({
    this.faces = true,
    this.bodies = true,
    this.skeleton = false,
    this.areas = false,
    this.equipment = false,
  });

  final bool faces;
  final bool bodies;
  final bool skeleton;
  final bool areas;
  final bool equipment;

  ViewerLayers copyWith({
    bool? faces,
    bool? bodies,
    bool? skeleton,
    bool? areas,
    bool? equipment,
  }) {
    return ViewerLayers(
      faces: faces ?? this.faces,
      bodies: bodies ?? this.bodies,
      skeleton: skeleton ?? this.skeleton,
      areas: areas ?? this.areas,
      equipment: equipment ?? this.equipment,
    );
  }
}

/// Availability of detections in the current media item.
class LayerAvailability {
  const LayerAvailability({
    this.hasFaces = true,
    this.hasBodies = true,
    this.hasAreas = false,
    this.hasEquipment = false,
  });

  final bool hasFaces;
  final bool hasBodies;
  final bool hasAreas;
  final bool hasEquipment;
}

/// L3 / P5b — Layers popover sheet allowing users to toggle visual annotations.
class LayersPopover extends StatelessWidget {
  const LayersPopover({
    super.key,
    required this.layers,
    required this.availability,
    required this.onChanged,
  });

  final ViewerLayers layers;
  final LayerAvailability availability;
  final ValueChanged<ViewerLayers> onChanged;

  static Future<void> show({
    required BuildContext context,
    required ViewerLayers layers,
    required LayerAvailability availability,
    required ValueChanged<ViewerLayers> onChanged,
  }) {
    var currentLayers = layers;
    return SheetScaffold.show<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SheetScaffold(
            title: 'Detection Layers',
            child: LayersPopover(
              layers: currentLayers,
              availability: availability,
              onChanged: (updated) {
                currentLayers = updated;
                onChanged(updated);
                setSheetState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CheckboxListTile(
          key: const Key('layer-toggle-faces'),
          title: const Text('Faces'),
          subtitle: availability.hasFaces
              ? null
              : const Text('No faces detected in media'),
          value: layers.faces,
          enabled: availability.hasFaces,
          secondary: const Icon(Icons.face_outlined),
          onChanged: availability.hasFaces
              ? (v) => onChanged(layers.copyWith(faces: v ?? false))
              : null,
        ),
        CheckboxListTile(
          key: const Key('layer-toggle-bodies'),
          title: const Text('Bodies'),
          subtitle: availability.hasBodies
              ? null
              : const Text('No bodies detected in media'),
          value: layers.bodies,
          enabled: availability.hasBodies,
          secondary: const Icon(Icons.accessibility_new_outlined),
          onChanged: availability.hasBodies
              ? (v) => onChanged(layers.copyWith(bodies: v ?? false))
              : null,
        ),
        CheckboxListTile(
          key: const Key('layer-toggle-skeleton'),
          title: const Text('Skeleton / Pose'),
          subtitle: availability.hasBodies
              ? null
              : const Text('Requires detected bodies'),
          value: layers.skeleton,
          enabled: availability.hasBodies,
          secondary: const Icon(Icons.linear_scale_outlined),
          onChanged: availability.hasBodies
              ? (v) => onChanged(layers.copyWith(skeleton: v ?? false))
              : null,
        ),
        CheckboxListTile(
          key: const Key('layer-toggle-areas'),
          title: const Text('Areas & Regions'),
          subtitle: availability.hasAreas
              ? null
              : const Text('No areas detected'),
          value: layers.areas,
          enabled: availability.hasAreas,
          secondary: const Icon(Icons.crop_square_outlined),
          onChanged: availability.hasAreas
              ? (v) => onChanged(layers.copyWith(areas: v ?? false))
              : null,
        ),
        CheckboxListTile(
          key: const Key('layer-toggle-equipment'),
          title: const Text('Equipment & Objects'),
          subtitle: availability.hasEquipment
              ? null
              : const Text('No equipment detected'),
          value: layers.equipment,
          enabled: availability.hasEquipment,
          secondary: const Icon(Icons.sports_tennis_outlined),
          onChanged: availability.hasEquipment
              ? (v) => onChanged(layers.copyWith(equipment: v ?? false))
              : null,
        ),
      ],
    );
  }
}
