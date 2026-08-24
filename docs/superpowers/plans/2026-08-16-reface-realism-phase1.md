# Reface Realism Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the compositing stage of the V3 reface pipeline so swapped faces keep occluders and real teeth, match the frame's lighting, focus and grain, stay stable in video, and no longer show a seam.

**Architecture:** A new pure-function module `face_harmonize.py` holds the image math (noise estimation, lighting gain, focus, detail transfer, grain). A new `face_compositor.py` holds `CompositeConfig` and `FaceCompositor`, which owns everything after the swap: align → restore → mask → harmonize → paste, plus per-track temporal state. `RefaceEngineV3` becomes an orchestrator. The compositor takes the swapper's affine matrix as a parameter, so inswapper, DFM, and phase 2's 256px model all share one realism core.

**Tech Stack:** Python 3.13, NumPy, OpenCV, onnxruntime-gpu, insightface, Streamlit. No new dependencies, no new model downloads.

**Spec:** [docs/superpowers/specs/2026-08-16-reface-realism-design.md](../specs/2026-08-16-reface-realism-design.md)

---

## Before you start

**You must not run terminal commands.** `CLAUDE.md` carries an always-on standing rule for this repo: post the command and let the user run it, then work from the output they paste back. Every "Run:" step below is a command for *the user*. Wait for their output before continuing.

All commands assume the working directory is `D:\AndroidScan\gallary\the app` with the venv present. The repo has no pytest; tests are standalone scripts that print results and `exit(1)` on failure. Task 1 builds a tiny runner so individual tests can be run by name.

Two deliberate simplifications from the spec, both consistent with its intent:

1. The spec described subtracting an inner-mouth hole from the mask. Excluding class 11 from the region list achieves the same thing with less code, because the mask is an intersection of two region masks that both exclude it. The distance-transform feather then ramps around the hole automatically.
2. The spec put all the image math inside `face_compositor.py`. It is split into `face_harmonize.py` (pure functions, no state, no models) so it can be unit-tested without a GPU.

---

## File structure

| File | Responsibility |
|---|---|
| `the app/face_harmonize.py` | **New.** Pure image math: noise estimation, masked low-frequency, lighting gain, focus, detail transfer, grain. No state, no models, no I/O. |
| `the app/face_compositor.py` | **New.** `CompositeConfig`, presets, affine composition, `FaceCompositor` (align → restore → mask → harmonize → paste + temporal state). |
| `the app/face_masking.py` | Add `segment`, `region_from_seg`, `harden_occlusion`, `feather_mask`. Existing `region_mask` reimplemented on top of the new helpers so current callers keep working. |
| `the app/reface_engine_v3.py` | `_process_face` / `_process_face_dfm` route through the compositor; `_smooth` returns track ids; audio mux; per-video reset. |
| `the app/dashboard.py` | Realism expander in the V3 branch of the Reface V2 page. |
| `the app/job_manager.py` | Thread realism params through to `RefaceEngineV3`. |
| `the app/test_compositor.py` | **New.** Standalone test script with a name filter. |
| `the app/compare_v3.py` | **New.** Renders legacy vs new side by side for visual judgement. |
| `the app/CLAUDE.md` | Document the two new modules. |

---

## Task 1: Test harness

**Files:**
- Create: `the app/test_compositor.py`
- Create: `the app/face_harmonize.py`

- [ ] **Step 1: Write the test runner and the first failing test**

Create `the app/test_compositor.py`:

```python
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
```

- [ ] **Step 2: Run it to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py imports`
Expected: FAIL with `ModuleNotFoundError: No module named 'face_harmonize'`

- [ ] **Step 3: Create the module**

Create `the app/face_harmonize.py`:

```python
"""
Antigravity Local - face harmonization math

Pure functions used by face_compositor.py to make a swapped face sit in its
frame: lighting, focus, skin detail and sensor grain. No state, no models, no
I/O - everything here is testable with synthetic arrays on CPU.

All image arguments are BGR uint8 unless stated otherwise. All mask arguments
are float32 in [0, 1] with the same height and width as the image.
"""

import cv2
import numpy as np
```

- [ ] **Step 4: Run it to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py imports`
Expected: `[PASS] test_imports` and `1/1 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "test: add compositor test harness"
```

---

## Task 2: Noise estimator

Immerkær's estimator. The kernel `[[1,-2,1],[-2,4,-2],[1,-2,1]]` has a sum of squares of 36, so for pure Gaussian noise the mean absolute response is `6 * sigma * sqrt(2/pi)`, giving `sigma = sqrt(pi/2) * mean(|conv|) / 6`.

**Files:**
- Modify: `the app/face_harmonize.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py noise`
Expected: 3 FAILs with `ImportError: cannot import name 'estimate_noise_sigma'`

- [ ] **Step 3: Implement**

Append to `the app/face_harmonize.py`:

```python
_NOISE_KERNEL = np.array([[1, -2, 1],
                          [-2, 4, -2],
                          [1, -2, 1]], dtype=np.float32)


def estimate_noise_sigma(gray, mask=None, max_sigma: float = 12.0) -> float:
    """Immerkaer's fast noise estimate, in 0-255 units.

    `mask` restricts the measurement (pass the non-face region so skin texture
    doesn't inflate the reading). Structure inside the measured area biases the
    estimate upward, so the result is clamped: slightly too much grain is a far
    smaller tell than none at all.
    """
    if gray is None or gray.ndim != 2 or min(gray.shape) < 8:
        return 0.0
    conv = np.abs(cv2.filter2D(gray.astype(np.float32), -1, _NOISE_KERNEL))[2:-2, 2:-2]
    if mask is not None:
        sel = mask[2:-2, 2:-2] > 0.5
        if int(sel.sum()) >= 256:
            conv = conv[sel]
    if conv.size == 0:
        return 0.0
    sigma = float(np.sqrt(np.pi / 2.0) * conv.mean() / 6.0)
    return float(np.clip(sigma, 0.0, max_sigma))
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py noise`
Expected: 3 `[PASS]` lines, `3/3 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "feat: add Immerkaer noise estimator for grain matching"
```

---

## Task 3: Lighting gain

Split into `compute_gain` and `apply_gain` so the compositor can EMA the gain map across video frames.

**Files:**
- Modify: `the app/face_harmonize.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py gain`
Expected: 3 FAILs with `ImportError: cannot import name 'compute_gain'`

Run: `venv\Scripts\python.exe test_compositor.py lab_color`
Expected: 2 FAILs with `ImportError: cannot import name 'lab_color_match'`

- [ ] **Step 3: Implement**

Append to `the app/face_harmonize.py`:

