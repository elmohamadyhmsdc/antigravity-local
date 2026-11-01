"""
Phase 6 (roadmap section 7.4): does a candidate skin patch show the same tattoo as the reference patch?

Plain OpenCV (AKAZE binary features + ratio test + RANSAC homography): no model, no download, nothing stored.
Mirror selfies flip a tattoo, so every candidate is also tried flipped; the phone sends the same body segment AND
the opposite segment as separate candidates, so a left/right swap is covered by the same call.

The output is evidence, not a decision: the phone treats a match as a SUGGESTION until Phase 0 shows precision.
"""

from typing import Dict, List, Optional, Sequence

import cv2
import numpy as np

MAX_SIDE = 400
RATIO = 0.8
RANSAC_PX = 4.0
MIN_MATCHES = 6
MAX_CANDIDATES = 64


def prepare(patch_bgr: np.ndarray) -> np.ndarray:
    """Grayscale, contrast-normalised, at most MAX_SIDE px."""
    gray = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2GRAY) if patch_bgr.ndim == 3 else patch_bgr
    h, w = gray.shape[:2]
    scale = MAX_SIDE / max(h, w)
    if scale < 1:
        gray = cv2.resize(gray, (max(1, int(w * scale)), max(1, int(h * scale))), interpolation=cv2.INTER_AREA)
    return cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4)).apply(gray)


def features(gray: np.ndarray):
    akaze = cv2.AKAZE_create()
    return akaze.detectAndCompute(gray, None)


def match(reference, candidate) -> Dict:
    """Inlier count / ratio of the homography between two (keypoints, descriptors) pairs."""
    (kp_a, des_a), (kp_b, des_b) = reference, candidate
    if des_a is None or des_b is None or len(kp_a) < MIN_MATCHES or len(kp_b) < MIN_MATCHES:
        return {"inliers": 0, "matches": 0, "inlier_ratio": 0.0}
    pairs = cv2.BFMatcher(cv2.NORM_HAMMING).knnMatch(des_a, des_b, k=2)
    good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < RATIO * n.distance]
    if len(good) < MIN_MATCHES:
        return {"inliers": 0, "matches": len(good), "inlier_ratio": 0.0}
    src = np.float32([kp_a[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([kp_b[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    homography, mask = cv2.findHomography(src, dst, cv2.RANSAC, RANSAC_PX)
    if homography is None or mask is None:
        return {"inliers": 0, "matches": len(good), "inlier_ratio": 0.0}
    inliers = int(mask.sum())
    return {"inliers": inliers, "matches": len(good), "inlier_ratio": round(inliers / len(good), 4)}


def match_patches(reference_bgr: np.ndarray, candidates_bgr: Sequence[np.ndarray]) -> List[Dict]:
    """One result per candidate: the better of straight / mirrored, with `mirrored` telling which."""
    ref = features(prepare(reference_bgr))
    results = []
    for patch in candidates_bgr:
        if patch is None or patch.size == 0:
            results.append({"inliers": 0, "matches": 0, "inlier_ratio": 0.0, "mirrored": False})
            continue
        gray = prepare(patch)
        straight = match(ref, features(gray))
        flipped = match(ref, features(cv2.flip(gray, 1)))
        mirrored = flipped["inliers"] > straight["inliers"]
        best = dict(flipped if mirrored else straight)
        best["mirrored"] = mirrored
        results.append(best)
    return results


def decode_patch(data: bytes) -> Optional[np.ndarray]:
    arr = np.frombuffer(data, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    return img if img is not None and img.size else None
