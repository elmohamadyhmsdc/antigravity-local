import 'package:flutter/material.dart';

import '../../features/shared/crop_image.dart';

class AvatarView extends StatelessWidget {
  const AvatarView({
    super.key,
    required this.cropPath,
    this.radius = 28,
    this.name,
    this.expandable = false,
  });

  final String? cropPath;
  final double radius;
  final String? name;
  final bool expandable;

  @override
  Widget build(BuildContext context) {
    if (cropPath != null && cropPath!.isNotEmpty) {
      return PersonAvatar(
        cropPath: cropPath,
        radius: radius,
        expandable: expandable,
      );
    }

    final theme = Theme.of(context);
    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : '?';

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Text(
        initial,
        style: TextStyle(fontSize: radius * 0.9, fontWeight: FontWeight.bold),
      ),
    );
  }
}
