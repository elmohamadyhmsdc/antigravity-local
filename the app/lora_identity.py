"""
Antigravity Local - LoRA identity source for Reface V2

Builds a swap-ready Faceset for a trained person from their real photos
and/or their LoRA-generated reference portraits (Character LoRA -> Generate).
See docs/plans/2026-09-17-lora-in-reface-v2-design.md for the design and the
Phase 0 measurement (compare_lora_identity.py) this was built to support.

Runs in the main venv. Loads no models itself: every function here takes an
already-prepared face_app (dashboard.py's get_face_analyzer()) or plain data.
"""
import re
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

import cv2
import numpy as np

from identity import build_identity_embedding
from lora_dataset import _slugify
from reface_engine import FaceData, Faceset

MODE_REAL = "real"
MODE_LORA = "lora"
MODE_MIXED = "mixed"
MODE_LABELS = {MODE_REAL: "Real photos", MODE_LORA: "LoRA portraits", MODE_MIXED: "Both"}

# Placeholder pending the Phase 0 measurement (design doc section 2): compare_lora_identity.py's
# 10th-percentile real-photo-vs-held-out-mean similarity should replace this once measured.
MIN_ANCHOR_SIMILARITY = 0.4

_REFERENCE_NAME_RE = re.compile(r"^reference_(?P<job_id>[^_]+)_\d{2}_seed-?\d+\.png$")


def _unit(v) -> Optional[np.ndarray]:
    v = np.asarray(v, dtype=np.float32).ravel()
    n = np.linalg.norm(v)
    return v / n if np.isfinite(n) and n >= 1e-8 else None


def _cosine(a, b) -> Optional[float]:
    ua, ub = _unit(a), _unit(b)
    return None if ua is None or ub is None else float(np.dot(ua, ub))


def _pose_of(face) -> Tuple[float, float, float]:
    p = getattr(face, "pose", None)
    return tuple(float(x) for x in p[:3]) if p is not None else (0.0, 0.0, 0.0)


def detect_largest_face(image_path, face_app) -> Optional[FaceData]:
    """The largest detected face in one image, as a FaceData, or None if the file can't be read
    or has no face. Shared by the real-photo dataset-crop fallback and the generated-portrait gate."""
    image = cv2.imread(str(image_path))
    if image is None:
        return None
    detections = face_app.get(image)
    if not detections:
        return None
    face = max(detections, key=lambda d: (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]))
    return FaceData(image_path=str(image_path), embedding=np.asarray(face.embedding, dtype=np.float32),
                    pose=_pose_of(face), bbox=[int(x) for x in face.bbox], quality=float(face.det_score))


# --- 4.1 Real-photo reference vectors -------------------------------------------------------

def real_photo_embeddings(person_id: int, person_name: str, face_app) -> Tuple[List[FaceData], str]:
    """Real photos of the person as FaceData. Tries gallery faces first (no detection needed -
    embeddings are already stored), then training-set body crops. Returns ([], "") if neither
    source has anything, which blocks LoRA/Mixed mode (generated faces can't be checked)."""
    from database import get_faces_by_person

    gallery_faces = []
    for f in get_faces_by_person(person_id):
        embedding = f.get("embedding")
        if not embedding:
            continue
        gallery_faces.append(FaceData(
            image_path=f.get("image_path") or "", embedding=np.asarray(embedding, dtype=np.float32),
            pose=(0.0, 0.0, 0.0),
            bbox=[f.get("bbox_x") or 0, f.get("bbox_y") or 0, f.get("bbox_width") or 0, f.get("bbox_height") or 0],
            quality=float(f.get("quality_score", 0.0)),
        ))
    if gallery_faces:
        return gallery_faces, "gallery"

    dataset_dir = Path(__file__).parent / "lora_datasets" / _slugify(person_name)
    dataset_faces = []
    for body_path in sorted(dataset_dir.glob("*person/*_body.jpg")):
        face = detect_largest_face(body_path, face_app)
        if face is not None:
            dataset_faces.append(face)
    if dataset_faces:
        return dataset_faces, "dataset"

    return [], ""


# --- 4.2 Clean generated portraits ----------------------------------------------------------

def clean_generated_images(person_name: str, jobs_manager) -> Tuple[List[Path], List[Tuple[Path, str]]]:
    """Generated reference portraits that are safe to check against the real person: the job that
    made them exists and used no reference image (a reference image can pull the face away from
    the LoRA's own identity). Returns (kept_paths, excluded) where excluded carries a reason."""
    from lora_generate_job import generation_output_dir

    out_dir = generation_output_dir(person_name)
    kept, excluded = [], []
    if not out_dir.exists():
        return kept, excluded

    for path in sorted(out_dir.glob("reference_*.png")):
        match = _REFERENCE_NAME_RE.match(path.name)
        if not match:
            continue
        job = jobs_manager.load_job(match.group("job_id"))
        if job is None:
            excluded.append((path, "job record not found - can't confirm this portrait is clean"))
        elif (job.params or {}).get("reference_image"):
            excluded.append((path, "generated with a reference image"))
        else:
            kept.append(path)
    return kept, excluded


