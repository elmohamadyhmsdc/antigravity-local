import 'package:flutter/material.dart';

import '../atoms/avatar.dart';
import '../atoms/crop.dart';
import '../atoms/thumb.dart';

enum EntityCardLayout { grid, row, hero }

enum EntityCardState { normal, selected, disabled, busy }

sealed class EntityCardVisual {
  const EntityCardVisual();
}

class ThumbVisual extends EntityCardVisual {
  const ThumbVisual({
    this.filePath,
    this.memoryBytes,
    this.isVideo = false,
    this.durationLabel,
  });

  final String? filePath;
  final List<int>? memoryBytes;
  final bool isVideo;
  final String? durationLabel;
}

class CropVisual extends EntityCardVisual {
  const CropVisual(this.path, {this.showExpand = true});
  final String? path;
  final bool showExpand;
}

class AvatarVisual extends EntityCardVisual {
  const AvatarVisual({this.cropPath, this.name});
  final String? cropPath;
  final String? name;
}

class CropStackVisual extends EntityCardVisual {
  const CropStackVisual(this.paths);
  final List<String> paths;
}

class IconVisual extends EntityCardVisual {
  const IconVisual(this.icon, {this.color});
  final IconData icon;
  final Color? color;
}

class EntityCard extends StatelessWidget {
  const EntityCard({
    super.key,
    required this.visual,
    this.title,
    this.subtitle,
    this.trailing,
    this.layout = EntityCardLayout.grid,
    this.state = EntityCardState.normal,
    this.onTap,
    this.onLongPress,
    this.badge,
  });

  final EntityCardVisual visual;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EntityCardLayout layout;
  final EntityCardState state;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case EntityCardLayout.grid:
        return _buildGrid(context);
      case EntityCardLayout.row:
        return _buildRow(context);
      case EntityCardLayout.hero:
        return _buildHero(context);
    }
  }

  Widget _buildVisual(BuildContext context) {
    final v = visual;
    if (v is ThumbVisual) {
      return ThumbView(
        filePath: v.filePath,
        memoryBytes: v.memoryBytes,
        isVideo: v.isVideo,
        durationLabel: v.durationLabel,
      );
    } else if (v is CropVisual) {
      return CropView(path: v.path, showExpandButton: v.showExpand);
    } else if (v is AvatarVisual) {
      return Center(
        child: AvatarView(cropPath: v.cropPath, name: v.name),
      );
    } else if (v is CropStackVisual) {
      return _buildCropStack(context, v.paths);
    } else if (v is IconVisual) {
      final theme = Theme.of(context);
      return Center(
        child: Icon(
          v.icon,
          size: 40,
          color: v.color ?? theme.colorScheme.primary,
        ),
      );
    }
    return const SizedBox();
  }

  Widget _buildCropStack(BuildContext context, List<String> paths) {
    if (paths.isEmpty) {
      return const SizedBox();
    }
    return Stack(
      children: [
        for (var i = 0; i < paths.length && i < 3; i++)
          Positioned(
            left: i * 16.0,
            top: i * 4.0,
            bottom: (2 - i) * 4.0,
            width: 70,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CropView(path: paths[i], showExpandButton: false),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGrid(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = state == EntityCardState.selected;
    final isDisabled = state == EntityCardState.disabled;
    final isBusy = state == EntityCardState.busy;

    return Semantics(
      selected: isSelected,
      enabled: !isDisabled,
      child: Opacity(
        opacity: isDisabled ? 0.45 : 1.0,
        child: InkWell(
          onTap: isDisabled || isBusy ? null : onTap,
          onLongPress: isDisabled || isBusy ? null : onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildVisual(context),
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.check, size: 16, color: Colors.blue),
                      ),
                    ),
                  ),
                ),
              if (isBusy)
                Container(
                  color: Colors.black38,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              if (badge != null) Positioned(top: 6, left: 6, child: badge!),
              if (title != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context) {
    final isSelected = state == EntityCardState.selected;
    final isDisabled = state == EntityCardState.disabled;
    final isBusy = state == EntityCardState.busy;

    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: ListTile(
        selected: isSelected,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildVisual(context),
          ),
        ),
        title: title != null ? Text(title!) : null,
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: isBusy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : trailing,
        onTap: isDisabled || isBusy ? null : onTap,
        onLongPress: isDisabled || isBusy ? null : onLongPress,
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: state == EntityCardState.disabled ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildVisual(context)),
            if (title != null || subtitle != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title!,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