```python
GAIN_MIN = 0.7
GAIN_MAX = 1.4
_GAIN_FLOOR = 4.0   # 0-255 units; keeps the ratio stable in near-black regions


def masked_lowfreq(img, mask, sigma: float) -> np.ndarray:
    """Low-frequency content of `img`, measured only over `mask`.

    A plain blur would drag background pixels into the estimate near the mask
    edge. Normalising by the blurred mask keeps the average local to the face.
    """
    m3 = np.dstack([mask.astype(np.float32)] * 3)
    num = cv2.GaussianBlur(img.astype(np.float32) * m3, (0, 0), sigma)
    den = cv2.GaussianBlur(m3, (0, 0), sigma)
    return num / (den + 1e-6)


def compute_gain(result, reference, mask, sigma: float = None) -> np.ndarray:
    """Per-channel low-frequency gain that moves `result` toward `reference`.

    Because it is a spatial map rather than a single number, this follows the
    scene's light direction and white balance instead of only its average tone.
    """
    h, w = result.shape[:2]
    if sigma is None:
        sigma = max(2.0, min(h, w) / 16.0)
    lo_ref = masked_lowfreq(reference, mask, sigma)
    lo_res = masked_lowfreq(result, mask, sigma)
    gain = (lo_ref + _GAIN_FLOOR) / (lo_res + _GAIN_FLOOR)
    return np.clip(gain, GAIN_MIN, GAIN_MAX).astype(np.float32)


def apply_gain(img, gain, strength: float = 1.0) -> np.ndarray:
    """Apply a gain map at the given strength. strength=0 is the identity."""
    if strength <= 0:
        return img
    scaled = 1.0 + (gain - 1.0) * float(strength)
    return np.clip(img.astype(np.float32) * scaled, 0, 255).astype(np.uint8)


def lab_color_match(result, reference, mask=None) -> np.ndarray:
    """Global LAB mean/std transfer - the fallback when the mask is too small.

    A spatial gain map needs enough pixels to be meaningful. On a handful of
    them it becomes noise, so tiny faces fall back to this single global shift.
    Same behaviour as the pre-rebuild `_color_match` in reface_engine_v3.
    """
    try:
        s = cv2.cvtColor(result, cv2.COLOR_BGR2LAB).astype(np.float32)
        r = cv2.cvtColor(reference, cv2.COLOR_BGR2LAB).astype(np.float32)
        sel = None
        if mask is not None:
            sel = mask > 0.5
            if int(sel.sum()) < 16:
                sel = None
        if sel is not None:
            s_mean, s_std = s[sel].mean(0), s[sel].std(0)
            r_mean, r_std = r[sel].mean(0), r[sel].std(0)
        else:
            s_mean, s_std = s.reshape(-1, 3).mean(0), s.reshape(-1, 3).std(0)
            r_mean, r_std = r.reshape(-1, 3).mean(0), r.reshape(-1, 3).std(0)
        out = (s - s_mean) * (r_std / (s_std + 1e-6)) + r_mean
        return cv2.cvtColor(np.clip(out, 0, 255).astype(np.uint8), cv2.COLOR_LAB2BGR)
    except Exception:
        return result
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py gain`
Expected: 3 `[PASS]` lines, `3/3 passed`

Run: `venv\Scripts\python.exe test_compositor.py lab_color`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "feat: add lighting gain map with a global LAB fallback"
```

---

## Task 4: Focus matching

`choose_focus_sigma` returns the blur radius rather than the blurred image, so the compositor can EMA the radius across frames.

**Files:**
- Modify: `the app/face_harmonize.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py focus`
Expected: 2 FAILs with `ImportError: cannot import name 'choose_focus_sigma'`

- [ ] **Step 3: Implement**

Append to `the app/face_harmonize.py`:

```python
FOCUS_SIGMAS = (0.5, 0.8, 1.2, 1.8, 2.6)


def laplacian_var(img, mask=None) -> float:
    """Laplacian variance - a cheap sharpness proxy - measured inside `mask`."""
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if img.ndim == 3 else img
    lap = cv2.Laplacian(gray.astype(np.float32), cv2.CV_32F)
    if mask is None:
        return float(lap.var())
    sel = mask > 0.5
    if int(sel.sum()) < 64:
        return float(lap.var())
    return float(lap[sel].var())


def choose_focus_sigma(result, reference, mask) -> float:
    """Smallest blur sigma that brings `result` down to `reference` sharpness.

    Returns 0.0 when the result is already as soft as the reference. A razor
    sharp face composited into a soft or motion-blurred frame floats on top of
    it, which reads as fake even when everything else is right.
    """
    ref_v = laplacian_var(reference, mask)
    if ref_v <= 0 or laplacian_var(result, mask) <= ref_v:
        return 0.0
    for s in FOCUS_SIGMAS:
        if laplacian_var(cv2.GaussianBlur(result, (0, 0), s), mask) <= ref_v:
            return float(s)
    return float(FOCUS_SIGMAS[-1])
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py focus`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "feat: add focus matching against the target frame"
```

---

## Task 5: Detail transfer

**Files:**
- Modify: `the app/face_harmonize.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py detail`
Expected: 2 FAILs with `ImportError: cannot import name 'transfer_detail'`

- [ ] **Step 3: Implement**

Append to `the app/face_harmonize.py`:

```python
def transfer_detail(result, reference, skin_mask, amount: float, sigma: float = 2.0) -> np.ndarray:
    """Re-inject the reference's high-frequency skin texture onto `result`.

    This is what stops restored faces looking plastic: the restorer produces
    clean skin, and real skin at close range is full of pores and fine noise
    that the original frame already contains. Restricted to the skin region so
    eyelashes and lip lines are not doubled up.
    """
    if amount <= 0:
        return result
    ref = reference.astype(np.float32)
    hf = ref - cv2.GaussianBlur(ref, (0, 0), sigma)
    m3 = np.dstack([skin_mask.astype(np.float32)] * 3)
    out = result.astype(np.float32) + hf * m3 * float(amount)
    return np.clip(out, 0, 255).astype(np.uint8)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py detail`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "feat: add skin detail transfer from the original frame"
```

---

## Task 6: Grain

**Files:**
- Modify: `the app/face_harmonize.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py grain`
Expected: 3 FAILs with `ImportError: cannot import name 'add_grain'`

- [ ] **Step 3: Implement**

Append to `the app/face_harmonize.py`:

```python
_CHROMA_RATIO = 0.3


def add_grain(img, sigma: float, mask=None, amount: float = 1.0, rng=None) -> np.ndarray:
    """Add luma-dominant, slightly correlated noise at the given sigma.

    Real sensor noise is demosaiced and compressed, so it is spatially
    correlated rather than white - hence the half-pixel blur, renormalised so
    `sigma` still means what it says.
    """
    if sigma <= 0 or amount <= 0:
        return img
    rng = rng if rng is not None else np.random.default_rng()
    h, w = img.shape[:2]

    luma = cv2.GaussianBlur(rng.standard_normal((h, w)).astype(np.float32), (0, 0), 0.5)
    s = float(luma.std())
    if s > 1e-6:
        luma /= s

    chroma = rng.standard_normal((h, w, 3)).astype(np.float32) * _CHROMA_RATIO
    noise = (luma[..., None] + chroma) * (float(sigma) * float(amount))

    if mask is not None:
        noise *= np.dstack([mask.astype(np.float32)] * 3)

    return np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py grain`
Expected: 3 `[PASS]` lines, `3/3 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_harmonize.py" && git commit -m "feat: add matched sensor grain synthesis"
```

---

## Task 7: Mask helpers in face_masking.py

Adds occluder hardening, the distance-transform feather, and a `segment` / `region_from_seg` split so one parser pass can produce both the region mask and the skin mask.

**Files:**
- Modify: `the app/face_masking.py:116-135` (`region_mask`)
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py mask`
Expected: FAILs with `ImportError: cannot import name 'harden_occlusion'`

Run: `venv\Scripts\python.exe test_compositor.py occluder`
Expected: FAIL, same import error

- [ ] **Step 3: Implement**

In `the app/face_masking.py`, replace the `region_mask` method (currently lines 116-135) with a `segment` / `region_from_seg` split:

