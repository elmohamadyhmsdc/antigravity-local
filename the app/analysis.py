"""
Frame analysis - the pure "what is in this picture?" step shared by the gallery
scanner and the mobile API.

`analyze_frame` runs everything that only needs the pixels:

    detect faces (multi-scale) -> embed -> quality v2 -> gate
    drop drawn (anime/cartoon) and other non-human faces - never a person
    detect bodies (+17 keypoints) -> outfit descriptor
    associate faces with bodies

and returns the raw results. It never touches the database, the filesystem or the
wire format - LibraryScanner stores the result in the JSON library, mobile_api
serialises it for the phone. Models are passed in (an insightface FaceAnalysis
and a body_detector.BodyAnalyzer), so this module is unit-testable with fakes.

The crop helpers live here too, so a "face crop" means the same thing (20 % pad)
in the gallery and in the API.
"""

import os
import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Tuple, Any

import cv2
import numpy as np

import drawn_faces
import face_quality
import person_linking as pl

_anime_detector: Optional[Any] = None


def get_anime_detector():
    """Lazily load AnimeFaceDetector if model exists."""
    global _anime_detector
    if _anime_detector is None:
        model_path = os.path.join(os.path.dirname(__file__), "models", "anime_face_detect.onnx")
        if os.path.exists(model_path):
            try:
                from anime_detector import AnimeFaceDetector
                _anime_detector = AnimeFaceDetector(model_path)
            except Exception:
                _anime_detector = None
    return _anime_detector


_ccip_embedder: Optional[Any] = None


def get_ccip_embedder():
    """Lazily load the CCIP character identity model if it is installed."""
    global _ccip_embedder
    if _ccip_embedder is None:
        model_path = os.path.join(os.path.dirname(__file__), "models", "ccip_character.onnx")
        if os.path.exists(model_path):
            from character_embedder import CcipEmbedder
            _ccip_embedder = CcipEmbedder(model_path)
    return _ccip_embedder


@dataclass
class AnalyzeOptions:
    """The subset of ScanOptions analysis needs. Any object with these three
    attributes (e.g. library_scanner.ScanOptions) works as `options`."""
    min_face_quality: float = face_quality.DEFAULT_MIN_QUALITY
    detect_bodies: bool = True
    body_score: float = 0.5
    detect_characters: bool = False
    outlines: bool = False
    # In character mode, a body with no face in a frame without real faces is a character.
    # False (photos the user did not mark illustrated): only when the frame shows drawn faces.
    faceless_characters: bool = True
    # The user's corrections. force_kind 'person' | 'character' is the whole frame;
    # kind_overrides are (kind, 'face' | 'body', (x1, y1, x2, y2) normalised) for single
    # detections and win over force_kind.
    force_kind: Optional[str] = None
    kind_overrides: tuple = ()


@dataclass
class FrameAnalysis:
    faces: list                                   # insightface Face (bbox, kps, det_score, embedding, pose?)
    quality: List[Dict]                           # face_quality.assess() per face
    passes_gate: List[bool]                       # det score, size and min quality (what gets stored as a gallery face)
    bodies: list                                  # body_detector.Body
    appearances: List[Optional[np.ndarray]]       # outfit descriptor per body (80 floats) or None
    pairs: List[Tuple[int, int, float]]           # (face_index, body_index, score)
    image_w: int = 0
    image_h: int = 0
    timings_ms: Dict[str, float] = field(default_factory=dict)
    characters: list = field(default_factory=list)
    face_outlines: list = field(default_factory=list)
    body_outlines: list = field(default_factory=list)
    forced: List[bool] = field(default_factory=list)  # per face: the user said this is a person

    @property
    def body_of_face(self) -> Dict[int, int]:
        return {fi: bi for fi, bi, _ in self.pairs}

    @property
    def face_of_body(self) -> Dict[int, int]:
        return {bi: fi for fi, bi, _ in self.pairs}


# --- detection ---------------------------------------------------------------

# In anime/cartoon sources, a face at least this good (face_quality v2) that is not drawn
# (drawn_faces) counts as a real person. Above the 0.40 store gate on purpose: a borderline
# face stays a character.
REAL_FACE_MIN_QUALITY = 0.50


