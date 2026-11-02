import 'package:flutter/material.dart';

import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';

/// L3a / P5c — VideoTrackStrip: Timeline strip above the video scrubber
/// indicating detection appearances, tracks, and jumping directly to timestamp.
class VideoTrackStrip extends StatelessWidget {
  const VideoTrackStrip({
    super.key,
    required this.durationMs,
    required this.currentPositionMs,
    required this.detections,
    this.people = const {},
    this.selectedDetectionId,
    this.onSeek,
    this.onSelect,
  });

  final int durationMs;
  final int currentPositionMs;
  final List<MediaDetection> detections;
  final Map<int, PersonSummary> people;
  final int? selectedDetectionId;
  final ValueChanged<int>? onSeek;
  final ValueChanged<MediaDetection>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (durationMs <= 0 || detections.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final timedDetections =
        detections
            .where((d) => d.timestampMs != null && d.timestampMs! >= 0)
            .toList()
          ..sort((a, b) => a.timestampMs!.compareTo(b.timestampMs!));

    if (timedDetections.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('video-track-strip'),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final progress = (currentPositionMs / durationMs).clamp(0.0, 1.0);
          final playheadX = progress * constraints.maxWidth;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Background track
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Playhead position marker
              Positioned(
                left: (playheadX - 2).clamp(0.0, constraints.maxWidth - 4),
                top: 8,
                bottom: 8,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Detection markers
              for (final d in timedDetections)
                Builder(
                  builder: (context) {
                    final frac = (d.timestampMs! / durationMs).clamp(0.0, 1.0);
                    final x = frac * constraints.maxWidth;
                    final isSelected = d.id == selectedDetectionId;
                    final person = d.personId != null
                        ? people[d.personId]
                        : null;

                    Color markerColor = theme.colorScheme.tertiary;
                    if (person != null) {
                      markerColor = theme.colorScheme.primary;
                    } else if (d.isFace) {
                      markerColor = theme.colorScheme.secondary;
                    }

                    return Positioned(
                      left: (x - 8).clamp(0.0, constraints.maxWidth - 16),
                      top: 4,
                      child: GestureDetector(
                        key: Key('track-marker-${d.id}'),
                        onTap: () {
                          if (d.timestampMs != null) {
                            onSeek?.call(d.timestampMs!);
                          }
                          onSelect?.call(d);
                        },
                        child: Tooltip(
                          message:
                              person?.name ??
                              '${d.isFace ? "Face" : "Body"} @ ${(d.timestampMs! / 1000).toStringAsFixed(1)}s',
                          child: Container(
                            width: isSelected ? 16 : 12,
                            height: isSelected ? 16 : 12,
                            decoration: BoxDecoration(
                              color: markerColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black26,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: markerColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        blurRadius: 6,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
