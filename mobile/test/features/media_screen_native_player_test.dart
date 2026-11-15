import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/features/media/media_screen.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:antigravity_mobile/providers.dart';
import '../support/fakes.dart';
import '../support/seed.dart';

void main() {
  testWidgets(
    'gallery video can use the in-app Android player or an external player',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final mediaId = await seedMedia(
        db,
        asset: 'video_asset_1',
        kind: 'video',
        status: 'done',
      );

      final library = FakeMediaLibrary(
        uris: {'video_asset_1': 'content://media/external/video/media/42'},
      );

      const channel = MethodChannel('antigravity/video_player');
      MethodCall? playerCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async {
              playerCall = call;
              return true;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mediaLibraryProvider.overrideWithValue(library),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: MediaScreen(mediaId: mediaId),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final play = find.byKey(const Key('media-play-video'));
      expect(play, findsOneWidget);
      expect(playerCall, isNull);
      await tester.tap(play);
      await tester.pump();
      expect(playerCall?.method, 'playNativeVideo');
      expect(
        playerCall?.arguments['uri'],
        'content://media/external/video/media/42',
      );

      final playerButton = find.byKey(const Key('media-open-native-player'));
      expect(playerButton, findsOneWidget);

      await tester.tap(playerButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(playerCall, isNotNull);
      expect(playerCall?.method, 'openNativePlayer');
      expect(
        playerCall?.arguments['uri'],
        'content://media/external/video/media/42',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
