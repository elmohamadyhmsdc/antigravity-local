"""
Antigravity Local - face compositor

Owns everything after the swap: align -> restore -> mask -> harmonize -> paste,
plus the per-track temporal state that keeps video stable.

The swapper hands over its own affine matrix, so inswapper, DeepFaceLab DFM
models and any future higher-resolution swapper all share one realism core
instead of each carrying a copy of it.
"""

from dataclasses import dataclass
from typing import List, Optional

import cv2
import numpy as np

from face_masking import (DEFAULT_REGIONS, box_mask, feather_mask,
                          harden_occlusion, region_from_seg)
from face_harmonize import (add_grain, apply_gain, choose_focus_sigma,
                            compute_gain, estimate_noise_sigma,
                            lab_color_match, transfer_detail)


def _as_2x3(m) -> Optional[np.ndarray]:
    """Accept a 2x3 or 3x3 affine; return float32 2x3 or None."""
    if m is None:
        return None
    a = np.asarray(m, np.float64)
    if a.shape == (3, 3):
        a = a[:2]
    if a.shape != (2, 3) or not np.isfinite(a).all():
        return None
    return a.astype(np.float32)


def _to_h(m: np.ndarray) -> np.ndarray:
    """2x3 affine -> 3x3 homogeneous."""
    a = _as_2x3(m)
    if a is None:
        raise ValueError(f"expected a 2x3 affine, got shape {np.shape(m)}")
    return np.vstack([np.asarray(a, np.float64), [0.0, 0.0, 1.0]])


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
    # RANSAC with a loose threshold matches FaceFusion; LMEDS with only 5
    # points can treat real landmarks as outliers and return a bad matrix.
    m, _ = cv2.estimateAffinePartial2D(
        src, dst, method=cv2.RANSAC, ransacReprojThreshold=100.0,
    )
    if m is None or np.asarray(m).shape != (2, 3):
        return None
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
            print(f"[COMPOSITE] {msg}", flush=True)

    def _guard(self, name: str, fn, fallback):
        try:
            return fn()
        except Exception as e:
            self._log_once(f"{name} failed ({e}); skipping that step")
            return fallback

    # ------------------------------------------------------------- alignment

    def _place_via_frame(self, frame, aligned_swap, m_swap, m_ffhq, orig_aligned, size):
        """Paste the swap crop the same way insightface does (invert M onto
        the frame), then recrop into FFHQ space.

        compose_affine(M_ffhq, M_swap) is the one-resample ideal, but mixing
        insightface's skimage matrix with OpenCV's FFHQ matrix sent the swapped
        pixels outside the paste mask, so the original face was written back.
        """
        m_swap = _as_2x3(m_swap)
        if m_swap is None:
            raise ValueError("unusable swap affine")
        h, w = frame.shape[:2]
        im = cv2.invertAffineTransform(m_swap)
        canvas = cv2.warpAffine(aligned_swap, im, (w, h), borderValue=0)
        ones = np.ones(aligned_swap.shape[:2], np.float32)
        cov_f = cv2.warpAffine(ones, im, (w, h), borderValue=0.0)
        warped = cv2.warpAffine(canvas, m_ffhq, (size, size),
                                borderMode=cv2.BORDER_REPLICATE)
        cov = cv2.warpAffine(cov_f, m_ffhq, (size, size), borderValue=0.0)
        cov = np.clip(cv2.GaussianBlur(cov, (0, 0), 2.0), 0.0, 1.0)[..., None]
        blended = (warped.astype(np.float32) * cov
                   + orig_aligned.astype(np.float32) * (1.0 - cov))
        return blended.astype(np.uint8), float(cov.mean())

    def _place_swap(self, aligned_swap, m_swap, m_ffhq, orig_aligned, size, frame=None):
        """Warp the swapper's crop into FFHQ space, filling anything it doesn't
        cover (forehead, chin edges) from the original."""
        if frame is not None:
            try:
                blended, cov_mean = self._place_via_frame(
                    frame, aligned_swap, m_swap, m_ffhq, orig_aligned, size,
                )
                if cov_mean >= 0.02:
                    return blended
                self._log_once(
                    f"frame-paste coverage {cov_mean:.3f}; trying composed affine"
                )
            except Exception as e:
                self._log_once(f"frame-paste failed ({e}); trying composed affine")

        t = compose_affine(m_ffhq, m_swap)
        warped = cv2.warpAffine(aligned_swap, t, (size, size),
                                borderMode=cv2.BORDER_REPLICATE)
        ones = np.ones(aligned_swap.shape[:2], np.float32)
        cov = cv2.warpAffine(ones, t, (size, size), borderValue=0.0)
        cov = np.clip(cv2.GaussianBlur(cov, (0, 0), 2.0), 0.0, 1.0)[..., None]
        if float(cov.mean()) < 0.02:
            self._log_once(
                f"swap coverage {float(cov.mean()):.3f}; fill is mostly the original face"
            )
        blended = warped.astype(np.float32) * cov + orig_aligned.astype(np.float32) * (1.0 - cov)
        return blended.astype(np.uint8)

    # ------------------------------------------------------------------ mask

    def _regions(self) -> List[str]:
        regions = list(self.config.mask_regions or DEFAULT_REGIONS)
        if self.config.preserve_mouth_interior:
            # Class 11 is the inner mouth. A 128px swap carries about 30 real
            # pixels of teeth, which the restorer then turns into a smear -
            # keeping the target's own teeth is both cheaper and more honest.
            regions = [r for r in regions if r != "mouth"]
        return regions

    @staticmethod
    def _mask_area(mask) -> float:
        return float((np.asarray(mask) > 0.01).mean())

    def _build_mask(self, restored, orig_aligned):
        """Return (paste_mask, region_orig, skin_orig), all float32 [0,1]."""
        h, w = restored.shape[:2]
        regions = self._regions()
        floor = self.config.mask_area_floor

        seg_orig = self.masker.segment(orig_aligned) if self.config.use_parser else None
        seg_res = self.masker.segment(restored) if self.config.use_parser else None

        if seg_orig is None or seg_res is None:
            region = box_mask(h, w)
            region_orig = region
            skin = region
        else:
            region_orig = region_from_seg(seg_orig, regions)
            region_res = region_from_seg(seg_res, regions)
            # Prefer the intersection so we never paint where the real frame
            # was not face. If that collapses (parser miss on either crop,
            # class-map mismatch after restore), fall back rather than
            # returning a zero mask — with paste_back=False a zero mask
            # writes the original image out as the "result".
            region = region_res * region_orig
            if self._mask_area(region) < floor:
                if self._mask_area(region_orig) >= floor:
                    self._log_once("parser intersection empty; using original-crop region")
                    region = region_orig
                elif self._mask_area(region_res) >= floor:
                    self._log_once("parser intersection empty; using restored-crop region")
                    region = region_res
                else:
                    self._log_once("parser region empty; falling back to box mask")
                    region = box_mask(h, w)
                    region_orig = region
            skin = region_from_seg(seg_orig, ["skin"])
            if self._mask_area(skin) < floor:
                skin = region

        mask = feather_mask(region, self.config.mask_erode, self.config.mask_feather)

        if self.config.use_occluder and self.masker.occluder is not None:
            occ = self.masker.occlusion_mask(orig_aligned)
            if occ is not None:
                hardened = harden_occlusion(occ)
                masked = mask * hardened
                if self._mask_area(masked) < floor:
                    self._log_once("occluder wiped the paste mask; ignoring occluder")
                else:
                    mask = masked

        if self._mask_area(mask) < floor:
            self._log_once("paste mask collapsed; using box fallback")
            mask = box_mask(h, w)
            region_orig = np.maximum(region_orig, mask)
            skin = np.maximum(skin, mask)

        return np.clip(mask, 0.0, 1.0), region_orig, skin

    # -------------------------------------------------------------- harmonize

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
            base = self._place_swap(aligned_swap, m_swap, m_ffhq, orig_aligned,
                                    size, frame=frame)
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
