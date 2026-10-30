"""
Antigravity Local - Reface Engine V3 (HD)

A clean, facefusion-style pipeline that runs entirely on onnxruntime-gpu:

    detect -> swap (inswapper, averaged identity) -> align face to 512
           -> restore (CodeFormer/GFPGAN/GPEN) -> parser+occluder mask
           -> color-match -> feathered paste back

Why this is sharper/more stable than V1/V2:
  * Identity comes from ONE averaged embedding (identity.py), not a per-target
    source pick -> stronger likeness, zero source flicker in video.
  * The 128px swap is regenerated at 512 by an ONNX restorer on the face crop
    only (not the whole frame) -> natively sharp, background untouched.
  * The paste mask is a real face-parser region intersected with an occluder
    mask -> clean hairline/jaw, and hands/glasses are preserved.
  * Video uses the fixed identity + EMA-smoothed landmarks (no frame averaging)
    -> no ghosting, no jitter; frames are piped straight to x264.
"""

import os
import sys
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout
from fractions import Fraction
from pathlib import Path
from typing import List, Optional
from datetime import datetime

import cv2
import numpy as np

from reface_engine import RefaceEngine, RefaceResult, Faceset, FaceData  # noqa: F401
from identity import AveragedSource, build_source_from_faceset, select_identity_faces
from face_restore import FaceRestorer, resolve_restorer_name
from face_masking import FaceMasker, DEFAULT_REGIONS
from face_compositor import CompositeConfig, FaceCompositor, config_from_preset, alignment_matrix
from reface_tracking import FaceTracker
from reface_selection import FaceSelector, match_reference, SELECT_MIN_SIMILARITY, SELECT_RECHECK_FRAMES
from reface_video_detection import VideoFaceRecovery, detect_faces as detect_video_faces
from reface_video_io import validate_video
from face_swappers import SWAPPERS, available_swappers, load_swapper

# Order tried by swapper="auto": the first one that is downloaded wins.
# Set from eval_reface.py results (identity, then sharpness, then stability).
# 2026-10-14, 4 people x 2 clips (160 frames each), independent glintr100 score:
# hyperswap_1b 0.430 / inswapper 0.421 / hyperswap_1c 0.411 identity, 369 vs
# 403 ms/frame, equal flicker. 1b won 5 of 8 person/clip pairs - a small,
# person-dependent edge, so inswapper stays as the fallback.
SWAPPER_PREFERENCE = ["hyperswap_1b_256", "inswapper_128"]
# The restorer the UI preselects; also from eval_reface.py. 2026-10-14 on
# hyperswap_1b: identity none 0.517 / gpen_1024 0.514 / gpen_512 0.508 /
# restoreformer++ 0.490 / gfpgan 0.485 / codeformer 0.430; sharpness vs the
# source gpen_512 0.879 (best), none 0.824; 312 ms/frame vs codeformer 420.
# CodeFormer at w=0.5 pulls faces toward a generic face - the lowest identity.
DEFAULT_RESTORER = "gpen_bfr_512"
# Identity strength the UI preselects (0 = off); also from eval_reface.py.
# 2026-10-14 (hyperswap_1b + gpen_512): boost 0 / 0.5 / 1.0 -> identity
# 0.508 / 0.516 / 0.515, leak 0.355 / 0.293 / 0.244, sharpness 0.879 / 0.879 /
# 0.875. 0.5 raised identity in all 8 person/clip pairs; 1.0 starts to alter
# the face shape by eye, so it stays a slider option.
DEFAULT_IDENTITY_BOOST = 0.5


def resolve_swapper_name(requested: str = "auto") -> str:
    have = available_swappers()
    if requested and requested != "auto":
        return requested if requested in have else "inswapper_128"
    return next((n for n in SWAPPER_PREFERENCE if n in have), "inswapper_128")

try:
    from dfm_engine import DFMEngine, align_face
    _DFM_OK = True
except Exception:
    _DFM_OK = False

# FFHQ-512 5-point template (identical to GFPGAN/CodeFormer FaceRestoreHelper)
FFHQ_512 = np.array(
    [[192.98138, 239.94708],
     [318.90277, 240.19360],
     [256.63416, 314.01935],
     [201.26117, 371.41043],
     [313.08905, 371.15118]],
    dtype=np.float32,
)

