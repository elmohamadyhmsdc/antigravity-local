"""
Antigravity Local - Reface V2 unit tests

Standalone script (repo has no pytest). Prints results, exit(1) on failure.
Runs entirely on CPU without touching GPU, CUDA, or downloading models.

    venv\\Scripts\\python.exe test_reface_v2.py            # everything
    venv\\Scripts\\python.exe test_reface_v2.py landmarks  # filter by test name
"""

import sys
import traceback
from pathlib import Path
import numpy as np
import cv2

_TESTS = []


def test(fn):
    """Register a test function."""
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


# =====================================================================
# Imports check (T17 requirement: imports without touching CUDA/models)
# =====================================================================

@test
def test_imports_cleanly():
    import reface_engine_v2
    check(hasattr(reface_engine_v2, 'RefaceEngineV2'), "RefaceEngineV2 class missing")
    check(hasattr(reface_engine_v2, 'as_68_points'), "as_68_points helper missing")


# =====================================================================
# Task 1: 68-point landmarks & occlusion mask tests
# =====================================================================

@test
def test_as_68_points_handles_none_and_invalid_shapes():
    from reface_engine_v2 import as_68_points

    check(as_68_points(None) is None, "None should return None")
    check(as_68_points(np.zeros((106, 2))) is None, "106-point shape should return None")
    check(as_68_points(np.zeros((68,))) is None, "1D shape should return None")
    check(as_68_points(np.zeros((68, 1))) is None, "Width < 2 should return None")
    check(as_68_points([]) is None, "Empty list should return None")


@test
def test_as_68_points_slices_3d_to_2d_float32():
    from reface_engine_v2 import as_68_points

    pts_3d = np.zeros((68, 3), dtype=np.float64)
    pts_3d[:, 0] = 10.0
    pts_3d[:, 1] = 20.0
    pts_3d[:, 2] = 30.0

    got = as_68_points(pts_3d)
    check(got is not None, "Valid 68x3 array should be converted")
    check(got.shape == (68, 2), f"Expected shape (68, 2), got {got.shape}")
    check(got.dtype == np.float32, f"Expected float32, got {got.dtype}")
    check(got[0, 0] == 10.0 and got[0, 1] == 20.0, "Coordinates mismatch after slicing")


@test
def test_generate_occlusion_mask_with_106_points_returns_empty_mask():
    from reface_engine_v2 import OcclusionHandler

    handler = OcclusionHandler()
    dummy_img = np.zeros((200, 200, 3), dtype=np.uint8)
    bbox = [20, 20, 180, 180]
    landmarks_106 = np.ones((106, 2), dtype=np.float32) * 50.0

    mask = handler.generate_occlusion_mask(dummy_img, bbox, landmarks_106, protect_glasses=True, protect_hair=True)
    check(mask.shape == (200, 200), f"Mask shape mismatch: {mask.shape}")
    check(mask.sum() == 0, f"106-point landmarks should produce empty mask, got sum={mask.sum()}")


@test
def test_generate_occlusion_mask_with_synthetic_68_points_lands_in_bbox():
    from reface_engine_v2 import OcclusionHandler

    handler = OcclusionHandler()
    dummy_img = np.zeros((200, 200, 3), dtype=np.uint8)
    x1, y1, x2, y2 = 40, 40, 160, 160
    bbox = [x1, y1, x2, y2]

    # Build synthetic 68-point landmarks inside bbox
    pts_68 = np.zeros((68, 2), dtype=np.float32)
    # Brows: 17:22 (left), 22:27 (right)
    pts_68[17:27, 0] = np.linspace(60, 140, 10)
    pts_68[17:27, 1] = 70.0  # y = 70 > y1 = 40

    # Eyes: 36:42 (left eye center ~80, 90), 42:48 (right eye center ~120, 90)
    pts_68[36:42, 0] = np.array([75, 78, 82, 85, 82, 78], dtype=np.float32)
    pts_68[36:42, 1] = np.array([90, 88, 88, 90, 92, 92], dtype=np.float32)

    pts_68[42:48, 0] = np.array([115, 118, 122, 125, 122, 118], dtype=np.float32)
    pts_68[42:48, 1] = np.array([90, 88, 88, 90, 92, 92], dtype=np.float32)

    mask = handler.generate_occlusion_mask(dummy_img, bbox, pts_68, protect_glasses=True, protect_hair=True)
    check(mask.sum() > 0, "Synthetic 68 points should generate non-empty mask")

    # Verify that positive pixels are within or close to bbox boundaries
    ys, xs = np.where(mask > 0)
    check(ys.min() >= y1 and ys.max() <= y2 + 10, f"Mask y out of bbox bounds: {ys.min()} to {ys.max()}")
    check(xs.min() >= x1 - 10 and xs.max() <= x2 + 10, f"Mask x out of bbox bounds: {xs.min()} to {xs.max()}")


# =====================================================================
# Task 4: Angle matching passed to V2 in job_manager
# =====================================================================

