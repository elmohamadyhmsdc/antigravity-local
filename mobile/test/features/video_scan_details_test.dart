import 'package:antigravity_mobile/domain/scan/video_scan_progress.dart';
import 'package:antigravity_mobile/features/scan/video_scan_details.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    VideoScanProgress progress, {
    bool active = true,
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VideoScanDetails(progress: progress, active: active),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('upload shows stage bytes, speed and measured stage ETA', (
    tester,
  ) async {
    final now = DateTime.now();
    await show(
      tester,
      VideoScanProgress(
        stage: VideoScanStage.upload,
        startedAt: now.subtract(const Duration(minutes: 2)),
        stageStartedAt: now.subtract(const Duration(seconds: 30)),
        updatedAt: now,
        fraction: 0.4,
        processedBytes: 400 * 1024 * 1024,
        totalBytes: 1000 * 1024 * 1024,
        bytesPerSecond: 10 * 1024 * 1024,
        eta: const Duration(minutes: 1),
        fileName: 'holiday.mp4',
        fileBytes: 1000 * 1024 * 1024,
        width: 1920,
        height: 1080,
      ),
    );
    expect(find.text('400.0 MB / 1000.0 MB'), findsOneWidget);
    expect(find.text('holiday.mp4'), findsOneWidget);
    expect(find.text('1000.0 MB · 1920 × 1080'), findsOneWidget);
    expect(find.text('10.0 MB/s'), findsOneWidget);
    expect(find.text('About 1:00'), findsOneWidget);
    expect(find.text('40% of this stage'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const Key('video-stage-progress')),
          )
          .value,
      0.4,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'waiting has no invented percent and stale transfers explain the wait',
    (tester) async {
      final now = DateTime.now();
      await show(
        tester,
        VideoScanProgress(
          stage: VideoScanStage.queue,
          startedAt: now.subtract(const Duration(minutes: 3)),
          stageStartedAt: now.subtract(const Duration(seconds: 25)),
          updatedAt: now.subtract(const Duration(seconds: 25)),
          serverMessage: 'Resource protection: waiting for available RAM.',
        ),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('video-stage-progress')),
            )
            .value,
        isNull,
      );
      expect(find.textContaining('Resource protection'), findsOneWidget);
      expect(find.byKey(const Key('video-awaiting-update')), findsOneWidget);
      expect(find.textContaining('% of this stage'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'analysis measurements and live results fit narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      await show(
        tester,
        VideoScanProgress(
          stage: VideoScanStage.analyze,
          startedAt: now,
          stageStartedAt: now,
          updatedAt: now,
          fraction: 0.5,
          durationMs: 7200000,
          analyzedTimestampMs: 3600000,
          framesDone: 360,
          totalSamples: 720,
          frameInterval: 10,
          framesSaved: 350,
          facesFound: 1234,
          bodiesFound: 567,
          charactersFound: 12,
          skippedSamples: 2,
          warning: 'Two unreadable samples were skipped.',
          incrementalResults: true,
          serverStage: 'inference',
          serverUpdatedAt: now,
        ),
        scale: 1.5,
      );
      expect(find.text('1:00:00 / 2:00:00'), findsOneWidget);
      expect(find.text('362 / 720'), findsOneWidget);
      expect(
        find.text('1234 faces · 567 bodies · 12 characters'),
        findsOneWidget,
      );
      expect(find.text('One frame every 10.00 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
