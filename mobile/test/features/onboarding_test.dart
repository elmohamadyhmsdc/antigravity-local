// S01 Welcome / Pair and S02 Permissions: QR, typed address with fingerprint confirmation,
// tapped links, failures, and the permission rows.

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/platform/platform_services.dart';
import 'package:antigravity_mobile/features/onboarding/qr_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

final _fp = 'ab12cd34' * 8;
String _link({
  String host = '192.168.1.20',
  String code = 'K7QM-3XRD',
  String? fp,
}) => 'agmobile://pair?h=$host&p=8443&fp=${fp ?? _fp}&c=$code';

/// Stands in for the camera: one button per "scanned" text.
QrScannerBuilder _fakeScanner(List<String> codes) =>
    (context, onCode) => Column(
      children: [
        for (final c in codes)
          TextButton(
            key: Key('scan:$c'),
            onPressed: () => onCode(c),
            child: Text('scan $c'),
          ),
      ],
    );

void main() {
  group('S01 Welcome', () {
    appTest(
      'a fresh install starts on the Welcome screen with both ways to pair',
      (tester, env) async {
        await env.pump(tester);
        expect(find.text('Connect to your PC'), findsOneWidget);
        expect(find.text('Scan QR code'), findsOneWidget);
        expect(find.text('Enter address manually'), findsOneWidget);
        expect(
          find.byType(NavigationBar),
          findsNothing,
          reason: 'no tabs before a PC is paired',
        );
      },
    );

    appTest('a paired phone starts on Home', (tester, env) async {
      await env.pump(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Connect to your PC'), findsNothing);
    }, session: testSession);
  });

  group('typed address', () {
    appTest('validates every field before touching the network', (
      tester,
      env,
    ) async {
      await env.pump(tester);
      await tester.tap(find.text('Enter address manually'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      expect(find.text("Enter the PC's address."), findsOneWidget);
      expect(
        find.text('The code has 8 letters and digits, like K7QM-3XRD.'),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('host')), '8.8.8.8');
      await tester.enterText(find.byKey(const Key('code')), 'K7QM-3XRD');
      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      expect(
        textContaining('must be on your Wi-Fi'),
        findsOneWidget,
        reason: 'public addresses are refused',
      );

      await tester.enterText(find.byKey(const Key('host')), '192.168.1.20');
      await tester.enterText(find.byKey(const Key('port')), '70000');
      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a port between 1 and 65535.'), findsOneWidget);
      expect(env.pairing.probeCalls, isEmpty);
    });

    appTest(
      'shows the certificate fingerprint, pairs only after the user confirms, then asks for permissions',
      (tester, env) async {
        await env.pump(tester);
        await tester.tap(find.text('Enter address manually'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('host')), '192.168.1.20');
        await tester.enterText(find.byKey(const Key('code')), 'k7qm3xrd');
        await tester.tap(find.byKey(const Key('connect')));
        await tester.pumpAndSettle();

        expect(env.pairing.probeCalls, [('192.168.1.20', 8443)]);
        expect(find.text('Is this your PC?'), findsOneWidget);
        expect(
          env.pairing.completeCalls,
          isEmpty,
          reason:
              'the code is not sent before the user confirms the fingerprint',
        );
        final shown = tester
            .widget<SelectableText>(find.byKey(const Key('fingerprint')))
            .data!;
        expect(
          shown.replaceAll(' ', '').toLowerCase(),
          env.pairing.fingerprint,
        );
        expect(
          shown,
          startsWith('AB12 CD34'),
          reason: 'grouped for comparing with the PC screen',
        );

        await tester.tap(find.text('They match - pair'));
        await tester.pumpAndSettle();

        expect(env.pairing.completeCalls.single, {
          'host': '192.168.1.20',
          'port': 8443,
          'fingerprint': env.pairing.fingerprint,
          'code': 'K7QM-3XRD',
          'deviceName': 'Test phone',
        });
        expect(
          find.text('Permissions'),
          findsWidgets,
          reason: 'pairing continues to S02',
        );
        final saved = await env.db.latestServer();
        expect(
          (saved!.id, saved.host, saved.fingerprint),
          ('srv_7f3a91c2', '192.168.1.20', env.pairing.fingerprint),
        );
        expect(
          env.secrets.values.values.any((v) => v.startsWith('agm_')),
          isTrue,
          reason: 'token in the keystore',
        );
      },
    );

    appTest('cancelling the fingerprint check pairs nothing', (
      tester,
      env,
    ) async {
      await env.pump(tester);
      await tester.tap(find.text('Enter address manually'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host')), '192.168.1.20');
      await tester.enterText(find.byKey(const Key('code')), 'K7QM-3XRD');
      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(env.pairing.completeCalls, isEmpty);
      expect(await env.db.latestServer(), isNull);
      expect(
        find.text('Enter the address'),
        findsOneWidget,
        reason: 'still on the form',
      );
    });

    appTest('an unreachable PC explains what to check', (tester, env) async {
      env.pairing.probeError = ApiException.network(
        'Could not reach 192.168.1.20:8443. Is the PC server running?',
      );
      await env.pump(tester);
      await tester.tap(find.text('Enter address manually'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host')), '192.168.1.20');
      await tester.enterText(find.byKey(const Key('code')), 'K7QM-3XRD');
      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      expect(
        textContaining('Could not reach 192.168.1.20:8443'),
        findsOneWidget,
      );
      expect(find.text('Is this your PC?'), findsNothing);
    });

    appTest('a wrong code is reported and nothing is stored', (
      tester,
      env,
    ) async {
      env.pairing.completeError = const ApiException(
        code: 'invalid_code',
        message: 'Wrong pairing code (4 attempts left).',
        statusCode: 401,
      );
      await env.pump(tester);
      await tester.tap(find.text('Enter address manually'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('host')), '10.0.2.2');
      await tester.enterText(find.byKey(const Key('code')), 'AAAA-AAAA');
      await tester.tap(find.byKey(const Key('connect')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('They match - pair'));
      await tester.pumpAndSettle();
      expect(
        find.text('Wrong pairing code (4 attempts left).'),
        findsOneWidget,
      );
      expect(await env.db.latestServer(), isNull);
      expect(env.secrets.values, isEmpty);
    });
  });

  group('QR code', () {
    appTest(
      'a valid QR pairs straight away with the fingerprint it carries - no typing, no probe',
      (tester, env) async {
        await env.pump(
          tester,
          extra: [
            qrScannerBuilderProvider.overrideWithValue(_fakeScanner([_link()])),
          ],
        );
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('scan:${_link()}')));
        await tester.pumpAndSettle();

        expect(
          env.pairing.probeCalls,
          isEmpty,
          reason: 'the QR already carries the pinned fingerprint',
        );
        expect(env.pairing.completeCalls.single['fingerprint'], _fp);
        expect(env.pairing.completeCalls.single['code'], 'K7QM-3XRD');
        expect(find.text('Permissions'), findsWidgets);
      },
    );

    appTest('foreign or off-network QR codes are rejected', (
      tester,
      env,
    ) async {
      final codes = ['https://example.com/', _link(host: '8.8.8.8')];
      await env.pump(
        tester,
        extra: [
          qrScannerBuilderProvider.overrideWithValue(_fakeScanner(codes)),
        ],
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('scan:${codes[0]}')));
      await tester.pump();
      expect(
        find.text('That is not a Your Gallery pairing code.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('scan:${codes[1]}')));
      await tester.pumpAndSettle();
      expect(env.pairing.completeCalls, isEmpty);
    });

    appTest('the scanner offers a way out to manual entry', (
      tester,
      env,
    ) async {
      await env.pump(
        tester,
        extra: [qrScannerBuilderProvider.overrideWithValue(_fakeScanner([]))],
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enter address manually'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the address'), findsOneWidget);
    });
  });

  group('pairing links', () {
    // What Android hands Flutter when an agmobile:// link is tapped: the raw URI as the location.
    Future<void> openLink(WidgetTester tester, TestEnv env, String link) async {
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue(link)],
      );
    }

    appTest(
      'a tapped link never pairs silently: the user sees the address and can cancel',
      (tester, env) async {
        await openLink(tester, env, _link());
        expect(find.text('Pair with 192.168.1.20?'), findsOneWidget);
        expect(env.pairing.completeCalls, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(env.pairing.completeCalls, isEmpty);
        expect(find.text('Connect to your PC'), findsOneWidget);
      },
    );

    appTest('confirming the link pairs with the fingerprint it carries', (
      tester,
      env,
    ) async {
      await openLink(tester, env, _link());
      await tester.tap(find.text('Pair'));
      await tester.pumpAndSettle();
      expect(env.pairing.completeCalls.single['fingerprint'], _fp);
      expect(env.pairing.probeCalls, isEmpty);
      expect(find.text('Permissions'), findsWidgets);
    });

    appTest('a link to a server outside the home network is refused', (
      tester,
      env,
    ) async {
      await openLink(tester, env, _link(host: 'evil.example.com'));
      expect(find.text('Pair with evil.example.com?'), findsNothing);
      expect(textContaining('not valid'), findsOneWidget);
      expect(env.pairing.completeCalls, isEmpty);
    });
  });

  group('S02 Permissions', () {
    appTest('explains each permission and requests it on tap', (
      tester,
      env,
    ) async {
      env.pairing.fingerprint = _fp;
      await env.pump(
        tester,
        extra: [
          qrScannerBuilderProvider.overrideWithValue(_fakeScanner([_link()])),
        ],
      );
      await tester.tap(find.text('Scan QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('scan:${_link()}')));
      await tester.pumpAndSettle();

      expect(find.text('Photos and videos'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(
        textContaining('Only to scan the pairing QR code'),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsNWidgets(3));

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('perm-media')),
          matching: find.text('Allow'),
        ),
      );
      await tester.pumpAndSettle();
      expect(env.permissions.requested, [AppPermission.media]);
      expect(find.text('Allow'), findsNWidgets(2));
      expect(find.text('Allowed'), findsOneWidget);
    });

    appTest(
      'a blocked permission sends the user to Android settings; Continue works regardless',
      (tester, env) async {
        env.permissions.states[AppPermission.camera] = PermissionState.blocked;
        await env.pump(
          tester,
          extra: [
            qrScannerBuilderProvider.overrideWithValue(_fakeScanner([_link()])),
          ],
        );
        await tester.tap(find.text('Scan QR code'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('scan:${_link()}')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Blocked - open settings'));
        await tester.pumpAndSettle();
        expect(env.permissions.settingsOpened, 1);
        expect(env.permissions.requested, isEmpty);

        await tester.tap(find.byKey(const Key('permissions-continue')));
        await tester.pumpAndSettle();
        expect(
          find.byType(NavigationBar),
          findsOneWidget,
          reason: 'Home with the tab bar',
        );
        expect(find.byKey(const Key('status-chip')), findsOneWidget);
      },
    );
  });
}
