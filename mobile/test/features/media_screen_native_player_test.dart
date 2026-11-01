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
  testWidgets('MediaScreen shows native player button for videos and launches intent', (tester) async {
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

    MethodCall? playerCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('antigravity/video_player'),
      (call) async {
        playerCall = call;
        return true;
      },
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

    final playerButton = find.byKey(const Key('media-open-native-player'));
    expect(playerButton, findsOneWidget);

    await tester.tap(playerButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(playerCall, isNotNull);
    expect(playerCall?.method, 'openNativePlayer');
    expect(playerCall?.arguments['uri'], 'content://media/external/video/media/42');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
