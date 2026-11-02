import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/activity/activity_screen.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/ui/collection/segmented_bar.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  group('A1 ActivityScreen', () {
    appTest(
      'renders empty state when there are no running tasks or scans',
      (tester, env) async {
        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue('/activity'),
            scanProgressProvider.overrideWith(
              (ref) => Stream.value(const ScanProgress(phase: ScanPhase.idle)),
            ),
          ],
        );
        expect(find.text('No active activity'), findsOneWidget);
        expect(find.byType(ActivityScreen), findsOneWidget);
      },
      session: testSession,
    );

    appTest('shows active scan with pause and resume controls', (
      tester,
      env,
    ) async {
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/activity'),
          scanProgressProvider.overrideWith(
            (ref) => Stream.value(
              const ScanProgress(
                phase: ScanPhase.running,
                total: 10,
                done: 4,
                facesFound: 8,
                bodiesFound: 4,
              ),
            ),
          ),
        ],
      );
      expect(find.text('Library Scan'), findsOneWidget);
      expect(
        find.text('4 of 10 items scanned (8 faces, 4 bodies)'),
        findsOneWidget,
      );
      expect(find.text('Pause'), findsOneWidget);

      await tester.tap(find.text('Pause'));
      await tester.pump();
    }, session: testSession);

    appTest(
      'switches between Now and History tabs and filters history',
      (tester, env) async {
        await env.db
            .into(env.db.jobs)
            .insert(
              JobsCompanion.insert(
                id: 'job-1',
                serverId: testSession.serverId,
                type: 'reface_image',
                requestJson: '{}',
                targetPath: 'target.jpg',
                targetSha: 'a' * 64,
                targetSize: 1,
                status: 'completed',
                createdAt: DateTime.now().millisecondsSinceEpoch,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
        await env.db
            .into(env.db.jobs)
            .insert(
              JobsCompanion.insert(
                id: 'job-2',
                serverId: testSession.serverId,
                type: 'reface_video',
                requestJson: '{}',
                targetPath: 'target.mp4',
                targetSha: 'b' * 64,
                targetSize: 1,
                status: 'failed',
                error: const Value('GPU out of memory'),
                createdAt: DateTime.now().millisecondsSinceEpoch,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        await env.pump(
          tester,
          extra: [initialLocationProvider.overrideWithValue('/activity')],
        );

        // Switch to History tab
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();

        expect(find.text('Reface · Photo'), findsOneWidget);
        expect(find.text('Reface · Video'), findsOneWidget);
        expect(find.textContaining('GPU out of memory'), findsOneWidget);

        // Filter by Completed
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedBar<int>),
            matching: find.text('Completed'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reface · Photo'), findsOneWidget);
        expect(find.text('Reface · Video'), findsNothing);

        // Filter by Failed
        await tester.tap(
          find.descendant(
            of: find.byType(SegmentedBar<int>),
            matching: find.text('Failed'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Reface · Photo'), findsNothing);
        expect(find.text('Reface · Video'), findsOneWidget);
      },
      session: testSession,
    );

    appTest(
      'shows failed scan items sheet when failed scans exist',
      (tester, env) async {
        final mediaId = await seedMedia(
          env.db,
          asset: 'corrupt-photo.jpg',
          status: 'failed',
        );
        await (env.db.update(
          env.db.media,
        )..where((m) => m.id.equals(mediaId))).write(
          const MediaCompanion(scanError: Value('Corrupt JPEG header')),
        );

        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue('/activity'),
            scanProgressProvider.overrideWith(
              (ref) => Stream.value(
                const ScanProgress(
                  phase: ScanPhase.paused,
                  pauseReason: PauseReason.user,
                  total: 5,
                  done: 4,
                  failed: 1,
                ),
              ),
            ),
          ],
        );

        expect(find.text('1 files could not be scanned'), findsOneWidget);
        await tester.tap(find.text('1 files could not be scanned'));
        await tester.pumpAndSettle();

        expect(find.text('Failed Scan Items'), findsOneWidget);
        expect(find.text('corrupt-photo.jpg'), findsOneWidget);
        expect(find.text('Corrupt JPEG header'), findsOneWidget);
        expect(find.text('Retry scan'), findsOneWidget);
      },
      session: testSession,
    );
  });
}
