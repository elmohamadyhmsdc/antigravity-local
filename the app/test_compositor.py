"""
Antigravity Local - compositing core tests

Standalone script (the repo has no pytest). Prints results, exit(1) on failure.

    venv\\Scripts\\python.exe test_compositor.py            # everything
    venv\\Scripts\\python.exe test_compositor.py grain      # only names containing "grain"
"""

import sys
import traceback

_TESTS = []


def test(fn):
    """Register a test function."""
    _TESTS.append(fn)
    return fn


def check(cond, msg):
    if not cond:
        raise AssertionError(msg)


@test
def test_imports():
    import face_harmonize  # noqa: F401


@test
def test_noise_sigma_recovers_known_value():
    import numpy as np
    from face_harmonize import estimate_noise_sigma

    rng = np.random.default_rng(0)
    flat = np.full((256, 256), 128.0, np.float32)
    noisy = flat + rng.standard_normal((256, 256)).astype(np.float32) * 8.0
    got = estimate_noise_sigma(np.clip(noisy, 0, 255).astype(np.uint8))
    check(abs(got - 8.0) < 0.8, f"expected sigma near 8.0, got {got:.3f}")


@test
def test_noise_sigma_is_clamped():
    import numpy as np
    from face_harmonize import estimate_noise_sigma

    rng = np.random.default_rng(1)
    wild = rng.integers(0, 255, (128, 128)).astype(np.uint8)
    got = estimate_noise_sigma(wild, max_sigma=12.0)
    check(got <= 12.0, f"sigma should be clamped to 12.0, got {got:.3f}")


@test
def test_noise_sigma_honours_mask():
    import numpy as np
    from face_harmonize import estimate_noise_sigma

    rng = np.random.default_rng(2)
    img = np.full((256, 256), 128.0, np.float32)
    img[:, 128:] += rng.standard_normal((256, 128)).astype(np.float32) * 10.0
    img = np.clip(img, 0, 255).astype(np.uint8)

    mask = np.zeros((256, 256), np.float32)
    mask[:, :128] = 1.0          # measure only the clean half
    quiet = estimate_noise_sigma(img, mask=mask)
    check(quiet < 1.0, f"clean half should read near zero, got {quiet:.3f}")


@test
def test_gain_is_clipped_to_bounds():
    import numpy as np
    from face_harmonize import compute_gain, GAIN_MIN, GAIN_MAX

    dark = np.full((128, 128, 3), 50, np.uint8)
    bright = np.full((128, 128, 3), 220, np.uint8)
    mask = np.ones((128, 128), np.float32)

    gain = compute_gain(dark, bright, mask)
    check(gain.min() >= GAIN_MIN - 1e-4, f"gain below floor: {gain.min():.4f}")
    check(gain.max() <= GAIN_MAX + 1e-4, f"gain above ceiling: {gain.max():.4f}")
    check(gain.mean() > 1.3, f"expected gain near the ceiling, got {gain.mean():.4f}")


@test
def test_gain_follows_light_direction():
    import numpy as np
    from face_harmonize import compute_gain, apply_gain

    # Reference is lit from the right; result is flat.
    ramp = np.linspace(60, 200, 128, dtype=np.float32)
    reference = np.repeat(ramp[None, :, None], 128, axis=0).repeat(3, axis=2).astype(np.uint8)
    result = np.full((128, 128, 3), 128, np.uint8)
    mask = np.ones((128, 128), np.float32)

    out = apply_gain(result, compute_gain(result, reference, mask), 1.0)
    left = float(out[:, :32].mean())
    right = float(out[:, -32:].mean())
    check(right > left + 15, f"expected a left-to-right ramp, got {left:.1f} -> {right:.1f}")


@test
def test_gain_strength_zero_is_identity():
    import numpy as np
    from face_harmonize import compute_gain, apply_gain

    result = np.full((64, 64, 3), 100, np.uint8)
    reference = np.full((64, 64, 3), 200, np.uint8)
    mask = np.ones((64, 64), np.float32)

    out = apply_gain(result, compute_gain(result, reference, mask), 0.0)
    check(np.array_equal(out, result), "strength 0.0 must leave the image untouched")


@test
def test_lab_color_match_shifts_tone_toward_the_reference():
    import numpy as np
    from face_harmonize import lab_color_match

    result = np.full((64, 64, 3), 90, np.uint8)
    reference = np.full((64, 64, 3), 180, np.uint8)
    mask = np.ones((64, 64), np.float32)

    out = lab_color_match(result, reference, mask)
    check(abs(float(out.mean()) - 180.0) < 8.0,
          f"expected tone near the reference, got {out.mean():.1f}")


@test
def test_lab_color_match_survives_a_tiny_mask():
    import numpy as np
    from face_harmonize import lab_color_match

    rng = np.random.default_rng(10)
    result = rng.integers(0, 255, (64, 64, 3)).astype(np.uint8)
    reference = rng.integers(0, 255, (64, 64, 3)).astype(np.uint8)
    mask = np.zeros((64, 64), np.float32)
    mask[0, 0] = 1.0                       # far below the 16-pixel floor

    out = lab_color_match(result, reference, mask)
    check(out.shape == result.shape and out.dtype == result.dtype,
          "a degenerate mask must still return a usable image")


