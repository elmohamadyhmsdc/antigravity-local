import 'package:flutter/material.dart';

import '../../data/repositories/app_settings.dart';
import '../../l10n/app_localizations.dart';

class VideoScanModeSelector extends StatelessWidget {
  const VideoScanModeSelector({super.key, required this.mode, required this.enabled,
    required this.onChanged});
  final VideoScanMode mode;
  final bool enabled;
  final ValueChanged<VideoScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListTile(
      title: Text(l.videoScanModeTitle),
      subtitle: Text(mode == VideoScanMode.quick ? l.videoScanQuickHint : l.videoScanDetailedHint),
      trailing: DropdownButton<VideoScanMode>(
        key: const Key('video-scan-mode'), value: mode,
        items: [
          DropdownMenuItem(value: VideoScanMode.quick, child: Text(l.videoScanQuick)),
          DropdownMenuItem(value: VideoScanMode.detailed, child: Text(l.videoScanDetailed)),
        ],
        onChanged: enabled ? (value) { if (value != null) onChanged(value); } : null,
      ),
    );
  }
}
