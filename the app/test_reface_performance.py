"""
Tests for Phase 3: Performance, memory optimization, eviction, adaptive recognition, and adaptive restorer.
"""
import unittest
from unittest.mock import MagicMock, patch
import numpy as np

from reface_selection import FaceSelector
from face_compositor import FaceCompositor, CompositeConfig, _ONES_128
from face_restore import FaceRestorer
from face_masking import FaceMasker
from mobile_api.engines import InsightEngines


class TestInsightEnginesLifecycle(unittest.TestCase):
    def test_insight_engines_unload_and_lazy_restart(self):
        """Scan -> unload -> Reface -> Scan transition works without holding closed worker."""
        log_messages = []
        engines = InsightEngines(log=log_messages.append, isolate_scans=True)

        mock_worker = MagicMock()
        mock_worker.loaded = True
        engines._scan_worker = mock_worker

        self.assertIsNotNone(engines._scan_worker)
        # Unload must close worker and set to None
        engines.unload()
        mock_worker.close.assert_called_once()
        self.assertIsNone(engines._scan_worker)
        self.assertIsNone(engines._face_app)

        # Next scan demand lazily recreates worker
        with patch("mobile_api.scan_worker.ScanWorker") as MockScanWorker:
            fresh_worker = MagicMock()
            MockScanWorker.return_value = fresh_worker
            worker = engines._get_scan_worker()
            self.assertIs(worker, fresh_worker)
            self.assertIs(engines._scan_worker, fresh_worker)


class TestAdaptiveRecognition(unittest.TestCase):
    def test_adaptive_recognition_skips_arcface_on_stable_tracks(self):
        """Stable confirmed tracks skip ArcFace calls on intermediate frames with immediate re-check on low confidence."""
        ref = np.random.randn(512).astype(np.float32)
        ref /= np.linalg.norm(ref)
        selector = FaceSelector([ref], [0], adaptive_recognition=True)

        calls = []
        def embed_fn():
            calls.append(1)
            return ref

        # Frames 0, 1, 2: Initial confirmation (3 consecutive hits)
        for f in range(3):
            self.assertFalse(selector.can_skip_recognition(1, f, det_score=0.95, motion_jump=False))
            self.assertTrue(selector.wants(1, f, embed_fn))
        self.assertEqual(len(calls), 3)
        self.assertEqual(selector.track_confirmed_counts[1], 3)

        # Frame 3: Confirmed track, confident det, no jump, frame 3 % 4 != 0 -> CAN SKIP!
        self.assertTrue(selector.can_skip_recognition(1, 3, det_score=0.90, motion_jump=False))
        # Embed_fn was NOT called because recognition was skipped!
        self.assertEqual(len(calls), 3)

        # Frame 4: Cadence check frame (4 % 4 == 0) -> CANNOT SKIP (triggers ArcFace re-verification)
        self.assertFalse(selector.can_skip_recognition(1, 4, det_score=0.90, motion_jump=False))
        self.assertTrue(selector.wants(1, 4, embed_fn))
        self.assertEqual(len(calls), 4)

        # Frame 5: Confident det, frame 5 % 4 != 0 -> CAN SKIP!
        self.assertTrue(selector.can_skip_recognition(1, 5, det_score=0.90, motion_jump=False))
        self.assertEqual(len(calls), 4)

        # Frame 6: Det score dips below 0.65 -> CANNOT SKIP (triggers immediate re-verification)
        self.assertFalse(selector.can_skip_recognition(1, 6, det_score=0.55, motion_jump=False))
        self.assertTrue(selector.wants(1, 6, embed_fn))
        self.assertEqual(len(calls), 5)

        # Frame 7: Motion jump occurs -> CANNOT SKIP (triggers immediate re-verification)
        self.assertFalse(selector.can_skip_recognition(1, 7, det_score=0.90, motion_jump=True))
        self.assertTrue(selector.wants(1, 7, embed_fn))
        self.assertEqual(len(calls), 6)

    def test_bystander_swap_resets_confirmed_track(self):
        """If a bystander (unselected reference) matches better during re-check, track is zeroed and rejected."""
        ref_target = np.random.randn(512).astype(np.float32)
        ref_target /= np.linalg.norm(ref_target)

        ref_bystander = np.random.randn(512).astype(np.float32)
        ref_bystander /= np.linalg.norm(ref_bystander)

        selector = FaceSelector([ref_target, ref_bystander], [0], adaptive_recognition=True)

        # Confirm track on target
        for f in range(3):
            self.assertTrue(selector.wants(1, f, lambda: ref_target))
        self.assertEqual(selector.track_confirmed_counts[1], 3)

        # Face suddenly resembles bystander: must reject and reset
        rejected = selector.wants(1, 4, lambda: ref_bystander)
        self.assertFalse(rejected)
        self.assertEqual(selector.track_confirmed_counts[1], 0)

    def test_track_zero_does_not_pollute_confirmed_counts(self):
        """Track 0 used by video recovery checks does not mutate track_confirmed_counts."""
        ref = np.random.randn(512).astype(np.float32)
        ref /= np.linalg.norm(ref)
        selector = FaceSelector([ref], [0], adaptive_recognition=True)

        self.assertTrue(selector.wants(0, 0, lambda: ref))
        self.assertNotIn(0, selector.track_confirmed_counts)


