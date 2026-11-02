import 'dart:io';
import 'package:flutter/material.dart';

import '../../features/shared/image_preview.dart';
import 'crop.dart';

class ThumbView extends StatelessWidget {
  const ThumbView({
    super.key,
    this.filePath,
    this.memoryBytes,
    this.isVideo = false,
    this.durationLabel,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.showExpandButton = false,
  });

  final String? filePath;
  final List<int>? memoryBytes;
  final bool isVideo;
  final String? durationLabel;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool showExpandButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget image;

    if (memoryBytes != null && memoryBytes!.isNotEmpty) {
      image = Image.memory(
        memoryBytes as dynamic,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(theme),
      );
    } else if (filePath != null && filePath!.isNotEmpty) {
      image = Image.file(
        File(filePath!),
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _placeholder(theme),
      );
    } else {
      image = _placeholder(theme);
    }

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (isVideo) ...[
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow, size: 12, color: Colors.white),
                  if (durationLabel != null) ...[
                    const SizedBox(width: 2),
                    Text(
                      durationLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (showExpandButton && filePath != null) ...[
          Positioned(
            right: 4,
            bottom: 4,
            child: ExpandButton(
              source: ImagePreviewSource.file(File(filePath!)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          isVideo ? Icons.movie_outlined : Icons.photo_outlined,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
