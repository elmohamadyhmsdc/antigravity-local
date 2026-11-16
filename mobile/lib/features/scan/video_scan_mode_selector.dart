import 'package:flutter/material.dart';

import '../../data/repositories/app_settings.dart';
import '../../l10n/app_localizations.dart';

class VideoScanModeSelector extends StatelessWidget {
  const VideoScanModeSelector({
    super.key,
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });
  final VideoScanMode mode;
  final bool enabled;
  final ValueChanged<VideoScanMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(l.videoScanModeTitle),
          trailing: DropdownButton<VideoScanMode>(
            key: const Key('video-scan-mode'),
            value: mode,
            items: [
              DropdownMenuItem(
                value: VideoScanMode.quick,
                child: Text(l.videoScanQuick),
              ),
              DropdownMenuItem(
                value: VideoScanMode.detailed,
                child: Text(l.videoScanDetailed),
              ),
            ],
            onChanged: enabled
                ? (value) {
                    if (value != null) onChanged(value);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            mode == VideoScanMode.quick
                ? l.videoScanQuickHint
                : l.videoScanDetailedHint,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