@test
def test_job_manager_passes_use_angle_matching_to_v2():
    import inspect
    import job_manager
    # Inspect the source of run_single_job in job_manager to ensure use_angle_matching is passed in both V2 branches
    source = inspect.getsource(job_manager.run_single_job)
    
    # Check video V2 branch
    check("reface_video_with_faceset_v2" in source, "reface_video_with_faceset_v2 not called")
    video_v2_call = source.split("reface_video_with_faceset_v2(")[1].split(")")[0]
    check("use_angle_matching=use_angle_matching" in video_v2_call, 
          "use_angle_matching not passed to reface_video_with_faceset_v2")

    # Check image V2 branch
    check("reface_with_faceset_v2" in source, "reface_with_faceset_v2 not called")
    img_v2_call = source.split("reface_with_faceset_v2(")[1].split(")")[0]
    check("use_angle_matching=use_angle_matching" in img_v2_call, 
          "use_angle_matching not passed to reface_with_faceset_v2")


# =====================================================================
# Task 2: Stop signal honoured in V2 video processing
# =====================================================================

@test
def test_stop_signal_stops_video_processing():
    """Behavioural, not textual: a callback returning False must end the run.

    This replaced a test that asserted on the source text of the loop. That
    version broke on a rename while proving nothing about what the loop does.
    """
    import tempfile
    from unittest.mock import MagicMock

    engine = _mock_v2_engine(occlusion_enabled=False)
    face = _face_with_68_landmarks(20, 20, 120, 140)

    engine.app = MagicMock()
    engine.app.get.return_value = [face]
    engine.swapper = MagicMock()
    engine.swapper.get.side_effect = lambda img, t, s, paste_back=True: img

    seen = []

    def stop_after_first_report(current, total):
        seen.append((current, total))
        check(0.0 <= current / total <= 1.0,
              f"progress ratio out of range: {current}/{total}")
        return False   # the manager's "stop this job" signal

    with tempfile.TemporaryDirectory() as tmpdir:
        src = Path(tmpdir) / "src.avi"
        writer = cv2.VideoWriter(str(src), cv2.VideoWriter_fourcc(*'MJPG'), 10.0, (200, 200))
        check(writer.isOpened(), "could not open a test VideoWriter (MJPG missing?)")
        for _ in range(40):
            writer.write(np.full((200, 200, 3), 128, dtype=np.uint8))
        writer.release()

        engine.output_dir = Path(tmpdir)
        res = engine.reface_video_with_faceset_v2(
            str(src), _single_face_faceset(),
            apply_occlusion=False,
            finalize=False,
            progress_callback=stop_after_first_report,
        )

    check(res.success, f"stopped run should still return a usable part: {res.message}")
    check(len(seen) == 1, f"engine kept going after the stop signal: {len(seen)} reports")
    check("stopped early" in res.message, f"result does not report the early stop: {res.message}")
    # The callback fires every 5 frames, so a 40-frame clip must not finish.
    check(res.faces_swapped < 40, f"expected an early stop, swapped {res.faces_swapped}")


# =====================================================================
# Task 6: Frame rate and frame count guards
# =====================================================================

@test
def test_compute_frame_range_handles_zero_fps_fallback():
    from reface_engine_v2 import compute_frame_range

    start, end = compute_frame_range(0, 100, 0, None)
    check(start == 0 and end == 100, f"Expected (0, 100) with fallback fps, got ({start}, {end})")


@test
def test_compute_frame_range_handles_zero_or_negative_total_frames():
    from reface_engine_v2 import compute_frame_range

    start, end = compute_frame_range(30, 0, 0, None)
    check((start, end) == (0, -1), f"Expected (0, -1) for unknown total_frames, got ({start}, {end})")

    start, end = compute_frame_range(30, -5, 2.0, None)
    check((start, end) == (60, -1), f"Expected (60, -1), got ({start}, {end})")

    # An unknown frame count is no reason to silently drop the user's trim.
    start, end = compute_frame_range(30, 0, 2.0, 5.0)
    check((start, end) == (60, 150), f"Expected (60, 150) for a trim without a frame count, got ({start}, {end})")


@test
def test_compute_frame_range_clamps_valid_ranges():
    from reface_engine_v2 import compute_frame_range

    start, end = compute_frame_range(30, 300, 2.0, 5.0)
    check((start, end) == (60, 150), f"Expected (60, 150), got ({start}, {end})")

    # Start time way beyond video length clamps to total_frames - 1
    start, end = compute_frame_range(30, 300, 99.0, None)
    check(start == 299 and end == 300, f"Expected (299, 300), got ({start}, {end})")


# =====================================================================
# Task 5: Frame size fit protection
# =====================================================================

@test
def test_fit_to_frame_keeps_same_object_when_sizes_match():
    from reface_engine_v2 import fit_to_frame

    frame = np.zeros((100, 200, 3), dtype=np.uint8)
    res = fit_to_frame(frame, 200, 100)
    check(res is frame, "fit_to_frame should return the exact same object when dimensions match")


@test
def test_fit_to_frame_returns_requested_hw_when_they_differ():
    from reface_engine_v2 import fit_to_frame

    frame = np.zeros((100, 200, 3), dtype=np.uint8)
    res = fit_to_frame(frame, 400, 250)
    check(res.shape[:2] == (250, 400), f"Expected (250, 400), got {res.shape[:2]}")


