import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/api/dtos/targeted.dart';

void main() {
  group('TargetedAnalysisResponse DTO', () {
    test(
      'parses targeted response with bounding box, outline, and keypoints',
      () {
        final json = {
          'target_kind': 'body',
          'detections': [
            {
              'bbox': {'x': 0.1, 'y': 0.2, 'w': 0.3, 'h': 0.4},
              'score': 0.95,
              'label': 'person',
              'outline': [
                [0.1, 0.2],
                [0.4, 0.2],
                [0.4, 0.6],
              ],
              'keypoints': [
                [0.2, 0.25, 0.9],
              ],
            },
          ],
        };

        final response = TargetedAnalysisResponse.fromJson(json);
        expect(response.targetKind, 'body');
        expect(response.detections.length, 1);

        final item = response.detections.first;
        expect(item.label, 'person');
        expect(item.score, 0.95);
        expect(item.bbox.x, 0.1);
        expect(item.bbox.w, 0.3);
        expect(item.outline?.length, 3);
        expect(item.keypoints?.first.length, 3);
      },
    );

    test('parses fallback custom container without outline or keypoints', () {
      final json = {
        'target_kind': 'area',
        'detections': [
          {
            'bbox': {'x': 0.3, 'y': 0.4, 'w': 0.2, 'h': 0.2},
            'score': 1.0,
            'label': 'custom',
            'outline': null,
            'keypoints': null,
          },
        ],
      };

      final response = TargetedAnalysisResponse.fromJson(json);
      expect(response.targetKind, 'area');
      expect(response.detections.length, 1);
      expect(response.detections.first.label, 'custom');
      expect(response.detections.first.outline, isNull);
      expect(response.detections.first.keypoints, isNull);
    });
  });
}