@test
def test_focus_sigma_softens_a_too_sharp_result():
    import cv2
    import numpy as np
    from face_harmonize import choose_focus_sigma, laplacian_var

    rng = np.random.default_rng(3)
    sharp = rng.integers(0, 255, (256, 256, 3)).astype(np.uint8)
    soft = cv2.GaussianBlur(sharp, (0, 0), 2.0)
    mask = np.ones((256, 256), np.float32)

    s = choose_focus_sigma(sharp, soft, mask)
    check(s > 0, "a sharp result against a soft reference must pick a blur")

    softened = cv2.GaussianBlur(sharp, (0, 0), s)
    check(
        laplacian_var(softened, mask) <= laplacian_var(soft, mask) * 1.05,
        "softened result should be no sharper than the reference",
    )


@test
def test_focus_sigma_is_zero_when_already_soft():
    import cv2
    import numpy as np
    from face_harmonize import choose_focus_sigma

    rng = np.random.default_rng(4)
    sharp = rng.integers(0, 255, (256, 256, 3)).astype(np.uint8)
    soft = cv2.GaussianBlur(sharp, (0, 0), 2.0)
    mask = np.ones((256, 256), np.float32)

    check(choose_focus_sigma(soft, sharp, mask) == 0.0,
          "a result softer than the reference must not be blurred further")


@test
def test_detail_transfer_adds_texture_inside_the_mask_only():
    import numpy as np
    from face_harmonize import transfer_detail, laplacian_var

    rng = np.random.default_rng(5)
    textured = rng.integers(0, 255, (128, 128, 3)).astype(np.uint8)
    flat = np.full((128, 128, 3), 128, np.uint8)

    mask = np.zeros((128, 128), np.float32)
    mask[:, :64] = 1.0

    out = transfer_detail(flat, textured, mask, amount=0.6)

    left = laplacian_var(out[:, :64])
    check(left > 50, f"masked half should gain texture, got variance {left:.1f}")
    check(np.array_equal(out[:, 64:], flat[:, 64:]),
          "pixels outside the mask must be untouched")


@test
def test_detail_transfer_amount_zero_is_identity():
    import numpy as np
    from face_harmonize import transfer_detail

    rng = np.random.default_rng(6)
    textured = rng.integers(0, 255, (64, 64, 3)).astype(np.uint8)
    flat = np.full((64, 64, 3), 128, np.uint8)
    mask = np.ones((64, 64), np.float32)

    check(np.array_equal(transfer_detail(flat, textured, mask, 0.0), flat),
          "amount 0.0 must leave the image untouched")


@test
def test_grain_amplitude_matches_requested_sigma():
    import numpy as np
    from face_harmonize import add_grain

    flat = np.full((256, 256, 3), 128, np.uint8)
    out = add_grain(flat, sigma=6.0, rng=np.random.default_rng(7))

    delta = out.astype(np.float32) - flat.astype(np.float32)
    # luma (unit variance) plus an independent chroma term at 0.3 -> ~1.044 sigma
    expected = 6.0 * 1.044
    check(abs(float(delta.std()) - expected) < expected * 0.15,
          f"expected noise std near {expected:.2f}, got {delta.std():.2f}")


@test
def test_grain_respects_mask_and_zero_amount():
    import numpy as np
    from face_harmonize import add_grain

    flat = np.full((128, 128, 3), 128, np.uint8)
    mask = np.zeros((128, 128), np.float32)
    mask[:, :64] = 1.0

    out = add_grain(flat, sigma=8.0, mask=mask, rng=np.random.default_rng(8))
    check(np.array_equal(out[:, 64:], flat[:, 64:]), "masked-out half must be untouched")
    check(not np.array_equal(out[:, :64], flat[:, :64]), "masked-in half must get grain")

    check(np.array_equal(add_grain(flat, 8.0, amount=0.0), flat),
          "amount 0.0 must leave the image untouched")


@test
def test_grain_differs_between_frames():
    import numpy as np
    from face_harmonize import add_grain

    flat = np.full((64, 64, 3), 128, np.uint8)
    rng = np.random.default_rng(9)
    a = add_grain(flat, 6.0, rng=rng)
    b = add_grain(flat, 6.0, rng=rng)
    check(not np.array_equal(a, b),
          "grain must be regenerated per frame; frozen grain reads as a dirty lens")


@test
def test_harden_occlusion_remaps_the_matte():
    import numpy as np
    from face_masking import harden_occlusion

    # Constant fields, so the blur inside harden_occlusion is a no-op.
    check(float(harden_occlusion(np.full((64, 64), 0.40, np.float32)).mean()) < 0.01,
          "0.40 should clamp to 0")
    check(abs(float(harden_occlusion(np.full((64, 64), 0.75, np.float32)).mean()) - 0.5) < 0.02,
          "0.75 should map to 0.5")
    check(abs(float(harden_occlusion(np.full((64, 64), 1.0, np.float32)).mean()) - 1.0) < 0.02,
          "1.0 should stay 1.0")


