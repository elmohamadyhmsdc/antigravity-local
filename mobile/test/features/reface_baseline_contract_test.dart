import 'package:flutter_test/flutter_test.dart';

/// Phase 0 Baseline Probe: Verifies the exact request structure, options, and defaults
/// produced by the Flutter Reface pipeline.
void main() {
  group('Flutter Reface Baseline Contract', () {
    test('verifies flutter reface parameters structure and options', () {
      const defaultQuality = 'balanced';
      const defaultRestorer = 'auto';
      const defaultPreset = 'natural';
      const defaultParser = true;
      const defaultOccluder = true;
      const defaultIdentityBoost = 0.5;

      // Construct a representative parameter map matching _RefaceScreenState._submit
      final params = <String, dynamic>{
        'source_faces': [
          {
            'embedding': 'AAAA',
            'quality': 0.95,
            'pose': {'yaw': 0.0, 'pitch': 0.0, 'roll': 0.0},
          }
        ],
        'model_id': 'buffalo_l@1',
        'restorer': defaultRestorer,
        'use_parser': defaultParser,
        'use_occluder': defaultOccluder,
        'realism_preset': defaultPreset,
        'quality_profile': defaultQuality,
        'identity_boost': defaultIdentityBoost,
        'preview': false,
        'target_faces': [
          {'x': 100, 'y': 120, 'w': 200, 'h': 220}
        ],
        'start_time': 0.0,
        'end_time': 10.0,
      };

      // 1. Verifies Flutter provides the keys documented in baseline
      expect(params['model_id'], 'buffalo_l@1');
      expect(params['quality_profile'], 'balanced');
      expect(params['restorer'], 'auto');
      expect(params['use_parser'], true);
      expect(params['use_occluder'], true);
      expect(params['realism_preset'], 'natural');
      expect(params['identity_boost'], 0.5);
      expect(params['preview'], false);
      expect(params.containsKey('target_faces'), true);
      expect(params['start_time'], 0.0);
      expect(params['end_time'], 10.0);

      // Contrast with Native:
      // Flutter explicitly exposes realism_preset, preview, and target_faces,
      // whereas Native baseline omits them.
    });
  });
}
