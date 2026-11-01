"""
Tests for outlines.py pure helpers and OutlineEngine.
"""

import sys
import math
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from outlines import (
    mask_to_polygon,
    apply_affine,
    to_image_coords,
    skeleton_mask,
    encode_outline,
    OutlineEngine,
)


def test_filled_circle():
    h, w = 300, 300
    mask = np.zeros((h, w), dtype=np.uint8)
    center = (150, 150)
    radius = 60
    cv2.circle(mask, center, radius, 255, -1)

    poly = mask_to_polygon(mask, max_points=64, min_area_frac=0.01)
    assert poly is not None, "Failed to get polygon for filled circle"
    assert 8 <= len(poly) <= 64, f"Expected 8..64 points, got {len(poly)}"

    expected_area = math.pi * (radius ** 2)
    actual_area = cv2.contourArea(poly)
    error_frac = abs(actual_area - expected_area) / expected_area
    assert error_frac <= 0.03, f"Area error {error_frac:.4f} > 3% (expected {expected_area}, got {actual_area})"
    print("PASS: test_filled_circle")


def test_noisy_mask_and_holes():
    h, w = 300, 300
    mask = np.zeros((h, w), dtype=np.uint8)
    # Main shape
    cv2.rectangle(mask, (50, 50), (250, 250), 255, -1)
    # Hole inside
    cv2.circle(mask, (150, 150), 30, 0, -1)
    # Specks outside
    cv2.circle(mask, (15, 15), 2, 255, -1)
    cv2.circle(mask, (280, 280), 3, 255, -1)

    poly = mask_to_polygon(mask, max_points=64, min_area_frac=0.01)
    assert poly is not None, "Failed to get polygon for noisy mask"
    # The external contour should enclose the whole box ~ (50, 50) to (250, 250)
    # Area of 200x200 box is 40000
    actual_area = cv2.contourArea(poly)
    assert actual_area >= 38000, f"External contour should ignore internal hole, got area {actual_area}"
    print("PASS: test_noisy_mask_and_holes")


def test_two_blobs_with_prefer():
    h, w = 300, 300
    mask = np.zeros((h, w), dtype=np.uint8)
    # Blob A: large (radius 60, center 100, 100)
    cv2.circle(mask, (100, 100), 60, 255, -1)
    # Blob B: smaller (radius 30, center 220, 220)
    cv2.circle(mask, (220, 220), 30, 255, -1)

    # Without prefer -> chooses Blob A (larger)
    poly_no_pref = mask_to_polygon(mask)
    assert poly_no_pref is not None
    assert poly_no_pref[:, 0].mean() < 150, "Expected larger blob A on left"

    # With prefer overlapping Blob B
    prefer_mask = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(prefer_mask, (220, 220), 10, 255, -1)
    poly_pref = mask_to_polygon(mask, prefer=prefer_mask)
    assert poly_pref is not None
    assert poly_pref[:, 0].mean() > 180, "Expected smaller blob B chosen due to prefer overlap"
    print("PASS: test_two_blobs_with_prefer")


def test_detailed_contour_max_points():
    h, w = 500, 500
    mask = np.zeros((h, w), dtype=np.uint8)
    # Draw star-like shape with many lobes
    center = (250, 250)
    pts = []
    for angle in np.linspace(0, 2 * math.pi, 200, endpoint=False):
        r = 150 + 40 * math.sin(10 * angle)
        x = int(center[0] + r * math.cos(angle))
        y = int(center[1] + r * math.sin(angle))
        pts.append([x, y])
    cv2.fillPoly(mask, [np.array(pts, dtype=np.int32)], 255)

    poly = mask_to_polygon(mask, max_points=32, min_area_frac=0.01)
    assert poly is not None
    assert 3 <= len(poly) <= 32, f"Expected <= 32 points, got {len(poly)}"
    print("PASS: test_detailed_contour_max_points")


