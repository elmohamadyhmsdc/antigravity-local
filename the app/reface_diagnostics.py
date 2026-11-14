"""
Antigravity Reface - Frame-level Diagnostics & Telemetry Tracker.

Provides fine-grained phase latency tracking, gap detection, bounded memory logging,
and traceable failure classification for Reface video and image jobs.
"""

import math
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional


FAILURE_REASONS = (
    "not_detected",        # No face detected in frame / search region
    "identity_rejected",   # Face detected but did not match target identity
    "tracking_failed",     # Face tracker lost track across temporal frames
    "alignment_invalid",   # Landmarks invalid or outside affine crop bounds
    "model_failed",        # Neural network inference raised error or returned null
    "mask_invalid",        # Segmentation mask empty, corrupted or out of bounds
    "no_visible_change",   # Output identical to input or masked out completely
    "low_quality",         # Face too small (< MIN_FACE_PX) or blurred below gate
)

GROUND_TRUTH_STATES = (
    "present_processable", # Target face clearly visible and processable
    "occluded",            # Target face heavily occluded (> 70% covered)
    "out_of_frame",        # Target person physically not in camera view
    "uncertain",           # Extreme blur, motion streak, or ambiguous identity
)


@dataclass
class FrameTiming:
    frame_index: int
    timestamp_sec: float
    decode_ms: float = 0.0
    detect_ms: float = 0.0
    match_ms: float = 0.0
    swap_ms: float = 0.0
    restore_ms: float = 0.0
    composite_ms: float = 0.0
    encode_ms: float = 0.0
    total_frame_ms: float = 0.0
    prepare_ms: float = 0.0


@dataclass
class FrameOutcome:
    frame_index: int
    timestamp_sec: float
    track_id: int
    status: str            # "swapped", "skipped", "failed", "degraded"
    reason: str = ""       # One of FAILURE_REASONS or custom warning
    ground_truth: str = "present_processable"
    face_px: int = 0
    confidence: float = 1.0


@dataclass
class GapRecord:
    start_frame: int
    end_frame: int
    length_frames: int
    start_sec: float
    end_sec: float
    reason_breakdown: Dict[str, int] = field(default_factory=dict)


