"""Face-independent character appearance, using the installed HumanArt body boxes.

This is a versioned visual descriptor, not an ArcFace embedding or a character-name
classifier. Enable it for illustrated sources. Head/hair, upper/lower clothing,
edge details and foreground silhouette contribute independently. No downloads.
Keep similarity in sync with mobile/lib/domain/scan/character_descriptor.dart.
"""
from dataclasses import dataclass

import cv2
import numpy as np

MODEL_ID = "character-appearance@1"
DIM = 160
AUTO_MATCH = 0.93
MATCH_MARGIN = 0.06


@dataclass
class Character:
    bbox: np.ndarray
    score: float
    descriptor: np.ndarray
    model_id: str = MODEL_ID


def describe(img, bbox):
    h, w = img.shape[:2]
    box = np.asarray(bbox, dtype=float)
    if box.shape != (4,) or not np.isfinite(box).all():
        return None
    x1, y1 = np.floor(box[:2]).astype(int)
    x2, y2 = np.ceil(box[2:]).astype(int)
    x1, x2 = np.clip([x1, x2], 0, w)
    y1, y2 = np.clip([y1, y2], 0, h)
    crop = img[y1:y2, x1:x2]
    if min(crop.shape[:2], default=0) < 16:
        return None
    crop = cv2.resize(crop, (64, 128), interpolation=cv2.INTER_AREA)
    # Mask colours connected to the border. Interior pixels of the same colour
    # remain foreground (e.g. white clothes on a white background).
    lab = cv2.cvtColor(crop, cv2.COLOR_BGR2LAB).astype(np.float32)
    border = np.concatenate((lab[0], lab[-1], lab[:, 0], lab[:, -1]))
    bg = np.median(border, axis=0)
    near_bg = (np.linalg.norm(lab - bg, axis=2) < 18).astype(np.uint8)
    _, labels = cv2.connectedComponents(near_bg, connectivity=4)
    outside = np.unique(np.concatenate((labels[0], labels[-1], labels[:, 0], labels[:, -1])))
    outside = outside[outside != 0]
    mask = (~np.isin(labels, outside)).astype(np.uint8)
    if mask.mean() < 0.08:
        return None
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    edges = cv2.magnitude(cv2.Sobel(gray, cv2.CV_32F, 1, 0),
                          cv2.Sobel(gray, cv2.CV_32F, 0, 1)) * mask
    parts = []
    for ya, yb in ((0, 39), (36, 84), (80, 128)):
        region = hsv[ya:yb, 8:56]
        selected = mask[ya:yb, 8:56].astype(bool)
        pixels = region[selected]
        hist = np.zeros(32, np.float32)
        if len(pixels):
            chromatic = (pixels[:, 1] >= 48) & (pixels[:, 2] >= 40)
            bins = np.where(chromatic,
                            np.minimum(pixels[:, 0].astype(int) * 12 // 180, 11) * 2
                            + (pixels[:, 1] >= 160),
                            24 + np.minimum(pixels[:, 2].astype(int) * 8 // 256, 7))
            hist = np.bincount(bins, minlength=32).astype(np.float32)
            hist /= hist.sum()
        detail = cv2.resize(edges[ya:yb, 8:56], (4, 4), interpolation=cv2.INTER_AREA).flatten()
        norm = np.linalg.norm(detail)
        if norm > 0:
            detail /= norm
        parts.extend((hist, detail))
    silhouette = cv2.resize(mask.astype(np.float32), (2, 8), interpolation=cv2.INTER_AREA).flatten()
    norm = np.linalg.norm(silhouette)
    if norm > 0:
        silhouette /= norm
    return np.concatenate((*parts, silhouette)).astype(np.float32)


def similarity(left, right):
    a, b = np.asarray(left, dtype=float), np.asarray(right, dtype=float)
    if a.shape != (DIM,) or b.shape != (DIM,) or not np.isfinite(a).all() or not np.isfinite(b).all():
        return 0.0
    if np.any(a < 0) or np.any(b < 0):
        return 0.0
    scores = []
    for start in (0, 48, 96):
        # A hidden/missing region cannot provide identity evidence.
        ah, bh = a[start:start + 32], b[start:start + 32]
        if ah.sum() < 0.5 or bh.sum() < 0.5:
            return 0.0
        colour = np.sqrt(ah * bh).sum() / np.sqrt(ah.sum() * bh.sum())
        ae, be = a[start + 32:start + 48], b[start + 32:start + 48]
        den = np.linalg.norm(ae) * np.linalg.norm(be)
        detail = float(ae @ be / den) if den > 0 else 0.0
        scores.append(0.8 * colour + 0.2 * detail)
    # Hair/head disagreement blocks a merge despite a shared uniform.
    if scores[0] < 0.80 or scores[1] < 0.75:
        return 0.0
    den = np.linalg.norm(a[144:]) * np.linalg.norm(b[144:])
    shape = float(a[144:] @ b[144:] / den) if den > 0 else 0.0
    return float(np.clip(.35 * scores[0] + .30 * scores[1] + .20 * scores[2] + .15 * shape, 0, 1))


def detect_characters(img, bodies, anime_faces=None):
    """Detect characters from bodies and/or anime face detections."""
    found = []
    h, w = img.shape[:2]
    used_bodies = set()

    # 1. If anime faces were detected, associate them with bodies or expand to upper torso
    if anime_faces:
        for af in anime_faces:
            abox = af["bbox"] if isinstance(af, dict) else af.bbox
            ascore = float(af["score"] if isinstance(af, dict) else af.score)

            # Look for a body that contains the centre of the anime face
            cx = (abox[0] + abox[2]) / 2.0
            cy = (abox[1] + abox[3]) / 2.0
            matched_body_idx = None
            for bi, b in enumerate(bodies):
                bbox = b.bbox
                if bbox[0] <= cx <= bbox[2] and bbox[1] <= cy <= bbox[3]:
                    matched_body_idx = bi
                    break

            if matched_body_idx is not None:
                used_bodies.add(matched_body_idx)
                char_box = bodies[matched_body_idx].bbox
            else:
                # Expand face box to include hair and upper torso
                bw = abox[2] - abox[0]
                bh = abox[3] - abox[1]
                x1 = max(0.0, abox[0] - bw * 0.25)
                y1 = max(0.0, abox[1] - bh * 0.25)
                x2 = min(float(w), abox[2] + bw * 0.25)
                y2 = min(float(h), abox[3] + bh * 1.5)
                char_box = np.array([x1, y1, x2, y2], dtype=np.float32)

            descriptor = describe(img, char_box)
            if descriptor is None:
                descriptor = describe(img, abox)
            if descriptor is not None:
                found.append(Character(np.asarray(char_box, np.float32), ascore, descriptor))

    # 2. For any bodies not already matched to an anime face, process them
    for bi, body in enumerate(bodies):
        if bi in used_bodies:
            continue
        descriptor = describe(img, body.bbox)
        if descriptor is not None:
            found.append(Character(np.asarray(body.bbox, np.float32), float(body.score), descriptor))

    return found
