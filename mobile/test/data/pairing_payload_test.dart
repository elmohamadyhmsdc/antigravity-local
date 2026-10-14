import 'package:antigravity_mobile/data/api/lan_host.dart';
import 'package:antigravity_mobile/data/api/pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

final _fp = 'ab12cd34' * 8;

void main() {
  group('PairingPayload.tryParse', () {
    test(
      'reads the exact format the PC puts in the QR (pairing.pair_payload)',
      () {
        final p = PairingPayload.tryParse(
          'agmobile://pair?h=192.168.1.20&p=8443&fp=$_fp&c=K7QM-3XRD',
        );
        expect(p, isNotNull);
        expect(
          (p!.host, p.port, p.fingerprint, p.code),
          ('192.168.1.20', 8443, _fp, 'K7QM-3XRD'),
        );
      },
    );

    test('tolerates fingerprint and code formatting', () {
      final p = PairingPayload.tryParse(
        'agmobile://pair?h=10.0.2.2&p=8443&fp=${_fp.toUpperCase().replaceAllMapped(RegExp('..'), (m) => '${m[0]}:').replaceFirst(RegExp(r':$'), '')}&c=k7qm3xrd',
      );
      expect(p!.fingerprint, _fp);
      expect(p.code, 'K7QM-3XRD');
    });

    test('rejects other schemes, missing or malformed fields', () {
      final bad = [
        null,
        '',
        'https://192.168.1.20/pair',
        'agmobile://other?h=192.168.1.20&p=8443&fp=$_fp&c=K7QM-3XRD',
        'agmobile://pair?p=8443&fp=$_fp&c=K7QM-3XRD', // no host
        'agmobile://pair?h=192.168.1.20&fp=$_fp&c=K7QM-3XRD', // no port
        'agmobile://pair?h=192.168.1.20&p=0&fp=$_fp&c=K7QM-3XRD',
        'agmobile://pair?h=192.168.1.20&p=70000&fp=$_fp&c=K7QM-3XRD',
        'agmobile://pair?h=192.168.1.20&p=8443&fp=abc&c=K7QM-3XRD', // short fingerprint
        'agmobile://pair?h=192.168.1.20&p=8443&fp=$_fp', // no code
        'agmobile://pair?h=192.168.1.20/evil&p=8443&fp=$_fp&c=K7QM-3XRD',
        'agmobile://pair?h=user@192.168.1.20&p=8443&fp=$_fp&c=K7QM-3XRD',
      ];
      for (final text in bad) {
        expect(PairingPayload.tryParse(text), isNull, reason: '$text');
      }
    });

    test('never accepts a server outside the home network', () {
      for (final host in [
        '8.8.8.8',
        'example.com',
        '203.0.113.7',
        '172.32.0.1',
        '192.169.1.1',
        'evil.example.org',
      ]) {
        expect(
          PairingPayload.tryParse(
            'agmobile://pair?h=$host&p=8443&fp=$_fp&c=K7QM-3XRD',
          ),
          isNull,
          reason: host,
        );
      }
    });
  });

  group('isLanHost', () {
    test('accepts private ranges, loopback, link-local and local names', () {
      for (final host in [
        '192.168.0.1',
        '192.168.255.254',
        '10.0.0.1',
        '10.0.2.2',
        '172.16.0.1',
        '172.31.255.1',
        '127.0.0.1',
        '169.254.10.10',
        'localhost',
        'my-pc.local',
        'DESKTOP-ABC',
        '::1',
        'fe80::1',
        'fd12:3456::1',
      ]) {
        expect(isLanHost(host), isTrue, reason: host);
      }
    });

    test('rejects public addresses and internet names', () {
      for (final host in [
        '',
        '8.8.8.8',
        '1.1.1.1',
        '172.15.0.1',
        '172.32.0.1',
        '300.1.1.1',
        'example.com',
        'a.b.c',
        '2001:db8::1',
      ]) {
        expect(isLanHost(host), isFalse, reason: host);
      }
    });
  });

  test('normalizeCode / normalizeFingerprint / formatFingerprint', () {
    expect(PairingPayload.normalizeCode(' k7qm 3xrd '), 'K7QM-3XRD');
    expect(PairingPayload.normalizeCode('K7QM'), 'K7QM');
    expect(PairingPayload.normalizeFingerprint('AB:12:' * 1), isNull);
    expect(PairingPayload.normalizeFingerprint(_fp), _fp);
    expect(formatFingerprint('abcdef012345', group: 4), 'ABCD EF01 2345');
  });
}