@test
def test_feather_mask_keeps_a_solid_centre():
    import numpy as np
    from face_masking import feather_mask

    solid = np.ones((512, 512), np.float32)
    out = feather_mask(solid, erode=0.02, feather=0.05)
    check(out[256, 256] > 0.99, f"centre should stay solid, got {out[256, 256]:.3f}")
    check(out[2, 256] < 0.05, f"edge should ramp to zero, got {out[2, 256]:.3f}")


@test
def test_occluder_regression_hand_survives():
    """The destroyed-hand bug: an occluder hole must stay a hole."""
    import numpy as np
    from face_masking import feather_mask, harden_occlusion

    region = np.ones((512, 512), np.float32)
    occ = np.ones((512, 512), np.float32)
    occ[200:300, 200:300] = 0.0          # a hand across the cheek

    mask = feather_mask(region, erode=0.02, feather=0.05) * harden_occlusion(occ)
    check(mask[250, 250] < 0.01,
          f"hand centre must be fully protected, got {mask[250, 250]:.4f}")
    check(mask[256, 400] > 0.9,
          f"face away from the hand must still be swapped, got {mask[256, 400]:.4f}")


@test
def test_affine_composition_round_trips():
    import cv2
    import numpy as np
    from face_compositor import compose_affine

    # Two unrelated similarity transforms out of frame space.
    m_swap = np.array([[0.8, 0.1, 12.0],
                       [-0.1, 0.8, -5.0]], np.float32)
    m_ffhq = np.array([[1.6, 0.2, -30.0],
                       [-0.2, 1.6, 8.0]], np.float32)

    t = compose_affine(m_ffhq, m_swap)

    for pt in [(10.0, 20.0), (300.0, 45.0), (128.0, 128.0)]:
        p = np.array([pt[0], pt[1], 1.0])
        in_swap = m_swap @ p
        in_ffhq = m_ffhq @ p
        got = t @ np.array([in_swap[0], in_swap[1], 1.0])
        check(np.allclose(got, in_ffhq, atol=1e-3),
              f"{pt}: expected {in_ffhq}, got {got}")


@test
def test_affine_scale_prefix_matches_a_resize():
    import numpy as np
    from face_compositor import scale_affine

    im = np.array([[2.0, 0.0, 5.0],
                   [0.0, 2.0, -3.0]], np.float32)
    f = 0.5
    scaled = scale_affine(im, f)

    # A point at (c*f) in the shrunk crop must land where c did before.
    c = np.array([100.0, 60.0, 1.0])
    before = im @ c
    after = scaled @ np.array([100.0 * f, 60.0 * f, 1.0])
    check(np.allclose(before, after, atol=1e-3), f"expected {before}, got {after}")


@test
def test_presets_have_expected_shape():
    from face_compositor import CompositeConfig, config_from_preset

    natural = config_from_preset("natural")
    check(natural.detail_transfer == 0.4, f"natural detail: {natural.detail_transfer}")
    check(natural.preserve_mouth_interior is True, "natural must preserve teeth")

    clean = config_from_preset("clean")
    check(clean.detail_transfer == 0.0, "clean must disable detail transfer")
    check(clean.grain_match == 0.0, "clean must disable grain")
    check(clean.relight == 0.0, "clean must disable relight")
    check(clean.preserve_mouth_interior is False, "clean reproduces legacy teeth swapping")

    hi = config_from_preset("maximum_detail")
    check(hi.detail_transfer == 0.6, f"maximum_detail: {hi.detail_transfer}")

    check(isinstance(config_from_preset("natural"), CompositeConfig), "wrong type")


@test
def test_presets_accept_overrides_and_reject_unknown_names():
    from face_compositor import config_from_preset

    cfg = config_from_preset("natural", grain_match=0.25, temporal=True)
    check(cfg.grain_match == 0.25, f"override ignored: {cfg.grain_match}")
    check(cfg.temporal is True, "temporal override ignored")
    check(cfg.detail_transfer == 0.4, "unrelated preset values must survive")

    try:
        config_from_preset("nope")
    except ValueError:
        return
    raise AssertionError("unknown preset name should raise ValueError")


class _StubRestorer:
    """Stands in for FaceRestorer without loading an ONNX model."""
    available = False

    def enhance(self, crop):
        return crop


class _StubMasker:
    """Stands in for FaceMasker with no models loaded."""
    parser = None
    occluder = None

    def segment(self, crop):
        return None

    def occlusion_mask(self, crop):
        return None


@test
def test_alignment_matrix_maps_landmarks_to_the_template():
    import numpy as np
    from face_compositor import alignment_matrix
    from reface_engine_v3 import FFHQ_512

    kps = np.array([[100.0, 120.0], [180.0, 122.0], [140.0, 160.0],
                    [108.0, 195.0], [172.0, 196.0]], np.float32)
    m = alignment_matrix(kps, 512)
    check(m is not None, "expected a matrix for valid landmarks")

    mapped = np.array([m @ np.array([x, y, 1.0]) for x, y in kps])
    err = float(np.abs(mapped - FFHQ_512).max())
    check(err < 12.0, f"landmarks should land near the template, max error {err:.2f}")

    check(alignment_matrix(np.zeros((3, 2), np.float32), 512) is None,
          "wrong landmark count must return None")


