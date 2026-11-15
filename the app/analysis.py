"""
Frame analysis - the pure "what is in this picture?" step shared by the gallery
scanner and the mobile API.

`analyze_frame` runs everything that only needs the pixels:

    detect faces (multi-scale) -> embed -> quality v2 -> gate
    drop drawn (anime/cartoon) and other non-human faces - never a person; in character
    mode a drawn face is the character's face, boxed by this same detector
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
    # Allow pose-supported faceless characters in an explicitly illustrated source.
    faceless_characters: bool = True
    # The user's corrections. force_kind 'person' | 'character' is the whole frame;
    # kind_overrides are (kind, 'face' | 'body', (x1, y1, x2, y2) normalised) for single
    # detections and win over force_kind.
    force_kind: Optional[str] = None
    kind_overrides: tuple = ()
    # Roadmap section 8: also return exposed / covered body-part regions (NudeNet). Off by default;
    # engines.InsightEngines.analyze runs it after analyze_frame, so analyze_frame ignores it.
    sensitive: bool = False
    # Roadmap 7.5 (Phase 8): DINOv2 chest / lower-body embeddings + morphology per body. Implies the regions.
    body_embeddings: bool = False


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
    # None = not requested. Else sensitive_detection regions (pixels) with `body_index`.
    sensitive: Optional[list] = None
    # None = not requested. Else one dict per body: chest_embedding, buttocks_embedding (base64) and morphology.
    body_embeddings: Optional[list] = None
    # Same two, for the bodies of drawn characters (aligned with `characters`; None entries = no body).
    # Characters get exactly what people get: exposed / covered regions, chest / lower-body vectors, morphology.
    character_body_embeddings: Optional[list] = None

    @property
    def body_of_face(self) -> Dict[int, int]:
        return {fi: bi for fi, bi, _ in self.pairs}

    @property
    def face_of_body(self) -> Dict[int, int]:
        return {bi: fi for fi, bi, _ in self.pairs}


# --- detection ---------------------------------------------------------------

# Small detections can veto a cartoon false positive before they are large enough to store.
DRAWN_TEST_MIN_PX = 48
TINY_REAL_FACE_PX = 24
TINY_REAL_FACE_DET = 0.70
MIN_CHARACTER_FACE_PX = 32
ANIME_CANDIDATE_SCORE = 0.55
ANIME_ALONE_SCORE = 0.80
ANIME_ILLUSTRATED_SCORE = 0.70


def _character_face_box(box) -> bool:
    box = np.asarray(box, dtype=float)
    if box.shape != (4,) or not np.isfinite(box).all():
        return False
    w, h = box[2:] - box[:2]
    return bool(min(w, h) >= MIN_CHARACTER_FACE_PX and 0.50 <= w / h <= 1.65)


def _face_landmarks(face) -> bool:
    """Two distinct eyes and a mouth separated from the eye line, even for a tilted head."""
    pts = np.asarray(getattr(face, "kps", None), dtype=float)
    box = np.asarray(face.bbox, dtype=float)
    if pts.shape != (5, 2) or not np.isfinite(pts).all() or not _character_face_box(box):
        return False
    size = box[2:] - box[:2]
    w, h = size
    pad = 0.15 * size
    if np.any(pts < box[:2] - pad) or np.any(pts > box[2:] + pad):
        return False
    eye_axis = pts[1] - pts[0]
    eye_distance = np.linalg.norm(eye_axis)
    if eye_distance < 0.12 * w:
        return False
    down = np.array([-eye_axis[1], eye_axis[0]]) / eye_distance
    eye_mid = (pts[0] + pts[1]) / 2
    nose_depth = float((pts[2] - eye_mid) @ down)
    mouth_depth = float(((pts[3] + pts[4]) / 2 - eye_mid) @ down)
    return 0.02 * h <= nose_depth < mouth_depth and mouth_depth >= 0.15 * h


def _body_pose(body):
    points = np.asarray(getattr(body, "kpts", None), dtype=float)
    scores = np.asarray(getattr(body, "kpt_scores", None), dtype=float)
    if points.shape != (17, 2) or scores.shape != (17,):
        return None
    visible = (scores >= 0.5) & np.isfinite(points).all(axis=1)
    return points, visible


def _character_body_pose(body) -> bool:
    """A faceless figure needs torso evidence or a strong full-height box without pose."""
    w, h = np.asarray(body.bbox[2:]) - body.bbox[:2]
    if not np.isfinite([w, h]).all() or min(w, h) < MIN_CHARACTER_FACE_PX:
        return False
    pose = _body_pose(body)
    if pose is None:
        return body.score >= 0.85 and h >= 1.3 * w
    points, visible = pose
    shoulders = points[5:7][visible[5:7]]
    hips = points[11:13][visible[11:13]]
    if not len(shoulders) or not len(hips) or len(shoulders) + len(hips) < 3:
        return False
    return np.linalg.norm(hips.mean(axis=0) - shoulders.mean(axis=0)) >= 0.12 * h


def _at_wrist_without_head(box, body) -> bool:
    """Reject automatic face boxes over a visible hand when the head is elsewhere."""
    pose = _body_pose(body)
    if pose is None:
        return False
    points, visible = pose
    heads = points[:5][visible[:5]]
    wrists = points[9:11][visible[9:11]]
    if len(heads) < 2 or not len(wrists):
        return False
    lower, upper = np.asarray(box[:2]), np.asarray(box[2:])

    def inside(pts, padding):
        return np.any(np.all((pts >= lower - padding) & (pts <= upper + padding), axis=1))

    return inside(wrists, 0) and not inside(heads, 0.2 * (upper - lower))


def _box_px(box) -> float:
    return float(min(float(box[2]) - float(box[0]), float(box[3]) - float(box[1])))


def drop_background(sizes, protected=None):
    """Which faces to keep in a crowd. With at least `face_quality.CROWD_MIN_FACES` faces in a frame, one
    markedly smaller than the biggest (under `BACKGROUND_REL` of it, and under `BACKGROUND_MAX_PX`) is
    background, not a subject: it is never stored, grouped or trained on. `protected` (the user's own
    corrections) always stay. Fewer faces: everything stays (an ordinary portrait or a couple)."""
    protected = protected or [False] * len(sizes)
    if len(sizes) < face_quality.CROWD_MIN_FACES:
        return [True] * len(sizes)
    biggest = max(sizes)
    floor = min(face_quality.BACKGROUND_MAX_PX, face_quality.BACKGROUND_REL * biggest)
    return [bool(protected[i]) or sizes[i] >= floor for i in range(len(sizes))]


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
    # Drawn faces get good quality scores too; the embedding tells them apart - but only on a face with
    # enough detail (tiny / blurred real faces drift toward the drawn direction).
    drawn = [k != "person" and _box_px(f.bbox) >= DRAWN_TEST_MIN_PX
             and drawn_faces.is_drawn(getattr(f, "embedding", None))
             for f, k in zip(faces, face_kinds)]
    for i, f in enumerate(faces):
        # A single face the user called a person is stored even below the gate.
        if face_kinds[i] == "person" and any(p == "face" and overlaps_real_face(f.bbox, b)
                                             for _, p, b in overrides):
            passes[i] = True
    forced = [k == "person" for k in face_kinds]
    # Crowds: faces far smaller than the biggest one are background, not subjects. Measured among the
    # people only: a big drawn face (a poster, a cartoon on TV) or one the user called a character is no
    # yardstick for the people in front of it (it used to make them all "background").
    sharp_idx = [i for i in range(len(faces)) if passes[i] and not drawn[i] and face_kinds[i] != "character"]
    keep_flags = drop_background([_box_px(faces[i].bbox) for i in sharp_idx], [forced[i] for i in sharp_idx])
    for i, keep in zip(sharp_idx, keep_flags):
        if not keep:
            passes[i] = False

    anime_faces = []
    illustrated_source = force == "character" or bool(getattr(options, "faceless_characters", True))
    real = []
    if want_characters:
        # An anime hit elsewhere in an image must never change how a real face is routed.
        real = [i for i, k in enumerate(face_kinds)
                if k == "person" or (k is None and passes[i] and not drawn[i])]
        real_ids = set(real)
        veto_boxes = [faces[i].bbox for i in real]
        if not illustrated_source:
            veto_boxes.extend(f.bbox for i, f in enumerate(faces)
                              if i not in real_ids and face_kinds[i] is None and not drawn[i]
                              and float(f.det_score) >= TINY_REAL_FACE_DET
                              and _box_px(f.bbox) >= TINY_REAL_FACE_PX)
        drawn_faces_with_landmarks = [
            (i, f) for i, f in enumerate(faces)
            if face_kinds[i] is None and drawn[i] and _face_landmarks(f)
        ]
        ad = get_anime_detector()
        raw_anime = []
        if ad is not None:
            try:
                raw_anime = ad.detect(img, score_thresh=ANIME_CANDIDATE_SCORE)
            except Exception:
                pass
        alone_score = ANIME_ILLUSTRATED_SCORE if illustrated_source else ANIME_ALONE_SCORE
        corroborated = set()
        for candidate in sorted(raw_anime, key=lambda a: -a["score"]):
            box, score = np.asarray(candidate["bbox"], dtype=float), float(candidate["score"])
            if box.shape != (4,) or not np.isfinite(box).all() or not np.isfinite(score) or _box_px(box) <= 0:
                continue
            kind = kind_of(box, "face")
            if kind == "person" or any(overlaps_real_face(rbox, box) for rbox in veto_boxes):
                continue
            if kind == "character":
                anime_faces.append({"bbox": box, "score": score})
                continue
            if score < ANIME_CANDIDATE_SCORE or not _character_face_box(box):
                continue
            match = next(((i, f) for i, f in drawn_faces_with_landmarks
                          if overlaps_real_face(f.bbox, box)), None)
            if match is not None:
                i, f = match
                if i not in corroborated:
                    anime_faces.append({"bbox": f.bbox, "score": max(float(f.det_score), score)})
                    corroborated.add(i)
            elif score >= alone_score:
                anime_faces.append({"bbox": box, "score": score})
        if illustrated_source:
            for i, f in drawn_faces_with_landmarks:
                if i not in corroborated and passes[i]:
                    anime_faces.append({"bbox": f.bbox, "score": float(f.det_score)})
        # A user's face correction takes precedence over the automatic evidence.
        for i, f in enumerate(faces):
            if face_kinds[i] == "character":
                anime_faces = [a for a in anime_faces if not overlaps_real_face(f.bbox, a["bbox"])]
                anime_faces.append({"bbox": f.bbox, "score": float(f.det_score)})

    bodies: list = []
    if want_characters and (body is None or not getattr(body, "available", False)):
        raise RuntimeError("Character detection requires the installed HumanArt body models.")
    if (options.detect_bodies or want_characters) and body is not None and body.available:
        t = time.perf_counter()
        bodies = body.analyze(img, score_thr=options.body_score)
        if anime_faces:
            anime_faces = [a for a in anime_faces if kind_of(a["bbox"], "face") == "character"
                           or not any(_at_wrist_without_head(a["bbox"], b) for b in bodies)]
            sizes = [_box_px(a["bbox"]) for a in anime_faces]
            marked = [kind_of(a["bbox"], "face") == "character" for a in anime_faces]
            anime_faces = [a for a, keep in zip(anime_faces, drop_background(sizes, marked)) if keep]
        if hasattr(body, "recover_for_faces"):
            # A face with no body is a person the whole-picture pass missed (small, partly hidden): look closer
            # at it. Faces the gate drops as crowd background are not worth a second look; drawn faces are.
            wanted = ([f.bbox for i, f in enumerate(faces) if (passes[i] and not drawn[i]) or forced[i]]
                      + [a["bbox"] for a in anime_faces])
            bodies = body.recover_for_faces(img, wanted, bodies, score_thr=options.body_score)
        timings["body"] = (time.perf_counter() - t) * 1000.0
    body_kinds = [kind_of(b.bbox, "body") for b in bodies]
    characters = []
    if want_characters:
        from character_detection import attach_identity, detect_characters
        t = time.perf_counter()
        candidates = [b for b, k in zip(bodies, body_kinds) if k != "person"]
        characters = detect_characters(img, candidates, anime_faces=anime_faces,
                                       keep=lambda b: kind_of(b.bbox, "body") == "character")
        faceless_ok = illustrated_source and not real
        faceless_boxes = [b.bbox for b in candidates if faceless_ok and _character_body_pose(b)]

        def keep(c):
            if c.body_bbox is not None and kind_of(c.body_bbox, "body") == "character":
                return True
            # A body around a clear real face is a real person: keep the face (it goes to
            # People) and drop that "character".
            if any(_centre_inside(faces[i].bbox, c.bbox) for i in real):
                return False
            return c.face_bbox is not None or (
                c.body_bbox is not None
                and any(np.array_equal(c.body_bbox, box) for box in faceless_boxes)
            )

        characters = [c for c in characters if keep(c)]
        attach_identity(img, characters, get_ccip_embedder())
        timings["characters"] = (time.perf_counter() - t) * 1000.0
        drawn_face_boxes = [c.face_bbox for c in characters if c.face_bbox is not None]
        real_face_boxes = [faces[i].bbox for i in real]
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
            # A body around a clear real face is that person's, whatever drawing it wears (an anime print).
            if any(_centre_inside(fbox, b.bbox) for fbox in real_face_boxes):
                return False
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