```python
    def segment(self, crop_bgr: np.ndarray):
        """Run the parser and return a (H, W) class-index map at crop size.

        Returns None if the parser is unavailable or fails. One pass yields
        every region, so callers needing both a swap region and a skin mask
        should call this once rather than region_mask twice.
        """
        if self.parser is None:
            return None
        try:
            h, w = crop_bgr.shape[:2]
            layout, size = self._parser_layout
            prep = cv2.resize(crop_bgr, (size, size))[:, :, ::-1].astype(np.float32) / 255.0
            prep = (prep - _IMAGENET_MEAN) / _IMAGENET_STD
            if layout == "nchw":
                prep = prep.transpose(2, 0, 1)
            prep = prep[None, ...].astype(np.float32)
            out = self.parser.run(None, {self._parser_in: prep})[0][0]
            seg = out.argmax(0) if out.shape[0] <= 32 else out.argmax(-1)
            return cv2.resize(seg.astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST)
        except Exception as e:
            print(f"[MASK] segment failed: {e}")
            return None

    def region_mask(self, crop_bgr: np.ndarray, regions: List[str]) -> np.ndarray:
        """Float [0,1] mask of the given regions, at crop resolution."""
        h, w = crop_bgr.shape[:2]
        seg = self.segment(crop_bgr)
        if seg is None:
            return box_mask(h, w)
        return region_from_seg(seg, regions)
```

Then append these module-level functions to `the app/face_masking.py`, after `box_mask`:

```python
def region_from_seg(seg: np.ndarray, regions: List[str]) -> np.ndarray:
    """Float [0,1] mask selecting the named classes out of a segmentation map."""
    idx = [REGIONS[r] for r in regions if r in REGIONS]
    return np.isin(seg, idx).astype(np.float32)


def harden_occlusion(occ: np.ndarray, sigma: float = 5.0) -> np.ndarray:
    """Turn the occluder's soft probability field into a usable matte.

    Blur, then remap [0.5, 1] onto [0, 1] (facefusion's convention). Without
    this the raw field dissolves under feathering and an occluding hand comes
    back as a translucent ghost.
    """
    blurred = cv2.GaussianBlur(occ.astype(np.float32), (0, 0), sigma)
    return np.clip((np.clip(blurred, 0.5, 1.0) - 0.5) * 2.0, 0.0, 1.0)


def feather_mask(mask: np.ndarray, erode: float = 0.02, feather: float = 0.05) -> np.ndarray:
    """Erode, then ramp inward with a distance transform.

    A Gaussian applied to a binary mask gives an edge whose width varies with
    local shape. A distance transform gives a uniform-width ramp, which is what
    a clean paste boundary needs.
    """
    h, w = mask.shape[:2]
    size = min(h, w)
    binary = (mask > 0.5).astype(np.uint8)

    e = int(size * erode)
    if e > 0:
        binary = cv2.erode(binary, np.ones((2 * e + 1, 2 * e + 1), np.uint8))

    f = max(2.0, size * feather)
    dist = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    ramp = np.clip(dist / f, 0.0, 1.0).astype(np.float32)
    return cv2.GaussianBlur(ramp, (0, 0), 1.0)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py mask`
Expected: 2 `[PASS]` lines, `2/2 passed`

Run: `venv\Scripts\python.exe test_compositor.py occluder`
Expected: `[PASS] test_occluder_regression_hand_survives`, `1/1 passed`

- [ ] **Step 5: Verify existing callers still work**

Run: `venv\Scripts\python.exe -c "import face_masking; m = face_masking.FaceMasker(); print('parser', m.parser is not None, 'occluder', m.occluder is not None)"`
Expected: `parser True occluder True` (models are present in `models/`)

- [ ] **Step 6: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_masking.py" && git commit -m "feat: harden occluder matte and add distance-transform feather"
```

---

## Task 8: Affine composition

`T = M_ffhq . inv(M_swap)` maps the swapper's crop space directly into FFHQ space in one resample, instead of routing back through the full frame.

**Files:**
- Create: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py affine`
Expected: 2 FAILs with `ModuleNotFoundError: No module named 'face_compositor'`

- [ ] **Step 3: Implement**

Create `the app/face_compositor.py`:

```python
"""
Antigravity Local - face compositor

Owns everything after the swap: align -> restore -> mask -> harmonize -> paste,
plus the per-track temporal state that keeps video stable.

The swapper hands over its own affine matrix, so inswapper, DeepFaceLab DFM
models and any future higher-resolution swapper all share one realism core
instead of each carrying a copy of it.
"""

from dataclasses import dataclass, field
from typing import List, Optional

import cv2
import numpy as np


def _to_h(m: np.ndarray) -> np.ndarray:
    """2x3 affine -> 3x3 homogeneous."""
    return np.vstack([np.asarray(m, np.float64), [0.0, 0.0, 1.0]])


def compose_affine(outer: np.ndarray, inner: np.ndarray) -> np.ndarray:
    """The 2x3 affine equivalent to undoing `inner` then applying `outer`.

    Used as compose_affine(M_ffhq, M_swap): takes a point in the swapper's crop
    space straight to FFHQ crop space, so the swapped pixels are resampled once
    instead of being pasted into the frame and re-cropped.
    """
    return (_to_h(outer) @ np.linalg.inv(_to_h(inner)))[:2].astype(np.float32)


def scale_affine(m: np.ndarray, factor: float) -> np.ndarray:
    """Adjust a crop-to-frame affine for a crop that was resized by `factor`."""
    s = np.diag([1.0 / factor, 1.0 / factor, 1.0])
    return (_to_h(m) @ s)[:2].astype(np.float32)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py affine`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add affine composition helpers for single-resample alignment"
```

---

## Task 9: CompositeConfig and presets

**Files:**
- Modify: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py preset`
Expected: 2 FAILs with `ImportError: cannot import name 'CompositeConfig'`

- [ ] **Step 3: Implement**

Append to `the app/face_compositor.py`:

```python
@dataclass
class CompositeConfig:
    restore_size: int = 512
    mask_regions: Optional[List[str]] = None      # None -> face_masking.DEFAULT_REGIONS
    use_parser: bool = True
    use_occluder: bool = True
    preserve_mouth_interior: bool = True          # keep the target's real teeth
    mask_erode: float = 0.02                      # fraction of crop size
    mask_feather: float = 0.05                    # fraction of crop size
    relight: float = 1.0                          # 0..1
    detail_transfer: float = 0.4                  # 0..1, scaled again by face size
    grain_match: float = 1.0                      # 0..1
    focus_match: bool = True
    blend: float = 1.0
    temporal: bool = False
    temporal_alpha: float = 0.5                   # gain map and mask
    temporal_alpha_slow: float = 0.3              # noise sigma and focus radius
    mask_area_floor: float = 0.005                # below this, statistics are unreliable
    track_ttl: int = 30                           # frames before a track is evicted


PRESETS = {
    "natural": dict(detail_transfer=0.4, grain_match=1.0, relight=1.0,
                    focus_match=True, preserve_mouth_interior=True),
    "maximum_detail": dict(detail_transfer=0.6, grain_match=1.0, relight=1.0,
                           focus_match=True, preserve_mouth_interior=True),
    # Reproduces pre-rebuild V3 behaviour, so improvements can be A/B'd.
    "clean": dict(detail_transfer=0.0, grain_match=0.0, relight=0.0,
                  focus_match=False, preserve_mouth_interior=False),
}


def config_from_preset(name: str, **overrides) -> CompositeConfig:
    if name not in PRESETS:
        raise ValueError(f"unknown preset '{name}'; known: {', '.join(PRESETS)}")
    values = dict(PRESETS[name])
    values.update(overrides)
    return CompositeConfig(**values)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py preset`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add CompositeConfig and realism presets"