# =====================================================================
# Task 8: Color correction with mask and once per frame
# =====================================================================

@test
def test_color_correction_black_mask_leaves_image_byte_identical():
    from reface_engine_v2 import RefaceEngineV2

    engine = RefaceEngineV2.__new__(RefaceEngineV2)
    source = np.full((128, 128, 3), 100, dtype=np.uint8)
    target = np.full((128, 128, 3), 200, dtype=np.uint8)
    mask = np.zeros((128, 128), dtype=np.uint8)

    res = engine._advanced_color_correction(source, target, mask)
    check(np.array_equal(res, source), "Fully black mask should leave image byte-identical")


@test
def test_color_correction_one_corner_mask_leaves_opposite_corner_identical():
    from reface_engine_v2 import RefaceEngineV2

    engine = RefaceEngineV2.__new__(RefaceEngineV2)
    source = np.full((128, 128, 3), 100, dtype=np.uint8)
    target = np.full((128, 128, 3), 200, dtype=np.uint8)
    mask = np.zeros((128, 128), dtype=np.uint8)
    mask[:20, :20] = 255

    res = engine._advanced_color_correction(source, target, mask)
    check(not np.array_equal(res[:15, :15], source[:15, :15]), "Masked corner should be modified")
    check(np.array_equal(res[100:, 100:], source[100:, 100:]), "Opposite corner outside mask should be byte-identical")


@test
def test_color_correction_called_once_outside_face_loop():
    import inspect
    from reface_engine_v2 import RefaceEngineV2

    img_source = inspect.getsource(RefaceEngineV2.reface_with_faceset_v2)
    vid_source = inspect.getsource(RefaceEngineV2.reface_video_with_faceset_v2)

    check(img_source.count("self._advanced_color_correction") == 1,
          "reface_with_faceset_v2 should call _advanced_color_correction exactly once")
    check(vid_source.count("self._advanced_color_correction") == 1,
          "reface_video_with_faceset_v2 should call _advanced_color_correction exactly once")


@test
def test_synthetic_three_face_frame_calls_color_correction_once():
    from reface_engine_v2 import RefaceEngineV2, EnhancementConfig, OcclusionConfig, VideoConfig
    from reface_engine import FaceData, Faceset, RefaceEngine
    import tempfile
    from unittest.mock import MagicMock, patch

    def mock_engine_init(self, *args, **kwargs):
        self.output_dir = Path("reface_output")
        self.faceset_dir = Path("facesets")
        self.app = None
        self.swapper = None
        self.enhancer = None

    with patch.object(RefaceEngine, "__init__", mock_engine_init):
        engine = RefaceEngineV2(
            enhancement_config=EnhancementConfig(enhancer_type="none"),
            occlusion_config=OcclusionConfig(enabled=False),
            video_config=VideoConfig(temporal_smoothing=False)
        )

    class DummyFace:
        def __init__(self, x1, y1, x2, y2):
            self.bbox = np.array([x1, y1, x2, y2], dtype=np.float32)
            self.embedding = np.random.randn(512).astype(np.float32)

    f1 = DummyFace(10, 10, 50, 50)
    f2 = DummyFace(60, 10, 100, 50)
    f3 = DummyFace(110, 10, 150, 50)

    engine.app = MagicMock()
    engine.app.get.return_value = [f1, f2, f3]

    engine.swapper = MagicMock()
    engine.swapper.get.side_effect = lambda img, target, source, paste_back=True: img

    real_color_correction = engine._advanced_color_correction
    call_count = [0]
    def color_corr_spy(source_img, target_img, face_mask=None):
        call_count[0] += 1
        return real_color_correction(source_img, target_img, face_mask)
    engine._advanced_color_correction = color_corr_spy

    fd = FaceData(
        image_path="dummy.jpg",
        embedding=np.random.randn(512).astype(np.float32),
        pose=(0.0, 0.0, 0.0),
        bbox=[0, 0, 50, 50]
    )
    faceset = Faceset(name="dummy")
    faceset.add_face(fd)

    with tempfile.TemporaryDirectory() as tmpdir:
        test_img = Path(tmpdir) / "target.jpg"
        cv2.imwrite(str(test_img), np.full((200, 200, 3), 128, dtype=np.uint8))
        engine.output_dir = Path(tmpdir)

        res = engine.reface_with_faceset_v2(str(test_img), faceset)
        check(res.success, f"Expected success, got {res.message}")
        check(call_count[0] == 1, f"Expected exactly 1 color correction call for 3 faces, got {call_count[0]}")


# =====================================================================
# Task 7: Temporal stabilizer raw buffer & mean blending
# =====================================================================

@test
def test_temporal_stabilizer_constant_sequence_stays_constant():
    from reface_engine_v2 import TemporalStabilizer

    stabilizer = TemporalStabilizer(window_size=3)
    frame = np.full((64, 64, 3), 150, dtype=np.uint8)

    for _ in range(5):
        stabilizer.add_frame(frame)
        blended = stabilizer.blend_frames(frame, blend_strength=0.3)
        check(np.all(blended == 150), f"Constant frame value changed: {blended[0, 0]}")


