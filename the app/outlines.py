"""
Exact face & body outlines generation.

Extracts real shape contours for faces and bodies:
- Face: BiSeNet face parser (CelebAMask-HQ 19 classes via face_masking.FaceMasker)
        on aligned crop, mapped back to image pixels.
- Body: RMBG-1.4 background removal on padded body crop, batch-processed,
        disambiguated using COCO skeleton keypoints when present.

Converts masks to simplified polygon coordinates (3-64 points).
"""

import os
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

import cv2
import numpy as np

try:
    from cuda_dll_dirs import add_nvidia_dll_dirs
    add_nvidia_dll_dirs()
except Exception:
    pass

import onnxruntime as ort

from face_compositor import alignment_matrix
from face_masking import FaceMasker, REGIONS

MODELS_DIR = Path(__file__).parent / "models"
RMBG_FILE = "rmbg.onnx"
PARSER_FILE = "bisenet_resnet_34.onnx"

# COCO 17-keypoint skeleton limbs (16 pairs)
COCO_LIMBS = [
    (0, 1), (0, 2), (1, 3), (2, 4),      # head / face
    (5, 6), (5, 7), (7, 9),              # left arm
    (6, 8), (8, 10),                     # right arm
    (5, 11), (6, 12), (11, 12),          # torso
    (11, 13), (13, 15),                  # left leg
    (12, 14), (14, 16),                  # right leg
]

# Regions representing the face itself (excluding hair, hat, neck, and cloth)
FACE_OUTLINE_REGIONS = [
    "skin", "left-eyebrow", "right-eyebrow", "left-eye", "right-eye",
    "glasses", "left-ear", "right-ear", "nose", "mouth", "upper-lip", "lower-lip",
]


def mask_to_polygon(
    mask: np.ndarray,
    *,
    max_points: int = 64,
    min_area_frac: float = 0.01,
    prefer: Optional[np.ndarray] = None,
) -> Optional[np.ndarray]:
    """Convert a binary mask into a simplified polygon of 3-max_points vertices.

    Args:
        mask: 2D uint8 or bool array at crop resolution.
        max_points: maximum number of vertices in returned polygon.
        min_area_frac: minimum contour area as fraction of total mask area.
        prefer: optional uint8 mask of the same shape to select the best overlapping contour.

    Returns:
        (K, 2) float32 array in crop pixels, or None if no valid contour.
    """
    if mask is None or mask.size == 0:
        return None

    if mask.dtype == bool:
        m = (mask.astype(np.uint8) * 255)
    elif mask.dtype != np.uint8:
        m = (mask > 0).astype(np.uint8) * 255
    else:
        m = (mask > 0).astype(np.uint8) * 255 if mask.max() <= 1 else mask.copy()

    h, w = m.shape[:2]
    if h == 0 or w == 0:
        return None

    # Morphological open then close (kernel ≈ 1% of the shorter side, at least 3 px)
    k_size = max(3, int(round(min(h, w) * 0.01)))
    if k_size % 2 == 0:
        k_size += 1
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k_size, k_size))
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, kernel)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, kernel)

    # Find external contours
    contours, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    total_area = float(h * w)
    min_area = total_area * min_area_frac
    valid_contours = [c for c in contours if cv2.contourArea(c) >= min_area]

    if not valid_contours:
        return None

    # Choose contour: prefer overlap if provided, else largest area
    if prefer is not None:
        best_c = None
        best_overlap = -1.0
        for c in valid_contours:
            c_mask = np.zeros((h, w), dtype=np.uint8)
            cv2.drawContours(c_mask, [c], -1, 1, thickness=-1)
            overlap = float(np.sum((c_mask > 0) & (prefer > 0)))
            if overlap > best_overlap:
                best_overlap = overlap
                best_c = c
        if best_overlap <= 0:
            chosen_c = max(valid_contours, key=cv2.contourArea)
        else:
            chosen_c = best_c
    else:
        chosen_c = max(valid_contours, key=cv2.contourArea)

    perimeter = cv2.arcLength(chosen_c, closed=True)
    if perimeter <= 0:
        return None

    epsilon = 0.003 * perimeter
    poly = cv2.approxPolyDP(chosen_c, epsilon, closed=True)
    while len(poly) > max_points:
        epsilon *= 1.5
        poly = cv2.approxPolyDP(chosen_c, epsilon, closed=True)

    if len(poly) < 3:
        return None

    return poly.reshape(-1, 2).astype(np.float32)


