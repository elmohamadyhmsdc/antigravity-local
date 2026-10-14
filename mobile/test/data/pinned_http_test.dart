// Certificate pinning against a real local HTTPS server that uses a self-signed certificate
// (test/support/tls). The client must trust exactly the pinned SHA-256 and nothing else, and a
// wrong pin must abort the handshake before the bearer token is sent.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/api/pinned_http.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const _token = 'agm_0123456789abcdef0123456789abcdef01234567';

String _pemFingerprint(String path) {
  final body = File(
    path,
  ).readAsStringSync().split('\n').where((l) => !l.startsWith('-----')).join();
  return sha256.convert(base64Decode(body)).toString();
}

class _Seen {
  final requests = <HttpRequest>[];
  final bodies = <String, String>{};
}

void main() {
  final certPath = 'test/support/tls/test_server.crt';
  final keyPath = 'test/support/tls/test_server.key';
  late String realFingerprint;
  late HttpServer server;
  late _Seen seen;
  var gpuBusy = false;
  var dropNextRequest =
      false; // simulate a pooled connection the PC already closed

  ServerSession session({
    String? fingerprint,
    String token = _token,
    int? port,
  }) => ServerSession(
    serverId: 'srv_7f3a91c2',
    name: 'RTX-PC',
    host: '127.0.0.1',
    port: port ?? server.port,
    fingerprint: fingerprint ?? realFingerprint,
    token: token,
  );

  setUp(() async {
    gpuBusy = false;
    dropNextRequest = false;
    realFingerprint = _pemFingerprint(certPath);
    seen = _Seen();
    final context = SecurityContext()
      ..useCertificateChain(certPath)
      ..usePrivateKey(keyPath);
    server = await HttpServer.bindSecure('127.0.0.1', 0, context);
    server.listen((request) async {
      if (dropNextRequest) {
        dropNextRequest = false;
        // what a dead keep-alive connection looks like to the client: the request is swallowed and the socket dies
        (await request.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      seen.requests.add(request);
      final body = await utf8.decoder.bind(request).join();
      seen.bodies['${request.method} ${request.uri.path}'] = body;
      void json(
        int status,
        Object data, {
        Map<String, String> headers = const {},
      }) {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        headers.forEach(request.response.headers.set);
        request.response.write(jsonEncode(data));
        request.response.close();
      }

      final auth = request.headers.value('authorization');
      switch (request.uri.path) {
        case '/v1/health':
          json(200, fixture('Health.ok'));
        case '/v1/pair/complete':
          final sent = jsonDecode(body) as Map<String, dynamic>;
          sent['code'] == 'K7QM-3XRD'
              ? json(200, fixture('PairResponse.ok'))
              : json(401, fixture('Error.invalid_code'));
        case '/v1/capabilities':
          auth == 'Bearer $_token'
              ? json(200, fixture('Capabilities.idle'))
              : json(401, {
                  'error': {
                    'code': 'unauthorized',
                    'message': 'Missing or invalid device token.',
                    'retryable': false,
                  },
                });
        case '/v1/analyze/image':
          if (auth != 'Bearer $_token') {
            json(401, {
              'error': {
                'code': 'unauthorized',
                'message': 'no',
                'retryable': false,
              },
            });
          } else if (gpuBusy) {
            json(
              503,
              fixture('Error.gpu_busy'),
              headers: {'retry-after': '15'},
            );
          } else {
            json(200, fixture('AnalyzeImageResponse.two_faces_one_body'));
          }
        default:
          json(404, {
            'error': {
              'code': 'not_found',
              'message': 'Not found.',
              'retryable': false,
            },
          });
      }
    });
  });

  tearDown(() => server.close(force: true));

  test(
    'the pinned fingerprint is accepted and the typed answer parses',
    () async {
      final health = await HttpMobileApi(session()).health();
      expect(health.serverId, 'srv_7f3a91c2');
      expect(seen.requests, hasLength(1));
    },
  );

  test(
    'a wrong pin aborts the TLS handshake: the request - and the token - never reach the server',
    () async {
      final api = HttpMobileApi(session(fingerprint: 'ab' * 32));
      await expectLater(
        api.capabilities(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.certificateCode,
          ),
        ),
      );
      expect(
        seen.requests,
        isEmpty,
        reason:
            'nothing may be sent to a server whose certificate does not match the pin',
      );
    },
  );

  test(
    'without pinning the self-signed certificate is rejected (the pin is what lets it through)',
    () async {
      final plain = Dio(
        BaseOptions(
          baseUrl: baseUrl('127.0.0.1', server.port),
          connectTimeout: const Duration(seconds: 5),
        ),
      );
      await expectLater(plain.get('/v1/health'), throwsA(isA<DioException>()));
      expect(seen.requests, isEmpty);
    },
  );

  test('the pin is compared case-insensitively but exactly', () async {
    final upper = HttpMobileApi(
      session(fingerprint: realFingerprint.toUpperCase()),
    );
    expect((await upper.health()).name, 'RTX-PC');
    final almost =
        realFingerprint.substring(0, 63) +
        (realFingerprint.endsWith('0') ? '1' : '0');
    await expectLater(
      HttpMobileApi(session(fingerprint: almost)).health(),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'probeFingerprint reports what the server presents (for the user to confirm)',
    () async {
      expect(
        await probeCertificateFingerprint('127.0.0.1', server.port),
        realFingerprint,
      );
      expect(
        seen.requests,
        isEmpty,
        reason: 'probing completes the handshake but sends no HTTP request',
      );
    },
  );

  test(
    'capabilities sends the bearer token and parses the fixture; a bad token is "unauthorized"',
    () async {
      final caps = await HttpMobileApi(session()).capabilities();
      expect(caps.name, 'RTX-PC');
      expect(
        seen.requests.single.headers.value('authorization'),
        'Bearer $_token',
      );

      await expectLater(
        HttpMobileApi(session(token: 'agm_wrong')).capabilities(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'isUnauthorized',
            isTrue,
          ),
        ),
      );
    },
  );

  test(
    'analyzeImage uploads a multipart form (image + options) and parses the response',
    () async {
      final photo = Uint8List.fromList(
        utf8.encode('not really a jpeg - the fake server never decodes it'),
      );
      final result = await HttpMobileApi(session()).analyzeImage(
        photo,
        options: const AnalyzeOptions(modelId: 'buffalo_l@1'),
      );
      expect(result.faces, hasLength(2));
      expect(result.storableFaces, hasLength(1));

      final request = seen.requests.single;
      expect(request.headers.contentType!.mimeType, 'multipart/form-data');
      final body = seen.bodies['POST /v1/analyze/image']!;
      expect(body, contains('name="image"'));
      expect(body, contains('filename="photo.jpg"'));
      expect(body, contains('not really a jpeg'));
      expect(body, contains('name="options"'));
      expect(body, contains('"model_id":"buffalo_l@1"'));
      expect(body, contains('"min_quality":0.4'));
    },
  );

  test(
    '503 gpu_busy surfaces as a retryable exception with Retry-After',
    () async {
      gpuBusy = true;
      await expectLater(
        HttpMobileApi(session()).analyzeImage(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isGpuBusy, 'isGpuBusy', isTrue)
              .having((e) => e.retryable, 'retryable', isTrue)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 15),
              ),
        ),
      );
    },
  );

  test(
    'pairing exchanges the code for a token over the pinned channel; a wrong code is a 401 invalid_code',
    () async {
      const api = HttpPairingApi();
      final response = await api.completePairing(
        host: '127.0.0.1',
        port: server.port,
        fingerprint: realFingerprint,
        code: 'K7QM-3XRD',
        deviceName: 'Pixel 8',
      );
      expect(response.token, startsWith('agm_'));
      expect(
        jsonDecode(seen.bodies['POST /v1/pair/complete']!),
        fixture('PairRequest.ok'),
      );
      expect(
        seen.requests.single.headers.value('authorization'),
        isNull,
        reason: 'pairing happens before a token exists',
      );

      await expectLater(
        api.completePairing(
          host: '127.0.0.1',
          port: server.port,
          fingerprint: realFingerprint,
          code: 'AAAA-AAAA',
          deviceName: 'x',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'invalid_code'),
        ),
      );
      await expectLater(
        api.completePairing(
          host: '127.0.0.1',
          port: server.port,
          fingerprint: 'cd' * 32,
          code: 'K7QM-3XRD',
          deviceName: 'x',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.certificateCode,
          ),
        ),
      );
    },
  );

  test(
    'an unreachable PC is a retryable "network" exception, not a crash',
    () async {
      final closed = await ServerSocket.bind('127.0.0.1', 0);
      final port = closed.port;
      await closed.close(); // nothing listens here any more
      await expectLater(
        HttpMobileApi(session(port: port)).health(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isOffline, 'isOffline', isTrue)
              .having((e) => e.retryable, 'retryable', isTrue),
        ),
      );
      await expectLater(
        probeCertificateFingerprint('127.0.0.1', port),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'a keep-alive connection the PC already closed is retried once instead of failing the user',
    () async {
      // The PC idles connections out (uvicorn: 5 s) while dart:io keeps the dead one pooled, so the next
      // request dies with "Connection closed before full header was received" - seen on a real phone
      // (through the USB tunnel the close never reached the app).
      final api = HttpMobileApi(session());
      await api.capabilities(); // opens a pooled connection
      dropNextRequest = true; // the next request on it is swallowed

      final result = await api.analyzeImage(Uint8List.fromList([1, 2, 3]));
      expect(
        result.faces,
        hasLength(2),
        reason: 'the retry on a fresh connection succeeded',
      );
      expect(
        seen.requests.where((r) => r.uri.path == '/v1/analyze/image'),
        hasLength(1),
        reason:
            'the dead connection never delivered the first attempt, so the server sees it once',
      );
    },
  );

  test(
    'only the stale-connection failure is retried: a real server error is reported once',
    () async {
      gpuBusy = true;
      final api = HttpMobileApi(session());
      await expectLater(
        api.analyzeImage(Uint8List.fromList([1])),
        throwsA(isA<ApiException>()),
      );
      expect(
        seen.requests.where((r) => r.uri.path == '/v1/analyze/image'),
        hasLength(1),
      );
    },
  );

  test('baseUrl brackets IPv6 literals', () {
    expect(baseUrl('192.168.1.20', 8443), 'https://192.168.1.20:8443');
    expect(baseUrl('fe80::1', 8443), 'https://[fe80::1]:8443');
  });
}