from ffmpeg_utils import _ffmpeg_exe, build_mux_command


def unpack_swap_result(got):
    """Normalize INSwapper.get output to (crop_or_frame, affine_or_None).

    paste_back=False returns (bgr_fake, M). Some insightface builds ignore the
    flag and return a full-frame paste. Unpacking that as a 2-tuple throws,
    and the except path used to return the original image as a 'successful' swap.
    """
    if isinstance(got, (tuple, list)):
        if len(got) >= 2:
            return got[0], got[1]
        return (got[0] if got else None), None
    return got, None


def _mean_abs_diff(a, b) -> float:
    return float(np.mean(np.abs(a.astype(np.float32) - b.astype(np.float32))))


def _face_height(face) -> Optional[float]:
    """Target face height in original frame pixels; drives detail transfer."""
    bbox = getattr(face, "bbox", None)
    if bbox is None or len(bbox) < 4:
        return None
    return float(abs(bbox[3] - bbox[1]))


# Mean absolute difference (0-255) inside a face box below which the paste is
# treated as a no-op. A real swap moves the box by several grey levels; a
# collapsed mask leaves it at exactly zero.
UNCHANGED_FACE_MAD = 0.5


def face_changed(after, before, face, threshold: float = UNCHANGED_FACE_MAD) -> bool:
    """Did the pixels inside this face's box change?

    Measured inside the box, not over the frame: a 300px face is ~4% of a
    1080p frame, so a whole-frame mean stays under any sane threshold even
    for a complete swap (that is how the HD composite used to be thrown away
    for nearly every video face).
    """
    bbox = getattr(face, "bbox", None)
    if bbox is None or len(bbox) < 4:
        return _mean_abs_diff(after, before) >= threshold
    h, w = before.shape[:2]
    x0, y0 = max(0, int(bbox[0])), max(0, int(bbox[1]))
    x1, y1 = min(w, int(np.ceil(bbox[2]))), min(h, int(np.ceil(bbox[3])))
    if x1 <= x0 or y1 <= y0:
        return False
    return _mean_abs_diff(after[y0:y1, x0:x1], before[y0:y1, x0:x1]) >= threshold


def video_fps(cap) -> float:
    """The capture's frame rate as a float. int() turned 29.97 into 29, which
    slowed the render ~3% against its own audio."""
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0)
    return fps if np.isfinite(fps) and 1.0 <= fps <= 240.0 else 25.0


def rate_arg(fps: float) -> str:
    """ffmpeg frame-rate argument: 29.97 -> '30000/1001', 25 -> '25/1'."""
    r = Fraction(float(fps)).limit_denominator(1001)
    return f"{r.numerator}/{r.denominator}"


# --- picking the faces the user ticked, by identity ----------------------------