def _centre_inside(face_box, box) -> bool:
    cx, cy = (float(face_box[0]) + float(face_box[2])) / 2, (float(face_box[1]) + float(face_box[3])) / 2
    return float(box[0]) <= cx <= float(box[2]) and float(box[1]) <= cy <= float(box[3])


def det_sizes(img) -> List[Tuple[int, int]]:
    """Small scale catches faces that fill the frame, large ones catch small
    faces in big photos."""
    long_side = max(img.shape[:2])
    sizes = [(128, 128), (640, 640)]
    if long_side >= 1600:
        sizes.append((1280, 1280))
    return sizes


def detect_faces(face_app, img) -> list:
    """insightface's FaceAnalysis.get, but with per-image detector scales."""
    from insightface.app.common import Face
    sizes = det_sizes(img)
    bboxes, kpss = face_app.det_model.detect(img, input_size=sizes, max_num=0)
    # Preview frames may be smaller than 1600 px. If the ordinary passes found
    # nothing, try the finer detector grid before declaring the frame faceless.
    # Keep the same confidence threshold and avoid repeating an existing pass.
    if bboxes.shape[0] == 0 and (1280, 1280) not in sizes:
        bboxes, kpss = face_app.det_model.detect(img, input_size=[(1280, 1280)], max_num=0)
    faces = []
    for i in range(bboxes.shape[0]):
        face = Face(bbox=bboxes[i, 0:4], kps=kpss[i] if kpss is not None else None,
                    det_score=bboxes[i, 4])
        for taskname, model in face_app.models.items():
            if taskname != "detection":
                model.get(img, face)
        faces.append(face)
    return faces


def assess_face(img, face) -> Dict:
    from insightface.utils import face_align
    aligned = None
    if face.kps is not None:
        try:
            aligned = face_align.norm_crop(img, face.kps, 112)
        except Exception:
            aligned = None
    return face_quality.assess(face, aligned)


# --- one frame ---------------------------------------------------------------