@test
def test_place_swap_fills_uncovered_pixels_from_the_original():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    comp = FaceCompositor(_StubRestorer(), _StubMasker(), CompositeConfig())

    # Swap crop is a 128px red square; identity-ish placement into the middle
    # of a 512 space leaves the border uncovered.
    swap = np.zeros((128, 128, 3), np.uint8)
    swap[:, :] = (0, 0, 255)
    orig = np.zeros((512, 512, 3), np.uint8)
    orig[:, :] = (0, 255, 0)

    m_swap = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], np.float32)
    m_ffhq = np.array([[1.0, 0.0, 192.0], [0.0, 1.0, 192.0]], np.float32)

    base = comp._place_swap(swap, m_swap, m_ffhq, orig, 512)
    check(tuple(int(v) for v in base[256, 256]) == (0, 0, 255),
          f"centre should be the swap, got {base[256, 256]}")
    check(tuple(int(v) for v in base[10, 10]) == (0, 255, 0),
          f"corner should fall back to the original, got {base[10, 10]}")


@test
def test_as_2x3_accepts_3x3_and_rejects_garbage():
    import numpy as np
    from face_compositor import _as_2x3

    m23 = np.array([[1.0, 0.0, 4.0], [0.0, 1.0, 5.0]], np.float32)
    check(np.allclose(_as_2x3(m23), m23), "2x3 must pass through")

    m33 = np.vstack([m23, [0.0, 0.0, 1.0]])
    got = _as_2x3(m33)
    check(got is not None and np.allclose(got, m23), f"3x3 should strip to 2x3, got {got}")

    check(_as_2x3(np.zeros((128, 128, 3))) is None, "an image must not look like an affine")
    check(_as_2x3(None) is None, "None must stay None")


@test
def test_place_via_frame_puts_the_swap_on_the_face():
    """Production path: invert M_swap onto the frame (insightface paste),
    then recrop with M_ffhq. This is what composite() uses."""
    import cv2
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor, alignment_matrix

    frame, swap, kps, m_swap = _swap_inputs()
    size = 512
    m_ffhq = alignment_matrix(kps, size)
    check(m_ffhq is not None, "FFHQ matrix required")
    orig = cv2.warpAffine(frame, m_ffhq, (size, size), borderMode=cv2.BORDER_REPLICATE)

    comp = FaceCompositor(_StubRestorer(), _StubMasker(), CompositeConfig())
    base, cov = comp._place_via_frame(frame, swap, m_swap, m_ffhq, orig, size)
    check(cov > 0.02, f"swap coverage too low: {cov:.4f}")
    # Face centre in FFHQ space should be the red swap, not the original frame.
    centre = base[256, 256]
    check(int(centre[2]) > int(centre[1]) + 40,
          f"FFHQ centre should be the swap (red), got BGR {tuple(int(v) for v in centre)}")


class _SegMasker:
    """Masker returning a scripted segmentation map and occlusion mask."""

    parser = True
    occluder = True

    def __init__(self, seg, occ=None):
        self._seg = seg
        self._occ = occ

    def segment(self, crop):
        return self._seg

    def occlusion_mask(self, crop):
        return self._occ


@test
def test_build_mask_is_zero_outside_the_parser_region():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)
    seg[128:384, 128:384] = 1          # class 1 = skin
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg), CompositeConfig())

    crop = np.zeros((512, 512, 3), np.uint8)
    mask, region_orig, skin = comp._build_mask(crop, crop)

    check(mask[20, 20] == 0.0, f"outside the region must be 0, got {mask[20, 20]}")
    check(mask[256, 256] > 0.9, f"region centre must be solid, got {mask[256, 256]}")
    check(float(mask[region_orig < 0.5].max()) == 0.0,
          "no pixel outside region_orig may be painted")
    check(float(skin[256, 256]) == 1.0, "skin mask should cover the skin class")


@test
def test_build_mask_preserves_the_inner_mouth():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)
    seg[128:384, 128:384] = 1          # skin
    seg[280:320, 230:290] = 11         # inner mouth
    crop = np.zeros((512, 512, 3), np.uint8)

    keep = FaceCompositor(_StubRestorer(), _SegMasker(seg),
                          CompositeConfig(preserve_mouth_interior=True))
    mask_keep, _, _ = keep._build_mask(crop, crop)
    check(mask_keep[300, 260] < 0.01,
          f"real teeth must be preserved, got {mask_keep[300, 260]:.4f}")

    swap = FaceCompositor(_StubRestorer(), _SegMasker(seg),
                          CompositeConfig(preserve_mouth_interior=False))
    mask_swap, _, _ = swap._build_mask(crop, crop)
    check(mask_swap[300, 260] > 0.5,
          f"legacy behaviour should still swap the mouth, got {mask_swap[300, 260]:.4f}")


@test
def test_build_mask_protects_an_occluding_hand():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)
    seg[64:448, 64:448] = 1
    occ = np.ones((512, 512), np.float32)
    occ[200:320, 200:320] = 0.0

    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg, occ), CompositeConfig())
    crop = np.zeros((512, 512, 3), np.uint8)
    mask, _, _ = comp._build_mask(crop, crop)

    check(mask[260, 260] < 0.01, f"hand must be protected, got {mask[260, 260]:.4f}")
    check(mask[256, 400] > 0.8, f"face beside the hand must swap, got {mask[256, 400]:.4f}")


