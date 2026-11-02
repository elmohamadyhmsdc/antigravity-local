import 'package:flutter/material.dart';

import '../atoms/progress_bar.dart';

enum ProgressCardType { scan, job }

class ProgressCardData {
  const ProgressCardData({
    required this.type,
    required this.title,
    this.subtitle,
    this.progress,
    this.stepLabel,
    this.etaLabel,
    this.isPaused = false,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onTap,
  });

  final ProgressCardType type;
  final String title;
  final String? subtitle;
  final double? progress;
  final String? stepLabel;
  final String? etaLabel;
  final bool isPaused;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;
}

class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key, required this.data, this.margin});

  final ProgressCardData data;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = data.type == ProgressCardType.scan
        ? Icons.document_scanner_outlined
        : Icons.model_training;

    return Card(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      data.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (data.isPaused)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PAUSED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              if (data.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  data.subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CustomProgressBar(
                progress: data.isPaused
                    ? (data.progress ?? 0.0)
                    : data.progress,
                label: data.stepLabel,
                secondaryLabel: data.etaLabel,
              ),
              if (data.onPause != null ||
                  data.onResume != null ||
                  data.onCancel != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (data.isPaused && data.onResume != null)
                      TextButton.icon(
                        onPressed: data.onResume,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Resume'),
                      )
                    else if (!data.isPaused && data.onPause != null)
                      TextButton.icon(
                        onPressed: data.onPause,
                        icon: const Icon(Icons.pause, size: 16),
                        label: const Text('Pause'),
                      ),
                    if (data.onCancel != null)
                      TextButton(
                        onPressed: data.onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('Cancel'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
