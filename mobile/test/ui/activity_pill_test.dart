import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/ui/activity/activity_pill.dart';
import 'package:antigravity_mobile/ui/activity/activity_state_provider.dart';

Widget _buildPillWithState(
  ActivityState state, {
  VoidCallback? onTap,
  bool enabled = true,
}) {
  return ProviderScope(
    overrides: [activityStateProvider.overrideWithValue(state)],
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: ActivityPill(onTap: onTap, enabled: enabled),
        ),
      ),
    ),
  );
}

void main() {
  group('ActivityPill Component', () {
    testWidgets('renders nothing when activity is idle', (tester) async {
      await tester.pumpWidget(_buildPillWithState(const ActivityIdle()));
      expect(find.byKey(const Key('activity-pill')), findsNothing);
    });

    testWidgets('renders scanning state with count and progress bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildPillWithState(const ActivityScanning(done: 15, total: 60)),
      );

      expect(find.byKey(const Key('activity-pill')), findsOneWidget);
      expect(find.text('Scanning 15 / 60'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders job state with type and percentage', (tester) async {
      await tester.pumpWidget(
        _buildPillWithState(
          const ActivityJob(id: 'job-1', type: 'reface_image', progress: 0.75),
        ),
      );

      expect(find.byKey(const Key('activity-pill')), findsOneWidget);
      expect(find.text('reface_image 75%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders multiple active tasks indicator with count badge', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildPillWithState(
          const ActivityMultiple(
            primaryDescription: 'Scanning (10/50)',
            extraCount: 2,
          ),
        ),
      );

      expect(find.byKey(const Key('activity-pill')), findsOneWidget);
      expect(find.text('Scanning (10/50) (+2)'), findsOneWidget);
    });

    testWidgets('renders failed state with error message', (tester) async {
      await tester.pumpWidget(
        _buildPillWithState(
          const ActivityFailed(message: 'Connection timed out', jobId: 'job-9'),
        ),
      );

      expect(find.byKey(const Key('activity-pill')), findsOneWidget);
      expect(find.text('Connection timed out'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('tap triggers onTap callback when enabled', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildPillWithState(
          const ActivityScanning(done: 1, total: 10),
          onTap: () => tapped = true,
          enabled: true,
        ),
      );

      await tester.tap(find.byKey(const Key('activity-pill')));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('tap is disabled when enabled is false (popup route active)', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _buildPillWithState(
          const ActivityScanning(done: 1, total: 10),
          onTap: () => tapped = true,
          enabled: false,
        ),
      );

      await tester.tap(find.byKey(const Key('activity-pill')));
      await tester.pump();

      expect(tapped, isFalse);
    });
  });
}