```

---

## Task 10: FaceCompositor — alignment and coverage fill

The arcface-128 crop inswapper produces frames tighter than the FFHQ-512 template CodeFormer expects, and does not reach the forehead. Uncovered pixels are filled from the original.

**Files:**
- Modify: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py alignment`
Expected: FAIL with `ImportError: cannot import name 'alignment_matrix'`

Run: `venv\Scripts\python.exe test_compositor.py place_swap`
Expected: FAIL with `ImportError: cannot import name 'FaceCompositor'`

- [ ] **Step 3: Implement**

Append to `the app/face_compositor.py`:

```python
from face_masking import (DEFAULT_REGIONS, box_mask, feather_mask,
                          harden_occlusion, region_from_seg)
from face_harmonize import (add_grain, apply_gain, choose_focus_sigma,
                            compute_gain, estimate_noise_sigma,
                            lab_color_match, transfer_detail)

# FFHQ-512 5-point template, shared with reface_engine_v3.
_FFHQ_512 = np.array(
    [[192.98138, 239.94708],
     [318.90277, 240.19360],
     [256.63416, 314.01935],
     [201.26117, 371.41043],
     [313.08905, 371.15118]],
    dtype=np.float32,
)


def alignment_matrix(kps, size: int) -> Optional[np.ndarray]:
    """Similarity transform from 5-point landmarks to the FFHQ template."""
    src = np.asarray(kps, dtype=np.float32)
    if src.shape != (5, 2):
        return None
    dst = _FFHQ_512 * (size / 512.0)
    m, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)
    return m


class FaceCompositor:
    def __init__(self, restorer, masker, config: CompositeConfig = None):
        self.restorer = restorer
        self.masker = masker
        self.config = config or CompositeConfig()
        self._tracks = {}
        self._frame_no = 0
        self._rng = np.random.default_rng()
        self._logged = set()

    # -------------------------------------------------------------- lifecycle

    def reset(self):
        """Clear temporal state. Call at the start of each video."""
        self._tracks.clear()
        self._frame_no = 0
        self._logged.clear()

    def begin_frame(self):
        """Advance the frame counter and evict stale tracks."""
        self._frame_no += 1
        ttl = self.config.track_ttl
        dead = [k for k, v in self._tracks.items()
                if self._frame_no - v.get("_seen", 0) > ttl]
        for k in dead:
            self._tracks.pop(k, None)

    def _log_once(self, msg: str):
        """Log a degradation once per run. Per-frame logging buries the output
        on a 10,000-frame video."""
        if msg not in self._logged:
            self._logged.add(msg)
            print(f"[COMPOSITE] {msg}")

    def _guard(self, name: str, fn, fallback):
        try:
            return fn()
        except Exception as e:
            self._log_once(f"{name} failed ({e}); skipping that step")
            return fallback

    # ------------------------------------------------------------- alignment

    def _place_swap(self, aligned_swap, m_swap, m_ffhq, orig_aligned, size):
        """Warp the swapper's crop into FFHQ space in one resample, filling
        anything it doesn't cover (forehead, chin edges) from the original."""
        t = compose_affine(m_ffhq, m_swap)
        warped = cv2.warpAffine(aligned_swap, t, (size, size),
                                borderMode=cv2.BORDER_REPLICATE)
        ones = np.ones(aligned_swap.shape[:2], np.float32)
        cov = cv2.warpAffine(ones, t, (size, size), borderValue=0.0)
        cov = np.clip(cv2.GaussianBlur(cov, (0, 0), 2.0), 0.0, 1.0)[..., None]
        blended = warped.astype(np.float32) * cov + orig_aligned.astype(np.float32) * (1.0 - cov)
        return blended.astype(np.uint8)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py alignment`
Expected: `1/1 passed`

Run: `venv\Scripts\python.exe test_compositor.py place_swap`
Expected: `1/1 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add FaceCompositor alignment and coverage fill"
```

---

## Task 11: Mask assembly

**Files:**
- Modify: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py build_mask`
Expected: 3 FAILs with `AttributeError: 'FaceCompositor' object has no attribute '_build_mask'`

- [ ] **Step 3: Implement**

Append to the `FaceCompositor` class in `the app/face_compositor.py`:

```python
    # ------------------------------------------------------------------ mask

    def _regions(self) -> List[str]:
        regions = list(self.config.mask_regions or DEFAULT_REGIONS)
        if self.config.preserve_mouth_interior:
            # Class 11 is the inner mouth. A 128px swap carries about 30 real
            # pixels of teeth, which the restorer then turns into a smear -
            # keeping the target's own teeth is both cheaper and more honest.
            regions = [r for r in regions if r != "mouth"]
        return regions

    def _build_mask(self, restored, orig_aligned):
        """Return (paste_mask, region_orig, skin_orig), all float32 [0,1]."""
        h, w = restored.shape[:2]
        regions = self._regions()

        seg_orig = self.masker.segment(orig_aligned) if self.config.use_parser else None
        seg_res = self.masker.segment(restored) if self.config.use_parser else None

        if seg_orig is None or seg_res is None:
            region = box_mask(h, w)
            region_orig = region
            skin = region
        else:
            region_orig = region_from_seg(seg_orig, regions)
            # Intersect: never paint where the real frame was not face.
            region = region_from_seg(seg_res, regions) * region_orig
            skin = region_from_seg(seg_orig, ["skin"])

        mask = feather_mask(region, self.config.mask_erode, self.config.mask_feather)

        if self.config.use_occluder and self.masker.occluder is not None:
            occ = self.masker.occlusion_mask(orig_aligned)
            if occ is not None:
                mask = mask * harden_occlusion(occ)

        return np.clip(mask, 0.0, 1.0), region_orig, skin
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py build_mask`
Expected: 3 `[PASS]` lines, `3/3 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add region-intersected, occluder-aware mask assembly"
```

---

## Task 12: Harmonize and paste

**Files:**
- Modify: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
@test
def test_composite_leaves_the_frame_untouched_where_the_mask_is_zero():
    import numpy as np
    from face_compositor import CompositeConfig, FaceCompositor

    # Parser sees face only in a central box, so the frame border must survive
    # bit-for-bit - this is the seam/halo fix.
    seg = np.zeros((512, 512), np.uint8)
    seg[160:352, 160:352] = 1
    comp = FaceCompositor(_StubRestorer(), _SegMasker(seg), CompositeConfig())

    rng = np.random.default_rng(11)
    frame = rng.integers(0, 255, (720, 1280, 3)).astype(np.uint8)
    swap = rng.integers(0, 255, (128, 128, 3)).astype(np.uint8)

    kps = np.array([[600.0, 300.0], [680.0, 302.0], [640.0, 340.0],
                    [608.0, 375.0], [672.0, 376.0]], np.float32)
    m_swap = np.array([[1.0, 0.0, -560.0], [0.0, 1.0, -260.0]], np.float32)

    out = comp.composite(frame, swap, m_swap, kps, native_px=160.0)
    check(out.shape == frame.shape, f"shape changed: {out.shape}")
    check(np.array_equal(out[0:100, 0:100], frame[0:100, 0:100]),
          "a far corner of the frame must be bit-identical")
    check(not np.array_equal(out, frame), "the face region should have changed")


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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py composite`
Expected: 2 FAILs with `AttributeError: 'FaceCompositor' object has no attribute 'composite'`

- [ ] **Step 3: Implement**

Append to the `FaceCompositor` class in `the app/face_compositor.py`:

