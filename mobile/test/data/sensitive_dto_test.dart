// The shared golden fixtures (the app/mobile_api/contract/fixtures) for roadmap section 8.

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/system.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('SensitiveRegion.chest fixture parses and serializes back', () {
    final json = fixture('SensitiveRegion.chest');
    final region = SensitiveRegionDto.fromJson(json);
    expect(region.label, 'FEMALE_BREAST_EXPOSED');
    expect((region.exposed, region.bodyIndex), (true, 0));
    expect(region.bbox.w, 120.0);
    expect(region.toJson(), json);
  });

  test('AnalyzeSensitiveResponse.two_regions fixture parses completely', () {
    final r = AnalyzeSensitiveResponse.fromJson(
      fixture('AnalyzeSensitiveResponse.two_regions'),
    );
    expect(r.modelVersion, 1);
    expect(r.regions.map((g) => g.label), [
      'FEMALE_BREAST_EXPOSED',
      'BELLY_COVERED',
    ]);
    expect(r.regions.last.bodyIndex, isNull);
    expect(r.regions.last.exposed, isFalse);
  });

  test('SensitiveBodyTarget.with_kpts round-trips', () {
    final json = fixture('SensitiveBodyTarget.with_kpts');
    final target = SensitiveBodyTargetDto.fromJson(json);
    expect(target.kpts, hasLength(17));
    expect(target.toJson()['bbox'], json['bbox']);
  });

  test('return_sensitive is sent only when asked for', () {
    expect(
      const AnalyzeOptions().toJson().containsKey('return_sensitive'),
      isFalse,
    );
    final json = const AnalyzeOptions(returnSensitive: true).toJson();
    expect(json['return_sensitive'], isTrue);
    final fx = fixture('AnalyzeImageOptions.sensitive');
    expect(fx['return_sensitive'], isTrue);
  });

  test('an analyze response without regions has null, with them a list', () {
    final plain = AnalyzeImageResponse.fromJson(
      fixture('AnalyzeImageResponse.two_faces_one_body'),
    );
    expect(plain.sensitiveRegions, isNull);
    final json = {
      ...fixture('AnalyzeImageResponse.two_faces_one_body'),
      'sensitive_regions': [fixture('SensitiveRegion.chest')],
    };
    expect(AnalyzeImageResponse.fromJson(json).sensitiveRegions, hasLength(1));
  });

  test(
    'capabilities report the sensitive model; older servers default to false',
    () {
      final caps = Capabilities.fromJson(fixture('Capabilities.idle'));
      expect(caps.engines.sensitiveDetection, isTrue);
      final json = fixture('Capabilities.idle');
      (json['engines'] as Map<String, dynamic>).remove('sensitive_detection');
      expect(Capabilities.fromJson(json).engines.sensitiveDetection, isFalse);
    },
  );
}
