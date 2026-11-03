import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/curation/auto_dataset_curator.dart';
import 'package:antigravity_mobile/features/lora/curation_controller.dart';
import 'package:antigravity_mobile/features/lora/curation_review_screen.dart';

void main() {
  group('CurationReviewScreen', () {
    testWidgets('renders candidates, filter tabs, and handles delete with undo', (
      tester,
    ) async {
      const cFace = CurationCandidate(
        detectionId: 101,
        mediaId: 1,
        assetId: 'face_asset',
        isVideo: false,
        category: CurationCategory.face,
        quality: 0.9,
      );
      const cUpper = CurationCandidate(
        detectionId: 102,
        mediaId: 2,
        assetId: 'upper_asset',
        isVideo: false,
        category: CurationCategory.upper,
        quality: 0.8,
      );
      const cBody = CurationCandidate(
        detectionId: 103,
        mediaId: 3,
        assetId: 'body_asset',
        isVideo: true,
        timestampMs: 14000,
        category: CurationCategory.body,
        hasExposedRegion: true,
        quality: 0.85,
      );

      final initialState = CurationState(
        personId: 42,
        personName: 'Sara',
        faces: [cFace],
        upper: [cUpper],
        body: [cBody],
        triggerWord: 'sks_sara',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            curationControllerProvider.overrideWith(
              () => CurationNotifier(initialState: initialState),
            ),
          ],
          child: const MaterialApp(
            home: CurationReviewScreen(personId: 42, personName: 'Sara'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Header and Live Status Pill
      expect(find.byKey(const Key('curation-status-pill')), findsOneWidget);
      expect(find.textContaining('3'), findsAtLeast(1));

      // 2. Verify Badges
      expect(find.byKey(const Key('badge-exposed-103')), findsOneWidget);
      expect(find.byKey(const Key('badge-video-103')), findsOneWidget);

      // 3. Verify Category Tabs
      expect(find.byKey(const Key('curation-tab-all')), findsOneWidget);
      expect(find.byKey(const Key('curation-tab-face')), findsOneWidget);
      expect(find.byKey(const Key('curation-tab-body')), findsOneWidget);

      // 4. Test Category Filter
      await tester.tap(find.byKey(const Key('curation-tab-body')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('curation-card-103')), findsOneWidget);
      expect(find.byKey(const Key('curation-card-101')), findsNothing);

      // Switch back to All
      await tester.tap(find.byKey(const Key('curation-tab-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('curation-card-101')), findsOneWidget);

      // 5. Test Delete and Undo
      expect(find.byKey(const Key('curation-delete-101')), findsOneWidget);
      await tester.tap(find.byKey(const Key('curation-delete-101')));
      await tester.pumpAndSettle();

      // Face card removed, Undo snackbar displayed
      expect(find.byKey(const Key('curation-card-101')), findsNothing);
      expect(find.byKey(const Key('curation-undo')), findsOneWidget);

      // Tap Undo
      await tester.tap(find.byKey(const Key('curation-undo')));
      await tester.pumpAndSettle();

      // Face card restored
      expect(find.byKey(const Key('curation-card-101')), findsOneWidget);

      // 6. Test Settings Drawer
      await tester.tap(find.byKey(const Key('curation-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('curation-trigger-input')), findsOneWidget);
      expect(find.text('sks_sara'), findsOneWidget);
    });
  });
}
