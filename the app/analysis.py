"""
Frame analysis - the pure "what is in this picture?" step shared by the gallery
scanner and the mobile API.

`analyze_frame` runs everything that only needs the pixels:

    detect faces (multi-scale) -> embed -> quality v2 -> gate
    detect bodies (+17 keypoints) -> outfit descriptor
    associate faces with bodies

and returns the raw results. It never touches the database, the filesystem or the
wire format - LibraryScanner stores the result in the JSON library, mobile_api
serialises it for the phone. Models are passed in (an insightface FaceAnalysis
and a body_detector.BodyAnalyzer), so this module is unit-testable with fakes.

The crop helpers live here too, so a "face crop" means the same thing (20 % pad)
in the gallery and in the API.
"""

import time
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional, Tuple

import cv2
import numpy as np

import face_quality
import person_linking as pl


@dataclass
class AnalyzeOptions:
    """The subset of ScanOptions analysis needs. Any object with these three
    attributes (e.g. library_scanner.ScanOptions) works as `options`."""
    min_face_quality: float = face_quality.DEFAULT_MIN_QUALITY
    detect_bodies: bool = True
    body_score: float = 0.5
    detect_characters: bool = False


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

    @property
    def body_of_face(self) -> Dict[int, int]:
        return {fi: bi for fi, bi, _ in self.pairs}

    @property
    def face_of_body(self) -> Dict[int, int]:
        return {bi: fi for fi, bi, _ in self.pairs}


# --- detection ---------------------------------------------------------------

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
    detect = detect or (lambda im: detect_faces(face_app, im))
    assess = assess or assess_face
    timings: Dict[str, float] = {}
    want_characters = getattr(options, "detect_characters", False)

    t = time.perf_counter()
    faces = [] if want_characters else detect(img)
    timings["detect"] = (time.perf_counter() - t) * 1000.0
    t = time.perf_counter()
    quality = [assess(img, f) for f in faces]
    timings["quality"] = (time.perf_counter() - t) * 1000.0
    passes = [face_quality.passes_gate(f, options.min_face_quality, q["quality_score"])
              for f, q in zip(faces, quality)]

    bodies: list = []
    if want_characters and (body is None or not body.available):
        raise RuntimeError("Character detection requires the installed HumanArt body models.")
    if (options.detect_bodies or want_characters) and body is not None and body.available:
        t = time.perf_counter()
        bodies = body.analyze(img, score_thr=options.body_score)
        timings["body"] = (time.perf_counter() - t) * 1000.0
    characters = []
    if want_characters:
        from character_detection import detect_characters
        t = time.perf_counter()
        characters = detect_characters(img, bodies)
        timings["characters"] = (time.perf_counter() - t) * 1000.0
        # Illustrated characters never become human face/body identities.
        faces, quality, passes, bodies = [], [], [], []
    appearances = [pl.appearance_descriptor(img, b.bbox, b.kpts, b.kpt_scores) for b in bodies]
    pairs = pl.associate_faces_bodies([f.bbox for f in faces], bodies,
                                      face_kps=[f.kps for f in faces]) if bodies else []

    h, w = img.shape[:2]
    return FrameAnalysis(faces=faces, quality=quality, passes_gate=passes, bodies=bodies,
                         appearances=appearances, pairs=list(pairs), image_w=w, image_h=h, characters=characters,
                         timings_ms={k: round(v, 1) for k, v in timings.items()})


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
