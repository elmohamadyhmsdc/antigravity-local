"""
Antigravity Local - identity builder (a "model" of one person for Reface)

Turns photos and videos of one person into a swap identity:

    detect every face -> decide which faces are the person -> quality, size,
    duplicate and outlier filters -> pose-diverse picks from videos ->
    one identity vector + a report of what was kept and why

It replaces RefaceEngine.build_faceset_from_media for V3. That took faces[0]
of every image - the detector's most confident face, which in a group photo
or a video with other people is often somebody else - weighted faces by
det_score only, and never checked that the faces agree with each other.

Saved twice:
    identities/<slug>/manifest.json + embeddings.npy + crops/NNNN.jpg   the identity
    facesets/<slug>.pkl                                                 what the engines and jobs load

The crops are FFHQ-aligned 512 px faces: material for evaluation and for
training a per-person model later (DeepFaceLab).

Pure logic (assign / filter / select / summarise) takes plain arrays, so it is
tested on CPU with fake faces (test_identity_builder.py).
"""

import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

import cv2
import numpy as np

import face_quality

APP_DIR = Path(__file__).parent
IDENTITIES_DIR = APP_DIR / "identities"
FACESETS_DIR = APP_DIR / "facesets"

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".wmv", ".m4v"}

# --- thresholds ---------------------------------------------------------------
MATCH_MIN_SIMILARITY = 0.40   # a face belongs to the identity at this cosine (person_linking's match score)
MATCH_MIN_LEAD = 0.08         # ...and beats the next face in the same picture by this much
MIN_FACE_PX = 80              # smaller faces carry too little identity to be worth averaging
DUPLICATE_SIMILARITY = 0.95   # same as the phone's dedupe: near-identical shots count once
OUTLIER_MAD = 3.0             # drop faces this many MADs below the median similarity...
OUTLIER_MIN_GAP = 0.10        # ...but never closer than this to the median (a tight set has a tiny MAD)
VIDEO_SAMPLES_PER_SECOND = 3.0
VIDEO_MAX_SAMPLES = 600
POSE_BUCKET_DEG = 15.0
PER_POSE_BUCKET = 6           # from one video, keep at most this many faces per pose bucket


@dataclass
class Candidate:
    """One detected face, before anyone decided whether it is the person."""
    source: str
    frame: Optional[int]
    embedding: np.ndarray               # raw 512-d, as insightface returns it
    quality: float
    face_px: float
    det_score: float
    yaw: float = 0.0
    pitch: float = 0.0
    bbox: Tuple[float, float, float, float] = (0, 0, 0, 0)
    kps: Optional[np.ndarray] = None
    sharpness: float = 0.0
    similarity: Optional[float] = None  # to the identity, once known
    status: str = "candidate"           # "kept" or the reason it was dropped

    @property
    def unit(self) -> np.ndarray:
        v = np.asarray(self.embedding, np.float32).ravel()
        n = float(np.linalg.norm(v))
        return v / n if n > 1e-8 else v


@dataclass
class Identity:
    name: str
    slug: str
    vector: np.ndarray                  # unit-norm 512-d
    faces: List[Candidate]              # kept faces only
    report: Dict = field(default_factory=dict)
    created_at: str = field(default_factory=lambda: datetime.now().isoformat(timespec="seconds"))


# --- small helpers --------------------------------------------------------------

def slugify(name: str) -> str:
    s = re.sub(r"[^\w\-]+", "_", name.strip(), flags=re.UNICODE).strip("_")
    return s or f"identity_{datetime.now():%Y%m%d_%H%M%S}"


def _unit_rows(m: np.ndarray) -> np.ndarray:
    m = np.asarray(m, np.float32)
    return m / np.maximum(np.linalg.norm(m, axis=1, keepdims=True), 1e-8)


def weighted_identity(faces: Sequence[Candidate]) -> Optional[np.ndarray]:
    """Quality-weighted mean of unit embeddings, re-normalised (identity.py's recipe)."""
    if not faces:
        return None
    e = _unit_rows(np.stack([f.unit for f in faces]))
    w = np.array([max(f.quality, 1e-3) for f in faces], np.float32)
    v = (e * (w / w.sum())[:, None]).sum(0)
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-8 else None


