import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/action_api.dart';
import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/jobs.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(
          File(
            '../the app/mobile_api/contract/fixtures/$name.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  final Map<String, dynamic> Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(reply(options)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'capabilities distinguish legacy unknown from installed model-aware paths',
    () {
      final legacy = Capabilities.fromJson(fixture('Capabilities.idle'));
      expect(legacy.hasOperationSupport, isFalse);
      expect(legacy.supportsOperation('dataset_build', 'character'), isFalse);
      final current = Capabilities.fromJson(
        fixture('Capabilities.operation_support'),
      );
      expect(current.hasOperationSupport, isTrue);
      expect(
        current.supportsOperation(
          'dataset_build',
          'character',
          mediaType: 'photo',
          identityModelId: 'ccip-caformer24@1',
        ),
        isTrue,
      );
      expect(
        current.supportsOperation(
          'dataset_build',
          'character',
          identityModelId: 'buffalo_l@1',
        ),
        isFalse,
      );
      expect(
        current.supportsOperation(
          'dataset_build',
          'person',
          identityModelId: 'ccip-caformer24@1',
        ),
        isFalse,
      );
      expect(
        current.supportsOperation(
          'reface_reference',
          'character',
          mediaType: 'video',
        ),
        isTrue,
      );
    },
  );

  test(
    'CPU action HTTP call preserves opaque candidates and validates response identity',
    () async {
      final request = fixture('ActionMatchRequest.photo_group');
      var malformed = false;
      final dio = Dio()
        ..httpClientAdapter = _Adapter((options) {
          expect(options.path, '/v1/actions/match');
          final body = options.data as Map;
          expect(body.keys.toSet(), {
            'kind',
            'query',
            'allow_mirror',
            'candidates',
          });
          expect(body['query'], request['query']);
          final response = fixture('ActionMatchResponse.photo_group');
          if (malformed) (response['matches'] as List).removeLast();
          return response;
        });
      final api = HttpMobileApi(
        const ServerSession(
          serverId: 'server',
          name: 'fixture',
          host: '127.0.0.1',
          port: 8443,
          fingerprint: 'fixture',
          token: 'private-fixture-token',
        ),
        dio: dio,
      );
      addTearDown(api.close);
      Future<Map<String, double?>> call() =>
          (api as ActionMatchApi).compareActions(
            kind: 'photo',
            query: (request['query'] as List).cast<Map<String, dynamic>>(),
            candidates: [
              for (final c in request['candidates'])
                (
                  id: c['id'] as String,
                  frames: (c['frames'] as List).cast<Map<String, dynamic>>(),
                ),
            ],
          );
      final scores = await call();
      expect(scores, {'reverse-order': 1.0, 'one-member': null});
      malformed = true;
      await expectLater(
        call(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.badResponseCode,
          ),
        ),
      );
    },
  );

  test(
    'Studio manifest forwards explicit model metadata and rejects unknown identity spaces',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          (_) => {
            'files': [
              {
                'name': 'dataset.zip',
                'size': 5,
                'sha256': 'a' * 64,
                'mime': 'application/zip',
              },
            ],
            'meta': {
              'identity_model_id': 'ccip-caformer24@1',
              'image_count': 2,
            },
          },
        );
      final api = HttpMobileApi(
        const ServerSession(
          serverId: 'server',
          name: 'fixture',
          host: '127.0.0.1',
          port: 8443,
          fingerprint: 'fixture',
          token: 'private-fixture-token',
        ),
        dio: dio,
      );
      addTearDown(api.close);
      expect(
        (await api.studioResult('job')).metadata['identity_model_id'],
        'ccip-caformer24@1',
      );
      expect(
        () => StudioResultFile.fromJson({
          'name': 'dataset.zip',
          'size': 5,
          'sha256': 'a' * 64,
          'mime': 'application/zip',
          'meta': {'identity_model_id': 'made-up-space'},
        }),
        throwsFormatException,
      );
    },
  );
}