# --- 4.3 Per-face gate ------------------------------------------------------------------------

def filter_by_anchor(detections: List[FaceData], anchor: Optional[np.ndarray],
                     min_similarity: float = MIN_ANCHOR_SIMILARITY) -> Tuple[List[FaceData], List[Tuple[FaceData, float]]]:
    """Drops a face whose cosine similarity to `anchor` (the real-photo identity) is below
    min_similarity. Returns (kept, dropped); each dropped entry carries its similarity score."""
    kept, dropped = [], []
    for face in detections:
        similarity = _cosine(face.embedding, anchor) or 0.0
        if similarity >= min_similarity:
            kept.append(face)
        else:
            dropped.append((face, similarity))
    return kept, dropped


# --- 4.4 Building the faceset -----------------------------------------------------------------

def faceset_from_detections(name: str, detections: List[FaceData]) -> Faceset:
    """Builds FaceData directly (not via RefaceEngine.build_faceset_from_media, which creates a
    stray facesets/<name>/ folder and only keeps faces[0] per image)."""
    faceset = Faceset(name=name)
    for d in detections:
        faceset.add_face(FaceData(image_path=d.image_path, embedding=np.asarray(d.embedding, dtype=np.float32),
                                  pose=tuple(d.pose), bbox=list(d.bbox), quality=float(d.quality)))
    return faceset


def faceset_name(person_id: int) -> str:
    """lora_p<person_id>_<timestamp>: the person id (not a name slug) avoids collisions between
    persons whose names slugify the same, and every activation gets a new file so a background
    job that already started keeps the identity it was queued with."""
    return f"lora_p{person_id}_{datetime.now():%Y%m%d_%H%M%S}"


# --- 4.5 Orchestration -------------------------------------------------------------------------

def build_lora_faceset(person: dict, mode: str, selected_paths: List[str], face_app,
                       jobs_manager) -> Tuple[Optional[Faceset], dict]:
    """Builds the identity faceset for Reface V2's Trained LoRA source mode.

    mode is one of MODE_REAL / MODE_LORA / MODE_MIXED. selected_paths are the portrait paths
    checked in the UI (ignored for MODE_REAL). Returns (faceset, report); faceset is None when no
    face survived, with the reason in report["reason"].
    """
    person_id, person_name = person["id"], person["name"]
    real_faces, real_source = real_photo_embeddings(person_id, person_name, face_app)
    report = {"mode": mode, "real_photo_count": len(real_faces), "real_photo_source": real_source}

    if not real_faces:
        report["reason"] = "No real photos found for this person, so generated faces can't be checked against them."
        return None, report

    anchor = build_identity_embedding(faceset_from_detections("_anchor", real_faces))

    kept_faces: List[FaceData] = []
    if mode in (MODE_REAL, MODE_MIXED):
        kept_faces.extend(real_faces)

    portraits_used = portraits_no_face = 0
    dropped: List[Tuple[FaceData, float]] = []
    if mode in (MODE_LORA, MODE_MIXED):
        detected = []
        for path in selected_paths:
            face = detect_largest_face(path, face_app)
            if face is None:
                portraits_no_face += 1
            else:
                detected.append(face)
        gated, dropped = filter_by_anchor(detected, anchor)
        kept_faces.extend(gated)
        portraits_used = len(selected_paths)
        report.update(portraits_considered=portraits_used, portraits_no_face=portraits_no_face,
                      portraits_below_similarity=len(dropped),
                      dropped_scores=[round(score, 3) for _, score in dropped])

    if not kept_faces:
        report["reason"] = "No faces survived - nothing to build an identity from."
        return None, report

    faceset = faceset_from_detections(faceset_name(person_id), kept_faces)
    identity_vector = build_identity_embedding(faceset)
    report["identity_similarity_to_real"] = _cosine(identity_vector, anchor)

    parts = []
    if mode in (MODE_LORA, MODE_MIXED):
        kept_portraits = portraits_used - portraits_no_face - len(dropped)
        reasons = []
        if portraits_no_face:
            reasons.append(f"{portraits_no_face} had no face")
        if dropped:
            reasons.append(f"{len(dropped)} below similarity ({min(s for _, s in dropped):.2f})")
        detail = f" - {', '.join(reasons)}" if reasons else ""
        parts.append(f"Kept {kept_portraits} of {portraits_used} portrait(s){detail}")
    if mode in (MODE_REAL, MODE_MIXED):
        parts.append(f"{len(real_faces)} real photo(s) from {real_source}")
    if report["identity_similarity_to_real"] is not None:
        parts.append(f"Identity vs real photos: {report['identity_similarity_to_real']:.2f}")
    report["message"] = ". ".join(parts) + "."

    return faceset, report
