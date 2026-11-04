import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/bodies/pose_visuals.dart';

void main() {
  test(
    'overlay follows the padded crop and BoxFit without clamping joints',
    () {
      const box = (x: .2, y: .1, w: .4, h: .8);
      const source = Size(1000, 1000);
      const viewport = Size(300, 400);
      // Body crops add 6% horizontally and 4% vertically.
      final corner = bodyCropOverlayPoint(
        const Offset(.176, .068),
        box,
        source,
        viewport,
        BoxFit.contain,
      );
      expect(corner.dx, inInclusiveRange(40, 50));
      expect(corner.dy, closeTo(0, 1e-6));
      for (final fit in [BoxFit.contain, BoxFit.cover]) {
        final center = bodyCropOverlayPoint(
          const Offset(.4, .5),
          box,
          source,
          viewport,
          fit,
        );
        expect(center.dx, closeTo(150, 1e-6));
        expect(center.dy, closeTo(200, 1e-6));
      }
      expect(
        bodyCropOverlayPoint(
          const Offset(-1, -1),
          box,
          source,
          viewport,
          BoxFit.contain,
        ).dy,
        lessThan(0),
      );
    },
  );
  testWidgets(
    'BodyCropAnnotatedView renders crop and handles skeleton and area toggles',
    (tester) async {
      final kpts = jsonEncode([
        [0.5, 0.2, 0.9],
        [0.48, 0.18, 0.9],
        [0.52, 0.18, 0.9],
        [0.46, 0.18, 0.9],
        [0.54, 0.18, 0.9],
        [0.42, 0.3, 0.9],
        [0.58, 0.3, 0.9],
        [0.38, 0.45, 0.9],
        [0.62, 0.45, 0.9],
        [0.35, 0.6, 0.9],
        [0.65, 0.6, 0.9],
        [0.45, 0.6, 0.9],
        [0.55, 0.6, 0.9],
        [0.45, 0.8, 0.9],
        [0.55, 0.8, 0.9],
        [0.45, 0.98, 0.9],
        [0.55, 0.98, 0.9],
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: BodyCropAnnotatedView(
                kpts: kpts,
                bbox: (x: 0.3, y: 0.1, w: 0.4, h: 0.8),
                showSkeleton: true,
                showArea: true,
                area: 'chest',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(BodyCropAnnotatedView), findsOneWidget);
      expect(
        find.byKey(const Key('body-crop-skeleton-painter')),
        findsOneWidget,
      );
    },
  );
}
