import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _BodyRecorder implements HttpClientAdapter {
  final sizes = <int>[];
  final bytes = BytesBuilder();
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    await for (final block in stream!) {
      sizes.add(block.length);
      bytes.add(block);
    }
    return ResponseBody.fromString(
      '',
      202,
      headers: {
        'upload-offset': ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late HttpServer server;
  late Directory directory;
  late HttpMobileApi api;
  late Uint8List payload;
  late File target;
  late Future<void> Function(HttpRequest) handle;
  final requests = <String?>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('transfer_https_');
    target = File('${directory.path}/result.mp4.part');
    // Binary and not valid UTF-8: network or disk encoding mistakes are visible.
    payload = Uint8List.fromList(
      List.generate(2 * 1024 * 1024 + 173, (i) => i % 251),
    );
    requests.clear();
    final context = SecurityContext()
      ..useCertificateChain('test/support/tls/test_server.crt')
      ..usePrivateKey('test/support/tls/test_server.key');
    server = await HttpServer.bindSecure('127.0.0.1', 0, context);
    final pem = await File('test/support/tls/test_server.crt').readAsString();
    final der = base64Decode(
      pem.split('\n').where((line) => !line.startsWith('-----')).join(),
    );
    api = HttpMobileApi(
      ServerSession(
        serverId: 'test-transfer',
        name: 'Test',
        host: '127.0.0.1',
        port: server.port,
        fingerprint: sha256.convert(der).toString(),
        token: 'test-token',
      ),
    );
    handle = (request) async {
      final header = request.headers.value('range');
      final offset = header == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(header)![1]!);
      if (offset >= payload.length) {
        request.response.statusCode = 416;
        request.response.headers.set(
          'Content-Range',
          'bytes */${payload.length}',
        );
      } else {
        request.response.statusCode = offset == 0 ? 200 : 206;
        if (offset > 0) {
          request.response.headers.set(
            'Content-Range',
            'bytes $offset-${payload.length - 1}/${payload.length}',
          );
        }
        request.response.contentLength = payload.length - offset;
        request.response.add(Uint8List.sublistView(payload, offset));
      }
      await request.response.close();
    };
    server.listen((request) async {
      requests.add(request.headers.value('range'));
      await handle(request);
    });
  });

  tearDown(() async {
    api.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  Future<void> download() =>
      api.downloadStudioResult('studio_test', 'result.mp4', target);
  Future<void> checkResult() async {
    expect(await target.length(), payload.length);
    expect(sha256.convert(await target.readAsBytes()), sha256.convert(payload));
  }

  test(
    'binary upload keeps exact length/range and avoids thousands of copied blocks',
    () async {
      final recorder = _BodyRecorder();
      final dio = Dio()..httpClientAdapter = recorder;
      final client = HttpMobileApi(api.session, dio: dio);
      final bytes = Uint8List(4 * 1024 * 1024 + 13);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i % 251;
      }
      try {
        expect(
          await client.uploadChunk('a' * 64, bytes, 0, bytes.length + 1),
          bytes.length,
        );
        expect(
          recorder.request!.headers[Headers.contentLengthHeader].toString(),
          '${bytes.length}',
        );
        expect(
          recorder.request!.headers['Content-Range'],
          'bytes 0-${bytes.length - 1}/${bytes.length + 1}',
        );
        expect(recorder.sizes.length, lessThan(32));
        expect(recorder.sizes.reduce((a, b) => a + b), bytes.length);
        expect(
          sha256.convert(recorder.bytes.takeBytes()),
          sha256.convert(bytes),
        );
      } finally {
        client.close();
      }
    },
  );

  test(
    'full binary HTTPS download stays identical across disk block boundaries',
    () async {
      await download();
      await checkResult();
      expect(requests, [null]);
    },
  );

  test(
    'video download reports received bytes without changing result integrity',
    () async {
      final received = <int>[];
      await api.downloadVideoWithProgress(
        'vid_test',
        target,
        onProgress: received.add,
      );
      await checkResult();
      expect(received, isNotEmpty);
      expect(received.last, payload.length);
      for (var i = 1; i < received.length; i++) {
        expect(received[i], greaterThan(received[i - 1]));
      }
    },
  );

  test(
    'a persisted partial result resumes at its existing byte offset',
    () async {
      await target.writeAsBytes(Uint8List.sublistView(payload, 0, 700013));
      await download();
      await checkResult();
      expect(requests, ['bytes=700013-']);
    },
  );

  test(
    'a dropped HTTPS connection retains bytes and the retry downloads only the remainder',
    () async {
      final normal = handle;
      var first = true;
      handle = (request) async {
        if (!first) return normal(request);
        first = false;
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.add(
          ascii.encode(
            'HTTP/1.1 200 OK\r\nContent-Length: ${payload.length}\r\nConnection: close\r\n\r\n',
          ),
        );
        socket.add(Uint8List.sublistView(payload, 0, 1024 * 1024));
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        socket.destroy();
      };
      await expectLater(download(), throwsException);
      final received = await target.length();
      expect(received, greaterThan(0));
      expect(received, lessThan(payload.length));
      await download();
      await checkResult();
      expect(requests, [null, 'bytes=$received-']);
    },
  );

  test(
    'a server ignoring Range restarts safely without appending duplicate bytes',
    () async {
      await target.writeAsBytes([11, 22, 33]);
      handle = (request) async {
        request.response.contentLength = payload.length;
        request.response.add(payload);
        await request.response.close();
      };
      await download();
      await checkResult();
      expect(requests, ['bytes=3-']);
    },
  );

  test(
    'an already complete partial needs no body; an oversized partial restarts',
    () async {
      await target.writeAsBytes(payload);
      await download();
      await checkResult();
      expect(requests, ['bytes=${payload.length}-']);
      requests.clear();
      await target.writeAsBytes([1], mode: FileMode.append);
      await download();
      await checkResult();
      expect(requests, ['bytes=${payload.length + 1}-', null]);
    },
  );

  test('a wrong response range never modifies the verified prefix', () async {
    final prefix = Uint8List.sublistView(payload, 0, 100);
    await target.writeAsBytes(prefix);
    handle = (request) async {
      request.response.statusCode = 206;
      request.response.headers.set(
        'Content-Range',
        'bytes 0-${payload.length - 1}/${payload.length}',
      );
      request.response.add(payload);
      await request.response.close();
    };
    await expectLater(download(), throwsException);
    expect(await target.readAsBytes(), prefix);
  });

  test(
    'streaming downloads preserve auth/retry errors without writing error bodies',
    () async {
      await target.writeAsBytes([1, 2, 3]);
      var unauthorized = true;
      handle = (request) async {
        request.response.statusCode = unauthorized ? 401 : 503;
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('Retry-After', '7');
        request.response.write(
          jsonEncode({
            'error': {
              'code': unauthorized ? 'unauthorized' : 'gpu_busy',
              'message': 'Fixture error',
              'retryable': !unauthorized,
            },
          }),
        );
        await request.response.close();
      };
      await expectLater(
        download(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isUnauthorized,
            'unauthorized',
            isTrue,
          ),
        ),
      );
      unauthorized = false;
      await expectLater(
        download(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.retryable, 'retryable', isTrue)
              .having(
                (e) => e.retryAfter,
                'retry delay',
                const Duration(seconds: 7),
              ),
        ),
      );
      expect(await target.readAsBytes(), [1, 2, 3]);
    },
  );
}
