import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/bodies/pose_visuals.dart';

void main() {
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
