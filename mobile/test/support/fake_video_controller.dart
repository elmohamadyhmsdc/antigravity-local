import 'dart:ui';

import 'package:video_player/video_player.dart';

/// A controller seam for timeline gestures; native decoding is exercised on-device.
class FakeTrimVideoController extends VideoPlayerController {
  FakeTrimVideoController(
    super.file, {
    this.fixtureDuration = const Duration(minutes: 30),
  }) : super.file();
  final Duration fixtureDuration;
  final seeks = <Duration>[];
  bool didDispose = false;

  @override
  Future<void> initialize() async {
    value = VideoPlayerValue(
      duration: fixtureDuration,
      size: const Size(640, 360),
      isInitialized: true,
    );
  }

  @override
  Future<void> pause() async {
    if (!didDispose) value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> play() async {
    if (!didDispose) value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    if (!didDispose) value = value.copyWith(position: position);
  }

  @override
  Future<void> dispose() async {
    didDispose = true;
    await super.dispose();
  }
}
