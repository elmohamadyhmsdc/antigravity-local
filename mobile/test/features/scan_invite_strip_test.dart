import 'package:antigravity_mobile/data/repositories/library_repository.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/library/scan_invite_strip.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScanInviteStrip', () {
    testWidgets('is hidden when pending count is 0', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scanCountsProvider.overrideWith(
              (ref) => Stream.value(const ScanCounts(pending: 0)),
            ),
            scanProgressProvider.overrideWith(
              (ref) => Stream.value(const ScanProgress(phase: ScanPhase.idle)),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(body: ScanInviteStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-invite-strip')), findsNothing);
    });

    testWidgets('is visible when pending count > 0 and scan is idle', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scanCountsProvider.overrideWith(
              (ref) => Stream.value(const ScanCounts(pending: 42)),
            ),
            scanProgressProvider.overrideWith(
              (ref) => Stream.value(const ScanProgress(phase: ScanPhase.idle)),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(body: ScanInviteStrip()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan-invite-strip')), findsOneWidget);
      expect(find.text('42 unanalyzed items'), findsOneWidget);
      expect(find.byKey(const Key('scan-invite-start')), findsOneWidget);
    });

    testWidgets('is hidden when scan is actively running even if pending > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scanCountsProvider.overrideWith(
              (ref) => Stream.value(const ScanCounts(pending: 42)),
            ),
            scanProgressProvider.overrideWith(
              (ref) => Stream.value(
                const ScanProgress(
                  phase: ScanPhase.running,
                  total: 100,
                  done: 50,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(body: ScanInviteStrip()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('scan-invite-strip')), findsNothing);
    });
  });
}
