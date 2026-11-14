import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reface Shared Contract Cases Verification', () {
    test('validates shared profiles and contract test cases match Flutter definitions', () {
      final fixtureFile = File('../the app/mobile_api/contract/fixtures/reface/cases.json');
      expect(fixtureFile.existsSync(), true, reason: 'Shared cases fixture must exist');

      final data = json.decode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
      final profiles = data['profiles'] as Map<String, dynamic>;

      // Check Fast
      final fast = profiles['fast'] as Map<String, dynamic>;
      expect(fast['video_crf'], 16);
      expect(fast['video_preset'], 'medium');
      expect(fast['focus_match_strength'], 1.0);
      expect(fast['default_restorer'], 'none');
      expect(fast['use_parser'], false);

      // Check Balanced
      final balanced = profiles['balanced'] as Map<String, dynamic>;
      expect(balanced['video_crf'], 14);
      expect(balanced['video_preset'], 'medium');
      expect(balanced['focus_match_strength'], 0.5);
      expect(balanced['default_restorer'], 'gpen_bfr_512');
      expect(balanced['use_parser'], true);

      // Check Detail
      final detail = profiles['detail'] as Map<String, dynamic>;
      expect(detail['video_crf'], 12);
      expect(detail['video_preset'], 'slow');
      expect(detail['focus_match_strength'], 0.25);
      expect(detail['default_restorer'], 'gpen_bfr_1024');
      expect(detail['use_parser'], true);

      // Check valid cases
      final validCases = data['valid_test_cases'] as List<dynamic>;
      expect(validCases.length, greaterThanOrEqualTo(3));
      for (final testCase in validCases) {
        final payload = testCase['payload'] as Map<String, dynamic>;
        expect(payload.containsKey('type'), true);
        expect(payload.containsKey('params'), true);
        final params = payload['params'] as Map<String, dynamic>;
        expect(params['model_id'], 'buffalo_l@1');
        expect(['fast', 'balanced', 'detail'].contains(params['quality_profile']), true);
      }
    });
  });
}