```python
    # ------------------------------------------------------------- harmonize

    def _detail_fraction(self, native_px) -> float:
        """How much real skin detail the original frame can lend us.

        A 90px face has none worth borrowing, so we lean on the restorer. A
        700px face is full of real pores, so we borrow heavily and dial the
        synthetic grain back correspondingly.
        """
        if not native_px:
            return 0.0
        return float(np.clip((float(native_px) - 128.0) / 384.0, 0.0, 1.0))

    def _harmonize(self, restored, orig_aligned, mask, region_orig, skin,
                   track_id, native_px):
        cfg = self.config
        out = restored
        small = float((mask > 0.01).mean()) < cfg.mask_area_floor

        if cfg.relight > 0:
            def _relight():
                if small:
                    # A spatial gain map is noise on a few hundred pixels; use a
                    # single global shift instead.
                    return lab_color_match(out, orig_aligned, mask)
                gain = compute_gain(out, orig_aligned, mask)
                gain = self._ema(track_id, "gain", gain, cfg.temporal_alpha)
                return apply_gain(out, gain, cfg.relight)
            out = self._guard("relight", _relight, out)

        if cfg.focus_match:
            def _focus():
                s = choose_focus_sigma(out, orig_aligned, mask)
                s = self._ema(track_id, "focus", s, cfg.temporal_alpha_slow)
                return cv2.GaussianBlur(out, (0, 0), s) if s > 0.05 else out
            out = self._guard("focus match", _focus, out)

        if small:
            # Detail and grain statistics are meaningless on a few hundred
            # pixels; relight above already fell back to a stable global map.
            return out

        frac = self._detail_fraction(native_px)

        if cfg.detail_transfer > 0 and frac > 0:
            out = self._guard(
                "detail transfer",
                lambda: transfer_detail(out, orig_aligned, skin * mask,
                                        cfg.detail_transfer * frac),
                out,
            )

        if cfg.grain_match > 0:
            def _grain():
                gray = cv2.cvtColor(orig_aligned, cv2.COLOR_BGR2GRAY)
                sigma = estimate_noise_sigma(gray, mask=(region_orig < 0.5).astype(np.float32))
                sigma = self._ema(track_id, "sigma", sigma, cfg.temporal_alpha_slow)
                # Grain is regenerated every frame on purpose: only its sigma is
                # smoothed. Frozen grain reads as a dirty lens.
                return add_grain(out, sigma, mask,
                                 cfg.grain_match * (1.0 - frac), self._rng)
            out = self._guard("grain", _grain, out)

        return out

    # ----------------------------------------------------------------- entry

    def composite(self, frame, aligned_swap, m_swap, kps,
                  track_id: int = 0, native_px: float = None,
                  restore: bool = True) -> np.ndarray:
        """Composite one swapped face onto `frame`. Returns the updated frame."""
        size = self.config.restore_size
        m_ffhq = alignment_matrix(kps, size)
        if m_ffhq is None:
            self._log_once("degenerate landmarks; face skipped")
            return frame

        try:
            orig_aligned = cv2.warpAffine(frame, m_ffhq, (size, size),
                                          borderMode=cv2.BORDER_REPLICATE)
            base = self._place_swap(aligned_swap, m_swap, m_ffhq, orig_aligned, size)
        except Exception as e:
            self._log_once(f"alignment failed ({e}); face skipped")
            return frame

        if restore and getattr(self.restorer, "available", False):
            base = self._guard("restore", lambda: self.restorer.enhance(base), base)
            if base.shape[:2] != (size, size):
                base = cv2.resize(base, (size, size), interpolation=cv2.INTER_LINEAR)

        mask, region_orig, skin = self._guard(
            "mask", lambda: self._build_mask(base, orig_aligned),
            (box_mask(size, size), np.ones((size, size), np.float32),
             np.ones((size, size), np.float32)),
        )

        out = self._harmonize(base, orig_aligned, mask, region_orig, skin,
                              track_id, native_px)
        mask = self._ema(track_id, "mask", mask, self.config.temporal_alpha)
        self._touch(track_id)

        return self._paste(frame, out, mask, m_ffhq, native_px)

    def _paste(self, frame, crop, mask, m_ffhq, native_px):
        h, w = frame.shape[:2]
        size = crop.shape[0]
        im = cv2.invertAffineTransform(m_ffhq)

        # Pasting a 512 crop into a 90px face aliases badly; pre-shrink with
        # INTER_AREA, which warpAffine cannot do, and adjust the matrix to suit.
        if native_px and native_px < size * 0.5:
            f = max(0.25, float(native_px) / size)
            d = max(8, int(size * f))
            crop = cv2.resize(crop, (d, d), interpolation=cv2.INTER_AREA)
            mask = cv2.resize(mask, (d, d), interpolation=cv2.INTER_AREA)
            im = scale_affine(im, d / float(size))

        back = cv2.warpAffine(crop, im, (w, h), borderMode=cv2.BORDER_REPLICATE)
        m_back = cv2.warpAffine(mask, im, (w, h))
        m_back = np.clip(m_back * self.config.blend, 0.0, 1.0)[..., None]

        out = frame.astype(np.float32) * (1.0 - m_back) + back.astype(np.float32) * m_back
        return out.astype(np.uint8)
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py composite`
Expected: FAIL with `AttributeError: ... '_ema'` — the temporal helpers arrive in Task 13. This is expected; do not fix it here.

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add harmonize and paste-over-original stages"
```

---

## Task 13: Temporal state

**Files:**
- Modify: `the app/face_compositor.py`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py temporal`
Expected: 3 FAILs with `AttributeError: ... '_ema'`

- [ ] **Step 3: Implement**

Append to the `FaceCompositor` class in `the app/face_compositor.py`:

```python
    # -------------------------------------------------------------- temporal

    def _touch(self, track_id: int):
        self._tracks.setdefault(track_id, {})["_seen"] = self._frame_no

    def _ema(self, track_id: int, key: str, value, alpha: float):
        """Exponentially smooth `value` per track. Passthrough when temporal
        is off. Works for both scalars and same-shaped arrays."""
        if not self.config.temporal:
            return value

        state = self._tracks.setdefault(track_id, {})
        state["_seen"] = self._frame_no
        prev = state.get(key)

        if prev is None or np.shape(prev) != np.shape(value):
            state[key] = value
            return value

        smoothed = alpha * value + (1.0 - alpha) * prev
        state[key] = smoothed
        return smoothed
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py temporal`
Expected: 3 `[PASS]` lines, `3/3 passed`

Run: `venv\Scripts\python.exe test_compositor.py composite`
Expected: 2 `[PASS]` lines — Task 12's tests now pass too

- [ ] **Step 5: Run the whole suite**

Run: `venv\Scripts\python.exe test_compositor.py`
Expected: every test passes; the trailing line reads `N/N passed`

- [ ] **Step 6: Commit**

```bash
git add "the app/test_compositor.py" "the app/face_compositor.py" && git commit -m "feat: add per-track temporal smoothing to the compositor"
```

---

## Task 14: Stable track ids from _smooth

`_smooth` currently discards which track each face matched, so the compositor has nothing to key temporal state on. It also early-returns when `smooth_landmarks` is off, which would leave tracking dead. Both are fixed here.

