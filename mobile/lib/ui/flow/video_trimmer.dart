import 'package:flutter/material.dart';

/// Flow component: video trimmer with min and max bounds.
class VideoTrimmer extends StatefulWidget {
  const VideoTrimmer({
    super.key,
    required this.duration,
    required this.initialStart,
    required this.initialEnd,
    required this.onChanged,
    this.minDuration = const Duration(seconds: 3),
    this.maxDuration = const Duration(minutes: 2),
  });

  final Duration duration;
  final Duration initialStart;
  final Duration initialEnd;
  final void Function(Duration start, Duration end) onChanged;
  final Duration minDuration;
  final Duration maxDuration;

  @override
  State<VideoTrimmer> createState() => _VideoTrimmerState();
}

class _VideoTrimmerState extends State<VideoTrimmer> {
  late double _startSeconds;
  late double _endSeconds;
  late double _maxSeconds;

  @override
  void initState() {
    super.initState();
    _maxSeconds = widget.duration.inMilliseconds / 1000.0;
    _startSeconds = (widget.initialStart.inMilliseconds / 1000.0).clamp(
      0.0,
      _maxSeconds,
    );
    _endSeconds = (widget.initialEnd.inMilliseconds / 1000.0).clamp(
      _startSeconds + widget.minDuration.inSeconds,
      _maxSeconds,
    );
  }

  String _formatDuration(double seconds) {
    final s = seconds.toInt();
    final m = s ~/ 60;
    final remS = s % 60;
    return '$m:${remS.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_maxSeconds <= 0) return const SizedBox.shrink();

    final selectedLength = _endSeconds - _startSeconds;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Trim Range: ${_formatDuration(_startSeconds)} - ${_formatDuration(_endSeconds)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Length: ${selectedLength.toStringAsFixed(1)}s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selectedLength > widget.maxDuration.inSeconds
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          RangeSlider(
            key: const Key('video-trim-slider'),
            values: RangeValues(_startSeconds, _endSeconds),
            min: 0.0,
            max: _maxSeconds > 0 ? _maxSeconds : 1.0,
            onChanged: (values) {
              final newDiff = values.end - values.start;
              if (newDiff < widget.minDuration.inSeconds) return;
              if (newDiff > widget.maxDuration.inSeconds) return;

              setState(() {
                _startSeconds = values.start;
                _endSeconds = values.end;
              });
              widget.onChanged(
                Duration(milliseconds: (_startSeconds * 1000).toInt()),
                Duration(milliseconds: (_endSeconds * 1000).toInt()),
              );
            },
          ),
        ],
      ),
    );
  }
}
