"""Unit tests for RefaceDiagnostics tracking, latency percentiles, and gap analysis."""

import unittest
from reface_diagnostics import (
    FAILURE_REASONS,
    FrameOutcome,
    FrameTiming,
    RefaceDiagnostics,
)


class TestRefaceDiagnostics(unittest.TestCase):

    def test_failure_reasons_contain_mandatory_classifications(self):
        expected = [
            "not_detected",
            "identity_rejected",
            "tracking_failed",
            "alignment_invalid",
            "model_failed",
            "mask_invalid",
            "no_visible_change",
            "low_quality",
        ]
        for r in expected:
            self.assertIn(r, FAILURE_REASONS)

    def test_latency_percentiles_and_phase_averages(self):
        diag = RefaceDiagnostics(fps=30.0)
        # Record 10 frames with increasing latencies 10ms .. 100ms
        for i in range(10):
            ms = (i + 1) * 10.0
            timing = FrameTiming(
                frame_index=i,
                timestamp_sec=i / 30.0,
                decode_ms=2.0,
                detect_ms=5.0,
                match_ms=3.0,
                swap_ms=ms * 0.4,
                restore_ms=ms * 0.3,
                composite_ms=ms * 0.2,
                encode_ms=ms * 0.1,
                total_frame_ms=ms,
            )
            diag.record_timing(timing)
            status = "swapped" if i != 4 else "failed"
            reason = "" if status == "swapped" else "tracking_failed"
            diag.record_outcome(
                FrameOutcome(
                    frame_index=i,
                    timestamp_sec=i / 30.0,
                    track_id=1,
                    status=status,
                    reason=reason,
                )
            )

        diag.record_resource_usage(vram_mb=3500.0, ram_mb=2100.0)
        summary = diag.summarize()

        self.assertEqual(summary["total_frames"], 10)
        self.assertEqual(summary["swapped_count"], 9)
        self.assertEqual(summary["failed_count"], 1)
        self.assertEqual(summary["reasons"]["tracking_failed"], 1)

        # Percentiles
        self.assertEqual(summary["latency"]["min_ms"], 10.0)
        self.assertEqual(summary["latency"]["max_ms"], 100.0)
        self.assertEqual(summary["latency"]["p50_ms"], 60.0)
        self.assertEqual(summary["latency"]["median_ms"], 60.0)
        self.assertEqual(summary["latency"]["mean_ms"], 55.0)

        # Phases
        phases = summary["latency"]["phases"]
        self.assertEqual(phases["decode_ms"], 2.0)
        self.assertEqual(phases["detect_ms"], 5.0)
        self.assertEqual(phases["match_ms"], 3.0)

        # Resources
        self.assertEqual(summary["resources"]["vram_peak_mb"], 3500.0)
        self.assertEqual(summary["resources"]["ram_peak_mb"], 2100.0)

    def test_gap_detection_identifies_unswapped_runs(self):
        diag = RefaceDiagnostics(fps=30.0)
        # Frames 0..2 swapped, 3..5 skipped/failed, 6..9 swapped
        for i in range(10):
            diag.record_timing(
                FrameTiming(frame_index=i, timestamp_sec=i / 30.0, total_frame_ms=20.0)
            )
            if 3 <= i <= 5:
                status = "skipped" if i == 3 else "failed"
                reason = "not_detected" if i == 3 else "identity_rejected"
            else:
                status = "swapped"
                reason = ""
            diag.record_outcome(
                FrameOutcome(
                    frame_index=i,
                    timestamp_sec=i / 30.0,
                    track_id=1,
                    status=status,
                    reason=reason,
                )
            )

        summary = diag.summarize()
        self.assertEqual(summary["gap_count"], 1)
        self.assertEqual(summary["longest_gap_frames"], 3)
        self.assertEqual(summary["longest_gap_ms"], 100.0)

        gap = summary["gaps"][0]
        self.assertEqual(gap["start_frame"], 3)
        self.assertEqual(gap["end_frame"], 5)
        self.assertEqual(gap["length_frames"], 3)
        self.assertEqual(gap["reason_breakdown"], {"not_detected": 1, "identity_rejected": 2})

    def test_trimmed_video_reports_partial_target_failure_at_absolute_index(self):
        diag = RefaceDiagnostics(fps=25)
        for index in (100, 101):
            diag.record_timing(FrameTiming(index, index / 25))
            diag.record_outcome(FrameOutcome(index, index / 25, 1, "swapped"))
        diag.record_outcome(FrameOutcome(101, 101 / 25, 2, "failed", "mask_invalid"))
        gap, = diag.analyze_gaps()
        self.assertEqual((gap.start_frame, gap.end_frame, gap.start_sec), (101, 101, 4.04))

    def test_bounded_memory_logging(self):
        diag = RefaceDiagnostics(max_logged_frames=50, fps=25.0)
        for i in range(120):
            diag.record_timing(
                FrameTiming(frame_index=i, timestamp_sec=i / 25.0, total_frame_ms=15.0)
            )
            diag.record_outcome(
                FrameOutcome(
                    frame_index=i,
                    timestamp_sec=i / 25.0,
                    track_id=1,
                    status="swapped",
                )
            )
        self.assertEqual(len(diag.timings), 50)
        self.assertEqual(len(diag.outcomes), 50)
        summary = diag.summarize()
        self.assertTrue(summary["truncated_log"])


if __name__ == "__main__":
    unittest.main()