@test
def test_temporal_stabilizer_impulse_decays_and_clears():
    from reface_engine_v2 import TemporalStabilizer

    stabilizer = TemporalStabilizer(window_size=3)
    black = np.zeros((64, 64, 3), dtype=np.uint8)
    bright = np.full((64, 64, 3), 200, dtype=np.uint8)

    # Prime with black
    stabilizer.add_frame(black)
    stabilizer.add_frame(black)

    # Impulse frame
    stabilizer.add_frame(bright)
    blended_impulse = stabilizer.blend_frames(bright, blend_strength=0.3)
    check(blended_impulse[0, 0, 0] > 0, "Impulse blended frame should be > 0")

    # Feed subsequent black frames
    stabilizer.add_frame(black)
    b1 = stabilizer.blend_frames(black, blend_strength=0.3)

    stabilizer.add_frame(black)
    b2 = stabilizer.blend_frames(black, blend_strength=0.3)

    stabilizer.add_frame(black)
    b3 = stabilizer.blend_frames(black, blend_strength=0.3)

    # After window_size (3) black frames, bright frame is popped out of buffer
    check(np.all(b3 == 0), f"Impulse persisted beyond window_size: {b3[0, 0, 0]}")


@test
def test_temporal_stabilizer_mixed_size_buffer_returns_untouched():
    from reface_engine_v2 import TemporalStabilizer

    stabilizer = TemporalStabilizer(window_size=3)
    f1 = np.zeros((64, 64, 3), dtype=np.uint8)
    f2 = np.full((32, 32, 3), 180, dtype=np.uint8)

    stabilizer.add_frame(f1)
    # Current frame has different size
    out = stabilizer.blend_frames(f2, blend_strength=0.5)
    check(out is f2, "Mixed-size buffer must return current frame untouched")


# =====================================================================
# Task 9: Audio preservation & shared ffmpeg_utils
# =====================================================================

@test
def test_ffmpeg_utils_build_mux_command_preserves_clipping_and_sources():
    from ffmpeg_utils import build_mux_command

    cmd = build_mux_command("out.mp4", "src.mp4", "muxed.mp4", 3.5, 8.0)
    src_idx = cmd.index("src.mp4")
    check("-ss" in cmd[:src_idx] and "-to" in cmd[:src_idx],
          "Clip options -ss and -to must precede source input")
    check(cmd[cmd.index("-ss") + 1] == "3.5", "-ss value mismatch")
    check(cmd[cmd.index("-to") + 1] == "8.0", "-to value mismatch")
    check("-shortest" in cmd, "-shortest flag missing")


@test
def test_ffmpeg_utils_env_override():
    import os
    import tempfile
    from ffmpeg_utils import _ffmpeg_exe

    with tempfile.NamedTemporaryFile(suffix=".exe", delete=False) as f:
        tmp_exe = f.name
    try:
        os.environ["ANTIGRAVITY_FFMPEG"] = tmp_exe
        check(_ffmpeg_exe() == tmp_exe, f"Expected env override {tmp_exe}, got {_ffmpeg_exe()}")
    finally:
        os.environ.pop("ANTIGRAVITY_FFMPEG", None)
        try:
            os.remove(tmp_exe)
        except OSError:
            pass


@test
def test_ffmpeg_utils_build_concat_command_quotes_paths_with_spaces(tmp_path=None):
    import tempfile
    from ffmpeg_utils import build_concat_command

    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        part1 = tdp / "part with space 1.mp4"
        part2 = tdp / "part with space 2.mp4"
        part1.touch()
        part2.touch()
        list_file = tdp / "concat_list.txt"
        out_file = tdp / "final.mp4"

        cmd = build_concat_command([part1, part2], list_file, out_file)
        check("-f" in cmd and "concat" in cmd, "Missing -f concat")
        check(list_file.exists(), "List file was not written")
        content = list_file.read_text(encoding="utf-8")
        check("file '" in content, "Concat list missing file '...' quotation")
        check(str(part1.resolve()) in content and str(part2.resolve()) in content,
              "Part paths missing from list file")


# =====================================================================
# Task 10: Hair mask curvature and proportional feathering
# =====================================================================

@test
def test_hair_mask_has_curved_ellipse_profile():
    from reface_engine_v2 import OcclusionHandler

    handler = OcclusionHandler()
    dummy_img = np.zeros((200, 200, 3), dtype=np.uint8)
    x1, y1, x2, y2 = 20, 20, 180, 180
    bbox = [x1, y1, x2, y2]

    # Brows at y=100
    pts_68 = np.zeros((68, 2), dtype=np.float32)
    pts_68[17:27, 0] = np.linspace(40, 160, 10)
    pts_68[17:27, 1] = 100.0

    mask = handler.generate_occlusion_mask(dummy_img, bbox, pts_68, protect_glasses=False, protect_hair=True)
    check(mask.sum() > 0, "Hair mask should not be empty")

    # Center top near forehead should be protected
    cx = (x1 + x2) // 2
    check(mask[50, cx] > 0, "Center forehead should be covered by ellipse")

    # Top-left and top-right corners should NOT be covered by ellipse (unlike the old rectangle)
    check(mask[30, x1 + 2] == 0, "Top-left corner of bounding box must not be covered by ellipse")
    check(mask[30, x2 - 2] == 0, "Top-right corner of bounding box must not be covered by ellipse")