def _swap_inputs(swap_bgr=(0, 0, 255)):
    """A 720x1280 frame, a 128 crop, matching 5-point kps and an identity-scale
    crop matrix. Used by the composite integration tests."""
    import numpy as np

    rng = np.random.default_rng(11)
    frame = rng.integers(0, 255, (720, 1280, 3)).astype(np.uint8)
    swap = np.empty((128, 128, 3), np.uint8)
    swap[:] = swap_bgr
    kps = np.array([[600.0, 300.0], [680.0, 302.0], [640.0, 340.0],
                    [608.0, 375.0], [672.0, 376.0]], np.float32)
    m_swap = np.array([[1.0, 0.0, -560.0], [0.0, 1.0, -260.0]], np.float32)
    return frame, swap, kps, m_swap


@test
def test_composite_leaves_the_frame_untouched_where_the_mask_is_zero():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    # Parser sees face only in a central box, so the frame border must survive
    # bit-for-bit - this is the seam/halo fix.
    seg = np.zeros((512, 512), np.uint8)
    seg[160:352, 160:352] = 1
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg), CompositeConfig())

    frame, swap, kps, m_swap = _swap_inputs()
    out = comp.composite(frame, swap, m_swap, kps, native_px=160.0)
    check(out.shape == frame.shape, f"shape changed: {out.shape}")
    check(np.array_equal(out[0:100, 0:100], frame[0:100, 0:100]),
          "a far corner of the frame must be bit-identical")
    check(not np.array_equal(out, frame), "the face region should have changed")


@test
def test_composite_still_swaps_when_parser_region_is_empty():
    """Regression: paste_back=False + a collapsed parser mask returned the
    original image as a successful result. Pre-rebuild V3 still had the swap
    in the frame because insightface had already pasted it."""
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)          # parser sees only background
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg), CompositeConfig())
    frame, swap, kps, m_swap = _swap_inputs()

    out = comp.composite(frame, swap, m_swap, kps, native_px=160.0)
    check(not np.array_equal(out, frame),
          "an empty parser region must fall back to a box mask, not skip the swap")


@test
def test_composite_still_swaps_when_occluder_wipes_the_mask():
    """harden_occlusion maps values below 0.5 to 0. A miscalibrated occluder
    that outputs ~0.4 everywhere used to zero the whole paste mask."""
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)
    seg[128:384, 128:384] = 1
    occ = np.full((512, 512), 0.40, np.float32)
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg, occ), CompositeConfig())
    frame, swap, kps, m_swap = _swap_inputs()

    out = comp.composite(frame, swap, m_swap, kps, native_px=160.0)
    check(not np.array_equal(out, frame),
          "a collapsed occluder must be ignored rather than skipping the swap")


@test
def test_build_mask_falls_back_when_parser_region_is_empty():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    seg = np.zeros((512, 512), np.uint8)
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg), CompositeConfig())
    crop = np.zeros((512, 512, 3), np.uint8)
    mask, _, _ = comp._build_mask(crop, crop)
    check(mask[256, 256] > 0.9,
          f"empty parser must yield a usable box mask, centre={mask[256, 256]:.3f}")


@test
def test_place_swap_lands_an_arcface_crop_on_the_ffhq_template():
    """Uses the real ArcFace-128 and FFHQ-512 templates, the same pair the
    production path composes. A coverage miss here is the other way the
    pipeline silently returns the original face."""
    import cv2
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor, alignment_matrix

    arcface_128 = np.array(
        [[38.2946, 51.6963],
         [73.5318, 51.5014],
         [56.0252, 71.7366],
         [41.5493, 92.3655],
         [70.7299, 92.2041]], np.float32) * (128.0 / 112.0)

    kps = np.array([[400.0, 350.0], [500.0, 352.0], [450.0, 420.0],
                    [410.0, 480.0], [490.0, 482.0]], np.float32)
    m_swap, _ = cv2.estimateAffinePartial2D(kps, arcface_128, method=cv2.LMEDS)
    m_ffhq = alignment_matrix(kps, 512)
    check(m_swap is not None and m_ffhq is not None, "templates must produce matrices")

    swap = np.zeros((128, 128, 3), np.uint8)
    swap[:] = (0, 0, 255)
    orig = np.zeros((512, 512, 3), np.uint8)
    orig[:] = (0, 255, 0)

    comp = FaceCompositor(_StubRestorer(), _StubMasker(), CompositeConfig())
    base = comp._place_swap(swap, m_swap, m_ffhq, orig, 512)
    # Nose in FFHQ space should be the swapped (red) crop, not the original fill.
    nose = base[314, 257]
    check(int(nose[2]) > int(nose[1]) + 50,
          f"FFHQ nose should be the swap, got BGR {tuple(int(v) for v in nose)}")


