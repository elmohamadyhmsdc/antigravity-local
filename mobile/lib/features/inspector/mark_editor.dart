import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../marks/mark_tattoo.dart' show segmentLabel;
import '../shared/crop_image.dart';

class MarkChoice {
  const MarkChoice(this.segment, this.fx, this.fy, this.size);
  final String segment;
  final double fx, fy; // fraction of picture dimensions
  final double size; // fraction of picture width
}

/// L3a / P5c — MarkEditorSheet: Interactive sheet for positioning and sizing a tattoo/mark patch.
class MarkEditorSheet extends StatefulWidget {
  const MarkEditorSheet({
    super.key,
    required this.segments,
    required this.cropPath,
  });

  final List<String> segments;
  final String? cropPath;

  static Future<MarkChoice?> show({
    required BuildContext context,
    required List<String> segments,
    required String? cropPath,
  }) {
    return showModalBottomSheet<MarkChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MarkEditorSheet(segments: segments, cropPath: cropPath),
    );
  }

  @override
  State<MarkEditorSheet> createState() => _MarkEditorSheetState();
}

class _MarkEditorSheetState extends State<MarkEditorSheet> {
  late String _segment = widget.segments.first;
  Offset? _tap;
  double _size = 0.2;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.markTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(l.markPickSegment, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              DropdownButton<String>(
                key: const Key('mark-segment'),
                isExpanded: true,
                value: _segment,
                items: [
                  for (final s in widget.segments)
                    DropdownMenuItem(value: s, child: Text(segmentLabel(l, s))),
                ],
                onChanged: (v) => setState(() => _segment = v ?? _segment),
              ),
              const SizedBox(height: 12),
              Text(l.markTapToPlace, style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 0.75,
                child: LayoutBuilder(
                  builder: (context, c) => GestureDetector(
                    key: const Key('mark-picture'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => setState(
                      () => _tap = Offset(
                        (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0),
                        (d.localPosition.dy / c.maxHeight).clamp(0.0, 1.0),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CropImage(
                            path: widget.cropPath,
                            placeholderIcon: Icons.accessibility_new,
                            fit: BoxFit.contain,
                            cacheWidth: 512,
                          ),
                        ),
                        if (_tap != null)
                          Positioned(
                            left:
                                _tap!.dx * c.maxWidth - _size * c.maxWidth / 2,
                            top:
                                _tap!.dy * c.maxHeight - _size * c.maxWidth / 2,
                            width: _size * c.maxWidth,
                            height: _size * c.maxWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.redAccent,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(l.markSize),
                  Expanded(
                    child: Slider(
                      key: const Key('mark-size'),
                      min: 0.08,
                      max: 0.6,
                      value: _size,
                      onChanged: (v) => setState(() => _size = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      MaterialLocalizations.of(context).cancelButtonLabel,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('mark-save'),
                    onPressed: _tap == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            MarkChoice(_segment, _tap!.dx, _tap!.dy, _size),
                          ),
                    child: Text(l.markSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
