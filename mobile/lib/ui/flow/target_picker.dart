import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../data/media/media_library.dart';
import '../../data/repositories/media_queries.dart';
import '../pickers/media_picker.dart';

/// Flow component: reusable target picker (media + face/body detection selection).
class TargetPicker extends StatelessWidget {
  const TargetPicker({
    super.key,
    this.media,
    this.selectedDetectionId,
    this.availableDetections = const [],
    required this.onAssetSelected,
    this.onDetectionSelected,
    this.allowVideo = true,
  });

  final MediaRow? media;
  final int? selectedDetectionId;
  final List<MediaDetection> availableDetections;
  final void Function(AssetInfo asset) onAssetSelected;
  final void Function(int detectionId)? onDetectionSelected;
  final bool allowVideo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (media == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: FilledButton.tonalIcon(
            key: const Key('flow-target-pick'),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Select Target Media'),
            onPressed: () async {
              final chosen = await MediaPicker.pick(
                context,
                multiple: false,
                kind: allowVideo ? null : 'photo',
              );
              if (chosen != null && chosen.isNotEmpty) {
                onAssetSelected(chosen.first);
              }
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            media!.kind == 'video' ? Icons.videocam : Icons.photo,
            color: scheme.primary,
          ),
          title: Text(media!.kind == 'video' ? 'Target Video' : 'Target Photo'),
          subtitle: Text('ID #${media!.id} · ${media!.assetId}'),
          trailing: TextButton(
            key: const Key('flow-target-change'),
            onPressed: () async {
              final chosen = await MediaPicker.pick(
                context,
                multiple: false,
                kind: allowVideo ? null : 'photo',
              );
              if (chosen != null && chosen.isNotEmpty) {
                onAssetSelected(chosen.first);
              }
            },
            child: const Text('Change'),
          ),
        ),
        if (availableDetections.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Select Target:',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in availableDetections)
                ChoiceChip(
                  key: Key('target-detection-${d.id}'),
                  label: Text(
                    d.isFace ? 'Face #${d.refId}' : 'Body #${d.refId}',
                  ),
                  selected: selectedDetectionId == d.id,
                  onSelected: (selected) {
                    if (selected && onDetectionSelected != null) {
                      onDetectionSelected!(d.id);
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
