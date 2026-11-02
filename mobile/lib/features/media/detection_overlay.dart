import 'package:flutter/material.dart';

import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../domain/geometry/outline.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';
import 'layers_popover.dart';

/// L3 / P5b — Detection overlay widget rendering face/body bounding boxes, outlines, and tap handling.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.detections,
    required this.fittedSize,
    required this.layers,
    required this.people,
    required this.onTapDetection,
  });

  final List<MediaDetection> detections;
  final Size fittedSize;
  final ViewerLayers layers;
  final Map<int, PersonSummary> people;
  final ValueChanged<MediaDetection> onTapDetection;

  void _handleTap(BuildContext context, MediaDetection tapped) {
    onTapDetection(tapped);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final visibleDetections = detections.where((d) {
      if (d.isFace && !layers.faces) return false;
      if (!d.isFace && !layers.bodies) return false;
      return true;
    }).toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final d in visibleDetections)
          Positioned(
            left: d.x * fittedSize.width,
            top: d.y * fittedSize.height,
            width: d.w * fittedSize.width,
            height: d.h * fittedSize.height,
            child: GestureDetector(
              key: Key('box-${d.kind}-${d.refId}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleTap(context, d),
              child: CustomPaint(
                painter: DetectionBoxPainter(
                  isFace: d.isFace,
                  outline: d.outline,
                  fillColor: d.isFace
                      ? (d.personId == null
                            ? Colors.amber.withValues(alpha: 0.10)
                            : scheme.primary.withValues(alpha: 0.12))
                      : Colors.lightBlueAccent.withValues(alpha: 0.18),
                  borderColor: d.isFace
                      ? (d.personId == null ? Colors.amber : scheme.primary)
                      : Colors.lightBlueAccent,
                  borderWidth: d.isFace ? 2.5 : 2.0,
                ),
                child:
                    d.personId != null && people[d.personId] != null && d.isFace
                    ? Align(
                        alignment: Alignment.topLeft,
                        child: ColoredBox(
                          color: scheme.primary,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              personName(l10n, people[d.personId]!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.onPrimary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
