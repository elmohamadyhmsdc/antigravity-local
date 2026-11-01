import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest(
    'retry queues failed media without resuming a manual pause',
    (tester, env) async {
      await seedMedia(env.db, asset: 'failed', status: 'failed');
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/running-scan'),
          scanProgressProvider.overrideWith(
            (ref) => Stream.value(
              const ScanProgress(
                phase: ScanPhase.paused,
                pauseReason: PauseReason.user,
              ),
            ),
          ),
        ],
      );
      expect(find.text('You paused the scan.'), findsOneWidget);
      expect(find.text('Retry all'), findsOneWidget);
      await tester.tap(find.text('Retry all'));
      await tester.pumpAndSettle();
      expect(
        (await env.db.select(env.db.media).get()).single.scanStatus,
        'pending',
      );
      expect(find.text('You paused the scan.'), findsOneWidget);
    },
    session: testSession,
  );
}
