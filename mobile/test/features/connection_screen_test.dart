import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/connection_recovery.dart';
import 'package:antigravity_mobile/data/platform/lan_network.dart';
import 'package:antigravity_mobile/providers.dart';
import 'package:antigravity_mobile/features/settings/connection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

class _Network implements LanNetwork {
  @override
  bool get supported => true;
  @override
  Future<List<LanInterface>> interfaces() async => [
    const LanInterface('swlan0', '10.183.49.227', 24),
  ];
  @override
  Future<List<LanEndpoint>> discover({String? serverId}) async => const [];
}

void main() {
  appTest(
    'connection help is reachable before pairing and explains hotspot/discovery fallback',
    (tester, env) async {
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/connection'),
          lanNetworkProvider.overrideWithValue(_Network()),
        ],
      );
      expect(find.text('Connection help'), findsOneWidget);
      await tester.tap(find.byKey(const Key('connection-find')));
      await tester.pumpAndSettle();
      expect(textContaining('No PC answered local discovery'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Phone shares its hotspot'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('10.183.49.227/24'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('USB fallback'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(textContaining('uses no mobile data'), findsOneWidget);
    },
  );

  for (final valid in [true, false]) {
    appTest(
      'editing an endpoint verifies identity and preserves the saved pairing: valid=$valid',
      (tester, env) async {
        final calls = <String>[];
        await env.pump(
          tester,
          extra: [
            initialLocationProvider.overrideWithValue('/connection'),
            lanNetworkProvider.overrideWithValue(_Network()),
            endpointVerifierProvider.overrideWithValue((saved, endpoint) async {
              calls.add(endpoint.host);
              if (!valid) throw ApiException.certificate();
              return VerifiedEndpoint(
                saved.copyWith(host: endpoint.host, port: endpoint.port),
                env.api.capabilities_,
              );
            }),
          ],
        );
        await tester.enterText(
          find.byKey(const Key('connection-host')),
          '10.183.49.149',
        );
        await tester.ensureVisible(find.byKey(const Key('connection-test')));
        await tester.tap(find.byKey(const Key('connection-test')));
        await tester.pumpAndSettle();
        final scope = ProviderScope.containerOf(
          tester.element(find.byType(ConnectionScreen)),
        );
        expect(calls, ['10.183.49.149']);
        expect(
          scope.read(sessionProvider)!.host,
          valid ? '10.183.49.149' : testSession.host,
        );
        expect(scope.read(sessionProvider)!.token, testSession.token);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.textContaining('This is not the PC'),
          ),
          valid ? findsNothing : findsOneWidget,
        );
      },
      session: testSession,
    );
  }
}