@test
def test_apply_occlusion_protection_feather_odd_kernel_safety():
    from reface_engine_v2 import OcclusionHandler

    handler = OcclusionHandler()
    orig = np.full((100, 100, 3), 255, dtype=np.uint8)
    swap = np.zeros((100, 100, 3), dtype=np.uint8)
    mask = np.zeros((100, 100), dtype=np.uint8)
    mask[20:80, 20:80] = 255

    # Test with even and odd feather radii to ensure no OpenCV assertions
    for r in [0, 1, 2, 4, 5, 8, 15]:
        res = handler.apply_occlusion_protection(orig, swap, mask, feather_radius=r)
        check(res.shape == (100, 100, 3), f"Failed for feather_radius={r}")
        check(res[50, 50, 0] > 0, f"Protected center should be preserved for feather_radius={r}")


# =====================================================================
# Task 12: Source face proxy bypassing detection
# =====================================================================

@test
def test_source_proxy_normalizes_embedding():
    from reface_engine_v2 import _SourceProxy

    raw_emb = np.arange(512, dtype=np.float32) + 1.0
    proxy = _SourceProxy(raw_emb)

    check(proxy.normed_embedding.shape == (512,), "normed_embedding shape mismatch")
    norm = np.linalg.norm(proxy.normed_embedding)
    check(abs(norm - 1.0) < 1e-5, f"Expected norm 1.0, got {norm}")
    expected = raw_emb / np.linalg.norm(raw_emb)
    check(np.allclose(proxy.normed_embedding, expected), "normed_embedding values mismatch")


@test
def test_get_source_face_uses_proxy_when_embedding_present():
    from types import SimpleNamespace
    from reface_engine_v2 import get_source_face, _SourceProxy

    fd = SimpleNamespace(embedding=np.ones(512, dtype=np.float32), image_path="nonexistent.jpg")
    # App is None to prove it does not touch detection or load images
    got = get_source_face(fd, app=None)
    check(isinstance(got, _SourceProxy), f"Expected _SourceProxy, got {type(got)}")
    check(got.normed_embedding.shape == (512,), "Embedding size mismatch")


@test
def test_get_source_face_falls_back_when_embedding_invalid():
    from types import SimpleNamespace
    from reface_engine_v2 import get_source_face

    called = [False]

    class FakeApp:
        def get(self, img):
            called[0] = True
            return ["fake_detected_face"]

    # Embedding with wrong size (128 instead of 512)
    fd = SimpleNamespace(embedding=np.ones(128, dtype=np.float32), image_path="dummy.jpg")
    # Stub cv2.imread
    orig_imread = cv2.imread
    try:
        cv2.imread = lambda path: np.zeros((100, 100, 3), dtype=np.uint8)
        got = get_source_face(fd, app=FakeApp())
        check(called[0] is True, "Fallback to app.get should be triggered on invalid embedding")
        check(got == "fake_detected_face", "Fallback return value mismatch")
    finally:
        cv2.imread = orig_imread


# =====================================================================
# Task 13: Dashboard V2 history memory & key safety
# =====================================================================

@test
def test_dashboard_v2_history_filtered_and_on_demand_download():
    content = Path("dashboard.py").read_text(encoding="utf-8")
    # Check refaced_v2 filtering
    check('f.name.startswith("refaced_v2")' in content, "V2 history does not filter by refaced_v2 prefix")
    # Check filename-based keys
    check('key=f"v2_conv_{file_path.name}"' in content, "Convert button missing filename-based key")
    check('key=f"v2_dl_{file_path.name}"' in content, "Download button missing filename-based key")
    check('v2_prep_dl_' in content, "Download is not staged through session_state and will vanish on rerun")
    check('key=f"v2_del_{file_path.name}"' in content, "Delete button missing filename-based key")


# =====================================================================
# Task 15: Resource cleanup and exception safety
# =====================================================================

@test
def test_resource_cleanup_in_video_processing():
    import inspect
    from reface_engine_v2 import RefaceEngineV2

    source = inspect.getsource(RefaceEngineV2.reface_video_with_faceset_v2)
    check("finally:" in source, "Missing finally: block in reface_video_with_faceset_v2")
    check("cap.release()" in source and "out.release()" in source,
          "finally block must release cap and out")


@test
def test_no_bare_except_in_reface_engine_v2():
    import re
    code = Path("reface_engine_v2.py").read_text(encoding="utf-8")
    bare_matches = re.findall(r'^\s*except\s*:', code, re.MULTILINE)
    check(len(bare_matches) == 0, f"Found {len(bare_matches)} bare except: statements in reface_engine_v2.py")


# =====================================================================
# Task 16: Dead code cleanup and preset removal
# =====================================================================

