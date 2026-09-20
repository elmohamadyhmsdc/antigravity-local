"""
Face quality scoring for the gallery.

A face's quality here means "how much can we trust its identity embedding",
not how pretty the crop is. Each component was checked against that on the
curated library (290 faces, 3 people, 2026-09-19): Spearman correlation with a
face's similarity to its own person's mean embedding was

    embedding norm .43 | face size .38 | sharpness .27 | pose .27 | detector score ~0
    combined score .56 (the old det_score * size-ratio score: .40)

so the detector's confidence is only used as a hard gate, not in the score.
Pure NumPy/OpenCV - no models, unit-testable on CPU.
"""

from typing import Dict, Optional, Tuple

import cv2
import numpy as np

QUALITY_VERSION = 2

# Faces below this are not stored as gallery faces (they can still link a body
# to a person, see library_scanner). Overridable via FACE_MIN_QUALITY.
DEFAULT_MIN_QUALITY = 0.40
MIN_DET_SCORE = 0.50
MIN_FACE_PX = 24

WEIGHTS = {"norm": 0.35, "size": 0.20, "sharp": 0.20, "pose": 0.25}

TIERS = (  # (lower bound, key, label)
    (0.75, "great", "Great"),
    (0.55, "good", "Good"),
    (0.35, "fair", "Fair"),
    (0.0, "poor", "Poor"),
)


def _clip01(v: float) -> float:
    return float(min(1.0, max(0.0, v)))


def sharpness(aligned_bgr: np.ndarray) -> float:
    """Variance of the Laplacian on an aligned face crop (112x112 from norm_crop).
    Measuring on the aligned crop makes it comparable across face sizes."""
    if aligned_bgr is None or aligned_bgr.size == 0:
        return 0.0
    gray = aligned_bgr if aligned_bgr.ndim == 2 else cv2.cvtColor(aligned_bgr, cv2.COLOR_BGR2GRAY)
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def pose_from_kps(kps: np.ndarray) -> Tuple[float, float]:
    """Rough (yaw, pitch) in degrees from the detector's 5 landmarks
    (left eye, right eye, nose, left mouth, right mouth). Used only when the
    3D landmark model didn't provide face.pose."""
    kps = np.asarray(kps, dtype=np.float32).reshape(5, 2)
    eye_mid = (kps[0] + kps[1]) / 2
    mouth_mid = (kps[3] + kps[4]) / 2
    eye_dist = float(np.linalg.norm(kps[1] - kps[0])) or 1.0
    # Nose offset from the eye-mouth midline, relative to eye distance: ~0 frontal, ~±0.5 at 45°
    mid_x = (eye_mid[0] + mouth_mid[0]) / 2
    yaw = float(np.degrees(np.arcsin(np.clip((kps[2][0] - mid_x) / eye_dist * 1.4, -1, 1))))
    face_h = float(np.linalg.norm(mouth_mid - eye_mid)) or 1.0
    # Nose sits ~45% of the way from eyes to mouth on a level face
    rel = (kps[2][1] - eye_mid[1]) / face_h
    pitch = float(np.degrees(np.arcsin(np.clip((rel - 0.45) * 2.0, -1, 1))))
    return yaw, pitch


def components(face_px: float, embedding_norm: Optional[float], sharp: float,
               yaw: Optional[float], pitch: Optional[float]) -> Dict[str, float]:
    """Each component in [0, 1]. Ranges come from the calibration run above."""
    norm_s = 0.5 if embedding_norm is None else _clip01((embedding_norm - 17.0) / 8.0)
    size_s = _clip01((face_px - 32.0) / 128.0)
    sharp_s = _clip01((np.log10(max(sharp, 0.0) + 1.0) - 1.6) / 1.3)
    if yaw is None or pitch is None:
        pose_s = 0.6
    else:
        pose_s = _clip01(1.0 - (abs(yaw) - 20.0) / 50.0) * _clip01(1.0 - (abs(pitch) - 15.0) / 40.0)
    return {"norm": norm_s, "size": size_s, "sharp": sharp_s, "pose": pose_s}


def score(parts: Dict[str, float]) -> float:
    return round(sum(WEIGHTS[k] * parts[k] for k in WEIGHTS), 4)


def assess(face, aligned_bgr: Optional[np.ndarray]) -> Dict:
    """Quality metadata for an insightface Face (needs bbox, kps, det_score;
    uses embedding + pose when present). Returns the fields stored on a face record."""
    x1, y1, x2, y2 = [float(v) for v in face.bbox[:4]]
    face_px = max(0.0, min(x2 - x1, y2 - y1))
    sharp = sharpness(aligned_bgr) if aligned_bgr is not None else 0.0
    pose = getattr(face, "pose", None)
    if pose is not None:
        pitch, yaw, roll = (float(v) for v in pose[:3])
    elif getattr(face, "kps", None) is not None:
        yaw, pitch = pose_from_kps(face.kps)
        roll = None
    else:
        yaw = pitch = roll = None
    emb_norm = float(face.embedding_norm) if getattr(face, "embedding", None) is not None else None
    parts = components(face_px, emb_norm, sharp, yaw, pitch)
    return {
        "quality_score": score(parts),
        "quality_version": QUALITY_VERSION,
        "quality_parts": {k: round(v, 3) for k, v in parts.items()},
        "det_score": round(float(face.det_score), 4),
        "face_px": round(face_px, 1),
        "sharpness": round(sharp, 1),
        "embedding_norm": None if emb_norm is None else round(emb_norm, 3),
        "pose": None if yaw is None else {"yaw": round(yaw, 1), "pitch": round(pitch, 1),
                                          "roll": None if roll is None else round(roll, 1)},
    }


def passes_gate(face, min_quality: float, quality: float) -> bool:
    x1, y1, x2, y2 = [float(v) for v in face.bbox[:4]]
    return (float(face.det_score) >= MIN_DET_SCORE
            and min(x2 - x1, y2 - y1) >= MIN_FACE_PX
            and quality >= min_quality)


def tier(quality: Optional[float]) -> Tuple[str, str]:
    """(key, label) for a quality score."""
    q = float(quality or 0.0)
    for lower, key, label in TIERS:
        if q >= lower:
            return key, label
    return TIERS[-1][1], TIERS[-1][2]
