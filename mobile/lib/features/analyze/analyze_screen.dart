import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/dtos/analyze.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'analyze_controller.dart';

/// "Detect faces in a photo": the first screen that round-trips a real photo through the PC.
class AnalyzeScreen extends ConsumerWidget {
  const AnalyzeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(analyzeControllerProvider);
    final controller = ref.read(analyzeControllerProvider.notifier);
    final serverName = ref.watch(sessionProvider)?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analyzeTitle)),
      body: switch (state) {
        AnalyzeIdle() => _Centered(
          children: [
            Text(l10n.analyzeIdle, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('pick-photo'),
              onPressed: controller.pickAndAnalyze,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l10n.analyzePick),
            ),
          ],
        ),
        AnalyzeWorking(:final photo) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(photo, fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
              child: Text(
                l10n.analyzing(serverName),
                key: const Key('analyzing'),
              ),
            ),
          ],
        ),
        AnalyzeFailed(:final error) => _Centered(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.analyzeFailed,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.isGpuBusy ? l10n.gpuBusyMessage : error.message,
              key: const Key('analyze-error'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('analyze-retry'),
              onPressed: controller.retry,
              child: Text(l10n.retry),
            ),
            TextButton(
              onPressed: controller.pickAndAnalyze,
              child: Text(l10n.analyzePickAnother),
            ),
          ],
        ),
        AnalyzeDone(:final photo, :final result) => _Result(
          photo: photo,
          result: result,
          onPickAnother: controller.pickAndAnalyze,
        ),
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _Result extends StatelessWidget {
  const _Result({
    required this.photo,
    required this.result,
    required this.onPickAnother,
  });

  final Uint8List photo;
  final AnalyzeImageResponse result;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totalMs = result.timingsMs.values
        .fold<double>(0, (a, b) => a + b)
        .round();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: result.imageW / result.imageH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(photo, fit: BoxFit.fill),
                CustomPaint(
                  key: const Key('detections-overlay'),
                  painter: DetectionsPainter(
                    result: result,
                    faceColor: Colors.greenAccent,
                    skippedColor: Colors.amber,
                    bodyColor: Colors.lightBlueAccent,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.analyzeSummary(
            l10n.analyzeFacesFound(result.faces.length),
            l10n.analyzeBodiesFound(result.bodies.length),
            result.imageW,
            result.imageH,
            totalMs,
          ),
          key: const Key('analyze-summary'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (result.faces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(l10n.analyzeNoFaces),
          ),
        for (var i = 0; i < result.faces.length; i++)
          _FaceTile(index: i, face: result.faces[i]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onPickAnother,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(l10n.analyzePickAnother),
        ),
      ],
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({required this.index, required this.face});

  final int index;
  final DetectedFace face;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tier = qualityTier(face.quality.score);
    final tierLabel = switch (tier) {
      QualityTier.great => l10n.tierGreat,
      QualityTier.good => l10n.tierGood,
      QualityTier.fair => l10n.tierFair,
      QualityTier.poor => l10n.tierPoor,
    };
    return Card(
      key: Key('face-$index'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: face.cropJpeg != null
                ? Image.memory(face.cropJpeg!, fit: BoxFit.cover)
                : ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: const Icon(Icons.face_outlined),
                  ),
          ),
        ),
        title: Text(l10n.analyzeFaceTitle(index + 1)),
        subtitle: Text(
          '${l10n.analyzeFaceDetail(face.quality.facePx.round(), face.detScore.toStringAsFixed(2))}\n'
          '${face.passesGate ? l10n.analyzeMeetsGate : l10n.analyzeBelowGate}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(
            l10n.analyzeQuality(
              tierLabel,
              face.quality.score.toStringAsFixed(2),
            ),
          ),
          side: BorderSide(
            color: face.passesGate ? Colors.green : Colors.amber,
          ),
        ),
      ),
    );
  }
}

/// Face boxes (green = would be saved, amber = skipped) and body boxes over the analysed photo.
class DetectionsPainter extends CustomPainter {
  DetectionsPainter({
    required this.result,
    required this.faceColor,
    required this.skippedColor,
    required this.bodyColor,
  });

  final AnalyzeImageResponse result;
  final Color faceColor;
  final Color skippedColor;
  final Color bodyColor;

  Rect _rect(BBox b, Size size) {
    final sx = size.width / result.imageW;
    final sy = size.height / result.imageH;
    return Rect.fromLTWH(b.x * sx, b.y * sy, b.w * sx, b.h * sy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = bodyColor.withValues(alpha: 0.8);
    for (final b in result.bodies) {
      canvas.drawRect(_rect(b.bbox, size), body);
    }
    for (var i = 0; i < result.faces.length; i++) {
      final f = result.faces[i];
      final color = f.passesGate ? faceColor : skippedColor;
      final rect = _rect(f.bbox, size);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );
      final label = TextPainter(
        text: TextSpan(
          text: ' ${i + 1} ',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(rect.left, (rect.top - label.height).clamp(0, size.height)),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionsPainter old) => old.result != result;
}
