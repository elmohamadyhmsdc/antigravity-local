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
