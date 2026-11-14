import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/photo_edit/smart_selector.dart';

void main() {
  test('SmartSelector.floodSelect selects connected color region accurately', () {
    const width = 10;
    const height = 10;
    final rgba = Uint8List(width * height * 4);

    // Fill with white background: (255, 255, 255, 255)
    for (var i = 0; i < width * height; i++) {
      rgba[i * 4] = 255;
      rgba[i * 4 + 1] = 255;
      rgba[i * 4 + 2] = 255;
      rgba[i * 4 + 3] = 255;
    }

    // Draw a 4x4 blue box in the middle: x: 3..6, y: 3..6 -> (0, 0, 255, 255)
    for (var y = 3; y <= 6; y++) {
      for (var x = 3; x <= 6; x++) {
        final idx = (y * width + x) * 4;
        rgba[idx] = 0;
        rgba[idx + 1] = 0;
        rgba[idx + 2] = 255;
        rgba[idx + 3] = 255;
      }
    }

    // Tap inside the blue box: normalized (0.45, 0.45) -> (x: 4, y: 4)
    final blueRects = SmartSelector.floodSelect(
      rgbaBytes: rgba,
      width: width,
      height: height,
      seedNorm: const Offset(0.45, 0.45),
      tolerance: 0.15,
      dilate: false,
    );

    expect(blueRects, isNotEmpty);
    // Total area of blue box is 4 rows of width 4 * (1/10) = 0.4 width, 0.1 height each
    expect(blueRects.length, 4);
    for (final r in blueRects) {
      expect(r.left, closeTo(0.3, 0.01));
      expect(r.right, closeTo(0.7, 0.01));
      expect(r.top, greaterThanOrEqualTo(0.3 - 0.01));
      expect(r.bottom, lessThanOrEqualTo(0.7 + 0.01));
    }

    // Tap on the white background: normalized (0.1, 0.1) -> (x: 1, y: 1)
    final bgRects = SmartSelector.floodSelect(
      rgbaBytes: rgba,
      width: width,
      height: height,
      seedNorm: const Offset(0.1, 0.1),
      tolerance: 0.15,
      dilate: false,
    );
    expect(bgRects, isNotEmpty);
    // Background should not contain the center of the blue box (0.5, 0.5)
    final containsCenter = bgRects.any((r) => r.contains(const Offset(0.5, 0.5)));
    expect(containsCenter, isFalse);
  });

  test('SmartSelector tolerance respects threshold', () {
    const width = 5;
    const height = 5;
    final rgba = Uint8List(width * height * 4);

    // Pixel 0,0 is (100, 100, 100, 255)
    // Pixel 0,1 is (120, 120, 120, 255) -> diff is ~20 on each channel (~11% diff)
    for (var i = 0; i < width * height; i++) {
      rgba[i * 4] = 100;
      rgba[i * 4 + 1] = 100;
      rgba[i * 4 + 2] = 100;
      rgba[i * 4 + 3] = 255;
    }
    // Change (1, 0)
    rgba[4] = 135;
    rgba[5] = 135;
    rgba[6] = 135;

    // Strict tolerance (0.05): does not include (1,0)
    final strict = SmartSelector.floodSelect(
      rgbaBytes: rgba,
      width: width,
      height: height,
      seedNorm: const Offset(0.0, 0.0),
      tolerance: 0.05,
      dilate: false,
    );
    expect(strict.any((r) => r.contains(const Offset(0.25, 0.05))), isFalse);

    // Lenient tolerance (0.25): includes (1,0)
    final lenient = SmartSelector.floodSelect(
      rgbaBytes: rgba,
      width: width,
      height: height,
      seedNorm: const Offset(0.0, 0.0),
      tolerance: 0.25,
      dilate: false,
    );
    expect(lenient.any((r) => r.contains(const Offset(0.25, 0.05))), isTrue);
  });
}
