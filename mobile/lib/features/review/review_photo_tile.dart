import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../shared/crop_image.dart';

/// Opening a photo and including it in a decision are separate controls.
class ReviewPhotoTile extends StatelessWidget {
  const ReviewPhotoTile({
    super.key,
    required this.photoKey,
    required this.selectionKey,
    required this.cropPath,
    required this.selected,
    required this.onOpen,
    required this.onSelect,
  });
  final Key photoKey, selectionKey;
  final String? cropPath;
  final bool selected;
  final VoidCallback onOpen, onSelect;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 88,
    child: Column(
      children: [
        Expanded(
          child: InkWell(
            key: photoKey,
            onTap: onOpen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CropImage(path: cropPath, cacheWidth: 300),
                ),
                const Positioned(
                  right: 4,
                  bottom: 4,
                  child: Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: Checkbox(
            key: selectionKey,
            value: selected,
            semanticLabel: AppLocalizations.of(context).reviewIncludeFace,
            onChanged: (_) => onSelect(),
          ),
        ),
      ],
    ),
  );
}
