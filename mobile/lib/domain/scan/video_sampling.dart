/// Match the PC policy for older servers; the new PC uses its decoded duration.
/// Aim for roughly 480 samples, bounded between 0.5s and 10s per sample.
double adaptiveVideoInterval(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return 1.0;
  return (durationMs / 1000 / 480).clamp(0.5, 10.0);
}