def test_empty_and_tiny_mask():
    h, w = 100, 100
    empty = np.zeros((h, w), dtype=np.uint8)
    assert mask_to_polygon(empty) is None, "Empty mask must return None"

    # Tiny mask < 1% area (100x100 = 10000, 1% = 100 px area)
    tiny = np.zeros((h, w), dtype=np.uint8)
    cv2.rectangle(tiny, (10, 10), (14, 14), 255, -1) # 16 px
    assert mask_to_polygon(tiny, min_area_frac=0.01) is None, "Tiny mask must return None"
    print("PASS: test_empty_and_tiny_mask")


def test_affine_round_trip():
    poly = np.array([
        [100.0, 150.0],
        [200.0, 120.0],
        [250.0, 220.0],
        [150.0, 280.0],
        [80.0, 210.0],
    ], dtype=np.float32)

    # Affine: rotation 30 deg + translation + scale 1.2
    angle = 30.0 * math.pi / 180.0
    scale = 1.2
    cos_a, sin_a = math.cos(angle) * scale, math.sin(angle) * scale
    M = np.array([
        [cos_a, -sin_a, 45.0],
        [sin_a, cos_a, -20.0]
    ], dtype=np.float32)

    warped = apply_affine(poly, M)
    M_inv = cv2.invertAffineTransform(M)
    restored = apply_affine(warped, M_inv)

    diff = np.max(np.abs(restored - poly))
    assert diff <= 0.5, f"Expected round trip within 0.5 px, got max diff {diff}"
    print("PASS: test_affine_round_trip")


def test_skeleton_and_encoding():
    # 17 keypoints
    kpts = np.zeros((17, 2), dtype=np.float32)
    kpt_scores = np.ones(17, dtype=np.float32) * 0.9
    for i in range(17):
        kpts[i] = [100.0 + i * 5, 200.0 + i * 10]

    mask = skeleton_mask(kpts, kpt_scores, (300, 200), (50.0, 100.0), min_score=0.3)
    assert mask is not None
    assert mask.shape == (300, 200)
    assert np.sum(mask) > 0

    poly = np.array([[12.345, 67.891], [99.111, 45.678], [10.0, 20.0]], dtype=np.float32)
    encoded = encode_outline(poly)
    assert encoded == [[12.3, 67.9], [99.1, 45.7], [10.0, 20.0]]
    assert encode_outline(None) is None
    assert encode_outline(np.array([[1, 2]])) is None
    print("PASS: test_skeleton_and_encoding")


@dataclass
class FakeFace:
    bbox: List[float]
    kps: Optional[np.ndarray] = None


@dataclass
class FakeBody:
    bbox: List[float]
    kpts: Optional[np.ndarray] = None
    kpt_scores: Optional[np.ndarray] = None


@dataclass
class FakeFrameAnalysis:
    faces: list
    bodies: list
    passes_gate: list
    timings_ms: Dict[str, float] = field(default_factory=dict)


def test_engine_missing_models():
    # Missing models directory
    nonexistent = Path("nonexistent_models_dir_12345")
    engine = OutlineEngine(models_dir=nonexistent)
    img = np.zeros((400, 400, 3), dtype=np.uint8)

    face = FakeFace(bbox=[50, 50, 150, 150], kps=np.zeros((5, 2)))
    body = FakeBody(bbox=[40, 40, 200, 350])
    res = FakeFrameAnalysis(faces=[face], bodies=[body], passes_gate=[True])

    f_out, b_out = engine.compute(img, res)
    assert f_out == [None]
    assert b_out == [None]
    assert "outline" in res.timings_ms
    print("PASS: test_engine_missing_models")