@test
def test_unpack_swap_result_handles_crop_tuple_and_full_frame():
    import numpy as np
    from reface_engine_v3 import unpack_swap_result

    crop = np.zeros((128, 128, 3), np.uint8)
    m = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], np.float32)
    got_crop, got_m = unpack_swap_result((crop, m))
    check(got_crop is crop and got_m is m, "tuple (crop, M) must pass through")

    frame = np.zeros((720, 1280, 3), np.uint8)
    got_frame, got_none = unpack_swap_result(frame)
    check(got_frame is frame and got_none is None,
          "a full-frame paste (paste_back ignored) must not be unpacked as a tuple")


@test
def test_composite_returns_the_frame_on_bad_landmarks():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    comp = FaceCompositor(_StubRestorer(), _StubMasker(), CompositeConfig())
    frame = np.zeros((256, 256, 3), np.uint8)
    swap = np.zeros((128, 128, 3), np.uint8)
    m_swap = np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], np.float32)

    out = comp.composite(frame, swap, m_swap, np.zeros((3, 2), np.float32))
    check(np.array_equal(out, frame), "degenerate landmarks must leave the frame alone")


@test
def test_temporal_ema_is_a_passthrough_when_disabled():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    comp = FaceCompositor(_StubRestorer(), _StubMasker(),
                          CompositeConfig(temporal=False))
    a = np.full((4, 4), 1.0, np.float32)
    b = np.full((4, 4), 5.0, np.float32)
    comp._ema(0, "k", a, 0.5)
    check(float(comp._ema(0, "k", b, 0.5).mean()) == 5.0,
          "with temporal off, the current value must pass straight through")


@test
def test_temporal_ema_converges_smoothly():
    from face_compositor import CompositeConfig, FaceCompositor

    comp = FaceCompositor(_StubRestorer(), _StubMasker(),
                          CompositeConfig(temporal=True))
    check(comp._ema(1, "sigma", 0.0, 0.5) == 0.0, "first value seeds the track")

    step = comp._ema(1, "sigma", 10.0, 0.5)
    check(abs(step - 5.0) < 1e-6, f"expected a half step to 5.0, got {step}")

    step2 = comp._ema(1, "sigma", 10.0, 0.5)
    check(5.0 < step2 < 10.0, f"expected continued convergence, got {step2}")


@test
def test_temporal_tracks_are_evicted_and_reset():
    from face_compositor import CompositeConfig, FaceCompositor

    comp = FaceCompositor(_StubRestorer(), _StubMasker(),
                          CompositeConfig(temporal=True, track_ttl=3))
    comp._ema(7, "sigma", 4.0, 0.5)
    comp._touch(7)
    check(7 in comp._tracks, "track should exist")

    for _ in range(5):
        comp.begin_frame()
    check(7 not in comp._tracks, "stale track should have been evicted")

    comp._ema(8, "sigma", 4.0, 0.5)
    comp.reset()
    check(comp._tracks == {}, "reset must clear all tracks")


class _FakeFace:
    def __init__(self, kps):
        import numpy as np
        self.kps = np.asarray(kps, dtype=np.float32)


def _face_at(cx, cy):
    return _FakeFace([[cx - 20, cy - 10], [cx + 20, cy - 10], [cx, cy],
                      [cx - 15, cy + 20], [cx + 15, cy + 20]])


@test
def test_smooth_returns_stable_track_ids():
    from reface_engine_v3 import RefaceEngineV3

    eng = RefaceEngineV3.__new__(RefaceEngineV3)   # no models, no GPU
    eng.smooth_landmarks = True
    eng.smooth_alpha = 0.6
    eng._reset_tracks()

    _, ids_a = eng._smooth([_face_at(100, 100)])
    _, ids_b = eng._smooth([_face_at(104, 102)])   # same face, moved slightly
    check(ids_a == ids_b, f"a moving face must keep its id: {ids_a} then {ids_b}")

    _, ids_c = eng._smooth([_face_at(104, 102), _face_at(600, 400)])
    check(ids_c[0] == ids_a[0], "the tracked face keeps its id")
    check(ids_c[1] != ids_a[0], "a new face must get a new id")


@test
def test_smooth_tracks_even_with_landmark_smoothing_off():
    import numpy as np
    from reface_engine_v3 import RefaceEngineV3

    eng = RefaceEngineV3.__new__(RefaceEngineV3)
    eng.smooth_landmarks = False
    eng.smooth_alpha = 0.6
    eng._reset_tracks()

    f1 = _face_at(100, 100)
    before = f1.kps.copy()
    _, ids_a = eng._smooth([f1])
    check(np.array_equal(f1.kps, before), "landmarks must not be modified when off")

    _, ids_b = eng._smooth([_face_at(103, 101)])
    check(ids_a == ids_b, "tracking must still work with smoothing disabled")


@test
def test_audio_mux_command_ordering():
    from reface_engine_v3 import build_mux_command

    cmd = build_mux_command("out.mp4", "src.mp4", "tmp.mp4", 0.0, None)
    check(cmd.index("-i") < cmd.index("src.mp4"), "source must follow an -i")
    check("-c" in cmd and "copy" in cmd, "must stream-copy, not re-encode")
    check(cmd[-1] == "tmp.mp4", f"output must be last, got {cmd[-1]}")
    check("0:v:0" in cmd and "1:a:0" in cmd, "must map video from 0 and audio from 1")