# --- 1. which face in each picture is the person ---------------------------------

def assign_identity(groups: Sequence[Sequence[Candidate]], seed: Optional[np.ndarray] = None,
                    min_similarity: float = MATCH_MIN_SIMILARITY,
                    min_lead: float = MATCH_MIN_LEAD, rounds: int = 3) -> Tuple[List[Candidate], Optional[np.ndarray]]:
    """Pick at most one face per picture (a person can't be in a photo twice).

    `groups` holds the faces of each picture or video frame. Without a seed
    the starting identity is the robust mean of pictures that contain a
    single face (usually the person's own photos); failing that, the largest
    face of every picture. Then, for a few rounds: in each picture take the
    face closest to the identity if it is close enough and clearly ahead of
    the runner-up, and re-estimate the identity from the picks.
    Returns (picked, identity vector).
    """
    groups = [list(g) for g in groups if g]
    if not groups:
        return [], None

    if seed is not None:
        anchor = np.asarray(seed, np.float32).ravel()
        anchor = anchor / max(float(np.linalg.norm(anchor)), 1e-8)
    else:
        singles = [g[0] for g in groups if len(g) == 1]
        start = singles if len(singles) >= 2 else [max(g, key=lambda f: f.face_px) for g in groups]
        anchor = _robust_anchor(start, min_similarity)
        if anchor is None:
            return [], None

    picked: List[Candidate] = []
    for _ in range(max(1, rounds)):
        picked = []
        for g in groups:
            sims = [float(f.unit @ anchor) for f in g]
            order = np.argsort(sims)[::-1]
            best = int(order[0])
            lead = sims[best] - (sims[int(order[1])] if len(order) > 1 else -1.0)
            if sims[best] >= min_similarity and lead >= min_lead:
                g[best].similarity = sims[best]
                picked.append(g[best])
        new_anchor = weighted_identity(picked)
        if new_anchor is None:
            break
        if float(new_anchor @ anchor) > 0.9999:
            anchor = new_anchor
            break
        anchor = new_anchor
    for f in picked:
        f.similarity = float(f.unit @ anchor)
    return picked, anchor


def _robust_anchor(faces: Sequence[Candidate], min_similarity: float) -> Optional[np.ndarray]:
    """Mean of the faces that agree with each other: start from the face with
    the most neighbours above min_similarity, average those neighbours."""
    if not faces:
        return None
    e = _unit_rows(np.stack([f.unit for f in faces]))
    sim = e @ e.T
    support = (sim >= min_similarity).sum(1)
    core = [faces[i] for i in np.flatnonzero(sim[int(np.argmax(support))] >= min_similarity)]
    return weighted_identity(core)


# --- 2. filters ------------------------------------------------------------------

def filter_faces(faces: Sequence[Candidate], identity: np.ndarray,
                 min_face_px: float = MIN_FACE_PX,
                 min_quality: float = face_quality.DEFAULT_MIN_QUALITY,
                 duplicate_similarity: float = DUPLICATE_SIMILARITY,
                 outlier_mad: float = OUTLIER_MAD) -> Tuple[List[Candidate], List[Candidate]]:
    """(kept, dropped); every face gets a status. Order: gates, outliers, duplicates."""
    kept, dropped = [], []
    for f in faces:
        f.similarity = float(f.unit @ identity)
        if f.det_score < face_quality.MIN_DET_SCORE:
            f.status = "low detector score"
        elif f.face_px < min_face_px:
            f.status = f"face smaller than {int(min_face_px)}px"
        elif f.quality < min_quality:
            f.status = f"quality {f.quality:.2f} below {min_quality:.2f}"
        else:
            f.status = "kept"
        (kept if f.status == "kept" else dropped).append(f)

    if len(kept) >= 5:
        sims = np.array([f.similarity for f in kept])
        med = float(np.median(sims))
        mad = float(np.median(np.abs(sims - med)))
        floor = med - max(outlier_mad * mad, OUTLIER_MIN_GAP)
        still = []
        for f in kept:
            if f.similarity < floor:
                f.status = f"looks unlike the others ({f.similarity:.2f} vs median {med:.2f})"
                dropped.append(f)
            else:
                still.append(f)
        kept = still

    # Near-duplicates: keep the better shot.
    kept.sort(key=lambda f: f.quality, reverse=True)
    unique: List[Candidate] = []
    unique_e: List[np.ndarray] = []
    for f in kept:
        u = f.unit
        if unique_e and float(np.max(np.stack(unique_e) @ u)) >= duplicate_similarity:
            f.status = "near-duplicate of a better shot"
            dropped.append(f)
            continue
        unique.append(f)
        unique_e.append(u)
    return unique, dropped


