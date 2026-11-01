"""Face-independent character appearance, using the installed HumanArt body boxes.

This is a versioned visual descriptor, not an ArcFace embedding or a character-name
classifier. Enable it for illustrated sources. Head/hair, upper/lower clothing,
edge details and foreground silhouette contribute independently. No downloads.
Keep similarity in sync with mobile/lib/domain/scan/character_descriptor.dart.
"""
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np

MODEL_ID = "character-appearance@1"
DIM = 160
AUTO_MATCH = 0.93
MATCH_MARGIN = 0.06


@dataclass
class Character:
    """One drawn figure. Like a person it can have a face, a body, or both:
    `bbox` is the whole figure, the face_* fields the anime face (with its CCIP
    identity embedding once `attach_identity` ran) and the body_* fields the body."""
    bbox: np.ndarray
    score: float
    descriptor: np.ndarray
    model_id: str = MODEL_ID
    face_bbox: Optional[np.ndarray] = None
    face_score: float = 0.0
    face_embedding: Optional[np.ndarray] = None  # CCIP, unit length
    body_bbox: Optional[np.ndarray] = None
    body_score: float = 0.0
    body_kpts: Optional[np.ndarray] = None
    body_kpt_scores: Optional[np.ndarray] = None
    body_appearance: Optional[np.ndarray] = None  # outfit descriptor, as for people
    body_outline: Optional[np.ndarray] = None  # exact silhouette (outlines.OutlineEngine), as for people


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


def detect_characters(img, bodies, anime_faces=None, keep=None):
    """Characters from anime faces and/or bodies. A face gets its body the way a person's
    face does (person_linking.associate_faces_bodies, one body per face); a face without
    one gets its hair and upper torso. `keep(body)` true = a figure the user called a
    character, kept even when its colours give no descriptor."""
    import person_linking as pl
    found = []
    h, w = img.shape[:2]
    faces = [(np.asarray(af["bbox"] if isinstance(af, dict) else af.bbox, np.float32),
              float(af["score"] if isinstance(af, dict) else af.score)) for af in (anime_faces or [])]
    body_of = {fi: bi for fi, bi, _ in pl.associate_faces_bodies([b for b, _ in faces], bodies)}         if faces and bodies else {}
    used_bodies = set(body_of.values())

    for fi, (abox, ascore) in enumerate(faces):
        matched_body = bodies[body_of[fi]] if fi in body_of else None
        if matched_body is not None:
            char_box = matched_body.bbox
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
        if descriptor is None:
            descriptor = np.zeros(DIM, np.float32)  # the face carries the identity
        found.append(Character(np.asarray(char_box, np.float32), ascore, descriptor,
                               face_bbox=abox, face_score=ascore, **_body_fields(matched_body)))

    # Bodies no face took are faceless figures.
    for bi, body in enumerate(bodies):
        if bi in used_bodies:
            continue
        descriptor = describe(img, body.bbox)
        if descriptor is None and keep is not None and keep(body):
            descriptor = np.zeros(DIM, np.float32)
        if descriptor is not None:
            found.append(Character(np.asarray(body.bbox, np.float32), float(body.score), descriptor,
                                   **_body_fields(body)))

    return found


def _body_fields(body):
    if body is None:
        return {}
    kpts = getattr(body, "kpts", None)
    scores = getattr(body, "kpt_scores", None)
    return dict(body_bbox=np.asarray(body.bbox, np.float32), body_score=float(body.score),
                body_kpts=None if kpts is None else np.asarray(kpts, np.float32),
                body_kpt_scores=None if scores is None else np.asarray(scores, np.float32))


def attach_identity(img, characters, embedder=None):
    """Give every character what a person has: a face identity embedding (CCIP, from the
    anime face) and a body outfit descriptor. Without the CCIP model a character keeps
    its appearance descriptor only."""
    import person_linking as pl
    for c in characters:
        if c.body_bbox is not None:
            c.body_appearance = pl.appearance_descriptor(img, c.body_bbox, c.body_kpts, c.body_kpt_scores)
        if embedder is not None and c.face_bbox is not None:
            l, t, r, b = _portrait(c.face_bbox, img.shape[1], img.shape[0])
            crop = img[t:b, l:r]
            if min(crop.shape[:2], default=0) >= 2:
                c.face_embedding = embedder.embed_crop(crop)
    return characters


def _portrait(bbox, w, h):
    from character_embedder import asymmetric_ccip_crop
    return asymmetric_ccip_crop([float(v) for v in bbox], w, h)