**Files:**
- Modify: `the app/reface_engine_v3.py:251-284`
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py smooth`
Expected: 2 FAILs — `_smooth` returns a list, not a tuple, so unpacking raises `ValueError` or `TypeError`

- [ ] **Step 3: Implement**

In `the app/reface_engine_v3.py`, replace `_reset_tracks` and `_smooth` (currently lines 251-284) with:

```python
    def _reset_tracks(self):
        self._tracks = []
        self._track_ids = []
        self._next_track_id = 0

    def _new_track_id(self) -> int:
        self._next_track_id += 1
        return self._next_track_id

    def _smooth(self, faces):
        """Match faces to previous tracks by centroid, EMA-smooth their kps in
        place, and return (faces, track_ids).

        The ids let the compositor keep per-face temporal state. Tracking runs
        even when smooth_landmarks is off, because the compositor still needs
        stable ids for its gain/grain/mask smoothing.
        """
        if not faces:
            self._tracks, self._track_ids = [], []
            return faces, []

        a = self.smooth_alpha
        used = [False] * len(self._tracks)
        new_tracks, new_ids = [], []

        for f in faces:
            if f.kps is None:
                new_tracks.append(None)
                new_ids.append(self._new_track_id())
                continue

            c = np.asarray(f.kps, np.float32).mean(0)
            best, best_d = -1, 1e9
            for i, t in enumerate(self._tracks):
                if used[i] or t is None:
                    continue
                d = np.linalg.norm(t.mean(0) - c)
                if d < best_d:
                    best, best_d = i, d

            # accept a match only if reasonably close (about inter-eye distance)
            thr = np.linalg.norm(np.asarray(f.kps[0]) - np.asarray(f.kps[1])) * 2.0 + 1e-3

            if best >= 0 and best_d < thr:
                used[best] = True
                sm = a * np.asarray(f.kps, np.float32) + (1 - a) * self._tracks[best]
                if self.smooth_landmarks:
                    f.kps = sm
                new_tracks.append(sm)
                new_ids.append(self._track_ids[best])
            else:
                new_tracks.append(np.asarray(f.kps, np.float32))
                new_ids.append(self._new_track_id())

        self._tracks, self._track_ids = new_tracks, new_ids
        return faces, new_ids
```

Also update `__init__` (currently line 117, `self._tracks: List[np.ndarray] = []`) to:

```python
        # per-video landmark tracks
        self._tracks: List[np.ndarray] = []
        self._track_ids: List[int] = []
        self._next_track_id = 0
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py smooth`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/reface_engine_v3.py" && git commit -m "feat: return stable track ids from landmark smoothing"
```

---

## Task 15: Route _process_face through the compositor

This is the change that fixes the destroyed hand, the seam and the halo: `paste_back=False` means insightface never paints its rectangle over the frame.

**Files:**
- Modify: `the app/reface_engine_v3.py:62-125` (`__init__`), `:159-204` (`_process_face`), `:206-247` (`_process_face_dfm`), `:317-318` and `:385-388` (call sites)

- [ ] **Step 1: Add the compositor to `__init__`**

In `the app/reface_engine_v3.py`, add to the imports near line 34:

```python
from face_compositor import CompositeConfig, FaceCompositor, config_from_preset
```

Add two parameters to `RefaceEngineV3.__init__`, after `dfm_path`:

```python
        realism_preset: str = "natural",          # "natural" | "maximum_detail" | "clean"
        realism_overrides: Optional[dict] = None,
```

Then, immediately before the final `print(...)` in `__init__` (currently line 119), insert:

```python
        # Compositing core: everything after the swap lives here, shared by the
        # inswapper and DFM paths and by any future higher-resolution swapper.
        overrides = dict(realism_overrides or {})
        overrides.setdefault("restore_size", self.restore_size)
        overrides.setdefault("mask_regions", self.mask_regions)
        overrides.setdefault("use_parser", self.use_parser)
        overrides.setdefault("use_occluder", self.use_occluder)
        overrides.setdefault("blend", self.blend)
        try:
            comp_config = config_from_preset(realism_preset, **overrides)
        except ValueError as e:
            print(f"[V3] {e}; falling back to 'natural'")
            comp_config = config_from_preset("natural", **overrides)
        self.compositor = FaceCompositor(self.restorer, self.masker, comp_config)
```

- [ ] **Step 2: Replace `_process_face`**

Replace the whole `_process_face` method (currently lines 159-204) with:

```python
    def _process_face(self, result, original, target_face, source, track_id: int = 0) -> np.ndarray:
        """Swap one face and composite it onto `result`.

        The swap is always computed from `original`, never from the running
        `result`, so multiple faces in one frame don't feed each other. Note
        paste_back=False: insightface's own paste uses a plain rectangle mask
        with no idea occluders exist, which is what used to paint over hands.
        """
        if self.dfm is not None:
            return self._process_face_dfm(result, original, target_face, track_id)

        try:
            aligned_swap, m_swap = self.swapper.get(original, target_face, source,
                                                    paste_back=False)
        except Exception as e:
            print(f"[V3] swap failed: {e}")
            return result

        return self.compositor.composite(
            result, aligned_swap, m_swap, target_face.kps,
            track_id=track_id, native_px=_face_height(target_face),
        )
```

Add this module-level helper just above the `RefaceEngineV3` class (after `_ffmpeg_exe`):

```python
def _face_height(face) -> Optional[float]:
    """Target face height in original frame pixels; drives detail transfer."""
    bbox = getattr(face, "bbox", None)
    if bbox is None or len(bbox) < 4:
        return None
    return float(abs(bbox[3] - bbox[1]))
```

- [ ] **Step 3: Replace `_process_face_dfm`**

Replace the whole `_process_face_dfm` method (currently lines 206-247) with:

```python
    def _process_face_dfm(self, result, original, target_face, track_id: int = 0) -> np.ndarray:
        """DeepFaceLab DFM swap, composited through the same realism core.

        DFM output is already HD, so restoration is skipped. The DFM's own
        celeb_mask is not used: the parser mask computed on the DFM output is
        both cleaner at the hairline and consistent with the inswapper path.
        """
        lmk = getattr(target_face, "landmark_2d_106", None)
        if lmk is None:
            lmk = target_face.kps
        try:
            aligned, m_swap = align_face(original, np.asarray(lmk, np.float32),
                                         output_size=self.dfm.resolution,
                                         face_type="whole_face")
        except Exception as e:
            print(f"[V3] DFM align failed: {e}")
            return result

        dres = self.dfm.swap_face(aligned)
        if not dres.success or dres.swapped_face is None:
            return result

        face = dres.swapped_face
        if face.shape[:2] != aligned.shape[:2]:
            face = cv2.resize(face, (aligned.shape[1], aligned.shape[0]))

        return self.compositor.composite(
            result, face, m_swap, target_face.kps,
            track_id=track_id, native_px=_face_height(target_face), restore=False,
        )
```

- [ ] **Step 4: Update the call sites**

In `reface_image_v3`, replace the loop (currently lines 317-318):

```python
            for tf in chosen:
                result = self._process_face(result, original, tf, source)
```

with:

```python
            self.compositor.reset()
            self.compositor.begin_frame()
            for i, tf in enumerate(chosen):
                result = self._process_face(result, original, tf, source, track_id=i)
```

In `reface_video_v3`, replace the detection and loop block (currently lines 379-389):

```python
                faces = self._smooth(self.app.get(frame))
                if faces:
                    if target_face_indices is not None:
                        chosen = [faces[i] for i in target_face_indices if 0 <= i < len(faces)]
                    else:
                        chosen = faces
                    result = frame
                    for tf in chosen:
                        result = self._process_face(result, original, tf, source)
                        swaps += 1
                    frame = result
```

with:

```python
                faces, track_ids = self._smooth(self.app.get(frame))
                self.compositor.begin_frame()
                if faces:
                    if target_face_indices is not None:
                        picked = [(faces[i], track_ids[i]) for i in target_face_indices
                                  if 0 <= i < len(faces)]
                    else:
                        picked = list(zip(faces, track_ids))
                    result = frame
                    for tf, tid in picked:
                        result = self._process_face(result, original, tf, source, track_id=tid)
                        swaps += 1
                    frame = result
```

