/// "About how long will this take", in words, from what the PC reported per face. Only the PC's own work:
/// uploading the target and fetching the result depend on the Wi-Fi and are not counted.
class RefaceTime {
  const RefaceTime._();

  /// Frames of a clip when its real frame rate is not known to the phone: a typical phone video.
  static const assumedFps = 30.0;

  /// [msPerFace] is the PC's typical cost for one normal-size face; null (older PC) gives no estimate.
  /// Small faces cost less, so this is an upper-ish figure for crowds and wide shots.
  static Duration? processing({
    required double? msPerFace,
    required int frames,
    required int faces,
  }) {
    if (msPerFace == null || msPerFace <= 0 || frames <= 0 || faces <= 0) {
      return null;
    }
    return Duration(milliseconds: (msPerFace * frames * faces).round());
  }

  static int framesOf(Duration clip, {double fps = assumedFps}) =>
      (clip.inMilliseconds / 1000 * fps).ceil();

  /// "a few seconds", "about 40 s", "about 6 min", "about 1 h 10 min".
  static String words(Duration d) {
    final s = d.inMilliseconds / 1000;
    if (s < 5) return 'a few seconds';
    if (s < 90) return 'about ${(s / 5).round() * 5} s';
    final minutes = s / 60;
    if (minutes < 10) return 'about ${minutes.round()} min';
    final rounded = (minutes / 5).round() * 5;
    if (rounded < 60) return 'about $rounded min';
    final hours = rounded ~/ 60, rest = rounded % 60;
    return rest == 0 ? 'about $hours h' : 'about $hours h $rest min';
  }
}