def pose_bucket(f: Candidate, step: float = POSE_BUCKET_DEG) -> Tuple[int, int]:
    return int(np.floor(f.yaw / step)), int(np.floor(f.pitch / step))


def select_pose_diverse(faces: Sequence[Candidate], per_bucket: int = PER_POSE_BUCKET) -> Tuple[List[Candidate], List[Candidate]]:
    """From one video, at most `per_bucket` faces per (yaw, pitch) bucket, best first.
    A clip of somebody talking to camera is 95% the same pose; without this the
    identity would be that pose plus a rounding error."""
    buckets: Dict[Tuple[int, int], List[Candidate]] = {}
    for f in faces:
        buckets.setdefault(pose_bucket(f), []).append(f)
    kept, dropped = [], []
    for fs in buckets.values():
        fs.sort(key=lambda f: f.quality, reverse=True)
        kept.extend(fs[:per_bucket])
        for f in fs[per_bucket:]:
            f.status = "pose already well covered"
            dropped.append(f)
    return kept, dropped


def coverage(faces: Sequence[Candidate]) -> Dict[str, int]:
    c = {"front": 0, "left": 0, "right": 0, "up": 0, "down": 0}
    for f in faces:
        if abs(f.yaw) < 20 and abs(f.pitch) < 15:
            c["front"] += 1
        if f.yaw <= -20:
            c["left"] += 1
        if f.yaw >= 20:
            c["right"] += 1
        if f.pitch >= 15:
            c["up"] += 1
        if f.pitch <= -15:
            c["down"] += 1
    return c


# --- 3. detection ------------------------------------------------------------------

def _candidates(img, face_app, source: str, frame: Optional[int]) -> List[Candidate]:
    from insightface.utils import face_align

    out = []
    for face in face_app.get(img) or []:
        if getattr(face, "embedding", None) is None or getattr(face, "kps", None) is None:
            continue
        aligned = face_align.norm_crop(img, face.kps, 112)
        q = face_quality.assess(face, aligned)
        pose = q.get("pose") or {}
        x1, y1, x2, y2 = (float(v) for v in face.bbox[:4])
        out.append(Candidate(
            source=source, frame=frame, embedding=np.asarray(face.embedding, np.float32),
            quality=float(q["quality_score"]), face_px=float(q["face_px"]), det_score=float(face.det_score),
            yaw=float(pose.get("yaw") or 0.0), pitch=float(pose.get("pitch") or 0.0),
            bbox=(x1, y1, x2, y2), kps=np.asarray(face.kps, np.float32), sharpness=float(q["sharpness"]),
        ))
    return out


def candidates_from_image(path: str, face_app) -> Optional[List[Candidate]]:
    """Faces in one photo; None when the file can't be read."""
    img = cv2.imread(str(path))
    return None if img is None else _candidates(img, face_app, str(path), None)


def candidates_from_video(path: str, face_app, per_second: float = VIDEO_SAMPLES_PER_SECOND,
                          max_samples: int = VIDEO_MAX_SAMPLES) -> List[List[Candidate]]:
    """Faces of evenly spaced frames, one list per sampled frame."""
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        return []
    fps = float(cap.get(cv2.CAP_PROP_FPS) or 0.0) or 25.0
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    step = max(1, int(round(fps / per_second)))
    if total > 0:
        step = max(step, int(np.ceil(total / max_samples)))
    groups, idx = [], 0
    while True:
        if not cap.grab():
            break
        if idx % step == 0:
            ok, img = cap.retrieve()
            if ok:
                groups.append(_candidates(img, face_app, str(path), idx))
        idx += 1
    cap.release()
    return groups


