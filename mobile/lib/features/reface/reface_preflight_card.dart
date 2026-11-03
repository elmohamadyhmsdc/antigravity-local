import 'package:flutter/material.dart';

import '../../domain/reface/angle_generation.dart';
import '../../domain/reface/reface_preflight.dart';

/// What the card shows about generating the missing head angles with the person's LoRA.
class AngleGenerationOffer {
  const AngleGenerationOffer({
    required this.plan,
    required this.running,
    required this.status,
    required this.onGenerate,
  });

  /// Null while a run is going and nothing more is missing.
  final AngleGenerationPlan? plan;
  final bool running;
  final String? status;
  final VoidCallback? onGenerate;
}

/// "Before we start": what the target asks for, what the source can give, and what is likely to go
/// wrong - found on the phone, before a job is queued.
class RefacePreflightCard extends StatelessWidget {
  const RefacePreflightCard({
    super.key,
    required this.preflight,
    this.generate,
  });

  final RefacePreflight preflight;
  final AngleGenerationOffer? generate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnings = preflight.warnings;
    final ok = warnings.isEmpty;
    final target = RefacePreflight.percent(preflight.targetShare);
    final real = RefacePreflight.counts(preflight.realCoverage);
    final generated = RefacePreflight.counts(preflight.generatedCoverage);
    return Card(
      key: const Key('reface-preflight'),
      color: ok
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.errorContainer.withValues(alpha: .5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.fact_check_outlined : Icons.warning_amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ok
                        ? 'Ready: the source fits this target'
                        : 'Before we start',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Target: ${preflight.targetFaces} face${preflight.targetFaces == 1 ? '' : 's'}'
              '${preflight.smallestTargetPx == null ? '' : ' · smallest ${preflight.smallestTargetPx!.round()} px'}',
              key: const Key('reface-preflight-target'),
            ),
            if (target.isNotEmpty)
              Text(
                'Looking: $target',
                key: const Key('reface-preflight-poses'),
              ),
            if (real.isNotEmpty || generated.isNotEmpty)
              Text(
                'Source: ${real.isEmpty ? 'no real faces' : real}'
                '${generated.isEmpty ? '' : ' (+ model portraits: $generated)'}',
                key: const Key('reface-preflight-source'),
              ),
            for (final w in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('• $w', style: theme.textTheme.bodyMedium),
              ),
            if (preflight.gaps.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  generate == null
                      ? 'Add source faces from those angles to improve the likeness.'
                      : 'Add source faces from those angles, or let the person\'s model draw them first.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (generate case final offer?) ..._generation(offer),
          ],
        ),
      ),
    );
  }

  List<Widget> _generation(AngleGenerationOffer offer) => [
    if (offer.running)
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: LinearProgressIndicator(key: Key('reface-angles-progress')),
      ),
    if (offer.plan case final plan? when !offer.running)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FilledButton.tonalIcon(
          key: const Key('reface-generate-angles'),
          onPressed: offer.onGenerate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(
            'Generate ${plan.count} missing angle${plan.count == 1 ? '' : 's'} (${plan.summary})',
          ),
        ),
      ),
    if (offer.status case final status?)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(status, key: const Key('reface-angles-status')),
      ),
  ];
}