def analyze_frame(face_app, body, img, options,
                  detect: Optional[Callable] = None,
                  assess: Optional[Callable] = None) -> FrameAnalysis:
    """Everything the pixels of one BGR frame can tell us.

    face_app  insightface FaceAnalysis (buffalo_l: detection, recognition, landmark_3d_68)
    body      body_detector.BodyAnalyzer, or None to skip bodies
    options   .min_face_quality, .detect_bodies, .body_score (AnalyzeOptions or ScanOptions)
    detect / assess
              optional replacements for detect_faces(face_app, img) / assess_face(img, face).
              LibraryScanner routes through its own overridable methods this way;
              `face_app` is not used (and may be None) when `detect` is given.
    """
    can_detect = detect is not None or face_app is not None
    detect = detect or (lambda im: detect_faces(face_app, im))
    assess = assess or assess_face
    timings: Dict[str, float] = {}
    h, w = img.shape[:2]
    from face_routing import box_iou, overlaps_real_face
    force = getattr(options, "force_kind", None)
    overrides = [(kind, part, np.array([b[0] * w, b[1] * h, b[2] * w, b[3] * h], np.float32))
                 for kind, part, b in (getattr(options, "kind_overrides", None) or ())]

    def kind_of(box, part):
        """The user's kind for this detection: its own correction, else the frame's, else None."""
        for kind, p, obox in reversed(overrides):
            if p == part and (overlaps_real_face(box, obox) if part == "face" else box_iou(box, obox) >= 0.5):
                return kind
        return force

    want_characters = any(k == "character" for k, _, _ in overrides) or (
        force != "person" and (getattr(options, "detect_characters", False) or force == "character"))

    t = time.perf_counter()
    # Character mode still looks for faces: a clear real face is a person, not a drawing.
    faces = detect(img) if can_detect or not want_characters else []
    if can_detect:
        # A face the user called a person where the full-frame pass found none: look closer.
        for _, part, obox in overrides:
            if part == "face" and kind_of(obox, "face") == "person" \
                    and not any(overlaps_real_face(f.bbox, obox) for f in faces):
                found = _face_in_region(detect, img, obox)
                if found is not None:
                    faces.append(found)
    timings["detect"] = (time.perf_counter() - t) * 1000.0
    t = time.perf_counter()
    quality = [assess(img, f) for f in faces]
    timings["quality"] = (time.perf_counter() - t) * 1000.0
    passes = [face_quality.passes_gate(f, options.min_face_quality, q["quality_score"])
              for f, q in zip(faces, quality)]
    face_kinds = [kind_of(f.bbox, "face") for f in faces]
    # Drawn faces get good quality scores too; the embedding tells them apart.
    drawn = [k != "person" and drawn_faces.is_drawn(getattr(f, "embedding", None))
             for f, k in zip(faces, face_kinds)]
    for i, f in enumerate(faces):
        # A single face the user called a person is stored even below the gate.
        if face_kinds[i] == "person" and any(p == "face" and overlaps_real_face(f.bbox, b)
                                             for _, p, b in overrides):
            passes[i] = True
    forced = [k == "person" for k in face_kinds]

    # Detect anime faces if characters are requested
    anime_faces = []
    if want_characters:
        ad = get_anime_detector()
        if ad is not None:
            try:
                raw_anime = ad.detect(img, score_thresh=0.55)
                # Real face veto at 0.40 quality/det threshold
                veto_boxes = [f.bbox for i, f in enumerate(faces)
                              if face_kinds[i] == "person" or (face_kinds[i] is None and passes[i]
                                                                and not drawn[i]
                                                                and quality[i]["quality_score"] >= 0.40)]
                anime_faces = [a for a in raw_anime
                               if not any(overlaps_real_face(rbox, a["bbox"]) for rbox in veto_boxes)
                               and kind_of(a["bbox"], "face") != "person"]
            except Exception:
                anime_faces = []
        # A human face the user called a character is that character's face.
        for i, f in enumerate(faces):
            if face_kinds[i] == "character":
                anime_faces = [a for a in anime_faces if not overlaps_real_face(f.bbox, a["bbox"])]
                anime_faces.append({"bbox": np.asarray(f.bbox, np.float32), "score": float(f.det_score)})

    bodies: list = []
    if want_characters and (body is None or not getattr(body, "available", False)):
        raise RuntimeError("Character detection requires the installed HumanArt body models.")
    if (options.detect_bodies or want_characters) and body is not None and body.available:
        t = time.perf_counter()
        bodies = body.analyze(img, score_thr=options.body_score)
        timings["body"] = (time.perf_counter() - t) * 1000.0
    body_kinds = [kind_of(b.bbox, "body") for b in bodies]
    characters = []
    if want_characters:
        from character_detection import attach_identity, detect_characters
        t = time.perf_counter()
        candidates = [i for i, k in enumerate(body_kinds) if k != "person"]
        characters = detect_characters(img, [bodies[i] for i in candidates], anime_faces=anime_faces,
                                       keep=lambda b: kind_of(b.bbox, "body") == "character")
        real = [i for i, f in enumerate(faces)
                if face_kinds[i] == "person" or (face_kinds[i] is None and passes[i] and not drawn[i]
                                                 and quality[i]["quality_score"] >= REAL_FACE_MIN_QUALITY)]
        # Without real faces, a faceless figure is a character only in a drawn source or
        # next to drawn faces; a person seen from behind in a photo stays a person.
        drawn_here = bool(anime_faces) or any(d and k is None for d, k in zip(drawn, face_kinds))
        faceless_ok = not real and (getattr(options, "faceless_characters", True) or drawn_here)

        def keep(c):
            if c.body_bbox is not None and kind_of(c.body_bbox, "body") == "character":
                return True
            # A body around a clear real face is a real person: keep the face (it goes to
            # People) and drop that "character".
            if any(_centre_inside(faces[i].bbox, c.bbox) for i in real):
                return False
            return c.face_bbox is not None or faceless_ok

        characters = [c for c in characters if keep(c)]
        attach_identity(img, characters, get_ccip_embedder())
        timings["characters"] = (time.perf_counter() - t) * 1000.0
        drawn_face_boxes = [f.bbox for i, f in enumerate(faces) if drawn[i] and face_kinds[i] is None]
        faces = [faces[i] for i in real]
        quality = [quality[i] for i in real]
        passes = [passes[i] for i in real]
        forced = [forced[i] for i in real]
        # Illustrated characters never become human body identities,
        # but real human bodies must be preserved when detect_bodies is requested.
        char_body_boxes = [c.body_bbox if getattr(c, "body_bbox", None) is not None else c.bbox
                           for c in characters]

        def is_char_body(b):
            if any(np.allclose(b.bbox, cbox, atol=1.0) for cbox in char_body_boxes):
                return True
            return any(_centre_inside(dbox, b.bbox) for dbox in drawn_face_boxes)

        bodies = [b for b, k in zip(bodies, body_kinds)
                  if k == "person" or (options.detect_bodies and not is_char_body(b))]
    pairs = pl.associate_faces_bodies([f.bbox for f in faces], bodies,
                                      face_kps=[f.kps for f in faces]) if bodies else []
    if any(drawn) and not want_characters:
        # A drawn face is no person, and the body around it is a drawn figure.
        drawn_bodies = {bi for fi, bi, _ in pairs if drawn[fi] and kind_of(bodies[bi].bbox, "body") != "person"}
        face_at = {old: new for new, old in enumerate(i for i in range(len(faces)) if not drawn[i])}
        body_at = {old: new for new, old in enumerate(i for i in range(len(bodies)) if i not in drawn_bodies)}
        pairs = [(face_at[fi], body_at[bi], s) for fi, bi, s in pairs if fi in face_at and bi in body_at]
        faces = [f for i, f in enumerate(faces) if i in face_at]
        quality = [q for i, q in enumerate(quality) if i in face_at]
        passes = [g for i, g in enumerate(passes) if i in face_at]
        forced = [g for i, g in enumerate(forced) if i in face_at]
        bodies = [b for i, b in enumerate(bodies) if i in body_at]
    appearances = [pl.appearance_descriptor(img, b.bbox, b.kpts, b.kpt_scores) for b in bodies]

    return FrameAnalysis(faces=faces, quality=quality, passes_gate=passes, bodies=bodies,
                         appearances=appearances, pairs=list(pairs), image_w=w, image_h=h, characters=characters,
                         timings_ms={k: round(v, 1) for k, v in timings.items()}, forced=forced)