# --- 4. orchestration ----------------------------------------------------------------

def build_identity(name: str, media_paths: Sequence[str], face_app,
                   seed: Optional[np.ndarray] = None,
                   progress: Optional[Callable[[int, int, str], None]] = None) -> Tuple[Optional[Identity], Dict]:
    """Build an identity from photos and/or videos of one person.

    Returns (identity or None, report). The report always explains itself:
    how many faces were seen, how many kept, why the rest were dropped, pose
    coverage, how consistent the kept faces are, and the weakest ones.
    """
    groups: List[List[Candidate]] = []
    video_groups: Dict[str, List[List[Candidate]]] = {}
    unreadable = []
    total = len(media_paths)
    for i, p in enumerate(media_paths):
        ext = Path(p).suffix.lower()
        if progress:
            progress(i, total, Path(p).name)
        if ext in VIDEO_EXTS:
            vg = candidates_from_video(p, face_app)
            if not vg:
                unreadable.append(str(p))
            video_groups[str(p)] = vg
            groups.extend(vg)
        else:
            c = candidates_from_image(p, face_app)
            if c is None:
                unreadable.append(str(p))
            groups.append(c or [])
    if progress:
        progress(total, total, "")

    seen = sum(len(g) for g in groups)
    report: Dict = {"name": name, "media": total, "faces_seen": seen, "unreadable": unreadable}
    picked, anchor = assign_identity(groups, seed=seed)
    report["pictures_with_the_person"] = len(picked)
    if anchor is None or not picked:
        report["reason"] = ("No face appeared consistently across the media - add more photos of the person, "
                            "ideally a few with them alone in the picture.")
        return None, report

    # Pose-diverse picks per video, then the shared filters.
    dropped: List[Candidate] = []
    from_videos = {p for p in video_groups}
    still = [f for f in picked if f.source not in from_videos]
    for p in from_videos:
        mine = [f for f in picked if f.source == p]
        keep, drop = select_pose_diverse(mine)
        still.extend(keep)
        dropped.extend(drop)
    kept, filtered = filter_faces(still, anchor)
    dropped.extend(filtered)
    if not kept:
        report["reason"] = "Every face of the person was too small, blurry or turned away."
        report["dropped"] = _reasons(dropped)
        return None, report

    vector = weighted_identity(kept)
    for f in kept:
        f.similarity = float(f.unit @ vector)
    report.update(summarise(kept, dropped))
    return Identity(name=name, slug=slugify(name), vector=vector, faces=kept, report=report), report


def _reasons(dropped: Sequence[Candidate]) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for f in dropped:
        key = re.sub(r"\(.*\)|\d+(\.\d+)?", "", f.status).strip()
        out[key] = out.get(key, 0) + 1
    return out


def summarise(kept: Sequence[Candidate], dropped: Sequence[Candidate]) -> Dict:
    sims = np.array([f.similarity for f in kept], np.float32)
    weakest = sorted(kept, key=lambda f: f.similarity)[:5]
    return {
        "kept": len(kept),
        "dropped": _reasons(dropped),
        "coverage": coverage(kept),
        "consistency": round(float(sims.mean()), 3) if sims.size else None,
        "weakest": [{"source": f.source, "frame": f.frame, "similarity": round(float(f.similarity), 3)}
                    for f in weakest],
        "grade": grade(len(kept), coverage(kept), float(sims.mean()) if sims.size else 0.0),
    }


def grade(n: int, cov: Dict[str, int], consistency: float) -> str:
    """A/B/C/D for the UI: enough faces, the side views covered, faces that agree."""
    score = min(n / 30.0, 1.0) * 0.4
    score += 0.15 * (cov.get("front", 0) > 0) + 0.1 * (cov.get("left", 0) > 0) + 0.1 * (cov.get("right", 0) > 0)
    score += 0.05 * (cov.get("up", 0) > 0) + 0.05 * (cov.get("down", 0) > 0)
    score += 0.15 * float(np.clip((consistency - 0.5) / 0.25, 0, 1))
    return "A" if score >= 0.85 else "B" if score >= 0.7 else "C" if score >= 0.5 else "D"