@test
def test_audio_mux_command_applies_clipping_to_the_source():
    from reface_engine_v3 import build_mux_command

    cmd = build_mux_command("out.mp4", "src.mp4", "tmp.mp4", 4.0, 9.5)
    src = cmd.index("src.mp4")
    check("-ss" in cmd[:src] and "-to" in cmd[:src],
          "clip options must precede the source input so they apply to it")
    check(cmd[cmd.index("-ss") + 1] == "4.0", "start time not passed through")
    check(cmd[cmd.index("-to") + 1] == "9.5", "end time not passed through")


@test
def test_face_changed_sees_a_small_face_in_a_big_frame():
    """Regression: the no-op guard averaged over the whole frame, so a fully
    swapped 300px face in 1080p read as 'unchanged' (~0.2) and the HD composite
    was replaced by insightface's plain paste on nearly every video frame."""
    import numpy as np
    from reface_engine_v3 import face_changed, _mean_abs_diff

    before = np.full((1080, 1920, 3), 120, np.uint8)
    after = before.copy()
    after[400:550, 900:1050] += 6          # a 150px face, swapped
    face = _FakeFace(np.zeros((5, 2)))
    face.bbox = np.array([900.0, 400.0, 1050.0, 550.0])

    check(_mean_abs_diff(after, before) < 0.5, "precondition: whole-frame mean is tiny")
    check(face_changed(after, before, face), "a swapped face must count as changed")
    other = _FakeFace(np.zeros((5, 2)))
    other.bbox = np.array([100.0, 100.0, 250.0, 250.0])
    check(not face_changed(after, before, other), "an untouched face must count as unchanged")


@test
def test_frame_rate_keeps_fractional_rates():
    from reface_engine_v3 import rate_arg, video_fps

    check(rate_arg(29.97002997) == "30000/1001", f"29.97 -> {rate_arg(29.97002997)}")
    check(rate_arg(23.976023976) == "24000/1001", f"23.976 -> {rate_arg(23.976023976)}")
    check(rate_arg(25.0) == "25/1", f"25 -> {rate_arg(25.0)}")

    class _Cap:
        def __init__(self, fps):
            self.fps = fps

        def get(self, _prop):
            return self.fps

    check(abs(video_fps(_Cap(29.97002997)) - 29.97002997) < 1e-6, "fps must stay fractional")
    check(video_fps(_Cap(0.0)) == 25.0, "an unknown rate falls back to 25")
    check(video_fps(_Cap(float("nan"))) == 25.0, "a NaN rate falls back to 25")


def _unit(v):
    import numpy as np
    v = np.asarray(v, np.float32)
    return v / np.linalg.norm(v)


@test
def test_match_reference_keeps_a_lookalike_bystander_out():
    import numpy as np
    from reface_engine_v3 import match_reference

    rng = np.random.default_rng(3)
    a = _unit(rng.standard_normal(512))
    noise = _unit(rng.standard_normal(512))
    b = _unit(0.6 * a + 0.8 * noise)               # a different person who looks a bit like A
    refs = np.stack([a, b])

    check(match_reference(_unit(a + 0.1 * noise), refs, {0}), "A again must be selected")
    check(not match_reference(_unit(b + 0.05 * a), refs, {0}),
          "B resembles A but is nearest to B's own reference: not selected")
    stranger = _unit(rng.standard_normal(512))
    check(not match_reference(stranger, refs, {0, 1}), "a stranger matches nobody")
    check(not match_reference(None, refs, {0}), "no embedding, no swap")


@test
def test_face_selector_reidentifies_tracks_periodically():
    import numpy as np
    from reface_engine_v3 import FaceSelector, SELECT_RECHECK_FRAMES

    a = _unit(np.random.default_rng(5).standard_normal(512))
    sel = FaceSelector([a.tolist()], [0])
    calls = []

    def embed():
        calls.append(1)
        return a

    for frame_no in range(SELECT_RECHECK_FRAMES):
        check(sel.wants(7, frame_no, embed), "the selected person must be swapped")
    check(len(calls) == 1, f"one embedding per recheck window, got {len(calls)}")
    sel.wants(7, SELECT_RECHECK_FRAMES, embed)
    check(len(calls) == 2, "the track must be re-identified after the window")


@test
def test_identity_boost_pushes_away_from_the_target():
    import numpy as np
    from identity import AveragedSource
    from reface_engine_v3 import RefaceEngineV3

    rng = np.random.default_rng(1)
    s, t = _unit(rng.standard_normal(512)), _unit(rng.standard_normal(512))
    src = AveragedSource(s)
    eng = RefaceEngineV3.__new__(RefaceEngineV3)   # no models
    eng._embed = lambda img, face: t

    eng.identity_boost = 0.0
    check(eng.boosted_source(src, None, None) is src, "boost 0 must leave the source untouched")
    eng.identity_boost = 1.0
    got = eng.boosted_source(src, None, None).normed_embedding
    check(np.allclose(got, s * 1.35 - t * 0.35, atol=1e-6), "boost 1 = FaceFusion's maximum extrapolation")
    check(float(_unit(got) @ t) < float(s @ t), "the boosted identity must be further from the target")


