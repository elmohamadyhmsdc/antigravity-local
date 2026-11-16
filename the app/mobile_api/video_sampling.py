"""Duration-aware sampling; the selected grid is pinned in each job checkpoint."""
import math

QUICK_SAMPLE_LIMIT = 60


def quick_sample_step(total_frames, fps):
    """At most 60 samples and no denser than once per second."""
    return max(1, math.ceil(fps), math.ceil(total_frames / QUICK_SAMPLE_LIMIT))


def adaptive_interval(duration_seconds):
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        return 1.0
    return min(10.0, max(0.5, duration_seconds / 480.0))