def test_engine_with_fake_sessions():
    img = np.zeros((500, 500, 3), dtype=np.uint8)

    class FakeMasker:
        def __init__(self):
            self.parser = "fake_parser"

        def segment(self, crop):
            h, w = crop.shape[:2]
            seg = np.zeros((h, w), dtype=np.uint8)
            # Class 1 = skin
            cv2.circle(seg, (w // 2, h // 2), min(h, w) // 3, 1, -1)
            return seg

    class FakeRmbgSession:
        def __init__(self):
            pass

        def get_inputs(self):
            class InputMeta:
                name = "input"
            return [InputMeta()]

        def run(self, _, feeds):
            batch = feeds["input"]
            b_size = batch.shape[0]
            # output shape (B, 1, 1024, 1024)
            out = np.zeros((b_size, 1, 1024, 1024), dtype=np.float32)
            for i in range(b_size):
                cv2.circle(out[i, 0], (512, 512), 300, 1.0, -1)
            return [out]

    engine = OutlineEngine(masker=FakeMasker(), rmbg_session=FakeRmbgSession())

    # Face with 5-point kps
    kps = np.array([
        [200.0, 200.0],
        [280.0, 200.0],
        [240.0, 240.0],
        [210.0, 280.0],
        [270.0, 280.0]
    ], dtype=np.float32)
    face = FakeFace(bbox=[180, 180, 300, 300], kps=kps)
    body = FakeBody(bbox=[150, 150, 350, 450])
    res = FakeFrameAnalysis(faces=[face], bodies=[body], passes_gate=[True])

    f_out, b_out = engine.compute(img, res)
    assert len(f_out) == 1 and f_out[0] is not None
    assert len(b_out) == 1 and b_out[0] is not None

    # Verify points lie roughly in image bounds
    for pt in f_out[0]:
        assert -50 <= pt[0] <= 550 and -50 <= pt[1] <= 550, f"Face point out of bounds: {pt}"
    for pt in b_out[0]:
        assert -50 <= pt[0] <= 550 and -50 <= pt[1] <= 550, f"Body point out of bounds: {pt}"

    print("PASS: test_engine_with_fake_sessions")


class RecordingRmbg:
    def __init__(self, provider="CPUExecutionProvider", error=None):
        self.provider, self.error = provider, error
        self.calls = []

    def get_providers(self):
        return [self.provider]

    def get_inputs(self):
        return [SimpleNamespace(name="input")]

    def run(self, _, feeds):
        inp = feeds["input"]
        self.calls.append(inp.copy())
        if self.error:
            raise RuntimeError(self.error)
        out = np.zeros((len(inp), 1, 32, 32), np.float32)
        out[:, :, 5:27, 5:27] = 1
        return [out]


def test_body_outlines_bound_memory_and_preserve_target_order():
    session = RecordingRmbg()
    engine = OutlineEngine(rmbg_session=session)
    img = np.full((200, 300, 3), 255, np.uint8)
    bodies = [FakeBody([10, 10, 70, 150]), FakeBody([0, 0, 0, 0]),
              FakeBody([180, 10, 260, 170])] * 5
    result = engine.body_outlines(img, bodies)
    assert len(session.calls) == 10
    assert all(inp.shape == (1, 3, 1024, 1024) for inp in session.calls)
    assert all(inp.dtype == np.float32 and np.all(inp == 0.5) for inp in session.calls)
    for i in range(0, len(bodies), 3):
        assert result[i] is not None and result[i][:, 0].max() < 80
        assert result[i + 1] is None
        assert result[i + 2] is not None and result[i + 2][:, 0].min() > 170


def test_gpu_oom_retries_same_crop_and_stays_on_cpu():
    gpu = RecordingRmbg("CUDAExecutionProvider", "Failed to allocate memory for requested buffer")
    cpu = RecordingRmbg()
    engine = OutlineEngine(rmbg_session=gpu)
    img = np.zeros((200, 200, 3), np.uint8)
    def create(providers):
        assert engine.rmbg_session is None, "Release CUDA session before constructing CPU session"
        assert providers == ["CPUExecutionProvider"]
        return cpu
    with patch.object(engine, "_create_rmbg_session", side_effect=create) as factory:
        result = engine.body_outlines(img, [FakeBody([10, 10, 150, 190])] * 3)
        assert all(poly is not None for poly in result)
        assert len(gpu.calls) == 1 and len(cpu.calls) == 3
        np.testing.assert_array_equal(gpu.calls[0], cpu.calls[0])
        assert engine.body_outlines(img, [FakeBody([10, 10, 150, 190])])[0] is not None
        assert factory.call_count == 1 and len(gpu.calls) == 1


def test_rmbg_errors_do_not_loop_or_switch_cpu_for_unrelated_errors():
    img = np.zeros((100, 100, 3), np.uint8)
    bodies = [FakeBody([10, 10, 90, 90])]
    for provider, error in [("CPUExecutionProvider", "out of memory"),
                            ("CUDAExecutionProvider", "Invalid input shape")]:
        session = RecordingRmbg(provider, error)
        engine = OutlineEngine(rmbg_session=session)
        with patch.object(engine, "_create_rmbg_session") as factory:
            assert engine.body_outlines(img, bodies) == [None]
            factory.assert_not_called()
        assert len(session.calls) == 1
    engine = OutlineEngine(rmbg_session=RecordingRmbg("CUDAExecutionProvider", "out of memory"))
    cpu = RecordingRmbg(error="out of memory")
    with patch.object(engine, "_create_rmbg_session", return_value=cpu) as factory:
        assert engine.body_outlines(img, bodies) == [None]
        assert factory.call_count == 1 and len(cpu.calls) == 1


def test_rmbg_session_uses_conservative_memory_options():
    engine = OutlineEngine()
    with patch("outlines.ort.InferenceSession") as factory:
        engine._create_rmbg_session(["CUDAExecutionProvider", "CPUExecutionProvider"])
        options = factory.call_args.kwargs
        assert options["sess_options"].enable_cpu_mem_arena is False
        assert options["sess_options"].enable_mem_pattern is False
        cuda = options["providers"][0]
        assert cuda[0] == "CUDAExecutionProvider"
        assert cuda[1]["cudnn_conv_use_max_workspace"] == "0"
        assert cuda[1]["arena_extend_strategy"] == "kSameAsRequested"


def test_failed_session_creation_can_recover_on_a_later_request():
    img = np.zeros((100, 100, 3), np.uint8)
    bodies = [FakeBody([10, 10, 90, 90])]
    for initial in (None, RecordingRmbg("CUDAExecutionProvider", "out of memory")):
        engine = OutlineEngine(rmbg_session=initial)
        recovered = RecordingRmbg()
        with patch.object(Path, "exists", return_value=True), patch.object(
            engine, "_create_rmbg_session", side_effect=[MemoryError("host memory"), recovered]
        ) as factory:
            assert engine.body_outlines(img, bodies) == [None]
            assert not engine._rmbg_loaded
            assert engine.body_outlines(img, bodies)[0] is not None
            assert factory.call_count == 2


if __name__ == "__main__":
    try:
        test_filled_circle()
        test_noisy_mask_and_holes()
        test_two_blobs_with_prefer()
        test_detailed_contour_max_points()
        test_empty_and_tiny_mask()
        test_affine_round_trip()
        test_skeleton_and_encoding()
        test_engine_missing_models()
        test_engine_with_fake_sessions()
        test_body_outlines_bound_memory_and_preserve_target_order()
        test_gpu_oom_retries_same_crop_and_stays_on_cpu()
        test_rmbg_errors_do_not_loop_or_switch_cpu_for_unrelated_errors()
        test_rmbg_session_uses_conservative_memory_options()
        test_failed_session_creation_can_recover_on_a_later_request()
        print("\nALL OUTLINES TESTS PASSED!")
    except Exception as e:
        import traceback
        traceback.print_exc()
        sys.exit(1)