class RefaceEngineV3(RefaceEngine):
    VERSION = "3.0"

    def __init__(
        self,
        output_dir: str = None,
        restorer: str = None,             # None -> DEFAULT_RESTORER; a face_restore name, "auto" or "none"
        restorer_weight: float = 0.5,     # CodeFormer fidelity (higher = closer to input, lower = sharper)
        use_parser: bool = True,
        use_occluder: bool = True,
        mask_regions: Optional[List[str]] = None,
        restore_size: int = 512,
        blend: float = 1.0,               # global paste strength
        smooth_landmarks: bool = True,    # video: EMA on landmarks
        smooth_alpha: float = 0.6,        # weight of current frame (1.0 = no smoothing)
        identity_boost: float = None,     # 0..1, None -> DEFAULT_IDENTITY_BOOST (see boosted_source)
        dfm_path: Optional[str] = None,   # DeepFaceLab .dfm -> "pro" per-person mode
        realism_preset: str = "natural",          # "natural" | "maximum_detail" | "clean"
        realism_overrides: Optional[dict] = None,
        swapper: str = "auto",                    # "auto" | a face_swappers.SWAPPERS name
        occluders: Optional[List[str]] = None,    # None -> face_masking.DEFAULT_OCCLUDERS
    ):
        super().__init__(output_dir=output_dir, enable_enhancement=False, upscale=1)

        # The base class always loads insightface's inswapper_128. A different
        # swapper replaces it (and frees it); both answer the same .get() call.
        self.swapper_name = "inswapper_128"
        wanted = resolve_swapper_name(swapper)
        if wanted != "inswapper_128":
            try:
                alt = load_swapper(wanted, self.providers)
            except Exception as e:
                print(f"[V3] swapper '{wanted}' failed to load ({e}); keeping inswapper_128")
                alt = None
            if alt is not None:
                self.swapper = alt
                self.swapper_name = wanted

        self.restore_size = int(restore_size)
        self.use_parser = use_parser
        self.use_occluder = use_occluder
        self.mask_regions = mask_regions or DEFAULT_REGIONS
        self.blend = float(blend)
        self.smooth_landmarks = smooth_landmarks
        self.smooth_alpha = float(smooth_alpha)
        self.identity_boost = float(np.clip(DEFAULT_IDENTITY_BOOST if identity_boost is None else identity_boost, 0.0, 1.0))

        # Face restorer (ONNX). "auto" picks any available; "none" disables.
        restorer = restorer or DEFAULT_RESTORER
        if restorer and restorer != "none":
            name = restorer if restorer != "auto" else (resolve_restorer_name() or "codeformer")
            self.restorer = FaceRestorer(model_name=name, providers=self.providers, weight=restorer_weight)
            # If the requested model file isn't present, fall back to any available
            # restorer instead of silently disabling HD restoration.
            if not self.restorer.available:
                alt = resolve_restorer_name()
                if alt and alt != name:
                    print(f"[V3] restorer '{name}' unavailable; falling back to '{alt}'")
                    self.restorer = FaceRestorer(model_name=alt, providers=self.providers, weight=restorer_weight)
        else:
            self.restorer = FaceRestorer(model_name="__disabled__")  # available=False

        # Masks (ONNX parser + occluder(s), with graceful fallback)
        self.masker = FaceMasker(providers=self.providers, occluders=occluders,
                                 load_parser=use_parser, load_occluder=use_occluder)

        # Optional DeepFaceLab DFM "pro" mode (per-person trained model)
        self.dfm = None
        if dfm_path and _DFM_OK:
            try:
                self.dfm = DFMEngine(dfm_path)
                if not self.dfm.is_loaded():
                    self.dfm = None
                else:
                    print(f"[INFO] V3 DFM mode active: {Path(dfm_path).name} ({self.dfm.resolution}px)")
            except Exception as e:
                print(f"[V3] DFM load failed: {e}")
                self.dfm = None

        # per-video landmark tracks
        self._tracks: List[np.ndarray] = []
        self._track_ids: List[int] = []
        self._next_track_id = 0

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

        print(
            f"[INFO] RefaceEngineV3 ready "
            f"(mode={'DFM' if self.dfm else self.swapper_name}, "
            f"restorer={'on' if self.restorer.available else 'off'}, "
            f"parser={'on' if self.masker.parser else 'off'}, "
            f"occluder={'on' if self.masker.occluder else 'off'})"
        )

    # ------------------------------------------------------------------ utils

    def _detect(self, img, embeddings: bool = False):
        """insightface's FaceAnalysis.get, running only the models this
        pipeline reads: boxes and 5-point landmarks (every swapper, DFM
        included, aligns from those), embeddings only when asked. Same boxes
        and landmarks as get() (det_10g is the same model); ~13 ms instead of
        ~55 ms on a 1080p frame, because recognition, gender/age and both
        landmark models are skipped.
        """
        from insightface.app.common import Face

        bboxes, kpss = self.app.det_model.detect(img, max_num=0, metric="default")
        models = self.app.models
        faces = []
        for i in range(bboxes.shape[0]):
            face = Face(bbox=bboxes[i, 0:4], kps=kpss[i] if kpss is not None else None,
                        det_score=bboxes[i, 4])
            if embeddings and "recognition" in models:
                models["recognition"].get(img, face)
            faces.append(face)
        return faces

    def _embed(self, img, face):
        """Identity embedding for one detected face, computed on demand."""
        rec = self.app.models.get("recognition")
        if rec is None:
            return None
        if getattr(face, "embedding", None) is None:
            rec.get(img, face)
        return face.normed_embedding

    def boosted_source(self, source, original, target_face):
        """The source identity pushed away from the target's own identity.

        The swappers blend some of the target's identity back in (eval_reface.py
        measures it as 'leak'). FaceFusion's face_swapper_weight counters that by
        extrapolating: source * (1 + c) - target * c, c up to 0.35. identity_boost
        1.0 is that maximum; 0 leaves the source untouched.
        """
        if self.identity_boost <= 0 or source is None:
            return source
        target = self._embed(original, target_face)
        if target is None:
            return source
        c = 0.35 * self.identity_boost
        return AveragedSource(np.asarray(source.normed_embedding, np.float32) * (1.0 + c)
                              - np.asarray(target, np.float32) * c)

    def _record_face(self, track_id, status, reason="", degraded=False):
        if not hasattr(self, "_frame_outcomes"):
            self._frame_outcomes = []
        self._frame_outcomes.append(dict(track_id=int(track_id), status=status, reason=reason, degraded=degraded))

    def _process_face(self, result, original, target_face, source, track_id=0):
        """Generate from original pixels; merge only through the protected compositor."""
        try:
            restore = self.dfm is None
            if not restore:
                aligned, matrix = align_face(original, np.asarray(target_face.kps, np.float32),
                                             output_size=self.dfm.resolution, face_type="whole_face")
                swapped = self.dfm.swap_face(aligned)
                if not swapped.success or swapped.swapped_face is None:
                    raise ValueError("DFM did not produce a face")
                crop = cv2.resize(swapped.swapped_face, (aligned.shape[1], aligned.shape[0]))
            else:
                boosted = self.boosted_source(source, original, target_face)
                crop, matrix = unpack_swap_result(self.swapper.get(original, target_face, boosted, paste_back=False))
                if matrix is None:
                    if not isinstance(crop, np.ndarray) or crop.shape != original.shape:
                        raise ValueError("swapper returned no crop affine")
                    # Compatibility with a full-frame return: extract just this face,
                    # then use exactly the same protected compositor as a crop swap.
                    size = self.compositor.config.restore_size
                    matrix = alignment_matrix(target_face.kps, size)
                    if matrix is None:
                        raise ValueError("invalid face landmarks")
                    crop = cv2.warpAffine(crop, matrix, (size, size), borderMode=cv2.BORDER_REPLICATE)
            updated = self.compositor.composite(result, crop, matrix, target_face.kps,
                                                track_id=track_id, native_px=_face_height(target_face),
                                                restore=restore, original_frame=original)
            status = getattr(self.compositor, "last_status", "swapped")
            reason = getattr(self.compositor, "last_reason", "")
            if status == "swapped" and not face_changed(updated, result, target_face):
                status, reason = "skipped", "no visible change"
            degradations = getattr(self.compositor, "last_degraded", [])
            self._record_face(track_id, status, reason or "; ".join(degradations), bool(degradations))
            return updated
        except Exception as exc:
            self._record_face(track_id, "failed", str(exc))
            self.compositor._log_once(f"face swap failed: {exc}")
            return result

    def _process_face_dfm(self, result, original, target_face, track_id=0):
        return self._process_face(result, original, target_face, None, track_id)

    def effective_settings(self):
        from dataclasses import asdict
        return dict(swapper="dfm" if self.dfm else self.swapper_name,
                    restorer=getattr(self.restorer, "model_name", "none") if self.restorer.available else "none",
                    identity_boost=self.identity_boost,
                    parser=bool(self.use_parser and self.masker.parser is not None),
                    occluder=bool(self.use_occluder and self.masker.occluder is not None),
                    composite=asdict(self.compositor.config))

    def _result_details(self, outcomes, **extra):
        if isinstance(outcomes, dict):
            counts = {key: outcomes[key] for key in ("faces_swapped", "faces_skipped", "faces_failed")}
            counts["faces_degraded"] = outcomes["faces_degraded"]
            warnings = sorted(outcomes["warnings"])
        else:
            counts = {f"faces_{status}": sum(f["status"] == status for f in outcomes)
                      for status in ("swapped", "skipped", "failed")}
            counts["faces_degraded"] = sum(f.get("degraded", False) for f in outcomes)
            warnings = sorted({f["reason"] for f in outcomes if f["reason"]})
        return dict(settings=self.effective_settings(), identity=getattr(self, "_identity_report", {}),
                    **counts, warnings=warnings, **extra)

    # ----------------------------------------------------------- landmark EMA

    def _reset_tracks(self):
        self._tracker = FaceTracker()
        self._tracks, self._track_ids = [], []
        self._next_track_id = 0
        self._previous_scene = None

    def _new_track_id(self):
        self._next_track_id += 1
        return self._next_track_id

    def _smooth(self, faces):
        if not hasattr(self, "_tracker"):
            self._reset_tracks()
        ids = self._tracker.update(faces, self.smooth_alpha, self.smooth_landmarks)
        self._tracks = [np.asarray(f.kps).copy() if f.kps is not None else None for f in faces]
        self._track_ids = ids
        return faces, ids

    def _check_scene(self, frame, selector=None):
        small = cv2.resize(frame, (32, 18), interpolation=cv2.INTER_AREA).astype(np.float32)
        previous = self._previous_scene
        self._previous_scene = small
        if previous is not None and float(np.mean(np.abs(previous - small))) > 65:
            self._tracker.clear()
            self.compositor.reset()
            if selector is not None:
                selector.reset()

    # ---------------------------------------------------------------- images

    def _pick_faces(self, img, faces, track_ids, frame_no, target_face_indices, selector):
        """[(face, track_id)] to swap: by identity when the UI sent reference
        embeddings, else by index (old jobs), else every face."""
        pairs = list(zip(faces, track_ids))
        if selector is not None:
            return [(f, t) for f, t in pairs
                    if selector.wants(t, frame_no, lambda f=f: self._embed(img, f))]
        if target_face_indices is not None:
            return [pairs[i] for i in target_face_indices if 0 <= i < len(pairs)]
        return pairs

    def begin_video(self):
        """Reset per-video state: landmark tracks and the compositor's temporal smoothing."""
        self._reset_tracks()
        self._video_recovery = VideoFaceRecovery()
        self.compositor.reset()
        self.compositor.config.temporal = True

    def render_frame(self, frame, source, frame_no: int = 0, target_face_indices=None, selector=None):
        """One video frame through the whole pipeline: detect, track, pick,
        swap and composite. Returns (frame, swaps, faces). Call begin_video()
        before the first frame. eval_reface.py drives this same method."""
        original = frame
        self._check_scene(frame, selector)
        detector = lambda image: detect_video_faces(self.app, image)
        accepts = (lambda face: selector.wants(0, frame_no, lambda: face.normed_embedding)) if selector else (lambda face: True)
        faces = self._video_recovery.detect(frame, detector, accepts)
        faces, track_ids = self._smooth(faces)
        self.compositor.begin_frame()
        self._frame_outcomes = []
        swaps = 0
        if faces:
            result = frame
            for tf, tid in self._pick_faces(frame, faces, track_ids, frame_no,
                                            target_face_indices, selector):
                result = self._process_face(result, original, tf, source, track_id=tid)
            swaps = sum(item["status"] == "swapped" for item in self._frame_outcomes)
            frame = result
        return frame, swaps, faces

    @staticmethod
    def _make_selector(target_face_indices, target_face_embeddings):
        if target_face_indices is None or target_face_embeddings is None or len(target_face_embeddings) == 0:
            return None
        try:
            return FaceSelector(target_face_embeddings, target_face_indices)
        except Exception as e:
            raise ValueError("Reference identities are invalid; detect the targets again") from e

    def reface_image_v3(
        self,
        target_image_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        target_face_embeddings: Optional[list] = None,
        **_ignore,
    ) -> RefaceResult:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        try:
            if self.swapper is None and self.dfm is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            target = cv2.imread(target_image_path)
            if target is None:
                return RefaceResult(False, None, f"Could not load: {target_image_path}")
            _, self._identity_report = select_identity_faces(faceset)
            source = build_source_from_faceset(faceset) if faceset is not None else None
            if source is None and self.dfm is None:
                return RefaceResult(False, None, "Faceset has no usable source faces")

            faces = self._detect(target)
            if not faces:
                return RefaceResult(False, None, "No faces detected in target")

            original = target.copy()
            result = target
            selector = self._make_selector(target_face_indices, target_face_embeddings)
            chosen = self._pick_faces(target, faces, list(range(len(faces))), 0,
                                      target_face_indices, selector)
            if not chosen:
                return RefaceResult(False, None, "None of the selected faces were found in the target")

            self.compositor.reset()
            self.compositor.config.temporal = False
            self.compositor.begin_frame()
            self._frame_outcomes = []
            for tf, tid in chosen:
                result = self._process_face(result, original, tf, source, track_id=tid)

            out = self.output_dir / f"refaced_v3_{ts}.png"  # PNG: no JPEG softening
            details = self._result_details(self._frame_outcomes, faces=self._frame_outcomes)
            count = details["faces_swapped"]
            if not count:
                return RefaceResult(False, None, "No faces were swapped: " + "; ".join(details["warnings"]), 0, details)
            if not cv2.imwrite(str(out), result):
                raise OSError("Could not save the result photo")
            return RefaceResult(True, str(out), f"V3 swap complete ({count}/{len(chosen)} faces)", count, details)
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {e}")

    # ----------------------------------------------------------------- video

    def reface_video_v3(
        self,
        target_video_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        progress_callback=None,
        start_time: float = 0.0,
        end_time: Optional[float] = None,
        target_face_embeddings: Optional[list] = None,
        resume_from_frame: int = 0,
        finalize: bool = True,
        **_ignore,
    ) -> RefaceResult:
        """Render [start_time, end_time) of the video.

        resume_from_frame skips that many frames of the range (a paused job
        picking up where it stopped). finalize=False writes a silent part file
        for the job manager to concatenate; the audio is muxed once, onto the
        joined result.
        """
        ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        cap = writer = proc = None
        try:
            if self.swapper is None and self.dfm is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            source = build_source_from_faceset(faceset) if faceset is not None else None
            if source is None and self.dfm is None:
                return RefaceResult(False, None, "Faceset has no usable source faces")

            cap = cv2.VideoCapture(target_video_path)
            if not cap.isOpened():
                return RefaceResult(False, None, f"Could not open: {target_video_path}")

            fps = video_fps(cap)
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            if total <= 0:
                total = 10 ** 9   # unknown length: read to the end of the stream

            start_frame = max(0, min(int(round(start_time * fps)) if start_time > 0 else 0, max(total - 1, 0)))
            end_frame = min(int(round(end_time * fps)), total) if (end_time and end_time > 0) else total
            end_frame = max(start_frame + 1, min(end_frame, total))
            first = min(start_frame + max(0, int(resume_from_frame or 0)), end_frame)
            n_target = end_frame - first
            if n_target <= 0:
                cap.release()
                return RefaceResult(True, None, "V3 video: nothing left to render", 0)
            print(f"[INFO] V3 video: frames {first}..{end_frame} ({n_target}, {n_target/fps:.1f}s @ {fps:.3f} fps)")

            name = f"refaced_v3_video_{ts}.mp4" if finalize else f"refaced_v3_part_{ts}_{first}.mp4"
            out_path = self.output_dir / name
            writer = proc = None   # opened on the first frame, at its real size

            self.begin_video()
            selector = self._make_selector(target_face_indices, target_face_embeddings)
            warmup = min(12, first) if resume_from_frame else 0
            if first > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, first - warmup)
            for offset in range(warmup):
                ok, context = cap.read()
                if not ok:
                    raise ValueError("Could not restore video context before the checkpoint")
                self.render_frame(context, source, first - warmup + offset, target_face_indices, selector)

            processed, swaps, cur = 0, 0, first
            outcomes = dict(faces_swapped=0, faces_skipped=0, faces_failed=0, faces_degraded=0, warnings=set())
            stopped = False
            while cur < end_frame:
                ret, frame = cap.read()
                if not ret:
                    break
                if writer is None and proc is None:
                    # Prefer piping raw frames to x264 (no intermediate MJPG re-compression)
                    writer, proc = self._open_writer(out_path, fps, frame.shape[1], frame.shape[0])
                frame, n, _ = self.render_frame(frame, source, cur, target_face_indices, selector)
                swaps += n
                for outcome in self._frame_outcomes:
                    outcomes["faces_" + outcome["status"]] += 1
                    outcomes["faces_degraded"] += bool(outcome.get("degraded"))
                    if outcome["reason"] and len(outcomes["warnings"]) < 16:
                        outcomes["warnings"].add(outcome["reason"])

                self._write(writer, proc, frame)
                processed += 1
                cur += 1

                if progress_callback and processed % 3 == 0:
                    cont = progress_callback(processed, n_target)
                    if cont is False:
                        stopped = True
                        break

            cap.release()
            self._close_writer(writer, proc)
            writer = proc = None
            if processed == 0:
                return RefaceResult(False, None, "Could not read any frame of the video")

            if not stopped and total != 10 ** 9 and processed != n_target:
                raise ValueError("The source video ended before the requested range was rendered")
            validate_video(out_path, processed, fps)
            if finalize and swaps == 0:
                raise ValueError("No faces were swapped in this video")
            if finalize and self._mux_audio(out_path, target_video_path, start_time, end_time):
                print("[INFO] V3 video: original audio preserved")

            # Report the frames actually written. A stopped run must not claim
            # the whole range, or a resume would skip what was never rendered.
            if progress_callback and not stopped:
                progress_callback(processed, processed)

            if finalize:
                validate_video(out_path, processed, fps)
            msg = f"V3 video {'stopped' if stopped else 'complete'} ({swaps} swaps in {processed} frames)"
            return RefaceResult(True, str(out_path), msg, swaps, self._result_details(
                outcomes, frames_done=processed, frames_recovered=self._video_recovery.recovered))
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {e}")
        finally:
            if cap is not None:
                cap.release()
            self._abort_writer(writer, proc)

    def _open_writer(self, out_path, fps, w, h):
        log = tempfile.TemporaryFile()
        try:
            command = [_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo",
                       "-pix_fmt", "bgr24", "-s", f"{w}x{h}", "-r", rate_arg(fps), "-i", "-",
                       "-an", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264",
                       "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", str(out_path)]
            proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log)
            proc._reface_log = log
            proc._reface_writer = ThreadPoolExecutor(max_workers=1, thread_name_prefix="encode")
            return None, proc
        except OSError:
            log.close()
            if w % 2 or h % 2:
                raise ValueError("FFmpeg is required for video frames with odd dimensions")
            writer = cv2.VideoWriter(str(out_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
            if not writer.isOpened():
                writer.release()
                raise OSError("Could not open the video encoder")
            return writer, None

    def _write(self, writer, proc, frame):
        if proc is not None:
            if proc.poll() is not None:
                raise OSError("FFmpeg stopped before the video was rendered")
            pixels = np.ascontiguousarray(frame).tobytes()
            def send():
                written = proc.stdin.write(pixels)
                proc.stdin.flush()
                return written
            pool = getattr(proc, "_reface_writer", None)
            try:
                written = pool.submit(send).result(timeout=getattr(self, "writer_timeout", 60)) if pool else send()
            except FutureTimeout as exc:
                proc.kill()
                proc.wait(timeout=10)
                raise OSError("The video encoder stopped accepting frames") from exc
            if written != len(pixels):
                raise OSError("The encoder accepted an incomplete video frame")
        elif writer is not None and writer.isOpened():
            writer.write(frame)
        else:
            raise OSError("The video encoder is not open")

    def _close_writer(self, writer, proc):
        if proc is None:
            if writer is not None:
                writer.release()
            return
        try:
            proc.stdin.close()
            code = proc.wait(timeout=60)
            if code:
                log = getattr(proc, "_reface_log", None)
                error = ""
                if log is not None:
                    log.seek(0, 2)
                    log.seek(max(0, log.tell() - 4096))
                    error = log.read().decode("utf-8", errors="replace")
                raise OSError(f"Video encoder failed ({code}): {error}")
        finally:
            self._abort_writer(None, proc)

    @staticmethod
    def _abort_writer(writer, proc):
        if writer is not None:
            writer.release()
        if proc is not None:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=10)
            try:
                if proc.stdin and not proc.stdin.closed:
                    proc.stdin.close()
            except (OSError, ValueError):
                pass
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=10)
            pool = getattr(proc, "_reface_writer", None)
            if pool is not None:
                pool.shutdown(wait=True)
            log = getattr(proc, "_reface_log", None)
            if log is not None:
                log.close()

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


if __name__ == "__main__":
    print("Testing RefaceEngineV3...")
    try:
        eng = RefaceEngineV3()
        print(f"✅ V3 init OK (version {eng.VERSION})")
        print(f"   swapper: {'loaded' if eng.swapper else 'MISSING'}")
        print(f"   restorer available: {eng.restorer.available}")
        print(f"   parser/occluder: {eng.masker.parser is not None}/{eng.masker.occluder is not None}")
    except Exception as e:
        import traceback
        traceback.print_exc()