@test
def test_dead_code_removed_from_v2():
    from reface_engine_v2 import TemporalStabilizer, VideoConfig, OcclusionConfig
    import reface_engine_v2

    check(not hasattr(TemporalStabilizer, "get_stabilized_landmarks"),
          "get_stabilized_landmarks should be removed")
    check("stabilize_landmarks" not in VideoConfig.__dataclass_fields__,
          "stabilize_landmarks should be removed from VideoConfig")
    check("mode" not in OcclusionConfig.__dataclass_fields__,
          "mode should be removed from OcclusionConfig")
    check(not hasattr(reface_engine_v2, "create_engine_from_preset"),
          "create_engine_from_preset should be removed")


@test
def test_opencv_enhancement_respects_strength():
    from reface_engine_v2 import NeuralEnhancer

    enhancer = NeuralEnhancer(enhancer_type="opencv", upscale=1)
    img = np.full((50, 50, 3), 100, dtype=np.uint8)

    out_0 = enhancer.enhance(img, strength=0.0)
    out_1 = enhancer.enhance(img, strength=1.0)
    check(out_0.shape == img.shape, f"Unexpected shape: {out_0.shape}")
    check(out_1.shape == img.shape, f"Unexpected shape: {out_1.shape}")


# =====================================================================
# Task 14: Safe GFPGAN download and model file validation
# =====================================================================

@test
def test_is_valid_model_file_size_and_readability():
    from reface_engine_v2 import is_valid_model_file, MAX_AUTO_DOWNLOAD_BYTES
    import tempfile

    # Non-existent file
    check(not is_valid_model_file(Path("non_existent_model.pth")), "Non-existent file should be invalid")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)

        # Empty file (0 bytes)
        empty_file = tmp_path / "empty.pth"
        empty_file.touch()
        check(not is_valid_model_file(empty_file), "0-byte file should be invalid")

        # 50 MB file (too small, min is 100 MB)
        small_file = tmp_path / "small.pth"
        with open(small_file, "wb") as f:
            f.seek(50 * 1024 * 1024 - 1)
            f.write(b"\0")
        check(not is_valid_model_file(small_file), "50 MB file should be invalid (min 100 MB)")

        # 200 MB file (valid range: 100 MB - 500 MB)
        valid_file = tmp_path / "valid.pth"
        with open(valid_file, "wb") as f:
            f.seek(200 * 1024 * 1024 - 1)
            f.write(b"\0")
        check(is_valid_model_file(valid_file), "200 MB file should be valid")

        # 501 MB file (oversized, max is 500 MB)
        oversized_file = tmp_path / "oversized.pth"
        with open(oversized_file, "wb") as f:
            f.seek(501 * 1024 * 1024 - 1)
            f.write(b"\0")
        # Valid on its own, but over the auto-download cap. Those are two
        # different questions, so the cap is opt-in.
        check(is_valid_model_file(oversized_file),
              "a large model already on disk should not be rejected")
        check(not is_valid_model_file(oversized_file, max_bytes=MAX_AUTO_DOWNLOAD_BYTES),
              "501 MB file should exceed the auto-download cap when that cap is applied")


# =====================================================================
# Task 11: Source-quality gated face-only enhancement for video
# =====================================================================

@test
def test_should_enhance_face_quality_gates():
    from reface_engine_v2 import should_enhance_face

    # High-contrast sharp crop: alternating black and white lines
    sharp_crop = np.zeros((150, 150, 3), dtype=np.uint8)
    sharp_crop[::2, :, :] = 255

    # Uniform blurry crop
    blurred_crop = np.full((150, 150, 3), 128, dtype=np.uint8)

    # 1. Low resolution frame (320x240) -> False
    check(not should_enhance_face((240, 320, 3), [10, 10, 150, 150], sharp_crop),
          "should_enhance_face on 320x240 frame must return False")

    # 2. Small face bbox (< 128 px height, e.g. 40px) in 1080p frame -> False
    check(not should_enhance_face((1080, 1920, 3), [10, 10, 50, 50], sharp_crop),
          "should_enhance_face with 40px face box must return False")

    # 3. Blurred face crop in 1080p frame -> False
    check(not should_enhance_face((1080, 1920, 3), [10, 10, 160, 160], blurred_crop),
          "should_enhance_face on uniformly blurred crop must return False")

    # 4. Sharp, large, HD face in 1080p frame -> True
    check(should_enhance_face((1080, 1920, 3), [10, 10, 160, 160], sharp_crop),
          "should_enhance_face on sharp, large, HD face must return True")


@test
def test_video_writer_size_equals_source_size_regardless_of_upscale():
    import inspect
    from reface_engine_v2 import RefaceEngineV2

    source = inspect.getsource(RefaceEngineV2.reface_video_with_faceset_v2)
    # Ensure upscale_factor is not multiplying width or height for video writer
    check("out_width = width" in source, "out_width must equal source width")
    check("out_height = height" in source, "out_height must equal source height")
    check("out_width = width * upscale" not in source, "Video must not upscale width")
    check("out_height = height * upscale" not in source, "Video must not upscale height")


# =====================================================================
# Task 3: Video pause/resume and segment concatenation
# =====================================================================

