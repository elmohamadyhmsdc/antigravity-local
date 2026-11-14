import 'dart:ui';
import 'package:flutter/material.dart';

import '../../data/db/app_database.dart';
import '../../l10n/app_localizations.dart';
import 'layers_popover.dart';

/// L3 / P5b — Media viewer chrome (top app bar and floating glass action dock).
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.black.withValues(alpha: 0.25),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 0.6,
                  ),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      _GlassIconButton(
                        tooltip: 'Back',
                        icon: Icons.arrow_back,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (media.kind == 'video')
                              Text(
                                l10n.videoTitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _GlassIconButton(
                        key: const Key('media-layers-toggle'),
                        tooltip: 'Layers',
                        icon: Icons.layers_outlined,
                        isActive: layers.faces || layers.bodies || layers.areas || layers.equipment,
                        onPressed: () => LayersPopover.show(
                          context: context,
                          layers: layers,
                          availability: availability,
                          onChanged: onLayersChanged,
                        ),
                      ),
                      if (media.kind == 'video') ...[
                        const SizedBox(width: 6),
                        _GlassIconButton(
                          key: const Key('media-open-native-player'),
                          tooltip: 'Open with native player',
                          icon: Icons.smart_display_outlined,
                          onPressed: onOpenNativePlayer,
                        ),
                      ],
                      const SizedBox(width: 6),
                      ClipOval(
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.12),
                          child: PopupMenuButton<String>(
                            key: const Key('media-more-menu'),
                            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                            tooltip: 'More options',
                            color: const Color(0xFF1B1F27),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 0.8),
                            ),
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
                                child: _MenuRow(
                                  icon: layers.faces ? Icons.visibility_off_outlined : Icons.face_outlined,
                                  text: layers.faces ? 'Hide faces' : 'Show faces',
                                ),
                              ),
                              PopupMenuItem(
                                key: const Key('toggle-bodies'),
                                value: 'toggle-bodies',
                                child: _MenuRow(
                                  icon: layers.bodies ? Icons.visibility_off_outlined : Icons.accessibility_new_outlined,
                                  text: layers.bodies ? 'Hide bodies' : 'Show bodies',
                                ),
                              ),
                              if (media.kind == 'photo' && onLens != null)
                                const PopupMenuItem(
                                  key: Key('google-lens'),
                                  value: 'lens',
                                  child: _MenuRow(
                                    icon: Icons.camera_alt_outlined,
                                    text: 'Google Lens',
                                  ),
                                ),
                              if (media.kind == 'photo')
                                PopupMenuItem(
                                  value: 'redetect',
                                  child: _MenuRow(
                                    icon: Icons.refresh_outlined,
                                    text: l10n.redetectTitle,
                                  ),
                                ),
                              PopupMenuItem(
                                value: 'kind',
                                child: _MenuRow(
                                  icon: Icons.category_outlined,
                                  text: l10n.mediaKindTitle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating Glass Dock at the bottom of the photo/video viewer.
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
    this.onDetect,
    this.visible = true,
  });

  final MediaRow media;
  final VoidCallback onShare;
  final VoidCallback onStudio;
  final VoidCallback onDetails;
  final VoidCallback onLens;
  final VoidCallback onOpenNativePlayer;
  final VoidCallback? onTools;
  final VoidCallback? onDetect;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xCC11141A),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ViewerDockItem(
                              key: const Key('media-actions-share'),
                              icon: Icons.share_outlined,
                              label: 'Share',
                              onTap: onShare,
                            ),
                          ),
                          Expanded(
                            child: _ViewerDockItem(
                              key: const Key('media-actions-studio'),
                              icon: Icons.auto_awesome,
                              label: 'Studio',
                              isEmphasized: true,
                              onTap: onStudio,
                            ),
                          ),
                          Expanded(
                            child: _ViewerDockItem(
                              key: const Key('media-actions-details'),
                              icon: Icons.info_outline,
                              label: 'Details',
                              onTap: onDetails,
                            ),
                          ),
                          Expanded(
                            child: _ViewerDockItem(
                              key: const Key('media-actions-tools'),
                              icon: Icons.tune_outlined,
                              label: 'Tools',
                              onTap: onTools ?? onStudio,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerDockItem extends StatelessWidget {
  const _ViewerDockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isEmphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isEmphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isEmphasized
                      ? primary.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isEmphasized ? primary : Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isEmphasized ? FontWeight.w600 : FontWeight.w500,
                  color: isEmphasized
                      ? primary
                      : Colors.white.withValues(alpha: 0.85),
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.isActive = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    Widget button = ClipOval(
      child: Material(
        color: isActive
            ? primary.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              icon,
              size: 20,
              color: isActive ? primary : Colors.white,
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.white70),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(fontSize: 14, color: Colors.white)),
      ],
    );
  }
}
