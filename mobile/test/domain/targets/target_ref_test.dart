import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/domain/targets/target_ref.dart';

void main() {
  group('TargetRef', () {
    test('parses unified target format with media and detection', () {
      final ref = TargetRef.fromQueryParams({
        'target': 'media:42,det:99',
        'person': '7',
        'identity': '3',
      });
      expect(ref.mediaId, 42);
      expect(ref.detectionId, 99);
      expect(ref.personId, 7);
      expect(ref.identitySetId, 3);
      expect(ref.toTargetParam(), 'media:42,det:99');
    });

    test('parses unified target with only media', () {
      final ref = TargetRef.fromQueryParams({'target': 'media:101'});
      expect(ref.mediaId, 101);
      expect(ref.detectionId, isNull);
      expect(ref.toTargetParam(), 'media:101');
    });

    test('parses unified target with only detection', () {
      final ref = TargetRef.fromQueryParams({'target': 'det:55'});
      expect(ref.mediaId, isNull);
      expect(ref.detectionId, 55);
      expect(ref.toTargetParam(), 'det:55');
    });

    test('parses legacy parameters (media, target as det, person, face)', () {
      final ref = TargetRef.fromQueryParams({
        'media': '20',
        'target': '88',
        'person': '12',
        'face': '5',
      });
      expect(ref.mediaId, 20);
      expect(ref.detectionId, 88);
      expect(ref.personId, 12);
      expect(ref.faceId, 5);
    });

    test('round-trips toQueryParams', () {
      const original = TargetRef(
        mediaId: 10,
        detectionId: 20,
        personId: 30,
        identitySetId: 40,
        faceId: 50,
      );
      final params = original.toQueryParams();
      final parsed = TargetRef.fromQueryParams(params);
      expect(parsed, original);
    });
  });
}