And enable temporal smoothing for video: immediately after `self._reset_tracks()` (currently line 368), add:

```python
            self.compositor.reset()
            self.compositor.config.temporal = True
```

- [ ] **Step 5: Remove the code the compositor replaced**

Three things in `reface_engine_v3.py` are now dead, and leaving them invites future
edits to the wrong copy:

- the `_alignment_matrix` method (currently lines 129-136) — superseded by
  `face_compositor.alignment_matrix`
- the `_color_match` method (currently lines 138-157) — superseded by
  `face_harmonize.lab_color_match`
- `box_mask` in the `face_masking` import (line 34) — no longer referenced

Delete both methods and drop `box_mask` from that import, leaving it as:

```python
from face_masking import FaceMasker, DEFAULT_REGIONS
```

Keep the module-level `FFHQ_512` constant: `test_compositor.py` imports it, and it
documents the template the engine aligns to.

- [ ] **Step 6: Verify the engine still constructs**

Run: `venv\Scripts\python.exe reface_engine_v3.py`
Expected: `✅ V3 init OK (version 3.0)`, `swapper: loaded`, `restorer available: True`, `parser/occluder: True/True`

- [ ] **Step 7: Run the full test suite**

Run: `venv\Scripts\python.exe test_compositor.py`
Expected: every test still passes

- [ ] **Step 8: Commit**

```bash
git add "the app/reface_engine_v3.py" && git commit -m "fix: composite over the original frame so occluders survive"
```

---

## Task 16: Keep the audio

**Files:**
- Modify: `the app/reface_engine_v3.py` (`reface_video_v3`, writer helpers)
- Test: `the app/test_compositor.py`

- [ ] **Step 1: Write the failing test**

Append to `the app/test_compositor.py`, above `def main`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `venv\Scripts\python.exe test_compositor.py audio`
Expected: 2 FAILs with `ImportError: cannot import name 'build_mux_command'`

- [ ] **Step 3: Implement**

Add to `the app/reface_engine_v3.py`, next to `_ffmpeg_exe`:

```python
def build_mux_command(video_path, source_path, out_path,
                      start_time: float = 0.0, end_time: Optional[float] = None) -> list:
    """ffmpeg args to copy the source's audio onto the rendered video.

    -ss/-to sit before the source input so they trim that input, matching the
    clip range the video was rendered from.
    """
    cmd = [_ffmpeg_exe(), "-y", "-loglevel", "error", "-i", str(video_path)]
    if start_time and start_time > 0:
        cmd += ["-ss", str(start_time)]
    if end_time and end_time > 0:
        cmd += ["-to", str(end_time)]
    cmd += ["-i", str(source_path),
            "-c", "copy", "-map", "0:v:0", "-map", "1:a:0",
            "-shortest", str(out_path)]
    return cmd
```

Add this method to `RefaceEngineV3`, after `_close_writer`:

```python
    def _mux_audio(self, video_path: Path, source_path: str,
                   start_time: float = 0.0, end_time: Optional[float] = None) -> bool:
        """Copy the source's audio onto the rendered video, in place.

        Silently does nothing when the source has no audio stream - ffmpeg
        fails the mapping and we keep the silent render.
        """
        tmp = video_path.with_suffix(".muxed.mp4")
        try:
            proc = subprocess.run(
                build_mux_command(video_path, source_path, tmp, start_time, end_time),
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            if proc.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
                tmp.replace(video_path)
                return True
        except Exception as e:
            print(f"[V3] audio mux failed: {e}")
        try:
            tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return False
```

In `reface_video_v3`, immediately after `self._close_writer(writer, proc)` (currently line 402), add:

```python
            if self._mux_audio(out_path, target_video_path, start_time, end_time):
                print("[INFO] V3 video: original audio preserved")
```

- [ ] **Step 4: Run to verify it passes**

Run: `venv\Scripts\python.exe test_compositor.py audio`
Expected: 2 `[PASS]` lines, `2/2 passed`

- [ ] **Step 5: Commit**

```bash
git add "the app/test_compositor.py" "the app/reface_engine_v3.py" && git commit -m "fix: keep the original audio track in refaced video"
```

---

## Task 17: Thread realism params through job_manager

**Files:**
- Modify: `the app/job_manager.py:326-334`

- [ ] **Step 1: Read the current construction site**

Open `the app/job_manager.py` and confirm the block at line 326 still reads:

```python
            from reface_engine_v3 import RefaceEngineV3
            engine = RefaceEngineV3(
                restorer=params.get('restorer', 'codeformer'),
                restorer_weight=params.get('restorer_weight', 0.5),
```

- [ ] **Step 2: Add the realism params**

Extend that constructor call so it reads:

```python
            from reface_engine_v3 import RefaceEngineV3
            engine = RefaceEngineV3(
                restorer=params.get('restorer', 'codeformer'),
                restorer_weight=params.get('restorer_weight', 0.5),
                realism_preset=params.get('realism_preset', 'natural'),
                realism_overrides=params.get('realism_overrides') or None,
```

Leave the remaining keyword arguments in that call exactly as they are.

- [ ] **Step 3: Verify the module still imports**

Run: `venv\Scripts\python.exe -c "import job_manager; print('job_manager OK')"`
Expected: `job_manager OK`

- [ ] **Step 4: Commit**

```bash
git add "the app/job_manager.py" && git commit -m "feat: pass realism settings through the job queue"
```

---

## Task 18: Realism controls in the dashboard

**Files:**
- Modify: `the app/dashboard.py:3184-3209` (V3 options block), `:3325-3345` (job params and engine construction)

- [ ] **Step 1: Add the Realism expander**

In `the app/dashboard.py`, inside `if use_v3:` and immediately after the `st.caption("V3 runs entirely on GPU via onnxruntime. ...")` line (currently line 3207), insert:

```python
                with st.expander("🎬 Realism", expanded=True):
                    v3_preset = st.selectbox(
                        "Preset",
                        ["natural", "maximum_detail", "clean"],
                        index=0,
                        format_func=lambda x: {
                            "natural": "Natural (recommended)",
                            "maximum_detail": "Maximum detail (stills / close-ups)",
                            "clean": "Clean — legacy V3 (for A/B comparison)",
                        }[x],
                        help="Natural matches the frame's lighting, focus and grain, and keeps "
                             "the target's real teeth. Clean reproduces the old behaviour so you "
                             "can compare.",
                    )
                    v3_realism_overrides = {}
                    if st.checkbox("Fine-tune realism", value=False):
                        rc1, rc2 = st.columns(2)
                        with rc1:
                            v3_realism_overrides["detail_transfer"] = st.slider(
                                "Skin detail transfer", 0.0, 1.0, 0.4, 0.05,
                                help="Borrows real pores from the original frame. Scales "
                                     "automatically with how large the face is.",
                            )
                            v3_realism_overrides["grain_match"] = st.slider(
                                "Grain match", 0.0, 1.0, 1.0, 0.05,
                                help="Adds noise matched to the surrounding frame.",
                            )
                        with rc2:
                            v3_realism_overrides["relight"] = st.slider(
                                "Relight strength", 0.0, 1.0, 1.0, 0.05,
                                help="Matches the scene's light direction and white balance.",
                            )
                            v3_realism_overrides["preserve_mouth_interior"] = st.checkbox(
                                "Keep the target's real teeth", value=True,
                                help="Swaps the lips but not the inner mouth. Stops open "
                                     "mouths turning to mush.",
                            )
                            v3_realism_overrides["focus_match"] = st.checkbox(
                                "Focus match", value=True,
                                help="Softens the face to match a soft or blurred frame.",
                            )
```

