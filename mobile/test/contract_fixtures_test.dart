// The server and the app share one set of golden fixtures:
//   the app/mobile_api/contract/fixtures/<Schema>.<variant>.json
// validate_contract.py checks them against openapi.yaml; this test proves Dart
// can read every one and decode the wire format for embeddings. Typed DTO tests
// are added next to the DTOs in phase P1.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

final _fixtureDir = Directory('../the app/mobile_api/contract/fixtures');

/// float32 little-endian, base64 - see openapi.yaml `Embedding` (512) and the character
/// face's CCIP vector (768), whose length follows its sibling `embedding_model_id`.
Float32List decodeEmbedding(String b64, [int dim = 512]) {
  final bytes = base64Decode(b64);
  expect(bytes.length, dim * 4, reason: 'embedding must be $dim float32');
  return bytes.buffer.asFloat32List(bytes.offsetInBytes, dim);
}

double norm(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  return sqrt(sum);
}

/// Every embedding in a document with its length in values.
Iterable<(String, int)> embeddingsIn(
  Object? node, [
  String? key,
  int dim = 512,
]) sync* {
  if (node is Map) {
    final ccip =
        node['strictness'] == 'character' ||
        '${node['identity_model_id'] ?? node['embedding_model_id'] ?? node['model_id'] ?? ''}'
            .startsWith('ccip');
    for (final e in node.entries) {
      yield* embeddingsIn(e.value, e.key as String, ccip ? 768 : dim);
    }
  } else if (node is List) {
    for (final v in node) {
      yield* embeddingsIn(v, key, dim);
    }
  } else if (node is String &&
      (key == 'anchor_embedding' ||
          key == 'embedding' ||
          key == 'target_embeddings' ||
          key == 'proto' ||
          key == 'weak_face_embedding' ||
          key == 'members')) {
    yield (node, dim);
  }
}

void main() {
  final files = _fixtureDir.existsSync()
      ? (_fixtureDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('fixtures directory is found and not empty', () {
    expect(
      _fixtureDir.existsSync(),
      isTrue,
      reason: 'run flutter test from the mobile/ folder',
    );
    expect(files, isNotEmpty);
  });

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    test('$name parses and its embeddings decode', () {
      final json = jsonDecode(file.readAsStringSync());
      expect(json, isA<Map<String, dynamic>>());
      expect(
        name.split('.').length,
        3,
        reason: 'expected <Schema>.<variant>.json',
      );
      for (final (s, dim) in embeddingsIn(json)) {
        final v = decodeEmbedding(s, dim);
        expect(v.every((x) => x.isFinite), isTrue);
        expect(
          norm(v),
          closeTo(1.0, 1e-3),
          reason: 'embeddings are unit length',
        );
      }
    });
  }

  test(
    'grouping apply fixture: decisions the server computed are readable',
    () {
      final res =
          jsonDecode(
                File(
                  '${_fixtureDir.path}/GroupingPlanResponse.apply_basic.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final assignments = (res['assignments'] as List)
          .cast<Map<String, dynamic>>();
      expect(assignments.map((a) => a['face_id']), [101, 102]);
      expect(assignments.every((a) => a['decision'] == 'auto'), isTrue);
      final groups = (res['groups'] as List).cast<Map<String, dynamic>>();
      expect(groups.single['face_ids'], [103, 104, 105]);
      expect(groups.single['auto_create'], isTrue);
    },
  );
}