class TestAdaptiveRestorerHysteresis(unittest.TestCase):
    def test_hysteresis_prevents_flicker_around_boundary(self):
        """Adaptive restorer does not flicker when face size hovers around threshold (64px)."""
        cfg = CompositeConfig(adaptive_restorer=True, restorer_min_size=64)
        mock_restorer = MagicMock()
        mock_restorer.available = True
        mock_restorer.enhance.return_value = np.zeros((512, 512, 3), dtype=np.uint8)
        mock_masker = MagicMock()
        mock_masker.segment.return_value = np.zeros((512, 512), dtype=np.int64)

        compositor = FaceCompositor(mock_restorer, mock_masker, config=cfg)

        dummy_frame = np.zeros((200, 200, 3), dtype=np.uint8)
        dummy_swap = np.zeros((128, 128, 3), dtype=np.uint8)
        kps = np.array([[60, 60], [100, 60], [80, 80], [65, 100], [95, 100]], dtype=np.float32)
        m_swap = np.array([[1, 0, 0], [0, 1, 0]], dtype=np.float32)

        # Frame 1: Face is 75px (> 64px) -> Restorer ACTIVE
        compositor.prepare(dummy_frame, dummy_swap, m_swap, kps, track_id=1, native_px=75.0, restore=True)
        self.assertTrue(compositor._track_restorer_active[1])

        # Frame 2: Face shrinks slightly to 60px (below 64px, but above 56px) -> STAYS ACTIVE (hysteresis)
        compositor.prepare(dummy_frame, dummy_swap, m_swap, kps, track_id=1, native_px=60.0, restore=True)
        self.assertTrue(compositor._track_restorer_active[1])

        # Frame 3: Face shrinks further to 50px (< 56px) -> TURNS OFF
        compositor.prepare(dummy_frame, dummy_swap, m_swap, kps, track_id=1, native_px=50.0, restore=True)
        self.assertFalse(compositor._track_restorer_active[1])

        # Frame 4: Face grows slightly to 68px (above 64px, but below 72px) -> STAYS OFF (hysteresis)
        compositor.prepare(dummy_frame, dummy_swap, m_swap, kps, track_id=1, native_px=68.0, restore=True)
        self.assertFalse(compositor._track_restorer_active[1])

        # Frame 5: Face grows to 76px (> 72px) -> TURNS ON
        compositor.prepare(dummy_frame, dummy_swap, m_swap, kps, track_id=1, native_px=76.0, restore=True)
        self.assertTrue(compositor._track_restorer_active[1])


class TestResourceUnloadAndEviction(unittest.TestCase):
    def test_face_restorer_unload(self):
        restorer = FaceRestorer(model_name="nonexistent_for_test")
        restorer.session = MagicMock()
        restorer.available = True
        restorer.unload()
        self.assertIsNone(restorer.session)
        self.assertFalse(restorer.available)

    def test_face_masker_unload(self):
        masker = FaceMasker(load_parser=False, load_occluder=False)
        masker.parser = MagicMock()
        masker.occluder = MagicMock()
        masker._occluders = [(MagicMock(), "in", ("nchw", 256))]
        masker.unload()
        self.assertIsNone(masker.parser)
        self.assertIsNone(masker.occluder)
        self.assertEqual(len(masker._occluders), 0)

    def test_face_compositor_unload(self):
        mock_restorer = MagicMock()
        mock_masker = MagicMock()
        compositor = FaceCompositor(mock_restorer, mock_masker)
        compositor._pool = MagicMock()
        compositor.unload()
        self.assertIsNone(compositor._pool)
        mock_restorer.unload.assert_called_once()
        mock_masker.unload.assert_called_once()


if __name__ == "__main__":
    unittest.main()