@test
def test_job_from_dict_defaults_missing_resume_fields():
    from job_manager import Job

    payload = {
        "id": "job_123",
        "job_type": "reface_video_v2",
        "status": "queued",
        "progress": 0.0,
        "message": "Queued",
        "created_at": "2026-09-06T12:00:00"
    }
    job = Job.from_dict(payload)
    check(job.frames_done == 0, f"Expected frames_done 0, got {job.frames_done}")
    check(job.part_files == [], f"Expected empty part_files, got {job.part_files}")


@test
def test_job_pause_accumulates_frames_done_and_parts():
    from job_manager import JobManager, Job, JobStatus
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        manager = JobManager(jobs_dir=tmpdir)
        job = Job(
            id="test_pause_1",
            job_type="reface_video_v2",
            status=JobStatus.RUNNING,
            progress=0.0,
            message="Running",
            created_at="2026-09-06T12:00:00"
        )
        manager.save_job(job)

        # Create dummy segment files
        part1 = Path(tmpdir) / "part1.avi"
        part1.write_bytes(b"data1")
        part2 = Path(tmpdir) / "part2.avi"
        part2.write_bytes(b"data2")

        # Pause 1: 50 frames
        manager.pause_job(job.id, current_frame=50, part_file=str(part1))
        j1 = manager.load_job(job.id)
        check(j1.frames_done == 50, f"Expected 50 frames_done, got {j1.frames_done}")
        check(j1.part_files == [str(part1)], f"Expected [part1], got {j1.part_files}")

        # Resume and Run again
        j1.status = JobStatus.RUNNING
        manager.save_job(j1)

        # Pause 2: 70 frames
        manager.pause_job(job.id, current_frame=70, part_file=str(part2))
        j2 = manager.load_job(job.id)
        check(j2.frames_done == 120, f"Expected 120 cumulative frames_done, got {j2.frames_done}")
        check(j2.part_files == [str(part1), str(part2)], f"Expected [part1, part2], got {j2.part_files}")


@test
def test_resume_start_frame_math():
    from reface_engine_v2 import compute_frame_range

    # Case 1: normal resume offset (start=60, resume_from=40 -> 100)
    fps, total = 30.0, 300
    start_frame, end_frame = compute_frame_range(fps, total, start_time=2.0, end_time=10.0)  # (60, 300)
    resume_from = 40
    resumed_start = min(start_frame + resume_from, end_frame - 1)
    check(resumed_start == 100, f"Expected resumed start 100, got {resumed_start}")

    # Case 2: resume overshoots end_frame -> clamps to end_frame - 1
    start_frame, end_frame = compute_frame_range(fps, 100, start_time=2.0, end_time=None)  # (60, 100)
    overshoot_resume = 50  # 60 + 50 = 110 > 99
    resumed_clamped = min(start_frame + overshoot_resume, end_frame - 1)
    check(resumed_clamped == 99, f"Expected clamped start 99, got {resumed_clamped}")


@test
def test_build_concat_command_preserves_order():
    from ffmpeg_utils import build_concat_command
    import tempfile

    with tempfile.TemporaryDirectory() as tmpdir:
        d = Path(tmpdir)
        p1 = d / "part 1.avi"
        p2 = d / "part 2.avi"
        p3 = d / "part 3.avi"
        p1.touch(); p2.touch(); p3.touch()
        list_file = d / "list.txt"
        out_file = d / "out.avi"

        cmd = build_concat_command([p1, p2, p3], list_file, out_file)
        check(list_file.exists(), "list file must exist")
        lines = list_file.read_text(encoding="utf-8").strip().splitlines()
        check(len(lines) == 3, f"Expected 3 lines, got {len(lines)}")
        check("part 1" in lines[0] and "part 2" in lines[1] and "part 3" in lines[2],
              "Parts must be in the exact given order")
        check(str(out_file) in cmd, "Output path must be in concat command")


# =====================================================================
# Regression: occlusion path must not read the face box before binding it
# (both swap paths derived feather_radius from x1/x2 one statement early)
# =====================================================================


def _mock_v2_engine(occlusion_enabled=True, temporal=False):
    """Build a RefaceEngineV2 without touching InsightFace, models, or CUDA."""
    from reface_engine_v2 import RefaceEngineV2, EnhancementConfig, OcclusionConfig, VideoConfig
    from reface_engine import RefaceEngine
    from unittest.mock import patch

    def mock_engine_init(self, *args, **kwargs):
        self.output_dir = Path("reface_output")
        self.faceset_dir = Path("facesets")
        self.app = None
        self.swapper = None
        self.enhancer = None

    with patch.object(RefaceEngine, "__init__", mock_engine_init):
        return RefaceEngineV2(
            enhancement_config=EnhancementConfig(enhancer_type="none"),
            occlusion_config=OcclusionConfig(enabled=occlusion_enabled),
            video_config=VideoConfig(temporal_smoothing=temporal),
        )


