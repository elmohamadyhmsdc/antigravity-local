import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';

class VideoTrimSelection {
  const VideoTrimSelection({
    required this.start,
    required this.end,
    required this.duration,
  });
  final Duration start, end, duration;
  double get startSeconds =>
      start.inMicroseconds / Duration.microsecondsPerSecond;
  double get endSeconds => end.inMicroseconds / Duration.microsecondsPerSecond;
}

String trimTime(Duration time) {
  final seconds = math.max(0, time.inSeconds);
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$tail'
      : '$minutes:$tail';
}

final refaceVideoControllerProvider =
    Provider<VideoPlayerController Function(File)>(
      (ref) =>
          (file) => VideoPlayerController.file(file),
    );

class RefaceVideoTrimmer extends ConsumerStatefulWidget {
  const RefaceVideoTrimmer({
    super.key,
    required this.file,
    required this.onChanged,
    this.onPositionChanged,
    this.active = true,
    this.enabled = true,
  });
  final File file;
  final ValueChanged<VideoTrimSelection> onChanged;
  final ValueChanged<Duration>? onPositionChanged;
  final bool active, enabled;

  @override
  ConsumerState<RefaceVideoTrimmer> createState() => _RefaceVideoTrimmerState();
}

class _RefaceVideoTrimmerState extends ConsumerState<RefaceVideoTrimmer>
    with WidgetsBindingObserver {
  late final VideoPlayerController _player;
  RangeValues? _range;
  double _duration = 0;
  bool _failed = false, _seeking = false, _stopping = false;
  Duration? _pendingSeek;

  double get _minimumClip => math.min(1.0, _duration);
  Duration _at(double seconds) => Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player = ref.read(refaceVideoControllerProvider)(widget.file);
    _player.addListener(_tick);
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.initialize();
      if (!mounted) return;
      _duration =
          _player.value.duration.inMicroseconds /
          Duration.microsecondsPerSecond;
      if (!_duration.isFinite || _duration <= 0) {
        throw const FormatException('Empty video');
      }
      setState(() => _range = RangeValues(0, _duration));
      _notify();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _notify() {
    final range = _range!;
    widget.onChanged(
      VideoTrimSelection(
        start: _at(range.start),
        end: _at(range.end),
        duration: _at(_duration),
      ),
    );
  }

  void _change(RangeValues proposed) {
    final old = _range!;
    final startMoved = proposed.start != old.start;
    final start = startMoved
        ? proposed.start.clamp(0.0, old.end - _minimumClip).toDouble()
        : old.start;
    final end = startMoved
        ? old.end
        : proposed.end.clamp(old.start + _minimumClip, _duration).toDouble();
    setState(() => _range = RangeValues(start, end));
    _notify();
    // Serialise seeks; fast drags keep only the latest pending position.
    _pendingSeek = _at(startMoved ? start : math.max(start, end - .001));
    unawaited(_seek());
  }

  Future<void> _seek() async {
    if (_seeking) return;
    _seeking = true;
    try {
      await _player.pause();
      while (mounted && _pendingSeek != null) {
        final target = _pendingSeek!;
        _pendingSeek = null;
        await _player.seekTo(target);
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      _seeking = false;
    }
  }

  void _tick() {
    if (mounted && _player.value.isInitialized) {
      widget.onPositionChanged?.call(_player.value.position);
    }
    final range = _range;
    if (!mounted ||
        range == null ||
        _stopping ||
        _seeking ||
        !_player.value.isPlaying) {
      return;
    }
    if (_player.value.position >= _at(range.end)) unawaited(_stopAtEnd(range));
  }

  Future<void> _stopAtEnd(RangeValues range) async {
    _stopping = true;
    try {
      await _player.pause();
      if (mounted && identical(range, _range)) {
        await _player.seekTo(_at(math.max(range.start, range.end - .001)));
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      _stopping = false;
    }
  }

  Future<void> _toggle() async {
    try {
      if (_player.value.isPlaying) {
        await _player.pause();
      } else {
        final range = _range!;
        final position = _player.value.position;
        if (position < _at(range.start) || position >= _at(range.end - .05)) {
          await _player.seekTo(_at(range.start));
        }
        if (mounted && widget.active) await _player.play();
      }
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pause() async {
    try {
      await _player.pause();
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant RefaceVideoTrimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || !widget.enabled) unawaited(_pause());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_tick);
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_failed || _player.value.hasError) return Text(l.videoUnavailableBody);
    final range = _range;
    if (range == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final enabled = widget.enabled && widget.active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox(
              height: 220,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _player.value.aspectRatio,
                  child: VideoPlayer(_player),
                ),
              ),
            ),
          ),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _player,
          builder: (context, value, _) => Row(
            children: [
              IconButton(
                key: const Key('reface-trim-play'),
                tooltip: value.isPlaying ? l.videoPause : l.videoPlay,
                onPressed: enabled ? _toggle : null,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Text('${trimTime(value.position)} / ${trimTime(value.duration)}'),
            ],
          ),
        ),
        Text(l.refaceTrimHint),
        Semantics(
          label: l.refaceTrimHint,
          child: RangeSlider(
            key: const Key('reface-trim-range'),
            min: 0,
            max: _duration,
            values: range,
            labels: RangeLabels(
              trimTime(_at(range.start)),
              trimTime(_at(range.end)),
            ),
            semanticFormatterCallback: (value) => trimTime(_at(value)),
            onChanged: enabled ? _change : null,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _boundary(l.refaceTrimStart, range.start, true, enabled),
            ),
            Expanded(
              child: _boundary(l.refaceTrimEnd, range.end, false, enabled),
            ),
          ],
        ),
        Text(
          '${l.refaceTrimDuration}: ${trimTime(_at(range.end - range.start))}',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _boundary(String label, double value, bool start, bool enabled) {
    final range = _range!;
    final earlier = start ? value > 0 : value - range.start > _minimumClip;
    final later = start ? range.end - value > _minimumClip : value < _duration;
    return Column(
      children: [
        Text(label),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: Key(start ? 'reface-start-earlier' : 'reface-end-earlier'),
              tooltip: AppLocalizations.of(context).refaceTrimEarlier,
              onPressed: enabled && earlier
                  ? () => _change(
                      start
                          ? RangeValues(math.max(0, value - 1), range.end)
                          : RangeValues(
                              range.start,
                              math.max(range.start + _minimumClip, value - 1),
                            ),
                    )
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Flexible(
              child: Text(
                trimTime(_at(value)),
                key: Key(start ? 'reface-start-time' : 'reface-end-time'),
              ),
            ),
            IconButton(
              key: Key(start ? 'reface-start-later' : 'reface-end-later'),
              tooltip: AppLocalizations.of(context).refaceTrimLater,
              onPressed: enabled && later
                  ? () => _change(
                      start
                          ? RangeValues(
                              math.min(range.end - _minimumClip, value + 1),
                              range.end,
                            )
                          : RangeValues(
                              range.start,
                              math.min(_duration, value + 1),
                            ),
                    )
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
