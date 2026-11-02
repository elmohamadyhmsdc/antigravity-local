import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import 'layers_popover.dart';

/// L3 / P5b — Media viewer chrome (top app bar and bottom actions bar).
class MediaChromeTopBar extends StatelessWidget implements PreferredSizeWidget {
  const MediaChromeTopBar({
    super.key,
    required this.media,
    required this.title,
    required this.layers,
    required this.availability,
    required this.onLayersChanged,
    required this.onOpenNativePlayer,
    required this.onRedetect,
    required this.onChangeFileKind,
    this.onLens,
    this.visible = true,
  });

  final MediaRow media;
  final String title;
  final ViewerLayers layers;
  final LayerAvailability availability;
  final ValueChanged<ViewerLayers> onLayersChanged;
  final VoidCallback onOpenNativePlayer;
  final VoidCallback onRedetect;
  final VoidCallback onChangeFileKind;
  final VoidCallback? onLens;
  final bool visible;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: !visible,
        child: AppBar(
          backgroundColor: Colors.black45,
          foregroundColor: Colors.white,
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            IconButton(
              key: const Key('media-layers-toggle'),
              tooltip: 'Layers',
              icon: const Icon(Icons.layers_outlined),
              onPressed: () => LayersPopover.show(
                context: context,
                layers: layers,
                availability: availability,
                onChanged: onLayersChanged,
              ),
            ),
            if (media.kind == 'video')
              IconButton(
                key: const Key('media-open-native-player'),
                tooltip: 'Open with native player',
                icon: const Icon(Icons.smart_display_outlined),
                onPressed: onOpenNativePlayer,
              ),
            PopupMenuButton<String>(
              key: const Key('media-more-menu'),
              onSelected: (value) {
                if (value == 'redetect') onRedetect();
                if (value == 'kind') onChangeFileKind();
                if (value == 'toggle-faces') {
                  onLayersChanged(layers.copyWith(faces: !layers.faces));
                }
                if (value == 'toggle-bodies') {
                  onLayersChanged(layers.copyWith(bodies: !layers.bodies));
                }
                if (value == 'lens') {
                  onLens?.call();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const Key('toggle-faces'),
                  value: 'toggle-faces',
                  child: Text(layers.faces ? 'Hide faces' : 'Show faces'),
                ),
                PopupMenuItem(
                  key: const Key('toggle-bodies'),
                  value: 'toggle-bodies',
                  child: Text(layers.bodies ? 'Hide bodies' : 'Show bodies'),
                ),
                if (media.kind == 'photo' && onLens != null)
                  const PopupMenuItem(
                    key: Key('google-lens'),
                    value: 'lens',
                    child: Text('Google Lens'),
                  ),
                if (media.kind == 'photo')
                  PopupMenuItem(
                    value: 'redetect',
                    child: Text(l10n.redetectTitle),
                  ),
                PopupMenuItem(value: 'kind', child: Text(l10n.mediaKindTitle)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MediaChromeBottomBar extends StatelessWidget {
  const MediaChromeBottomBar({
    super.key,
    required this.media,
    required this.onShare,
    required this.onStudio,
    required this.onDetails,
    required this.onLens,
    required this.onOpenNativePlayer,
    this.onTools,
    this.visible = true,
  });

  final MediaRow media;
  final VoidCallback onShare;
  final VoidCallback onStudio;
  final VoidCallback onDetails;
  final VoidCallback onLens;
  final VoidCallback onOpenNativePlayer;
  final VoidCallback? onTools;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 160),
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          top: false,
          child: Container(
            color: Colors.black45,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    key: const Key('media-actions-details'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: onDetails,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Details'),
                  ),
                  if (onTools != null)
                    TextButton.icon(
                      key: const Key('media-actions-tools'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onTools,
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Tools'),
                    ),
                  TextButton.icon(
                    key: const Key('media-actions-studio'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: onStudio,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Studio'),
                  ),
                  TextButton.icon(
                    key: const Key('media-actions-share'),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                  if (media.kind == 'photo')
                    TextButton.icon(
                      key: const Key('media-lens-bottom'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onLens,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Lens'),
                    ),
                  if (media.kind == 'video')
                    TextButton.icon(
                      key: const Key('media-open-native-player-bottom'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: onOpenNativePlayer,
                      icon: const Icon(Icons.smart_display_outlined),
                      label: const Text('Player'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
