import 'dart:math';
import 'dart:ui';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/domain/geometry/outline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  group('outline geometry & encoding', () {
    test('encode/decode round trip within 0.001', () {
      const box = BBox(x: 100.0, y: 150.0, w: 200.0, h: 300.0);
      final px = [
        const Offset(120.456, 180.789),
        const Offset(250.123, 220.456),
        const Offset(280.999, 410.111),
        const Offset(150.000, 420.333),
      ];

      final encoded = encodeOutline(px, box);
      expect(encoded, isNotNull);

      final decoded = decodeOutline(encoded);
      expect(decoded, isNotNull);
      expect(decoded!.length, px.length);

      for (var i = 0; i < px.length; i++) {
        final expectedRelX = (px[i].dx - box.x) / box.w;
        final expectedRelY = (px[i].dy - box.y) / box.h;
        expect(decoded[i].dx, closeTo(expectedRelX, 0.001));
        expect(decoded[i].dy, closeTo(expectedRelY, 0.001));
      }
    });

    test('clamping to [-0.25, 1.25]', () {
      const box = BBox(x: 100.0, y: 100.0, w: 100.0, h: 100.0);
      final px = [
        const Offset(50.0, 50.0), // rel -0.5 -> clamp to -0.25
        const Offset(250.0, 300.0), // rel 1.5, 2.0 -> clamp to 1.25
        const Offset(150.0, 150.0), // rel 0.5 -> unclamp
      ];

      final encoded = encodeOutline(px, box);
      final decoded = decodeOutline(encoded)!;

      expect(decoded[0].dx, closeTo(-0.25, 0.001));
      expect(decoded[0].dy, closeTo(-0.25, 0.001));
      expect(decoded[1].dx, closeTo(1.25, 0.001));
      expect(decoded[1].dy, closeTo(1.25, 0.001));
      expect(decoded[2].dx, closeTo(0.5, 0.001));
      expect(decoded[2].dy, closeTo(0.5, 0.001));
    });

    test('malformed strings return null without throwing', () {
      expect(decodeOutline(null), isNull);
      expect(decodeOutline(''), isNull);
      expect(decodeOutline('   '), isNull);
      expect(decodeOutline('not a json'), isNull);
      expect(decodeOutline('{"x": 1}'), isNull);
      expect(decodeOutline('[1, 2]'), isNull); // fewer than 6 values (< 3 points)
      expect(decodeOutline('[1, 2, 3, 4, 5]'), isNull); // odd number of values
      expect(decodeOutline('[1, 2, "three", 4, 5, 6]'), isNull);
      expect(decodeOutline('[1, 2, null, 4, 5, 6]'), isNull);
    });

    test('null / empty / small / zero-box encode returns null', () {
      const box = BBox(x: 0, y: 0, w: 100, h: 100);
      const zeroBox = BBox(x: 0, y: 0, w: 0, h: 100);
      expect(encodeOutline(null, box), isNull);
      expect(encodeOutline([], box), isNull);
      expect(encodeOutline([const Offset(1, 2), const Offset(3, 4)], box), isNull);
      expect(
        encodeOutline(
          [const Offset(1, 2), const Offset(3, 4), const Offset(5, 6)],
          zeroBox,
        ),
        isNull,
      );
    });

    test('detectionPath fallback bounds equal the box', () {
      const rect = Rect.fromLTWH(50.0, 60.0, 200.0, 300.0);

      final faceFallback = detectionPath(rect, isFace: true);
      expect(faceFallback.getBounds(), rect);

      final bodyFallback = detectionPath(rect, isFace: false);
      expect(bodyFallback.getBounds(), rect);
    });

    test('detectionPath with outline matches mapped bounds within 3%', () {
      const rect = Rect.fromLTWH(100.0, 100.0, 200.0, 200.0);
      // A representative 16-point smooth outline (e.g. oval/head)
      final outline = List.generate(16, (i) {
        final angle = i * 2 * pi / 16;
        return Offset(0.5 + 0.35 * cos(angle), 0.5 + 0.45 * sin(angle));
      });

      final mappedPoints = outline.map((p) => Offset(
        rect.left + p.dx * rect.width,
        rect.top + p.dy * rect.height,
      )).toList();

      var minX = mappedPoints[0].dx;
      var maxX = mappedPoints[0].dx;
      var minY = mappedPoints[0].dy;
      var maxY = mappedPoints[0].dy;
      for (final p in mappedPoints) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      final expectedBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

      final path = detectionPath(rect, outline: outline, isFace: true);
      final pathBounds = path.getBounds();

      // Check bounds within 3% of rect size
      final tolerance = rect.width * 0.03;
      expect(pathBounds.left, closeTo(expectedBounds.left, tolerance));
      expect(pathBounds.right, closeTo(expectedBounds.right, tolerance));
      expect(pathBounds.top, closeTo(expectedBounds.top, tolerance));
      expect(pathBounds.bottom, closeTo(expectedBounds.bottom, tolerance));
    });

    test('fixture parse gives 12 points for face 0, null for face 1, 20 for body', () {
      final json = fixture('AnalyzeImageResponse.two_faces_one_body');
      final response = AnalyzeImageResponse.fromJson(json);

      expect(response.faces[0].outline, isNotNull);
      expect(response.faces[0].outline!.length, 12);

      expect(response.faces[1].outline, isNull);

      expect(response.bodies[0].outline, isNotNull);
      expect(response.bodies[0].outline!.length, 20);
    });
  });
}
