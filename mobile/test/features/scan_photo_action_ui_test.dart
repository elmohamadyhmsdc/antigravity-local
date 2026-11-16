import 'dart:async';

import 'package:antigravity_mobile/data/media/media_library.dart';
import 'package:antigravity_mobile/domain/scan/scan_engine.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:antigravity_mobile/features/scan/redetect_flow.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest('redetect explains the wait and continues the running scan', (
    tester,
    env,
  ) async {
    env.library.addAlbum(
      const AlbumInfo(id: 'cam', name: 'Camera', count: 2),
      syntheticAssets(2),
    );
    final target = await seedMedia(env.db, asset: 'already-scanned');
    late ScanEngine engine;
    final container = ProviderContainer(
      overrides: [
        ...env.overrides,
        scanEngineProvider.overrideWith((_) => engine),
      ],
    );
    await container.read(appSettingsProvider).setAlbumIds(['cam']);
    engine = ScanEngine(
      library: container.read(libraryRepositoryProvider),
      media: env.library,
      api: () => env.api,
      settings: container.read(appSettingsProvider),
      store: container.read(photoResultStoreProvider),
      grouping: container.read(groupingRunnerProvider),
    );
    container.read(scanEngineLinkProvider).engine = engine;
    addTearDown(container.dispose);
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    env.api.analyzeHandler = (_, _) async {
      if (first) {
        first = false;
        entered.complete();
        await release.future;
      }
      return analysis(faces: []);
    };
    final scan = engine.start();
    await entered.future;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => redetectFlow(context, ref, mediaId: target),
                child: const Text('Detect again'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detect again'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('redetect-both')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Waiting for the current scan item to finish…'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(env.api.analyzeCalls, hasLength(1));
    expect(engine.progress.pausing, isFalse);
    release.complete();
    for (
      var i = 0;
      i < 100 && engine.progress.phase != ScanPhase.completed;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(engine.progress.phase, ScanPhase.completed);
    await scan;
    await tester.pumpAndSettle();
    expect(engine.progress.phase, ScanPhase.completed);
    expect(engine.progress.done, 2);
    expect(env.api.analyzeCalls, hasLength(3));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Detect again'), findsOneWidget);
    await engine.dispose();
  }, session: testSession);
}
