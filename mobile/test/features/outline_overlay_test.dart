import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/domain/geometry/outline.dart';
import 'package:antigravity_mobile/features/analyze/analyze_screen.dart';
import 'package:antigravity_mobile/features/review/review_media_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('outline overlays & painters', () {
    test('ReviewHighlightPainter carries outline and shouldRepaint compares outline', () {
      final outline1 = [const Offset(0.1, 0.1), const Offset(0.9, 0.1), const Offset(0.5, 0.9)];
      final outline2 = [const Offset(0.2, 0.2), const Offset(0.8, 0.2), const Offset(0.5, 0.8)];

      final p1 = ReviewHighlightPainter(
        const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
        label: 'Face',
        isFace: true,
        outline: outline1,
      );
      final p1Same = ReviewHighlightPainter(
        const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
        label: 'Face',
        isFace: true,
        outline: [const Offset(0.1, 0.1), const Offset(0.9, 0.1), const Offset(0.5, 0.9)],
      );
      final p2 = ReviewHighlightPainter(
        const Rect.fromLTWH(0.1, 0.1, 0.5, 0.5),
        label: 'Face',
        isFace: true,
        outline: outline2,
      );

      expect(p1.outline, outline1);
      expect(p1.shouldRepaint(p1Same), isFalse);
      expect(p1.shouldRepaint(p2), isTrue);
    });

    test('DetectionBoxPainter carries outline and shouldRepaint compares outline', () {
      final outline1 = [const Offset(0.1, 0.1), const Offset(0.9, 0.1), const Offset(0.5, 0.9)];
      final outline2 = [const Offset(0.2, 0.2), const Offset(0.8, 0.2), const Offset(0.5, 0.8)];

      const painterNoOutline = DetectionBoxPainter(
        isFace: true,
        borderColor: Colors.amber,
      );
      final painterWithOutline1 = DetectionBoxPainter(
        isFace: true,
        borderColor: Colors.amber,
        outline: outline1,
      );
      final painterWithOutline2 = DetectionBoxPainter(
        isFace: true,
        borderColor: Colors.amber,
        outline: outline2,
      );

      expect(painterNoOutline.outline, isNull);
      expect(painterWithOutline1.outline, outline1);
      expect(painterWithOutline1.shouldRepaint(painterNoOutline), isTrue);
      expect(painterWithOutline1.shouldRepaint(painterWithOutline2), isTrue);
      expect(
        painterWithOutline1.shouldRepaint(
          DetectionBoxPainter(
            isFace: true,
            borderColor: Colors.amber,
            outline: [const Offset(0.1, 0.1), const Offset(0.9, 0.1), const Offset(0.5, 0.9)],
          ),
        ),
        isFalse,
      );
    });

    testWidgets('DetectionBoxPainter renders without error for face and body', (tester) async {
      final outline = [
        const Offset(0.2, 0.1),
        const Offset(0.8, 0.15),
        const Offset(0.85, 0.75),
        const Offset(0.5, 0.9),
        const Offset(0.15, 0.6),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                children: [
                  CustomPaint(
                    key: const Key('face-paint'),
                    size: const Size(100, 100),
                    painter: DetectionBoxPainter(
                      isFace: true,
                      outline: outline,
                      borderColor: Colors.greenAccent,
                      fillColor: Colors.greenAccent.withValues(alpha: 0.15),
                      borderWidth: 3,
                    ),
                  ),
                  CustomPaint(
                    key: const Key('body-paint'),
                    size: const Size(100, 200),
                    painter: DetectionBoxPainter(
                      isFace: false,
                      outline: outline,
                      borderColor: Colors.lightBlueAccent,
                      fillColor: Colors.lightBlueAccent.withValues(alpha: 0.18),
                      borderWidth: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final facePaint = tester.widget<CustomPaint>(find.byKey(const Key('face-paint')));
      final bodyPaint = tester.widget<CustomPaint>(find.byKey(const Key('body-paint')));

      expect((facePaint.painter as DetectionBoxPainter).outline, outline);
      expect((facePaint.painter as DetectionBoxPainter).isFace, isTrue);

      expect((bodyPaint.painter as DetectionBoxPainter).outline, outline);
      expect((bodyPaint.painter as DetectionBoxPainter).isFace, isFalse);
    });

    testWidgets('DetectionsPainter paints with outline and without outline', (tester) async {
      final responseWithOutlines = AnalyzeImageResponse(
        modelId: 'buffalo_l@1',
        imageW: 1000,
        imageH: 800,
        faces: [
          DetectedFace(
            bbox: const BBox(x: 100, y: 100, w: 200, h: 200),
            kps: const [
              [150.0, 150.0],
              [180.0, 150.0],
              [165.0, 170.0],
              [155.0, 190.0],
              [175.0, 190.0],
            ],
            detScore: 0.95,
            embedding: Float32List(512),
            quality: const FaceQuality(score: 0.85, version: 2, facePx: 150, sharpness: 250, detScore: 0.95, embeddingNorm: 1.0, pose: null, parts: {}),
            passesGate: true,
            outline: const [
              Offset(120, 110),
              Offset(280, 110),
              Offset(290, 280),
              Offset(110, 280),
            ],
          ),
        ],
        bodies: [
          DetectedBody(
            bbox: const BBox(x: 50, y: 60, w: 400, h: 700),
            score: 0.9,
            outline: const [
              Offset(60, 70),
              Offset(440, 70),
              Offset(440, 750),
              Offset(60, 750),
            ],
          ),
        ],
        pairs: const [FaceBodyPair(faceIndex: 0, bodyIndex: 0, score: 0.9)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomPaint(
              key: const Key('analyze-paint'),
              size: const Size(500, 400),
              painter: DetectionsPainter(
                result: responseWithOutlines,
                faceColor: Colors.green,
                skippedColor: Colors.amber,
                bodyColor: Colors.blue,
              ),
            ),
          ),
        ),
      );

      final paintWidget = tester.widget<CustomPaint>(find.byKey(const Key('analyze-paint')));
      expect(paintWidget.painter, isA<DetectionsPainter>());
      final painter = paintWidget.painter as DetectionsPainter;
      expect(painter.result.faces.single.outline, hasLength(4));
      expect(painter.result.bodies.single.outline, hasLength(4));
    });

    test('MediaDetection preserves outline field', () {
      const det = MediaDetection(
        id: 1,
        kind: 'f',
        refId: 2,
        x: 0.1,
        y: 0.1,
        w: 0.2,
        h: 0.2,
        personId: 3,
        cropPath: 'faces/2.jpg',
        outline: [Offset(0.15, 0.15), Offset(0.25, 0.25), Offset(0.2, 0.3)],
      );
      expect(det.outline, hasLength(3));
      expect(det.isFace, isTrue);
    });
  });
}