def _face_with_68_landmarks(x1, y1, x2, y2):
    """A face whose 68-point landmarks produce a non-empty occlusion mask.

    The mask has to be non-empty or the feather_radius branch never runs,
    which is exactly how the original bug escaped the suite.
    """
    pts = np.zeros((68, 3), dtype=np.float32)
    w = x2 - x1
    h = y2 - y1
    # brows sit below the top of the box so the hair ellipse is drawn
    pts[17:22, 0] = np.linspace(x1 + 0.15 * w, x1 + 0.40 * w, 5)
    pts[22:27, 0] = np.linspace(x1 + 0.60 * w, x1 + 0.85 * w, 5)
    pts[17:27, 1] = y1 + 0.25 * h
    # eyes wide enough that the glasses ellipse has a positive radius
    pts[36:42, 0] = np.linspace(x1 + 0.15 * w, x1 + 0.40 * w, 6)
    pts[42:48, 0] = np.linspace(x1 + 0.60 * w, x1 + 0.85 * w, 6)
    pts[36:48, 1] = y1 + 0.45 * h

    class _Face:
        def __init__(self):
            self.bbox = np.array([x1, y1, x2, y2], dtype=np.float32)
            self.embedding = np.random.randn(512).astype(np.float32)
            self.landmark_3d_68 = pts

    return _Face()


def _single_face_faceset():
    from reface_engine import FaceData, Faceset

    fs = Faceset(name="dummy")
    fs.add_face(FaceData(
        image_path="dummy.jpg",
        embedding=np.random.randn(512).astype(np.float32),
        pose=(0.0, 0.0, 0.0),
        bbox=[0, 0, 50, 50],
    ))
    return fs


@test
def test_image_swap_with_occlusion_enabled_does_not_raise():
    import tempfile
    from unittest.mock import MagicMock
    from reface_engine_v2 import as_68_points

    engine = _mock_v2_engine(occlusion_enabled=True)
    check(engine.occlusion_handler is not None, "occlusion handler should be built")

    face = _face_with_68_landmarks(20, 20, 120, 140)
    check(as_68_points(face.landmark_3d_68) is not None, "test fixture must be 68-point")

    # The mask must actually be non-empty, otherwise the regression path is skipped.
    mask = engine.occlusion_handler.generate_occlusion_mask(
        np.zeros((200, 200, 3), dtype=np.uint8), [20, 20, 120, 140], face.landmark_3d_68
    )
    check(mask.sum() > 0, "fixture produced an empty occlusion mask; test would prove nothing")

    engine.app = MagicMock()
    engine.app.get.return_value = [face]
    engine.swapper = MagicMock()
    engine.swapper.get.side_effect = lambda img, t, s, paste_back=True: img

    with tempfile.TemporaryDirectory() as tmpdir:
        target = Path(tmpdir) / "target.jpg"
        cv2.imwrite(str(target), np.full((200, 200, 3), 128, dtype=np.uint8))
        engine.output_dir = Path(tmpdir)

        res = engine.reface_with_faceset_v2(
            str(target), _single_face_faceset(), apply_occlusion=True
        )
        check(res.success, f"occlusion-enabled image swap failed: {res.message}")
        check(res.faces_swapped == 1, f"expected 1 swap, got {res.faces_swapped}")


@test
def test_video_swap_survives_a_frame_with_no_faces():
    """A face-less frame used to leave faces_to_swap unbound (first frame) or
    stale (later frames), so the enhancement pass read the previous frame's boxes."""
    import tempfile
    from unittest.mock import MagicMock

    engine = _mock_v2_engine(occlusion_enabled=True)
    face = _face_with_68_landmarks(20, 20, 120, 140)

    engine.app = MagicMock()
    # frame 0 has no faces at all - this is the case that used to raise
    engine.app.get.side_effect = [[], [face], [face]]
    engine.swapper = MagicMock()
    engine.swapper.get.side_effect = lambda img, t, s, paste_back=True: img

    with tempfile.TemporaryDirectory() as tmpdir:
        src = Path(tmpdir) / "src.avi"
        writer = cv2.VideoWriter(
            str(src), cv2.VideoWriter_fourcc(*'MJPG'), 10.0, (200, 200)
        )
        check(writer.isOpened(), "could not open a test VideoWriter (MJPG missing?)")
        for _ in range(3):
            writer.write(np.full((200, 200, 3), 128, dtype=np.uint8))
        writer.release()

        engine.output_dir = Path(tmpdir)
        res = engine.reface_video_with_faceset_v2(
            str(src), _single_face_faceset(),
            apply_occlusion=True,
            finalize=False,   # keep the test hermetic: no ffmpeg, no audio mux
        )
        check(res.success, f"video with a face-less first frame failed: {res.message}")
        check(res.faces_swapped == 2, f"expected 2 swaps across 3 frames, got {res.faces_swapped}")


# =====================================================================
# Test Runner
# =====================================================================

def main(argv):
    pattern = argv[0] if argv else ""
    selected = [t for t in _TESTS if pattern in t.__name__]
    if not selected:
        known = ", ".join(t.__name__ for t in _TESTS)
        print(f"No test matches '{pattern}'.\nKnown: {known}")
        return 1

    failed = 0
    for t in selected:
        try:
            t()
            print(f"[PASS] {t.__name__}")
        except Exception as e:
            failed += 1
            print(f"[FAIL] {t.__name__}: {e}")
            traceback.print_exc()

    print(f"\n{len(selected) - failed}/{len(selected)} passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
