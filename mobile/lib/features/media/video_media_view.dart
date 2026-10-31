import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../data/media/media_library.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../shared/empty_state.dart';
import '../shared/crop_image.dart';

String videoTime(int ms) {
  final seconds = ms ~/ 1000;
  final h = seconds ~/ 3600;
  final m = (seconds ~/ 60) % 60;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// Plays the original on the phone. Boxes are shown only at their sampled timestamps;
/// jumping to a sample pauses playback, so identities never drift across unrelated frames.
class VideoMediaView extends StatefulWidget {
  const VideoMediaView({
    super.key,
    required this.assetId,
    required this.library,
    required this.detections,
    required this.people,
    required this.showBodies,
    required this.onTapBox,
    this.initialTimestampMs,
    this.focusKind,
    this.focusRefId,
  });
  final String assetId;
  final int? initialTimestampMs;
  final String? focusKind;
  final int? focusRefId;
  final MediaLibrary library;
  final List<MediaDetection> detections;
  final Map<int, PersonSummary> people;
  final bool showBodies;
  final ValueChanged<MediaDetection> onTapBox;

  @override
  State<VideoMediaView> createState() => _VideoMediaViewState();
}

class _VideoMediaViewState extends State<VideoMediaView> {
  bool _focused(MediaDetection d) =>
      d.kind == widget.focusKind && d.refId == widget.focusRefId;
  VideoPlayerController? _player;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    VideoPlayerController? player;
    try {
      final source = widget.library;
      final File? file = source is VideoMediaLibrary
          ? await (source as VideoMediaLibrary).videoFile(widget.assetId)
          : null;
      if (file == null) throw const FileSystemException('Video unavailable');
      player = VideoPlayerController.file(file);
      await player.initialize();
      if (widget.initialTimestampMs != null) {
        await player.seekTo(
          Duration(
            milliseconds: widget.initialTimestampMs!.clamp(
              0,
              player.value.duration.inMilliseconds,
            ),
          ),
        );
      }
      if (!mounted) {
        await player.dispose();
        return;
      }
      _player = player;
      player.addListener(_tick);
      setState(() => _loading = false);
    } catch (_) {
      await player?.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player?.removeListener(_tick);
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loading) return const LoadingBox();
    final player = _player;
    if (_error || player == null || player.value.hasError) {
      return EmptyState(
        icon: Icons.videocam_off_outlined,
        title: l10n.videoUnavailable,
        body: l10n.videoUnavailableBody,
      );
    }
    final value = player.value;
    final position = value.position.inMilliseconds;
    final duration = value.duration.inMilliseconds;
    final samples = {
      for (final d in widget.detections)
        if (d.timestampMs != null) d.timestampMs!,
    }.toList()..sort();
    final boxes = [
      for (final d in widget.detections)
        if ((d.isFace || widget.showBodies) &&
            d.timestampMs != null &&
            (d.timestampMs! - position).abs() <= 150)
          d,
    ];
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(player),
                    for (final d in boxes)
                      Positioned(
                        left: d.x * constraints.maxWidth,
                        top: d.y * constraints.maxHeight,
                        width: d.w * constraints.maxWidth,
                        height: d.h * constraints.maxHeight,
                        child: GestureDetector(
                          key: Key('video-box-${d.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await player.pause();
                            widget.onTapBox(d);
                          },
                          child: DecoratedBox(
                            key: _focused(d)
                                ? const Key('review-video-highlight')
                                : null,
                            decoration: BoxDecoration(
                              border: Border.all(
                                width: _focused(d) ? 3 : 2,
                                color: _focused(d)
                                    ? Colors.amberAccent
                                    : d.isFace
                                    ? (d.personId == null
                                          ? Colors.amber
                                          : Colors.greenAccent)
                                    : Colors.lightBlueAccent,
                              ),
                            ),
                            child: d.personId == null && !_focused(d)
                                ? null
                                : Align(
                                    alignment: Alignment.topLeft,
                                    child: ColoredBox(
                                      color: Colors.black54,
                                      child: Text(
                                        _focused(d)
                                            ? (d.isFace
                                                  ? l10n.reviewFace
                                                  : l10n.reviewBody)
                                            : personNameOf(
                                                l10n,
                                                d.personId!,
                                                widget.people,
                                              ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const Key('video-play'),
                      tooltip: value.isPlaying
                          ? l10n.videoPause
                          : l10n.videoPlay,
                      onPressed: () =>
                          value.isPlaying ? player.pause() : player.play(),
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${videoTime(position)} / ${videoTime(duration)}',
                      ),
                    ),
                  ],
                ),
                Slider(
                  min: 0,
                  max: duration > 0 ? duration.toDouble() : 1,
                  value: position.clamp(0, duration).toDouble(),
                  semanticFormatterCallback: (value) =>
                      videoTime(value.round()),
                  onChanged: (v) =>
                      player.seekTo(Duration(milliseconds: v.round())),
                ),
                if (samples.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.videoDetectedFrames,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context).scale(16) + 32,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: samples.length,
                      itemBuilder: (context, index) {
                        final sample = samples[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(
                              Icons.person_pin_outlined,
                              size: 18,
                            ),
                            label: Text(videoTime(sample)),
                            onPressed: () async {
                              await player.pause();
                              await player.seekTo(
                                Duration(milliseconds: sample),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ] else
                  Text(l10n.videoNoDetections),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
