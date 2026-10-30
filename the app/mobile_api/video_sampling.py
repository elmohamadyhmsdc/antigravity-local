"""Duration-aware sampling; the selected grid is pinned in each job checkpoint."""
import math


def adaptive_interval(duration_seconds):
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        return 1.0
    return min(10.0, max(0.5, duration_seconds / 480.0))
