import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/resources.dart';
import 'package:antigravity_mobile/data/api/resource_api.dart';
import 'package:antigravity_mobile/features/settings/resource_panel.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

class _Resources implements ResourceApi {
  int calls = 0;
  bool fail = false;

  @override
  Future<ResourceSnapshot> resources() async {
    calls++;
    if (fail) throw ApiException.network('Disconnected');
    return ResourceSnapshot.fromJson(fixture('ResourceSnapshot.idle'));
  }
}

Widget _app(_Resources api) => ProviderScope(
  overrides: [resourceApiProvider.overrideWithValue(api)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ListView(children: const [ResourcePanel()])),
  ),
);

void main() {
  testWidgets('collapsed panel does not poll; expansion shows PC readings', (
    tester,
  ) async {
    final api = _Resources();
    await tester.pumpWidget(_app(api));
    await tester.pump();
    expect(api.calls, 0);
    await tester.tap(find.text('PC resources'));
    await tester.pumpAndSettle();
    expect(api.calls, 1);
    expect(find.text('Application RAM (all PC workers)'), findsOneWidget);
    expect(find.text('Example NVIDIA GPU'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls, 1);
  });

  testWidgets('closing panel and backgrounding stop polling', (tester) async {
    final api = _Resources();
    await tester.pumpWidget(_app(api));
    await tester.tap(find.text('PC resources'));
    await tester.pumpAndSettle();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls, 1);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(api.calls, 2);
    await tester.tap(find.text('PC resources'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(api.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disconnect replaces old readings and offers retry', (
    tester,
  ) async {
    final api = _Resources();
    await tester.pumpWidget(_app(api));
    await tester.tap(find.text('PC resources'));
    await tester.pumpAndSettle();
    api.fail = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Example NVIDIA GPU'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('resource readings wrap at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_app(_Resources()));
    await tester.tap(find.text('PC resources'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
