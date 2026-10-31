import 'package:antigravity_mobile/domain/export/crop_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('faceCrop', () {
    test('is a square, margin times the longer side, centred on the face', () {
      // face box 200 x 150 px in a 4000 x 3000 photo, centre (1000, 1000)
      final plan = faceCrop(
        x: 900 / 4000,
        y: 925 / 3000,
        w: 200 / 4000,
        h: 150 / 3000,
        imgW: 4000,
        imgH: 3000,
        outSize: 512,
      )!;
      expect(plan.source.width, 320); // 200 * 1.6
      expect(plan.source.height, 320);
      expect(plan.source.left, 840); // 1000 - 160
      expect(plan.source.top, 840);
      expect(plan.outWidth, 512);
      expect(plan.outHeight, 512);
    });

    test('moves inside the image instead of padding at an edge', () {
      final plan = faceCrop(
        x: 0.0,
        y: 0.45,
        w: 0.05,
        h: 0.05 * 4000 / 3000,
        imgW: 4000,
        imgH: 3000,
        outSize: 512,
      )!;
      expect(plan.source.left, 0);
      expect(plan.source.top, greaterThanOrEqualTo(0));
      expect(plan.source.bottom, lessThanOrEqualTo(3000));
      expect(plan.source.width, plan.source.height);
    });

    test('a margin larger than the image shrinks to the image side', () {
      final plan = faceCrop(
        x: 0.2,
        y: 0.1,
        w: 0.5,
        h: 0.8,
        imgW: 1000,
        imgH: 1000,
        outSize: 512,
        maxUpscale: 4,
      )!;
      expect(plan.source, const PxRect(0, 0, 1000, 1000));
    });

    test('is null when the face does not fit a square at all', () {
      expect(
        faceCrop(x: 0, y: 0, w: 1, h: 1, imgW: 4000, imgH: 1000, outSize: 512),
        isNull,
      );
    });

    test('is null when it would be enlarged more than maxUpscale', () {
      // 100 px face -> 160 px crop -> 512 is x3.2
      expect(
        faceCrop(
          x: 0.4,
          y: 0.4,
          w: 100 / 1000,
          h: 100 / 1000,
          imgW: 1000,
          imgH: 1000,
          outSize: 512,
        ),
        isNull,
      );
      expect(
        faceCrop(
          x: 0.4,
          y: 0.4,
          w: 100 / 1000,
          h: 100 / 1000,
          imgW: 1000,
          imgH: 1000,
          outSize: 512,
          maxUpscale: 4,
        ),
        isNotNull,
      );
      expect(
        faceCrop(
          x: 0.4,
          y: 0.4,
          w: 100 / 1000,
          h: 100 / 1000,
          imgW: 1000,
          imgH: 1000,
          outSize: 256,
        ),
        isNotNull,
        reason: 'a 160 px crop to 256 is x1.6',
      );
    });

    test('the crop always lies inside the image', () {
      for (final x in [0.0, 0.3, 0.9]) {
        for (final y in [0.0, 0.5, 0.92]) {
          final plan = faceCrop(
            x: x,
            y: y,
            w: 0.08,
            h: 0.08,
            imgW: 3000,
            imgH: 2000,
            outSize: 512,
          )!;
          expect(
            plan.source.left,
            inInclusiveRange(0, 3000 - plan.source.width),
          );
          expect(
            plan.source.top,
            inInclusiveRange(0, 2000 - plan.source.height),
          );
        }
      }
    });
  });

  group('bodyCrop', () {
    test('keeps the aspect ratio and clamps the margin at the image edge', () {
      final plan = bodyCrop(
        x: 0.0,
        y: 0.1,
        w: 0.3,
        h: 0.8,
        imgW: 2000,
        imgH: 4000,
        longSide: 1024,
      )!;
      expect(plan.source.left, 0);
      expect(plan.source.top, 240); // centre 2000, half of 3200 * 1.1 = 1760
      expect(plan.source.bottom, lessThanOrEqualTo(4000));
      expect(
        plan.outWidth / plan.outHeight,
        closeTo(plan.source.width / plan.source.height, 0.01),
      );
      expect(plan.outHeight, 1024);
    });

    test('is never enlarged', () {
      final plan = bodyCrop(
        x: 0.25,
        y: 0.25,
        w: 0.5,
        h: 0.5,
        imgW: 800,
        imgH: 600,
        longSide: 1024,
      )!;
      expect(plan.outWidth, plan.source.width);
      expect(plan.outHeight, plan.source.height);
      expect(plan.scale, 1.0);
    });
  });

  group('EXIF orientation', () {
    test('upright size swaps the axes for 5..8 only', () {
      for (var o = 1; o <= 8; o++) {
        final s = uprightSize(400, 300, o);
        expect(s.width, o >= 5 ? 300 : 400, reason: 'orientation $o');
        expect(s.height, o >= 5 ? 400 : 300, reason: 'orientation $o');
      }
    });

    // Where the stored pixel (c, r) ends up in the upright image (EXIF spec, 0-based pixels).
    (int, int) forward(int o, int c, int r, int w, int h) => switch (o) {
      2 => (w - 1 - c, r),
      3 => (w - 1 - c, h - 1 - r),
      4 => (c, h - 1 - r),
      5 => (r, c),
      6 => (h - 1 - r, c),
      7 => (h - 1 - r, w - 1 - c),
      8 => (r, w - 1 - c),
      _ => (c, r),
    };

    test(
      'uprightToRaw selects exactly the stored pixels that show the rect',
      () {
        const w = 40, h = 30;
        for (var o = 1; o <= 8; o++) {
          final up = uprightSize(w, h, o);
          const rect = PxRect(5, 3, 11, 7);
          final raw = uprightToRaw(rect, o, w, h);
          final shown = <(int, int)>{};
          for (var r = raw.top; r < raw.bottom; r++) {
            for (var c = raw.left; c < raw.right; c++) {
              shown.add(forward(o, c, r, w, h));
            }
          }
          final expected = <(int, int)>{
            for (var y = rect.top; y < rect.bottom; y++)
              for (var x = rect.left; x < rect.right; x++) (x, y),
          };
          expect(shown, expected, reason: 'orientation $o');
          expect(raw.left >= 0 && raw.top >= 0, isTrue);
          expect(raw.right <= w && raw.bottom <= h, isTrue, reason: 'o=$o $up');
        }
      },
    );
  });
}