class RefaceDiagnostics:
    """Bounded, high-performance in-memory diagnostics tracker."""

    def __init__(self, max_logged_frames: int = 5000, fps: float = 30.0):
        self.max_logged_frames = max_logged_frames
        self.fps = max(fps, 1.0)
        self.start_wall_clock = time.perf_counter()
        self.end_wall_clock: Optional[float] = None

        self.timings: List[FrameTiming] = []
        self.outcomes: List[FrameOutcome] = []
        self.outcomes_truncated = False

        # Peak resource counters
        self.vram_peak_mb: float = 0.0
        self.ram_peak_mb: float = 0.0
        self.total_frames_recorded: int = 0

    def record_resource_usage(self, vram_mb: float = 0.0, ram_mb: float = 0.0):
        if vram_mb > self.vram_peak_mb:
            self.vram_peak_mb = vram_mb
        if ram_mb > self.ram_peak_mb:
            self.ram_peak_mb = ram_mb

    def record_timing(self, timing: FrameTiming):
        self.total_frames_recorded += 1
        if len(self.timings) < self.max_logged_frames:
            self.timings.append(timing)

    def record_outcome(self, outcome: FrameOutcome):
        if len(self.outcomes) < self.max_logged_frames:
            self.outcomes.append(outcome)
        else:
            self.outcomes_truncated = True

    def finish(self):
        self.end_wall_clock = time.perf_counter()

    def total_wall_clock_sec(self) -> float:
        end = self.end_wall_clock or time.perf_counter()
        return max(0.0, end - self.start_wall_clock)

    def analyze_gaps(self, min_gap_frames: int = 1) -> List[GapRecord]:
        """Detect contiguous sequences where processable target faces were not swapped."""
        gaps: List[GapRecord] = []
        in_gap = False
        gap_start = 0
        reasons: Dict[str, int] = {}

        # Sort outcomes by frame_index
        sorted_outcomes = sorted(self.outcomes, key=lambda o: (o.frame_index, o.track_id))
        
        # Group by frame index to see if target was swapped in that frame
        frames_map: Dict[int, List[FrameOutcome]] = {}
        for o in sorted_outcomes:
            frames_map.setdefault(o.frame_index, []).append(o)

        indices = sorted({t.frame_index for t in self.timings} | frames_map.keys())
        if not indices:
            return gaps
        for frame_idx in indices:
            frame_records = frames_map.get(frame_idx, [])
            expected = [r for r in frame_records if r.ground_truth == "present_processable"]
            missed = not frame_records or any(r.status != "swapped" for r in expected)

            if missed:
                if not in_gap:
                    in_gap = True
                    gap_start = frame_idx
                    reasons = {}
                for r in frame_records:
                    if r.reason:
                        reasons[r.reason] = reasons.get(r.reason, 0) + 1
            else:
                if in_gap:
                    length = frame_idx - gap_start
                    if length >= min_gap_frames:
                        gaps.append(
                            GapRecord(
                                start_frame=gap_start,
                                end_frame=frame_idx - 1,
                                length_frames=length,
                                start_sec=round(gap_start / self.fps, 3),
                                end_sec=round((frame_idx - 1) / self.fps, 3),
                                reason_breakdown=dict(reasons),
                            )
                        )
                    in_gap = False

        if in_gap:
            end_idx = indices[-1]
            length = end_idx - gap_start + 1
            if length >= min_gap_frames:
                gaps.append(
                    GapRecord(
                        start_frame=gap_start,
                        end_frame=end_idx,
                        length_frames=length,
                        start_sec=round(gap_start / self.fps, 3),
                        end_sec=round(end_idx / self.fps, 3),
                        reason_breakdown=dict(reasons),
                    )
                )

        return gaps

    def summarize(self) -> Dict[str, Any]:
        """Produce comprehensive summary metrics matching Phase 1 spec."""
        total_frames = self.total_frames_recorded if self.total_frames_recorded > 0 else len(self.timings)
        times = [t.total_frame_ms for t in self.timings if t.total_frame_ms > 0]
        swapped_count = sum(1 for o in self.outcomes if o.status == "swapped")
        skipped_count = sum(1 for o in self.outcomes if o.status == "skipped")
        failed_count = sum(1 for o in self.outcomes if o.status == "failed")
        degraded_count = sum(1 for o in self.outcomes if o.status == "degraded")

        gaps = self.analyze_gaps()
        longest_gap_frames = max((g.length_frames for g in gaps), default=0)
        longest_gap_ms = round((longest_gap_frames / self.fps) * 1000.0, 1)

        # Percentile calculations
        sorted_times = sorted(times)
        p50 = sorted_times[int(len(sorted_times) * 0.50)] if sorted_times else 0.0
        p95 = sorted_times[int(len(sorted_times) * 0.95)] if sorted_times else 0.0
        median = p50
        mean = sum(times) / max(len(times), 1)

        # Aggregate phase times
        phase_averages = {
            "decode_ms": round(sum(t.decode_ms for t in self.timings) / max(total_frames, 1), 2),
            "detect_ms": round(sum(t.detect_ms for t in self.timings) / max(total_frames, 1), 2),
            "match_ms": round(sum(t.match_ms for t in self.timings) / max(total_frames, 1), 2),
            "swap_ms": round(sum(t.swap_ms for t in self.timings) / max(total_frames, 1), 2),
            "restore_ms": round(sum(t.restore_ms for t in self.timings) / max(total_frames, 1), 2),
            "prepare_ms": round(sum(t.prepare_ms for t in self.timings) / max(total_frames, 1), 2),
            "composite_ms": round(sum(t.composite_ms for t in self.timings) / max(total_frames, 1), 2),
            "encode_ms": round(sum(t.encode_ms for t in self.timings) / max(total_frames, 1), 2),
        }

        # Reason breakdown
        reasons_dist: Dict[str, int] = {}
        for o in self.outcomes:
            if o.reason:
                reasons_dist[o.reason] = reasons_dist.get(o.reason, 0) + 1

        return {
            "total_frames": total_frames,
            "wall_clock_sec": round(self.total_wall_clock_sec(), 3),
            "fps": round(self.fps, 2),
            "gap_basis": "estimated_from_render_outcomes",
            "swapped_count": swapped_count,
            "skipped_count": skipped_count,
            "failed_count": failed_count,
            "degraded_count": degraded_count,
            "gaps": [asdict(g) for g in gaps],
            "gap_count": len(gaps),
            "longest_gap_frames": longest_gap_frames,
            "longest_gap_ms": longest_gap_ms,
            "latency": {
                "mean_ms": round(mean, 2),
                "median_ms": round(median, 2),
                "p50_ms": round(p50, 2),
                "p95_ms": round(p95, 2),
                "min_ms": round(sorted_times[0], 2) if sorted_times else 0.0,
                "max_ms": round(sorted_times[-1], 2) if sorted_times else 0.0,
                "phases": phase_averages,
            },
            "reasons": reasons_dist,
            "resources": {
                "vram_peak_mb": round(self.vram_peak_mb, 1),
                "ram_peak_mb": round(self.ram_peak_mb, 1),
            },
            "truncated_log": self.total_frames_recorded > len(self.timings) or self.outcomes_truncated,
        }
