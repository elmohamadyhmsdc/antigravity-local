// "Detect faces in a photo": pick -> upload -> boxes + per-face quality, and the failure paths.

import 'package:antigravity_mobile/data/api/api_exception.dart';
import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/features/analyze/analyze_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/harness.dart';

Future<void> _openAnalyze(WidgetTester tester, TestEnv env) async {
  await env.pump(tester);
  await tester.tap(find.byKey(const Key('try-detection')));
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'shows what the PC found: boxes on the photo and one tile per face',
    (tester, env) async {
      env.picker.photo = tinyPng;
      await _openAnalyze(tester, env);
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();

      expect(
        env.api.analyzeCalls,
        [tinyPng],
        reason: 'exactly the picked (already downscaled) photo is uploaded',
      );
      expect(find.byKey(const Key('detections-overlay')), findsOneWidget);
      expect(
        find.text('2 faces found · 1 body · 1280×960 · 124 ms'),
        findsOneWidget,
      );

      final good = env.api.analyzeResult.faces[0];
      expect(find.byKey(const Key('face-0')), findsOneWidget);
      expect(find.byKey(const Key('face-1')), findsOneWidget);
      expect(find.text('Face 1'), findsOneWidget);
      expect(textContaining('Would be saved'), findsOneWidget);
      expect(textContaining('Too small or unclear - skipped'), findsOneWidget);
      expect(
        textContaining('${good.quality.facePx.round()} px'),
        findsOneWidget,
      );
      final tier = qualityTier(good.quality.score);
      expect(
        textContaining(
          '${tier == QualityTier.great
              ? 'Great'
              : tier == QualityTier.good
              ? 'Good'
              : tier == QualityTier.fair
              ? 'Fair'
              : 'Poor'} ${good.quality.score.toStringAsFixed(2)}',
        ),
        findsOneWidget,
      );
    },
    session: testSession,
  );

  appTest('a photo without faces says so', (tester, env) async {
    env.picker.photo = tinyPng;
    env.api.analyzeResult = AnalyzeImageResponse.fromJson(
      fixture('AnalyzeImageResponse.no_faces'),
    );
    await _openAnalyze(tester, env);
    await tester.tap(find.byKey(const Key('pick-photo')));
    await tester.pumpAndSettle();
    expect(find.text('No faces were found in this photo.'), findsOneWidget);
    expect(textContaining('No faces found'), findsOneWidget);
  }, session: testSession);

  appTest('cancelling the picker changes nothing', (tester, env) async {
    env.picker.photo = null;
    await _openAnalyze(tester, env);
    await tester.tap(find.byKey(const Key('pick-photo')));
    await tester.pumpAndSettle();
    expect(env.picker.picks, 1);
    expect(env.api.analyzeCalls, isEmpty);
    expect(find.byKey(const Key('pick-photo')), findsOneWidget);
  }, session: testSession);

  appTest(
    'a busy GPU is explained and the photo can be retried without picking again',
    (tester, env) async {
      env.picker.photo = tinyPng;
      env.api.analyzeError = const ApiException(
        code: 'gpu_busy',
        message: 'A train_lora job is running on the GPU.',
        retryable: true,
        statusCode: 503,
        retryAfter: Duration(seconds: 15),
      );
      await _openAnalyze(tester, env);
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();
      expect(
        find.text("Your PC's GPU is busy right now. Try again in a moment."),
        findsOneWidget,
      );

      env.api.analyzeError = null;
      await tester.tap(find.byKey(const Key('analyze-retry')));
      await tester.pumpAndSettle();
      expect(env.picker.picks, 1, reason: 'retry reuses the same photo');
      expect(env.api.analyzeCalls, hasLength(2));
      expect(find.byKey(const Key('detections-overlay')), findsOneWidget);
    },
    session: testSession,
  );

  appTest('other failures show the server message', (tester, env) async {
    env.picker.photo = tinyPng;
    env.api.analyzeError = ApiException.network(
      'Could not reach the PC. Is the server running?',
    );
    await _openAnalyze(tester, env);
    await tester.tap(find.byKey(const Key('pick-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Analysis failed'), findsOneWidget);
    expect(textContaining('Could not reach the PC'), findsOneWidget);
  }, session: testSession);

  test('quality tiers match the server (face_quality.TIERS)', () {
    expect(qualityTier(0.75), QualityTier.great);
    expect(qualityTier(0.7499), QualityTier.good);
    expect(qualityTier(0.55), QualityTier.good);
    expect(qualityTier(0.35), QualityTier.fair);
    expect(qualityTier(0.3499), QualityTier.poor);
    expect(qualityTier(0), QualityTier.poor);
  });
}