def _full_frame_paste(frame, crop, mask, m_ffhq):
    """The pre-ROI paste, kept here as the reference the ROI version must match."""
    import cv2
    import numpy as np

    h, w = frame.shape[:2]
    im = cv2.invertAffineTransform(m_ffhq)
    back = cv2.warpAffine(crop, im, (w, h), borderMode=cv2.BORDER_REPLICATE)
    m_back = np.clip(cv2.warpAffine(mask, im, (w, h)), 0.0, 1.0)[..., None]
    return (frame.astype(np.float32) * (1.0 - m_back) + back.astype(np.float32) * m_back).astype(np.uint8)


@test
def test_roi_paste_matches_a_full_frame_paste():
    import cv2
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor, alignment_matrix

    # Face-like content: smooth crop, feathered mask. (On white noise the two
    # differ by OpenCV's 1/32-pixel interpolation steps, which a real face
    # never shows.)
    rng = np.random.default_rng(9)
    frame = rng.integers(0, 255, (720, 1280, 3)).astype(np.uint8)
    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    crop = np.dstack([128 + 60 * np.sin(xx / 40), 128 + 60 * np.cos(yy / 35),
                      128 + 40 * np.sin((xx + yy) / 50)]).astype(np.uint8)
    mask = np.zeros((512, 512), np.float32)
    mask[96:416, 96:416] = 1.0
    mask = cv2.GaussianBlur(mask, (0, 0), 12)
    comp = FaceCompositor(_StubRestorer(), _StubMasker(), CompositeConfig())

    for cx in (640.0, 40.0):                       # centred, and hanging off the left edge
        kps = np.array([[cx - 40, 300], [cx + 40, 302], [cx, 340],
                        [cx - 32, 375], [cx + 32, 376]], np.float32)
        m = alignment_matrix(kps, 512)
        got = comp._paste(frame, crop, mask, m, native_px=400.0)
        want = _full_frame_paste(frame, crop, mask, m)
        diff = np.abs(got.astype(int) - want.astype(int))
        check(diff.max() <= 3 and diff.mean() < 0.01,
              f"ROI paste drifted from the full-frame paste at cx={cx}: max {diff.max()}, mean {diff.mean():.4f}")


@test
def test_low_res_gain_map_matches_full_res():
    import numpy as np
    from face_harmonize import apply_gain, compute_gain

    yy, xx = np.mgrid[0:512, 0:512].astype(np.float32)
    ref = np.dstack([90 + 0.2 * xx, 100 + 0.1 * yy, 120 + 0.05 * (xx + yy)]).clip(0, 255).astype(np.uint8)
    res = np.full((512, 512, 3), 128, np.uint8)
    mask = np.zeros((512, 512), np.float32)
    mask[64:448, 96:416] = 1.0

    full = apply_gain(res, compute_gain(res, ref, mask, scale=1), 1.0).astype(int)
    fast = apply_gain(res, compute_gain(res, ref, mask), 1.0).astype(int)
    inside = mask > 0.5
    check(np.abs(full - fast)[inside].max() <= 2,
          f"low-res gain must stay within 2 grey levels, got {np.abs(full - fast)[inside].max()}")


@test
def test_finish_v3_video_joins_parts_and_adds_audio():
    import shutil
    import subprocess
    import tempfile
    from pathlib import Path
    from ffmpeg_utils import _ffmpeg_exe
    from job_manager import Job, JobStatus, finish_v3_video

    ff = _ffmpeg_exe()
    if not (Path(ff).exists() or shutil.which(ff)):
        print("   (skipped: no ffmpeg)")
        return

    tmp = Path(tempfile.mkdtemp())
    try:
        def make(path, seconds, start, audio=False):
            cmd = [ff, "-y", "-loglevel", "error", "-f", "lavfi",
                   "-i", f"testsrc=size=160x120:rate=30000/1001:duration={seconds}"]
            if audio:
                cmd += ["-f", "lavfi", "-i", f"sine=frequency=440:duration={seconds}", "-c:a", "aac"]
            cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p", str(path)]
            subprocess.run(cmd, check=True)

        source = tmp / "source.mp4"
        make(source, 4, 0, audio=True)
        part1, part2 = tmp / "refaced_v3_part_a.mp4", tmp / "refaced_v3_part_b.mp4"
        make(part1, 2, 0)
        make(part2, 2, 0)

        job = Job(id="t1", job_type="reface_video_v3", status=JobStatus.RUNNING,
                  progress=0.5, message="", created_at="", params={})
        job.part_files = [str(part1)]
        job.frames_done = 60
        final = finish_v3_video(job, str(part2), 60, str(source))

        probe = subprocess.run([ff, "-hide_banner", "-i", str(final)], capture_output=True, text=True).stderr
        check(final.exists(), "final video must exist")
        check("Audio:" in probe, "the source audio must be muxed onto the joined video")
        check("Duration: 00:00:04" in probe or "Duration: 00:00:03.9" in probe,
              f"both parts must be joined (~4s): {probe[probe.find('Duration'):][:30]}")
        check(not part1.exists() and not part2.exists(), "parts must be cleaned up")
        check(job.part_files == [] and job.frames_done == 120, "job bookkeeping must be updated")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


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
