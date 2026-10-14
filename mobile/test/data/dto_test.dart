// Typed DTOs parsed against the SAME golden fixtures the PC server's tests produce and check
// (the app/mobile_api/contract/fixtures). If the contract changes, make_fixtures.py regenerates
// them and these tests show exactly which field the app must follow.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

double _norm(Float32List v) => sqrt(v.fold<double>(0, (a, x) => a + x * x));

void main() {
  group('system', () {
    test('Health.ok', () {
      final h = Health.fromJson(fixture('Health.ok'));
      expect(
        (h.serverId, h.name, h.apiVersion),
        ('srv_7f3a91c2', 'RTX-PC', '1.0.0'),
      );
    });

    test('Health rejects a status other than ok', () {
      final json = copyOf(fixture('Health.ok'))..['status'] = 'degraded';
      expect(() => Health.fromJson(json), throwsFormatException);
    });

    test('Capabilities.idle', () {
      final c = Capabilities.fromJson(fixture('Capabilities.idle'));
      expect(c.name, 'RTX-PC');
      expect((c.embeddingModelId, c.embeddingDim), ('buffalo_l@1', 512));
      expect(c.gpu!.name, contains('RTX'));
      expect(c.gpu!.vramFreeMb, lessThanOrEqualTo(c.gpu!.vramTotalMb));
      expect(c.engines.refaceV3, isTrue);
      expect(c.engines.dfmModels, ['RTM_WF_224']);
      expect(c.restorers, ['codeformer']);
      expect(c.loraBaseCheckpoints, ['sd15_realistic_base']);
      expect(c.limits.maxImagePx, 4096);
      expect(c.isBusy, isFalse);
    });

    test('Capabilities.busy_with_dashboard_job', () {
      final c = Capabilities.fromJson(
        fixture('Capabilities.busy_with_dashboard_job'),
      );
      expect(c.isBusy, isTrue);
      expect(c.busy!.source, 'dashboard');
      expect(c.busy!.jobType, 'reface_video_v3');
    });

    test('a PC without a GPU reports gpu: null', () {
      final json = copyOf(fixture('Capabilities.idle'))..['gpu'] = null;
      expect(Capabilities.fromJson(json).gpu, isNull);
    });

    test('PairRequest serialises to the fixture; PairResponse parses', () {
      final request = PairRequest(code: 'K7QM-3XRD', deviceName: 'Pixel 8');
      expect(request.toJson(), fixture('PairRequest.ok'));
      final r = PairResponse.fromJson(fixture('PairResponse.ok'));
      expect(r.token, startsWith('agm_'));
      expect((r.serverId, r.serverName), ('srv_7f3a91c2', 'RTX-PC'));
    });
  });

  group('errors', () {
    test('Error.gpu_busy', () {
      final e = ApiException.fromEnvelope(
        503,
        fixture('Error.gpu_busy'),
        retryAfter: const Duration(seconds: 15),
      );
      expect(e.code, 'gpu_busy');
      expect(e.isGpuBusy, isTrue);
      expect(e.retryable, isTrue);
      expect(e.retryAfter, const Duration(seconds: 15));
      expect(e.statusCode, 503);
    });

    test('Error.invalid_code is not retryable', () {
      final e = ApiException.fromEnvelope(401, fixture('Error.invalid_code'));
      expect(
        (e.code, e.retryable, e.isUnauthorized),
        ('invalid_code', false, false),
      );
    });

    test('MissingBlobsError carries the missing hashes', () {
      final e = ApiException.fromEnvelope(
        409,
        fixture('MissingBlobsError.reface'),
      );
      expect(e.code, 'missing_blobs');
      expect(e.missing, hasLength(1));
      expect(e.missing.single, matches(RegExp(r'^[0-9a-f]{64}$')));
    });

    test('a non-envelope answer still becomes a usable exception', () {
      final e = ApiException.fromEnvelope(502, '<html>bad gateway</html>');
      expect((e.code, e.retryable, e.statusCode), ('internal', true, 502));
    });
  });

  group('embeddings', () {
    test('base64 <-> Float32List round-trips exactly and is little-endian', () {
      final v = Float32List.fromList(
        List.generate(512, (i) => sin(i.toDouble())),
      );
      final text = encodeEmbedding(v);
      expect(text.length, 2732);
      expect(decodeEmbedding(text), v);
      final raw = base64Decode(text);
      expect(
        ByteData.sublistView(raw).getFloat32(4, Endian.little),
        v[1],
        reason: 'wire format is little-endian',
      );
    });

    test('wrong sizes are rejected', () {
      expect(() => decodeEmbedding('AAAA'), throwsFormatException);
      expect(() => encodeEmbedding(Float32List(511)), throwsArgumentError);
    });

    test('local BLOB form round-trips', () {
      final v = Float32List.fromList(List.generate(512, (i) => i / 512));
      expect(embeddingFromBlob(embeddingToBlob(v)), v);
      expect(() => embeddingFromBlob(Uint8List(10)), throwsFormatException);
    });
  });

  group('AnalyzeImageResponse', () {
    final json = fixture('AnalyzeImageResponse.two_faces_one_body');

    test('two_faces_one_body parses completely', () {
      final r = AnalyzeImageResponse.fromJson(json);
      expect((r.modelId, r.imageW, r.imageH), ('buffalo_l@1', 1280, 960));
      expect(r.faces, hasLength(2));
      expect(r.bodies, hasLength(1));
      expect(r.pairs.single.faceIndex, 0);
      expect(r.pairs.single.bodyIndex, 0);
      expect(r.timingsMs['detect'], 41.2);

      final a = r.faces[0];
      expect(a.bbox, const BBox(x: 412.5, y: 188.0, w: 176.0, h: 214.5));
      expect(a.kps, hasLength(5));
      expect(a.kps.first, [455.1, 262.3]);
      expect(a.embedding, hasLength(512));
      expect(_norm(a.embedding), closeTo(1.0, 1e-3));
      expect(a.passesGate, isTrue);
      expect(a.quality.score, inInclusiveRange(0.0, 1.0));
      expect(a.quality.version, 2);
      expect(
        a.quality.parts.keys,
        containsAll(['norm', 'size', 'sharp', 'pose']),
      );
      expect(a.quality.pose!.yaw, 6.2);
      expect(a.cropJpeg, isNotNull);
      expect(a.cropJpeg!.sublist(0, 2), [
        0xFF,
        0xD8,
      ], reason: 'crop_jpeg decodes to JPEG bytes');

      final b = r.faces[1];
      expect(b.passesGate, isFalse);
      expect(b.cropJpeg, isNull);
      expect(r.storableFaces, [a]);

      final body = r.bodies.single;
      expect(body.score, closeTo(0.9121, 1e-9));
      expect(body.kpts, hasLength(17));
      expect(body.kpts!.first, hasLength(3));
      expect(body.appearance, hasLength(80));
      expect(body.extent, isNotNull);
      expect(body.cropJpeg, isNotNull);
    });

    test('no_faces parses to empty lists', () {
      final r = AnalyzeImageResponse.fromJson(
        fixture('AnalyzeImageResponse.no_faces'),
      );
      expect(r.faces, isEmpty);
      expect(r.bodies, isEmpty);
      expect(r.pairs, isEmpty);
      expect(r.timingsMs, isEmpty);
    });

    test('boxes normalise to 0..1 of the analysed image', () {
      final r = AnalyzeImageResponse.fromJson(json);
      final n = r.faces[0].bbox.normalized(r.imageW, r.imageH);
      expect(n.x, closeTo(412.5 / 1280, 1e-12));
      expect(n.h, closeTo(214.5 / 960, 1e-12));
      expect(n.x + n.w, lessThanOrEqualTo(1.0));
    });

    test('AnalyzeOptions serialises to the fixture', () {
      expect(
        const AnalyzeOptions(modelId: 'buffalo_l@1').toJson(),
        fixture('AnalyzeImageOptions.default'),
      );
      expect(const AnalyzeOptions().toJson().containsKey('model_id'), isFalse);
    });

    test('a contract drift names the offending field', () {
      final broken = copyOf(json);
      ((broken['faces'] as List)[0] as Map)['embedding'] = 'AAAA';
      expect(
        () => AnalyzeImageResponse.fromJson(broken),
        throwsFormatException,
      );

      final missing = copyOf(json);
      (((missing['faces'] as List)[0] as Map)['bbox'] as Map).remove('w');
      expect(
        () => AnalyzeImageResponse.fromJson(missing),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('faces[0].bbox.w'),
          ),
        ),
      );

      final fewer = copyOf(json);
      ((fewer['faces'] as List)[0] as Map)['kps'] = [
        [1, 2],
      ];
      expect(() => AnalyzeImageResponse.fromJson(fewer), throwsFormatException);
    });
  });
}