def apply_affine(poly: np.ndarray, inv_2x3: np.ndarray) -> np.ndarray:
    """Map a polygon using a 2x3 affine matrix."""
    if poly is None or len(poly) == 0:
        return poly
    pts = np.asarray(poly, dtype=np.float32).reshape(-1, 2)
    inv = np.asarray(inv_2x3, dtype=np.float32)
    ones = np.ones((len(pts), 1), dtype=np.float32)
    hom = np.hstack([pts, ones])
    mapped = hom @ inv.T
    return mapped.astype(np.float32)


def to_image_coords(poly: np.ndarray, crop_origin_xy: Tuple[float, float], scale: float = 1.0) -> np.ndarray:
    """Map a crop polygon back to image coordinates."""
    if poly is None or len(poly) == 0:
        return poly
    pts = np.asarray(poly, dtype=np.float32).reshape(-1, 2).copy()
    if scale != 1.0:
        pts *= scale
    pts[:, 0] += crop_origin_xy[0]
    pts[:, 1] += crop_origin_xy[1]
    return pts


def skeleton_mask(
    kpts: Optional[np.ndarray],
    kpt_scores: Optional[np.ndarray],
    shape: Tuple[int, int],
    origin_xy: Tuple[float, float],
    min_score: float = 0.3,
) -> Optional[np.ndarray]:
    """Draw COCO limbs (16 pairs) and visible joints in crop coordinates."""
    if kpts is None or len(kpts) < 17:
        return None
    h, w = shape[:2]
    ox, oy = origin_xy
    pts = np.asarray(kpts, dtype=np.float32)
    scores = np.asarray(kpt_scores, dtype=np.float32) if kpt_scores is not None else np.ones(len(pts), dtype=np.float32)
    if len(scores) < len(pts):
        scores = np.ones(len(pts), dtype=np.float32)

    thickness = max(2, int(round(h * 0.04)))
    radius = max(2, thickness // 2)

    mask = np.zeros((h, w), dtype=np.uint8)
    visible_count = 0

    # Limbs
    for i, j in COCO_LIMBS:
        if i < len(pts) and j < len(pts):
            if scores[i] >= min_score and scores[j] >= min_score:
                pt1 = (int(round(pts[i, 0] - ox)), int(round(pts[i, 1] - oy)))
                pt2 = (int(round(pts[j, 0] - ox)), int(round(pts[j, 1] - oy)))
                cv2.line(mask, pt1, pt2, 255, thickness=thickness)

    # Joints
    for i in range(min(17, len(pts))):
        if scores[i] >= min_score:
            pt = (int(round(pts[i, 0] - ox)), int(round(pts[i, 1] - oy)))
            cv2.circle(mask, pt, radius, 255, thickness=-1)
            visible_count += 1

    if visible_count == 0 and np.sum(mask) == 0:
        return None
    return mask


def encode_outline(poly: Optional[np.ndarray]) -> Optional[List[List[float]]]:
    """Encode polygon points as wire format [[x, y], ...], rounded to 1 decimal."""
    if poly is None or len(poly) < 3:
        return None
    return [[round(float(p[0]), 1), round(float(p[1]), 1)] for p in poly]


class OutlineEngine:
    """Computes exact face and body outlines using BiSeNet and RMBG-1.4."""

    def __init__(
        self,
        models_dir: Optional[Path] = None,
        providers: Optional[List[str]] = None,
        masker: Optional[Any] = None,
        rmbg_session: Optional[Any] = None,
    ):
        self.models_dir = Path(models_dir or MODELS_DIR)
        self.providers = providers or ["CUDAExecutionProvider", "CPUExecutionProvider"]

        # Face parser
        self.masker = masker
        self._masker_loaded = masker is not None

        # RMBG session
        self.rmbg_session = rmbg_session
        self._rmbg_loaded = rmbg_session is not None

    def _ensure_masker(self):
        if self._masker_loaded:
            return
        self._masker_loaded = True
        parser_path = self.models_dir / PARSER_FILE
        if parser_path.exists():
            try:
                self.masker = FaceMasker(
                    parser_path=str(parser_path),
                    load_occluder=False,
                    providers=self.providers,
                )
            except Exception as e:
                print(f"[OUTLINE] FaceMasker load failed: {e}")
                self.masker = None
        else:
            print(f"[OUTLINE] parser not found: {parser_path}")
            self.masker = None

    def _ensure_rmbg(self):
        if self._rmbg_loaded:
            return
        self._rmbg_loaded = True
        rmbg_path = self.models_dir / RMBG_FILE
        if rmbg_path.exists():
            try:
                self.rmbg_session = self._create_rmbg_session(self.providers)
                print(f"[OUTLINE] RMBG session loaded on {self.rmbg_session.get_providers()}")
            except Exception as e:
                print(f"[OUTLINE] RMBG load failed: {e}")
                self.rmbg_session = None
                self._rmbg_loaded = False  # a later request may have more memory
        else:
            print(f"[OUTLINE] RMBG model not found: {rmbg_path}")
            self.rmbg_session = None

    def _create_rmbg_session(self, providers):
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        # Outlines share a worker with several other models. Avoid retaining a
        # large host arena, or reserving oversized CUDA convolution workspaces.
        so.enable_cpu_mem_arena = False
        so.enable_mem_pattern = False
        providers = [
            (provider, {"arena_extend_strategy": "kSameAsRequested",
                        "cudnn_conv_algo_search": "HEURISTIC",
                        "cudnn_conv_use_max_workspace": "0"})
            if provider == "CUDAExecutionProvider" else provider
            for provider in providers
        ]
        return ort.InferenceSession(
            str(self.models_dir / RMBG_FILE), sess_options=so, providers=providers
        )

    def _rmbg_inference(self, inp):
        if hasattr(self.rmbg_session, "run"):
            in_name = self.rmbg_session.get_inputs()[0].name
            return self.rmbg_session.run(None, {in_name: inp})[0]
        if callable(self.rmbg_session):
            return self.rmbg_session(inp)
        return None

    def _run_rmbg(self, inp):
        try:
            return self._rmbg_inference(inp)
        except Exception as error:
            message = str(error).lower()
            memory_failure = isinstance(error, MemoryError) or any(
                marker in message for marker in (
                    "failed to allocate memory", "out of memory", "cuda_error_out_of_memory",
                    "cudaerrormemoryallocation", "cudnn_status_alloc_failed",
                )
            )
            providers = (self.rmbg_session.get_providers()
                         if hasattr(self.rmbg_session, "get_providers") else [])
            if not memory_failure or "CUDAExecutionProvider" not in providers:
                print(f"[OUTLINE] RMBG inference failed: {error}")
                return None
            print("[OUTLINE] RMBG GPU memory exhausted; releasing its session and retrying on CPU")

        # Leave the exception handler first so its traceback no longer holds the
        # failed CUDA session. Keep using CPU for later crops in this worker.
        self.rmbg_session = None
        try:
            self.rmbg_session = self._create_rmbg_session(["CPUExecutionProvider"])
            return self._rmbg_inference(inp)
        except Exception as error:
            print(f"[OUTLINE] RMBG CPU retry failed: {error}")
            if self.rmbg_session is None:
                self._rmbg_loaded = False
            return None

    def face_outline(self, img: np.ndarray, face: Any) -> Optional[np.ndarray]:
        """Compute exact face outline polygon in image coordinates."""
        self._ensure_masker()
        if self.masker is None or getattr(self.masker, "parser", None) is None:
            return None

        kps = getattr(face, "kps", None)
        M = None
        if kps is not None:
            M = alignment_matrix(kps, 512)

        class_ids = [REGIONS[r] for r in FACE_OUTLINE_REGIONS if r in REGIONS]

        if M is not None:
            crop = cv2.warpAffine(img, M, (512, 512))
            seg = self.masker.segment(crop)
            if seg is None:
                return None
            face_mask = np.isin(seg, class_ids).astype(np.uint8) * 255
            poly = mask_to_polygon(face_mask)
            if poly is None:
                return None
            M_inv = cv2.invertAffineTransform(M)
            if M_inv is None:
                return None
            return apply_affine(poly, M_inv)
        else:
            bbox = getattr(face, "bbox", None)
            if bbox is None:
                return None
            h, w = img.shape[:2]
            x1, y1, x2, y2 = [int(v) for v in bbox[:4]]
            bw, bh = x2 - x1, y2 - y1
            pad_x, pad_y = int(bw * 0.3), int(bh * 0.3)
            x0, y0 = max(0, x1 - pad_x), max(0, y1 - pad_y)
            x1_c, y1_c = min(w, x2 + pad_x), min(h, y2 + pad_y)
            if x1_c <= x0 or y1_c <= y0:
                return None
            crop = img[y0:y1_c, x0:x1_c]
            seg = self.masker.segment(crop)
            if seg is None:
                return None
            face_mask = np.isin(seg, class_ids).astype(np.uint8) * 255
            poly = mask_to_polygon(face_mask)
            if poly is None:
                return None
            return to_image_coords(poly, (x0, y0))

    def body_outlines(self, img: np.ndarray, bodies: list) -> List[Optional[np.ndarray]]:
        """Compute exact body outline polygons in image coordinates, batched."""
        if not bodies:
            return []
        self._ensure_rmbg()
        if self.rmbg_session is None:
            return [None] * len(bodies)

        h, w = img.shape[:2]
        outlines: List[Optional[np.ndarray]] = [None] * len(bodies)

        valid_indices = []
        crops_bgr = []
        crop_boxes = []

        for idx, b in enumerate(bodies):
            bbox = getattr(b, "bbox", None)
            if bbox is None:
                continue
            bx1, by1, bx2, by2 = [int(v) for v in bbox[:4]]
            pad_x, pad_y = int((bx2 - bx1) * 0.06), int((by2 - by1) * 0.04)
            x0, y0 = max(0, bx1 - pad_x), max(0, by1 - pad_y)
            x1, y1 = min(w, bx2 + pad_x), min(h, by2 + pad_y)
            if x1 <= x0 or y1 <= y0:
                continue
            crop = img[y0:y1, x0:x1]
            if crop.size == 0:
                continue
            valid_indices.append(idx)
            crops_bgr.append(crop)
            crop_boxes.append((x0, y0, x1 - x0, y1 - y0))

        if not valid_indices:
            return outlines

        # RMBG's 1024px activations are large; eight crops can exhaust a 6GB
        # GPU and leave its arena at that high-water mark for the entire scan.
        BATCH_SIZE = 1
        for chunk_start in range(0, len(valid_indices), BATCH_SIZE):
            if self.rmbg_session is None:
                break
            chunk_indices = valid_indices[chunk_start : chunk_start + BATCH_SIZE]
            chunk_crops = crops_bgr[chunk_start : chunk_start + BATCH_SIZE]
            chunk_boxes = crop_boxes[chunk_start : chunk_start + BATCH_SIZE]

            inp = np.empty((len(chunk_crops), 3, 1024, 1024), dtype=np.float32)
            for i, crop in enumerate(chunk_crops):
                rgb = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
                resized = cv2.resize(rgb, (1024, 1024), interpolation=cv2.INTER_LINEAR).astype(np.float32) / 255.0
                resized -= 0.5
                inp[i] = resized.transpose(2, 0, 1)
            del rgb, resized

            out = self._run_rmbg(inp)
            del inp

            if out is None:
                continue

            for i, (orig_idx, crop, (x0, y0, cw, ch)) in enumerate(zip(chunk_indices, chunk_crops, chunk_boxes)):
                raw_mask = out[i, 0] if out.ndim == 4 else out[i]
                mi, ma = float(raw_mask.min()), float(raw_mask.max())
                norm_mask = (raw_mask - mi) / (ma - mi + 1e-8)
                crop_mask = cv2.resize(norm_mask, (cw, ch), interpolation=cv2.INTER_LINEAR)
                bin_mask = (crop_mask >= 0.5).astype(np.uint8) * 255

                b = bodies[orig_idx]
                kpts = getattr(b, "kpts", None)
                kpt_scores = getattr(b, "kpt_scores", None)
                pref = skeleton_mask(kpts, kpt_scores, (ch, cw), (x0, y0)) if kpts is not None else None

                poly = mask_to_polygon(bin_mask, prefer=pref)
                if poly is not None:
                    outlines[orig_idx] = to_image_coords(poly, (x0, y0))

        return outlines

    def compute(self, img: np.ndarray, result: Any) -> Tuple[List[Optional[np.ndarray]], List[Optional[np.ndarray]]]:
        """Compute outlines for faces (passes_gate only) and all bodies.

        Updates result.timings_ms['outline'] with elapsed time.
        """
        t0 = time.perf_counter()
        face_outlines: List[Optional[np.ndarray]] = []

        faces = getattr(result, "faces", [])
        passes = getattr(result, "passes_gate", [True] * len(faces))

        for i, face in enumerate(faces):
            if i < len(passes) and passes[i]:
                face_outlines.append(self.face_outline(img, face))
            else:
                face_outlines.append(None)

        bodies = getattr(result, "bodies", [])
        body_outlines = self.body_outlines(img, bodies)

        # A character's body gets the same silhouette as a person's (set on the character).
        drawn = [c for c in getattr(result, "characters", []) if getattr(c, "body_bbox", None) is not None]
        if drawn:
            from types import SimpleNamespace
            shapes = self.body_outlines(img, [SimpleNamespace(bbox=c.body_bbox, kpts=c.body_kpts,
                                                              kpt_scores=c.body_kpt_scores) for c in drawn])
            for c, shape in zip(drawn, shapes):
                c.body_outline = shape

        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        if hasattr(result, "timings_ms") and isinstance(result.timings_ms, dict):
            result.timings_ms["outline"] = round(elapsed_ms, 1)

        return face_outlines, body_outlines
