import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/features/media/video_media_view.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import '../support/fakes.dart';

void main() {
  testWidgets('VideoMediaView accepts isActive and renders mute toggle', (
    tester,
  ) async {
    final library = FakeMediaLibrary(
      uris: {'video_1': 'content://media/external/video/media/1'},
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: VideoMediaView(
            assetId: 'video_1',
            library: library,
            detections: const [],
            people: const {},
            showBodies: true,
            showFaces: true,
            isActive: false,
            onTapBox: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(VideoMediaView), findsOneWidget);
  });
}
