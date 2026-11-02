import 'package:flutter/material.dart';

import '../../features/shared/crop_image.dart';
import '../../features/shared/image_preview.dart';

class ExpandButton extends StatelessWidget {
  const ExpandButton({super.key, required this.source, this.size = 28});

  final ImagePreviewSource source;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: size * 0.65,
        color: Colors.white,
        tooltip: 'Expand / Lens',
        icon: const Icon(Icons.fullscreen),
        onPressed: () {
          Navigator.of(context).push(
            PageRouteBuilder<void>(
              opaque: false,
              barrierDismissible: true,
              pageBuilder: (context, _, _) =>
                  ImagePreviewScreen(source: source),
            ),
          );
        },
      ),
    );
  }
}

class CropView extends StatelessWidget {
  const CropView({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth = 240,
    this.placeholderIcon = Icons.face_outlined,
    this.showExpandButton = true,
    this.borderRadius,
  });

  final String? path;
  final BoxFit fit;
  final int cacheWidth;
  final IconData placeholderIcon;
  final bool showExpandButton;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget child = CropImage(
      path: path,
      fit: fit,
      cacheWidth: cacheWidth,
      placeholderIcon: placeholderIcon,
      expandable: false, // We handle expansion via explicit corner button
    );

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }

    if (!showExpandButton || path == null || path!.isEmpty) {
      return child;
    }

    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          right: 4,
          bottom: 4,
          child: ExpandButton(source: ImagePreviewSource.crop(path!)),
        ),
      ],
    );
  }
}
