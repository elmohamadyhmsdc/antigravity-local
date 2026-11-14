import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Identity Bundle Contract Verification (Phase 4)', () {
    test('validates sample_bundle matches schema 1.0 and algorithm identity_v1', () {
      final sampleFile = File('../the app/mobile_api/contract/fixtures/identity/sample_bundle.json');
      expect(sampleFile.existsSync(), true, reason: 'sample_bundle.json fixture must exist');

      final data = json.decode(sampleFile.readAsStringSync()) as Map<String, dynamic>;

      expect(data['schema_version'], '1.0');
      expect(data['algorithm_version'], 'identity_v1');
      expect(data.containsKey('identity_id'), true);
      expect((data['identity_id'] as String).startsWith('ident_'), true);
      expect(data.containsKey('bundle_hash'), true);
      expect((data['bundle_hash'] as String).length, 64);

      // Primary embedding
      final primary = data['primary_embedding'] as List<dynamic>;
      expect(primary.length, 512);
      for (final val in primary) {
        expect(val is num, true);
      }

      // Angle embeddings
      final angleEmbeddings = data['angle_embeddings'] as Map<String, dynamic>;
      final allowedSectors = {'front', 'left', 'right', 'up', 'down'};
      for (final entry in angleEmbeddings.entries) {
        expect(allowedSectors.contains(entry.key), true);
        final vec = entry.value as List<dynamic>;
        expect(vec.length, 512);
      }

      // Sources
      final sources = data['sources'] as List<dynamic>;
      expect(sources.isNotEmpty, true);
      for (final src in sources) {
        final s = src as Map<String, dynamic>;
        expect(s.containsKey('source_id'), true);
        expect((s['embedding'] as List<dynamic>).length, 512);
        expect(s.containsKey('pose'), true);
        final pose = s['pose'] as Map<String, dynamic>;
        expect(pose.containsKey('yaw'), true);
        expect(pose.containsKey('pitch'), true);
        expect(s.containsKey('quality'), true);
        expect((s['quality'] as num) >= 0.0 && (s['quality'] as num) <= 1.0, true);
        expect(s.containsKey('bbox'), true);
      }

      // Metrics
      final metrics = data['metrics'] as Map<String, dynamic>;
      expect(metrics['input_count'], greaterThanOrEqualTo(metrics['kept_count']));
      expect(metrics['consistency_score'] is num, true);
      expect(metrics.containsKey('pose_coverage'), true);
      expect(metrics.containsKey('coverage_percentage'), true);
    });

    test('validates cases.json valid and invalid bundle contracts', () {
      final casesFile = File('../the app/mobile_api/contract/fixtures/identity/cases.json');
      expect(casesFile.existsSync(), true, reason: 'cases.json fixture must exist');

      final casesData = json.decode(casesFile.readAsStringSync()) as Map<String, dynamic>;

      // Valid bundles
      final valids = casesData['valid_bundles'] as List<dynamic>;
      expect(valids.isNotEmpty, true);
      for (final vb in valids) {
        final b = vb as Map<String, dynamic>;
        expect(b['schema_version'], '1.0');
        expect(b['algorithm_version'], 'identity_v1');
        expect((b['primary_embedding'] as List<dynamic>).length, 512);
      }

      // Invalid bundles
      final invalids = casesData['invalid_bundles'] as List<dynamic>;
      expect(invalids.length, greaterThanOrEqualTo(3));
      for (final inv in invalids) {
        final item = inv as Map<String, dynamic>;
        final desc = item['description'] as String;
        final bundle = item['bundle'] as Map<String, dynamic>;

        bool isValid = true;
        if (!bundle.containsKey('schema_version') ||
            !bundle.containsKey('primary_embedding') ||
            !bundle.containsKey('sources') ||
            !bundle.containsKey('bundle_hash')) {
          isValid = false;
        } else if ((bundle['primary_embedding'] as List<dynamic>).length != 512) {
          isValid = false;
        }

        if (desc == 'missing_required_fields' || desc == 'wrong_embedding_dimension') {
          expect(isValid, false, reason: 'Case $desc must be detected as invalid');
        }
      }
    });
  });
}