def _face_in_region(detect, img, box):
    """The best face found around `box` (twice its size each way), in frame coordinates."""
    h, w = img.shape[:2]
    x1, y1, x2, y2 = [float(v) for v in box]
    bw, bh = max(x2 - x1, 1.0), max(y2 - y1, 1.0)
    left, top = int(max(0.0, x1 - bw)), int(max(0.0, y1 - bh))
    right, bottom = int(min(float(w), x2 + bw)), int(min(float(h), y2 + bh))
    if min(right - left, bottom - top) < 16:
        return None
    from face_routing import overlaps_real_face
    offset = np.array([left, top], np.float32)
    best = None
    for f in detect(np.ascontiguousarray(img[top:bottom, left:right])):
        f.bbox = np.asarray(f.bbox, np.float32) + np.tile(offset, 2)
        if getattr(f, "kps", None) is not None:
            f.kps = np.asarray(f.kps, np.float32) + offset
        if overlaps_real_face(f.bbox, box) and (best is None or f.det_score > best.det_score):
            best = f
    return best


# --- crops -------------------------------------------------------------------

def face_crop(img, face, pad_ratio: float = 0.2):
    """The face box plus `pad_ratio` of its longer side on every side."""
    h, w = img.shape[:2]
    x1, y1, x2, y2 = [int(v) for v in face.bbox[:4]]
    pad = int(max(x2 - x1, y2 - y1) * pad_ratio)
    return img[max(0, y1 - pad):min(h, y2 + pad), max(0, x1 - pad):min(w, x2 + pad)].copy()


def body_crop(img, bbox, max_height: int = 512):
    h, w = img.shape[:2]
    x1, y1, x2, y2 = [int(v) for v in bbox[:4]]
    pad_x, pad_y = int((x2 - x1) * 0.06), int((y2 - y1) * 0.04)
    crop = img[max(0, y1 - pad_y):min(h, y2 + pad_y), max(0, x1 - pad_x):min(w, x2 + pad_x)].copy()
    if crop.shape[0] > max_height:
        scale = max_height / crop.shape[0]
        crop = cv2.resize(crop, (max(1, int(crop.shape[1] * scale)), max_height), interpolation=cv2.INTER_AREA)
    return crop
