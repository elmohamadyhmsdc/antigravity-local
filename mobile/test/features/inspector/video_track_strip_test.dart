import 'package:antigravity_mobile/data/repositories/media_queries.dart';
import 'package:antigravity_mobile/features/inspector/video_track_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('VideoTrackStrip renders markers and handles seek tap', (
    tester,
  ) async {
    const d1 = MediaDetection(
      id: 101,
      kind: 'f',
      refId: 1,
      x: 0.2,
      y: 0.2,
      w: 0.1,
      h: 0.1,
      personId: 5,
      cropPath: null,
      timestampMs: 3000,
    );
    const d2 = MediaDetection(
      id: 102,
      kind: 'b',
      refId: 2,
      x: 0.4,
      y: 0.4,
      w: 0.2,
      h: 0.4,
      personId: null,
      cropPath: null,
      timestampMs: 7000,
    );

    int? seekPosition;
    MediaDetection? selectedDetection;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoTrackStrip(
            durationMs: 10000,
            currentPositionMs: 2000,
            detections: const [d1, d2],
            selectedDetectionId: 101,
            onSeek: (pos) => seekPosition = pos,
            onSelect: (d) => selectedDetection = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('video-track-strip')), findsOneWidget);
    expect(find.byKey(const Key('track-marker-101')), findsOneWidget);
    expect(find.byKey(const Key('track-marker-102')), findsOneWidget);

    // Tap marker 102
    await tester.tap(find.byKey(const Key('track-marker-102')));
    await tester.pumpAndSettle();

    expect(seekPosition, 7000);
    expect(selectedDetection?.id, 102);
  });
}
