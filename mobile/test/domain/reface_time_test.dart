import 'package:antigravity_mobile/domain/reface/reface_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cost is frames x faces x the PC\'s typical ms per face', () {
    expect(
      RefaceTime.processing(msPerFace: 300, frames: 10, faces: 2),
      const Duration(seconds: 6),
    );
  });

  test(
    'no estimate when the PC did not report a cost or there is nothing to do',
    () {
      expect(
        RefaceTime.processing(msPerFace: null, frames: 10, faces: 1),
        isNull,
      );
      expect(RefaceTime.processing(msPerFace: 0, frames: 10, faces: 1), isNull);
      expect(
        RefaceTime.processing(msPerFace: 100, frames: 0, faces: 1),
        isNull,
      );
      expect(
        RefaceTime.processing(msPerFace: 100, frames: 5, faces: 0),
        isNull,
      );
    },
  );

  test('a clip is counted at an assumed 30 fps', () {
    expect(RefaceTime.framesOf(const Duration(seconds: 10)), 300);
    expect(RefaceTime.framesOf(const Duration(seconds: 10), fps: 60), 600);
  });

  test('durations are said the way a person would', () {
    String w(Duration d) => RefaceTime.words(d);
    expect(w(const Duration(seconds: 2)), 'a few seconds');
    expect(w(const Duration(seconds: 42)), 'about 40 s');
    expect(w(const Duration(minutes: 3, seconds: 20)), 'about 3 min');
    expect(w(const Duration(minutes: 27)), 'about 25 min');
    expect(w(const Duration(hours: 1, minutes: 12)), 'about 1 h 10 min');
    expect(w(const Duration(hours: 2)), 'about 2 h');
    expect(w(const Duration(hours: 1, minutes: 58)), 'about 2 h');
  });
}