# --- 5. storage ------------------------------------------------------------------------

def _aligned_crop(path: str, frame: Optional[int], kps: np.ndarray, size: int = 512) -> Optional[np.ndarray]:
    from face_compositor import alignment_matrix

    if frame is None:
        img = cv2.imread(path)
    else:
        cap = cv2.VideoCapture(path)
        cap.set(cv2.CAP_PROP_POS_FRAMES, frame)
        ok, img = cap.read()
        cap.release()
        img = img if ok else None
    if img is None or kps is None:
        return None
    m = alignment_matrix(kps, size)
    return None if m is None else cv2.warpAffine(img, m, (size, size), borderMode=cv2.BORDER_REPLICATE)


def save_identity(identity: Identity, root: Path = IDENTITIES_DIR, facesets_dir: Path = FACESETS_DIR,
                  write_crops: bool = True) -> Path:
    """Write identities/<slug>/ and facesets/<slug>.pkl. Returns the identity folder."""
    from reface_engine import FaceData, Faceset

    folder = Path(root) / identity.slug
    (folder / "crops").mkdir(parents=True, exist_ok=True)
    rows = []
    for i, f in enumerate(identity.faces):
        crop_rel = None
        if write_crops:
            crop = _aligned_crop(f.source, f.frame, f.kps)
            if crop is not None:
                crop_rel = f"crops/{i:04d}.jpg"
                cv2.imwrite(str(folder / crop_rel), crop, [cv2.IMWRITE_JPEG_QUALITY, 95])
        rows.append({"source": f.source, "frame": f.frame, "quality": round(f.quality, 4),
                     "face_px": round(f.face_px, 1), "yaw": round(f.yaw, 1), "pitch": round(f.pitch, 1),
                     "similarity": round(float(f.similarity), 4), "crop": crop_rel})
    np.save(folder / "embeddings.npy", np.stack([f.embedding for f in identity.faces]).astype(np.float32))
    np.save(folder / "identity.npy", identity.vector.astype(np.float32))
    manifest = {"name": identity.name, "slug": identity.slug, "created_at": identity.created_at,
                "version": 1, "faces": rows, "report": identity.report}
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")

    fs = Faceset(name=identity.slug)
    for f in identity.faces:
        fs.add_face(FaceData(image_path=f.source, embedding=np.asarray(f.embedding, np.float32),
                             pose=(float(f.yaw), float(f.pitch), 0.0), bbox=[int(v) for v in f.bbox],
                             quality=float(f.quality)))
    Path(facesets_dir).mkdir(parents=True, exist_ok=True)
    fs.save(Path(facesets_dir) / f"{identity.slug}.pkl")
    return folder


def load_manifest(slug: str, root: Path = IDENTITIES_DIR) -> Optional[Dict]:
    p = Path(root) / slug / "manifest.json"
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def list_identities(root: Path = IDENTITIES_DIR) -> List[str]:
    root = Path(root)
    return sorted(p.parent.name for p in root.glob("*/manifest.json")) if root.exists() else []


def faceset_from_media(media_paths: Sequence[str], face_app, name: str = "temp_identity"):
    """Drop-in for RefaceEngine.build_faceset_from_media (V3 paths): a Faceset of
    the identity's kept faces, or an empty one. Nothing is written to disk."""
    from reface_engine import FaceData, Faceset

    identity, report = build_identity(name, media_paths, face_app)
    fs = Faceset(name=name)
    if identity is not None:
        for f in identity.faces:
            fs.add_face(FaceData(image_path=f.source, embedding=np.asarray(f.embedding, np.float32),
                                 pose=(float(f.yaw), float(f.pitch), 0.0), bbox=[int(v) for v in f.bbox],
                                 quality=float(f.quality)))
    print(f"[IDENTITY] {name}: kept {report.get('kept', 0)} of {report.get('faces_seen', 0)} faces "
          f"({report.get('reason') or report.get('dropped')})")
    return fs
