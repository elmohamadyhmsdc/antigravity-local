import 'package:antigravity_mobile/domain/reface/angle_generation.dart';
import 'package:antigravity_mobile/domain/reface/reface_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'poses fall into five buckets; up/down beat the turn; left and right are one',
    () {
      expect(PoseBucket.of(5, 5), PoseBucket.frontal);
      expect(PoseBucket.of(-35, 0), PoseBucket.threeQuarter);
      expect(PoseBucket.of(35, 0), PoseBucket.threeQuarter);
      expect(PoseBucket.of(70, 0), PoseBucket.profile);
      expect(PoseBucket.of(60, 25), PoseBucket.up);
      expect(PoseBucket.of(0, -30), PoseBucket.down);
      expect(PoseBucket.of(null, null), isNull);
    },
  );

  test('a clean case has nothing to say', () {
    final p = RefacePreflight(
      targets: const [PreflightTarget(facePx: 200, yaw: 3, pitch: 0)],
      sources: [
        for (var i = 0; i < 6; i++)
          PreflightSource(yaw: i.toDouble(), pitch: 0),
      ],
    );

    expect(p.warnings, isEmpty);
    expect(p.hasProblems, isFalse);
    expect(p.gaps, isEmpty);
  });

  test('tiny and small target faces are counted and named', () {
    final p = RefacePreflight(
      targets: const [
        PreflightTarget(facePx: 30, yaw: 0, pitch: 0),
        PreflightTarget(facePx: 50, yaw: 0, pitch: 0),
        PreflightTarget(facePx: 300, yaw: 0, pitch: 0),
      ],
      sources: [
        for (var i = 0; i < 6; i++) const PreflightSource(yaw: 0, pitch: 0),
      ],
    );

    expect((p.tinyTargets, p.smallTargets, p.smallestTargetPx), (1, 1, 30));
    expect(p.warnings.first, contains('under 40 px'));
    expect(p.warnings[1], contains('under 64 px'));
  });

  test(
    'the poses the target asks for and the source lacks are the gaps, biggest first',
    () {
      // a video person: 60% frontal, 30% 3/4, 10% profile (weights are sampled frames)
      final p = RefacePreflight(
        targets: const [
          PreflightTarget(yaw: 0, pitch: 0, weight: 60),
          PreflightTarget(yaw: 30, pitch: 0, weight: 30),
          PreflightTarget(yaw: 80, pitch: 0, weight: 10),
        ],
        sources: [
          for (var i = 0; i < 8; i++)
            const PreflightSource(yaw: 2, pitch: 0), // all frontal
          const PreflightSource(
            yaw: 85,
            pitch: 0,
            generated: true,
          ), // a LoRA portrait does not count
        ],
      );

      expect(p.targetShare[PoseBucket.frontal], closeTo(0.6, 1e-9));
      expect(p.gaps, [PoseBucket.threeQuarter, PoseBucket.profile]);
      expect(p.realCoverage[PoseBucket.frontal], 8);
      expect(p.generatedCoverage[PoseBucket.profile], 1);
      expect(p.warnings.any((w) => w.startsWith('3/4 view is 30%')), isTrue);
      expect(
        RefacePreflight.percent(p.targetShare),
        '''Frontal 60% · 3/4 view 30% · Profile 10%''',
      );
      expect(RefacePreflight.counts(p.realCoverage), 'Frontal 8');
    },
  );

  test('a thin identity and an empty selection are called out', () {
    final thin = RefacePreflight(
      targets: const [PreflightTarget(facePx: 200, yaw: 0, pitch: 0)],
      sources: const [
        PreflightSource(yaw: 0, pitch: 0),
        PreflightSource(yaw: 5, pitch: 0),
      ],
    );
    expect(thin.warnings.single, startsWith('Only 2 real source faces'));

    final none = RefacePreflight(targets: const [], sources: const []);
    expect(none.warnings, ['No face is selected in the target.']);
  });

  group('what to generate', () {
    RefacePreflight check({List<PreflightSource> sources = const []}) =>
        RefacePreflight(
          targets: const [
            PreflightTarget(yaw: 0, pitch: 0, weight: 60),
            PreflightTarget(yaw: 30, pitch: 0, weight: 30),
            PreflightTarget(yaw: 80, pitch: 0, weight: 10),
          ],
          sources: [
            for (var i = 0; i < 8; i++) const PreflightSource(yaw: 2, pitch: 0),
            ...sources,
          ],
        );

    test('a plan asks for the open gaps, biggest first, a few tries each', () {
      final plan = AngleGenerationPlan.of(check())!;

      expect(plan.buckets, [PoseBucket.threeQuarter, PoseBucket.profile]);
      expect(plan.angles, [
        'three_quarter',
        'three_quarter',
        'three_quarter',
        'profile',
        'profile',
        'profile',
      ]);
      expect(plan.count, 6);
      expect(plan.summary, '3/4 view, Profile');
    });

    test(
      'model portraits already made count: only what is still missing is asked for',
      () {
        final plan = AngleGenerationPlan.of(
          check(
            sources: const [
              PreflightSource(yaw: 30, pitch: 0, generated: true),
              PreflightSource(yaw: 35, pitch: 0, generated: true),
            ],
          ),
        )!;

        expect(plan.buckets, [
          PoseBucket.profile,
        ], reason: '3/4 view is covered by two portraits');
        expect(
          check(
            sources: const [
              PreflightSource(yaw: 30, pitch: 0, generated: true),
              PreflightSource(yaw: 35, pitch: 0, generated: true),
              PreflightSource(yaw: 80, pitch: 0, generated: true),
              PreflightSource(yaw: 85, pitch: 0, generated: true),
            ],
          ).needsGeneration,
          isEmpty,
        );
      },
    );

    test('nothing missing means no plan, and the total is capped', () {
      expect(
        AngleGenerationPlan.of(
          RefacePreflight(
            targets: const [PreflightTarget(yaw: 0, pitch: 0)],
            sources: [
              for (var i = 0; i < 6; i++)
                const PreflightSource(yaw: 0, pitch: 0),
            ],
          ),
        ),
        isNull,
      );

      final many = RefacePreflight(
        targets: const [
          PreflightTarget(yaw: 30, pitch: 0, weight: 20),
          PreflightTarget(yaw: 80, pitch: 0, weight: 20),
          PreflightTarget(yaw: 0, pitch: 40, weight: 20),
          PreflightTarget(yaw: 0, pitch: -40, weight: 20),
          PreflightTarget(yaw: 0, pitch: 0, weight: 20),
        ],
        sources: const [],
      );
      expect(
        AngleGenerationPlan.of(many, maxImages: 10)!.count,
        lessThanOrEqualTo(10),
      );
    });
  });
}
