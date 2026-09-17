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
from pathlib import Path
from typing import List, Optional
from datetime import datetime

import cv2
import numpy as np

from reface_engine import RefaceEngine, RefaceResult, Faceset, FaceData  # noqa: F401
from identity import build_source_from_faceset
from face_restore import FaceRestorer, resolve_restorer_name
from face_masking import FaceMasker, DEFAULT_REGIONS
from face_compositor import CompositeConfig, FaceCompositor, config_from_preset

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


class RefaceEngineV3(RefaceEngine):
    VERSION = "3.0"

    def __init__(
        self,
        output_dir: str = None,
        restorer: str = "codeformer",     # "codeformer" | "gfpgan_1.4" | "gpen_bfr_512" | "auto" | "none"
        restorer_weight: float = 0.5,     # CodeFormer fidelity (higher = closer to input, lower = sharper)
        use_parser: bool = True,
        use_occluder: bool = True,
        mask_regions: Optional[List[str]] = None,
        restore_size: int = 512,
        blend: float = 1.0,               # global paste strength
        smooth_landmarks: bool = True,    # video: EMA on landmarks
        smooth_alpha: float = 0.6,        # weight of current frame (1.0 = no smoothing)
        dfm_path: Optional[str] = None,   # DeepFaceLab .dfm -> "pro" per-person mode
        realism_preset: str = "natural",          # "natural" | "maximum_detail" | "clean"
        realism_overrides: Optional[dict] = None,
    ):
        super().__init__(output_dir=output_dir, enable_enhancement=False, upscale=1)

        self.restore_size = int(restore_size)
        self.use_parser = use_parser
        self.use_occluder = use_occluder
        self.mask_regions = mask_regions or DEFAULT_REGIONS
        self.blend = float(blend)
        self.smooth_landmarks = smooth_landmarks
        self.smooth_alpha = float(smooth_alpha)

        # Face restorer (ONNX). "auto" picks any available; "none" disables.
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

        # Masks (ONNX parser + occluder, with graceful fallback)
        self.masker = FaceMasker(providers=self.providers)

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
            f"(mode={'DFM' if self.dfm else 'inswapper'}, "
            f"restorer={'on' if self.restorer.available else 'off'}, "
            f"parser={'on' if self.masker.parser else 'off'}, "
            f"occluder={'on' if self.masker.occluder else 'off'})"
        )

    # ------------------------------------------------------------------ utils

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
            aligned_swap, m_swap = unpack_swap_result(
                self.swapper.get(original, target_face, source, paste_back=False)
            )
        except Exception as e:
            print(f"[V3] swap failed: {e}")
            return result

        # Older insightface: paste_back is ignored and we get a full-frame paste.
        # Keep it — throwing it away is how the pipeline used to return the input.
        if m_swap is None:
            if (isinstance(aligned_swap, np.ndarray)
                    and aligned_swap.ndim == 3
                    and aligned_swap.shape[:2] == result.shape[:2]):
                print("[V3] swapper returned a full-frame paste; compositor skipped")
                return aligned_swap
            print("[V3] swap failed: no crop affine from swapper")
            return result

        updated = self.compositor.composite(
            result, aligned_swap, m_swap, target_face.kps,
            track_id=track_id, native_px=_face_height(target_face),
        )
        if _mean_abs_diff(updated, result) < 0.5:
            print("[V3] compositor left the frame unchanged; "
                  "falling back to insightface paste_back", flush=True)
            try:
                pasted = self.swapper.get(original, target_face, source, paste_back=True)
                if isinstance(pasted, np.ndarray) and pasted.shape[:2] == result.shape[:2]:
                    return pasted
            except Exception as e:
                print(f"[V3] paste_back fallback failed: {e}", flush=True)
        return updated

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

    # ----------------------------------------------------------- landmark EMA

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

    # ---------------------------------------------------------------- images

    def reface_image_v3(
        self,
        target_image_path: str,
        faceset: Faceset,
        target_face_indices: Optional[List[int]] = None,
        **_ignore,
    ) -> RefaceResult:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        try:
            if self.swapper is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            target = cv2.imread(target_image_path)
            if target is None:
                return RefaceResult(False, None, f"Could not load: {target_image_path}")
            source = build_source_from_faceset(faceset) if faceset is not None else None
            if source is None and self.dfm is None:
                return RefaceResult(False, None, "Faceset has no usable source faces")

            faces = self.app.get(target)
            if not faces:
                return RefaceResult(False, None, "No faces detected in target")

            original = target.copy()
            result = target
            if target_face_indices is not None:
                chosen = [faces[i] for i in target_face_indices if 0 <= i < len(faces)]
            else:
                chosen = faces

            self.compositor.reset()
            self.compositor.begin_frame()
            for i, tf in enumerate(chosen):
                result = self._process_face(result, original, tf, source, track_id=i)

            out = self.output_dir / f"refaced_v3_{ts}.png"  # PNG: no JPEG softening
            cv2.imwrite(str(out), result)
            delta = _mean_abs_diff(result, original)
            if delta < 0.5:
                return RefaceResult(
                    False, str(out),
                    "Swap produced no visible change (paste mask or placement failed — "
                    "check [COMPOSITE] logs)",
                    0,
                )
            return RefaceResult(True, str(out), f"V3 swap complete ({len(chosen)} faces)", len(chosen))
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
        **_ignore,
    ) -> RefaceResult:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        try:
            if self.swapper is None and self.dfm is None:
                return RefaceResult(False, None, "Inswapper model not loaded")
            source = build_source_from_faceset(faceset) if faceset is not None else None
            if source is None and self.dfm is None:
                return RefaceResult(False, None, "Faceset has no usable source faces")

            cap = cv2.VideoCapture(target_video_path)
            if not cap.isOpened():
                return RefaceResult(False, None, f"Could not open: {target_video_path}")

            fps = int(cap.get(cv2.CAP_PROP_FPS)) or 25
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

            start_frame = max(0, min(int(start_time * fps) if start_time > 0 else 0, max(total - 1, 0)))
            end_frame = min(int(end_time * fps), total) if (end_time and end_time > 0) else total
            end_frame = max(start_frame + 1, min(end_frame, total))
            n_target = end_frame - start_frame
            print(f"[INFO] V3 video: frames {start_frame}..{end_frame} ({n_target}, {n_target/fps:.1f}s)")

            out_path = self.output_dir / f"refaced_v3_video_{ts}.mp4"

            # Prefer piping raw frames to x264 (no intermediate MJPG re-compression)
            writer, proc = self._open_writer(out_path, fps, width, height)

            self._reset_tracks()
            self.compositor.reset()
            self.compositor.config.temporal = True
            if start_frame > 0:
                cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

            processed, swaps, cur = 0, 0, start_frame
            stopped = False
            while cur < end_frame:
                ret, frame = cap.read()
                if not ret:
                    break
                original = frame
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

            if self._mux_audio(out_path, target_video_path, start_time, end_time):
                print("[INFO] V3 video: original audio preserved")

            if progress_callback:
                progress_callback(n_target, n_target)

            msg = f"V3 video {'stopped' if stopped else 'complete'} ({swaps} swaps in {processed} frames)"
            return RefaceResult(True, str(out_path), msg, swaps)
        except Exception as e:
            import traceback
            traceback.print_exc()
            return RefaceResult(False, None, f"Error: {e}")

    # --------------------------------------------------------- writer helpers

    def _open_writer(self, out_path: Path, fps: int, w: int, h: int):
        """Return (cv2_writer_or_None, ffmpeg_proc_or_None)."""
        try:
            cmd = [
                _ffmpeg_exe(), "-y", "-loglevel", "error",
                "-f", "rawvideo", "-pix_fmt", "bgr24",
                "-s", f"{w}x{h}", "-r", str(fps), "-i", "-",
                "-an", "-c:v", "libx264", "-preset", "medium",
                "-crf", "16", "-pix_fmt", "yuv420p", str(out_path),
            ]
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return None, proc
        except Exception as e:
            print(f"[WARN] ffmpeg pipe unavailable ({e}); using cv2.VideoWriter")
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            return cv2.VideoWriter(str(out_path), fourcc, fps, (w, h)), None

    def _write(self, writer, proc, frame):
        if proc is not None:
            try:
                proc.stdin.write(np.ascontiguousarray(frame).tobytes())
            except Exception:
                pass
        elif writer is not None:
            writer.write(frame)

    def _close_writer(self, writer, proc):
        if proc is not None:
            try:
                proc.stdin.close()
                proc.wait()
            except Exception:
                pass
        elif writer is not None:
            writer.release()

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
