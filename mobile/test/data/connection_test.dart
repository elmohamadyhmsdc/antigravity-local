import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/connection_recovery.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/platform/lan_network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:antigravity_mobile/providers.dart';

import '../support/fakes.dart';

void main() {
  test(
    'a late response from a discarded connection check never uses a disposed provider',
    () async {
      final api = _DelayedApi();
      final container = ProviderContainer(
        overrides: [
          mobileApiProvider.overrideWithValue(api),
          initialSessionProvider.overrideWithValue(testSession),
        ],
      );
      final subscription = container.listen(serverStatusProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      container.invalidate(serverStatusProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(serverStatusProvider).value, isA<ServerReady>());
      subscription.close();
      container.dispose();
      api.first.complete(api.capabilities_);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    },
  );
  test(
    'hotspot route and broadcast use the connected prefix, including non-/24 LANs',
    () {
      const hotspot = LanInterface('swlan0', '10.183.49.227', 24);
      expect(hotspot.contains('10.183.49.149'), isTrue);
      expect(hotspot.contains('10.166.93.149'), isFalse);
      expect(hotspot.broadcast, '10.183.49.255');
      expect(
        const LanInterface('wlan0', '172.20.10.1', 28).broadcast,
        '172.20.10.15',
      );
      expect(
        lanSourceAddress('10.183.49.149', [
          const LanInterface('eth0', '10.2.1.1', 8),
          hotspot,
        ]),
        hotspot.address,
      );
      expect(lanSourceAddress('127.0.0.1', [hotspot]), isNull);
    },
  );

  test(
    'discovery rejects malformed, wrong-nonce and wrong-identity replies',
    () async {
      final server = await RawDatagramSocket.bind('127.0.0.1', 0);
      final events = server.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = server.receive()!;
        final request = jsonDecode(utf8.decode(packet.data)) as Map;
        void send(Object value) => server.send(
          utf8.encode(jsonEncode(value)),
          packet.address,
          packet.port,
        );
        final reply = {
          'service': 'antigravity-mobile',
          'version': 1,
          'nonce': request['nonce'],
          'server_id': testSession.serverId,
          'port': 8443,
          'name': 'PC',
        };
        send([]);
        send({...reply, 'nonce': 'bad'});
        send({...reply, 'server_id': 'srv_other'});
        send({...reply, 'port': 70000});
        send(reply);
        send(reply);
      });
      try {
        final found = await discoverLan(
          const [],
          serverId: testSession.serverId,
          port: server.port,
          targets: ['127.0.0.1'],
          duration: const Duration(milliseconds: 150),
        );
        expect(found, hasLength(1));
        expect(found.single.label, '127.0.0.1:8443');
      } finally {
        await events.cancel();
        server.close();
      }
    },
  );

  test(
    'an untrusted discovery identity cannot trigger an authenticated call',
    () async {
      final fake = _WrongIdentity();
      await expectLater(
        verifyEndpoint(
          testSession,
          const LanEndpoint('10.183.49.149', 8443),
          factory: (_) => fake,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(fake.capabilitiesCalls, 0);
      expect(testSession.host, '192.168.1.20');
    },
  );

  test(
    'verified reconnect changes only the endpoint and preserves credentials',
    () async {
      final result = await verifyEndpoint(
        testSession,
        const LanEndpoint('10.183.49.149', 9443),
        factory: (_) => FakeMobileApi(),
      );
      expect(result.session.host, '10.183.49.149');
      expect(result.session.port, 9443);
      expect(result.session.token, testSession.token);
      expect(result.session.fingerprint, testSession.fingerprint);
      expect(result.session.serverId, testSession.serverId);
    },
  );

  test('a public endpoint is rejected before making any connection', () async {
    var called = false;
    await expectLater(
      verifyEndpoint(
        testSession,
        const LanEndpoint('8.8.8.8', 8443),
        factory: (_) {
          called = true;
          return FakeMobileApi();
        },
      ),
      throwsA(isA<ApiException>()),
    );
    expect(called, isFalse);
  });
}

class _WrongIdentity extends FakeMobileApi {
  var capabilitiesCalls = 0;
  @override
  Future<Health> health() async =>
      const Health(serverId: 'srv_wrong', name: 'Wrong PC', apiVersion: '1.0');
  @override
  Future<Capabilities> capabilities() {
    capabilitiesCalls++;
    return super.capabilities();
  }
}

class _DelayedApi extends FakeMobileApi {
  final first = Completer<Capabilities>();
  var calls = 0;
  @override
  Future<Capabilities> capabilities() =>
      calls++ == 0 ? first.future : Future.value(capabilities_);
}