- [ ] **Step 2: Add the fallback for the Legacy V2 branch**

Change the `else:` fallback line (currently line 3209) from:

```python
                v3_restorer, v3_weight, v3_use_parser, v3_use_occluder = "codeformer", 0.7, True, True
```

to:

```python
                v3_restorer, v3_weight, v3_use_parser, v3_use_occluder = "codeformer", 0.7, True, True
                v3_preset, v3_realism_overrides = "natural", {}
```

- [ ] **Step 3: Pass them to the background job**

In the `if use_v3:` block that builds job params (currently lines 3325-3330), after `params['use_occluder'] = v3_use_occluder`, add:

```python
                                params['realism_preset'] = v3_preset
                                params['realism_overrides'] = v3_realism_overrides
```

- [ ] **Step 4: Pass them to the foreground engine**

In the foreground construction (currently lines 3340-3345), change:

```python
                                engine = RefaceEngineV3(
                                    restorer=v3_restorer,
                                    restorer_weight=v3_weight,
                                    use_parser=v3_use_parser,
                                    use_occluder=v3_use_occluder,
                                )
```

to:

```python
                                engine = RefaceEngineV3(
                                    restorer=v3_restorer,
                                    restorer_weight=v3_weight,
                                    use_parser=v3_use_parser,
                                    use_occluder=v3_use_occluder,
                                    realism_preset=v3_preset,
                                    realism_overrides=v3_realism_overrides,
                                )
```

- [ ] **Step 5: Verify the dashboard parses**

Run: `venv\Scripts\python.exe -c "import ast; ast.parse(open('dashboard.py', encoding='utf-8').read()); print('dashboard.py parses')"`
Expected: `dashboard.py parses`

- [ ] **Step 6: Commit**

```bash
git add "the app/dashboard.py" && git commit -m "feat: add realism preset controls to the V3 reface page"
```

---

## Task 19: Visual A/B script

The unit tests prove the mechanics. This is what proves the output is better.

**Files:**
- Create: `the app/compare_v3.py`

- [ ] **Step 1: Write the script**

Create `the app/compare_v3.py`:

```python
"""
Antigravity Local - V3 realism A/B

Renders one target image through the 'clean' preset (pre-rebuild behaviour) and
the 'natural' preset, and writes them side by side for visual comparison.

    venv\\Scripts\\python.exe compare_v3.py <target_image> <faceset_name>
    venv\\Scripts\\python.exe compare_v3.py <target_image> <faceset_name> maximum_detail

Output: reface_output/compare_<timestamp>.png
"""

import sys
from datetime import datetime
from pathlib import Path

import cv2
import numpy as np

from reface_engine_v3 import RefaceEngineV3


def _label(img, text):
    out = img.copy()
    cv2.rectangle(out, (0, 0), (out.shape[1], 48), (0, 0, 0), -1)
    cv2.putText(out, text, (16, 33), cv2.FONT_HERSHEY_SIMPLEX, 1.0,
                (255, 255, 255), 2, cv2.LINE_AA)
    return out


def render(target_path: str, faceset_name: str, preset: str):
    engine = RefaceEngineV3(realism_preset=preset)
    faceset = engine.load_faceset_by_name(faceset_name)
    if not faceset:
        print(f"[FAIL] faceset '{faceset_name}' not found")
        return None
    result = engine.reface_image_v3(target_path, faceset)
    if not result.success:
        print(f"[FAIL] {preset}: {result.message}")
        return None
    print(f"[OK]   {preset}: {result.output_path}")
    return cv2.imread(result.output_path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1

    target, faceset_name = argv[0], argv[1]
    challenger = argv[2] if len(argv) > 2 else "natural"

    if not Path(target).exists():
        print(f"[FAIL] target not found: {target}")
        return 1

    before = render(target, faceset_name, "clean")
    after = render(target, faceset_name, challenger)
    if before is None or after is None:
        return 1

    if before.shape != after.shape:
        after = cv2.resize(after, (before.shape[1], before.shape[0]))

    pair = np.hstack([_label(before, "clean (legacy V3)"),
                      _label(after, challenger)])

    out_dir = Path(__file__).parent / "reface_output"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"compare_{datetime.now():%Y%m%d_%H%M%S}.png"
    cv2.imwrite(str(out_path), pair)
    print(f"\nWrote {out_path}")
    print("Zoom in on: the jaw and hairline edge, skin texture, and any hand or open mouth.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 2: Run it on a real target**

Ask the user for a target image and a saved faceset name, then have them run:

Run: `venv\Scripts\python.exe compare_v3.py "path\to\target.jpg" "your_faceset_name"`
Expected: two `[OK]` lines and a `Wrote ...\reface_output\compare_<timestamp>.png` line

Ask them to open the PNG and check the jaw/hairline edge, the skin texture, and — if the target has one — a hand over the face or an open mouth.

- [ ] **Step 3: Commit**

```bash
git add "the app/compare_v3.py" && git commit -m "test: add legacy-vs-realism A/B comparison script"
```

---

## Task 20: Documentation

**Files:**
- Modify: `the app/CLAUDE.md:32-50` (core modules table)

- [ ] **Step 1: Add the new modules to the table**

In `the app/CLAUDE.md`, in the "Core Modules" table, insert these two rows immediately after the `reface_engine_v3.py` row:

```markdown
| `face_compositor.py` | **Compositing core** — align → restore → mask → harmonize → paste, plus per-track temporal state. Takes the swapper's affine matrix as a parameter, so inswapper, DFM and future swappers share one realism path |
| `face_harmonize.py` | Pure image math used by the compositor: noise estimation, lighting gain, focus matching, skin detail transfer, grain synthesis. No models, no state — unit-testable on CPU |
```

- [ ] **Step 2: Note the test script**

In the same file, under the commands section where the other test scripts are listed, add:

```markdown
python test_compositor.py           # compositing core, no GPU or models needed
python test_compositor.py grain     # or filter by name
python compare_v3.py <img> <faceset>  # legacy vs realism A/B
```

- [ ] **Step 3: Commit**

```bash
git add "the app/CLAUDE.md" && git commit -m "docs: document the compositing core modules"
```

---

## Final verification

- [ ] **Full unit suite**

Run: `venv\Scripts\python.exe test_compositor.py`
Expected: `N/N passed` with no `[FAIL]` lines

- [ ] **Engine smoke test**

Run: `venv\Scripts\python.exe test_v3_smoke.py`
Expected: passes as it did before this work — this is the regression check on the real ONNX path

- [ ] **Image A/B on real footage**

Run: `venv\Scripts\python.exe compare_v3.py "path\to\a_photo_with_a_hand_near_the_face.jpg" "your_faceset"`
Expected: in the output PNG, the hand is intact on the `natural` side and painted over on the `clean` side

- [ ] **Video end to end**

Through the dashboard: Reface V2 page → HD V3 → Realism preset "natural" → a short clip with an occlusion or an open mouth.
Expected: output plays with audio, the hand and teeth survive, and there is no shimmer in skin texture between frames.

- [ ] **Spec success criteria**

Confirm against `docs/superpowers/specs/2026-08-16-reface-realism-design.md`:
- pixels inside the occluder region are unchanged
- inner-mouth pixels are unchanged with the default preset
- no pixel outside the parser region differs from the input
- the refaced video has an audio stream when the source had one
