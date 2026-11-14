"""
Antigravity Local - Multi-Photo Reusable Identity Profile (Identity Bundle)

Encapsulates multi-photo face representations, angle coverage, outlier filtering,
provenance, and content-addressed verification.
"""

from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import json
import math
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple, Union

import numpy as np


SCHEMA_VERSION = "1.0"
ALGORITHM_VERSION = "identity_v1"
POSE_SECTORS = ("front", "left", "right", "up", "down")


def _unit_vector(v: Union[np.ndarray, Sequence[float]]) -> Optional[np.ndarray]:
    arr = np.asarray(v, dtype=np.float32).ravel()
    if arr.size != 512:
        return None
    norm = float(np.linalg.norm(arr))
    if not np.isfinite(norm) or norm < 1e-8:
        return None
    return arr / norm


def get_pose_sector(yaw: float, pitch: float, roll: float = 0.0) -> str:
    """Classify 3D head pose into canonical sectors."""
    y = float(yaw)
    p = float(pitch)
    if abs(y) <= 15.0 and abs(p) <= 15.0:
        return "front"
    if y < -15.0:
        return "left"
    if y > 15.0:
        return "right"
    if p > 15.0:
        return "up"
    if p < -15.0:
        return "down"
    return "front"


@dataclass
class SourceFaceRecord:
    source_id: str
    embedding: List[float]
    pose: Dict[str, float]
    quality: float
    bbox: Dict[str, float]
    is_synthetic: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {
            "source_id": self.source_id,
            "embedding": list(self.embedding),
            "pose": dict(self.pose),
            "quality": self.quality,
            "bbox": dict(self.bbox),
            "is_synthetic": bool(self.is_synthetic),
        }


@dataclass
class ExcludedSourceRecord:
    source_id: str
    reason: str  # "multiple_faces", "no_face_detected", "outlier_dissimilar", "duplicate", "low_quality", "extreme_pose"
    similarity: float
    details: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "source_id": self.source_id,
            "reason": self.reason,
            "similarity": self.similarity,
            "details": self.details,
        }


@dataclass
class IdentityBundle:
    schema_version: str
    algorithm_version: str
    identity_id: str
    label: str
    created_at: str
    primary_embedding: List[float]
    angle_embeddings: Dict[str, List[float]]
    sources: List[SourceFaceRecord]
    excluded_sources: List[ExcludedSourceRecord]
    metrics: Dict[str, Any]
    bundle_hash: str

    def get_best_embedding_for_pose(self, target_pose: Tuple[float, float, float]) -> np.ndarray:
        """Select sector-specific embedding if available, otherwise fallback to primary consensus."""
        yaw, pitch, roll = (float(v) for v in target_pose[:3])
        sector = get_pose_sector(yaw, pitch, roll)
        if sector in self.angle_embeddings:
            vec = _unit_vector(self.angle_embeddings[sector])
            if vec is not None:
                return vec
        primary = _unit_vector(self.primary_embedding)
        return primary if primary is not None else np.zeros(512, dtype=np.float32)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "schema_version": self.schema_version,
            "algorithm_version": self.algorithm_version,
            "identity_id": self.identity_id,
            "label": self.label,
            "created_at": self.created_at,
            "primary_embedding": list(self.primary_embedding),
            "angle_embeddings": {
                k: list(v) for k, v in self.angle_embeddings.items()
            },
            "sources": [s.to_dict() for s in self.sources],
            "excluded_sources": [e.to_dict() for e in self.excluded_sources],
            "metrics": dict(self.metrics),
            "bundle_hash": self.bundle_hash,
        }

    def to_json(self, indent: Optional[int] = None) -> str:
        return json.dumps(self.to_dict(), indent=indent)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "IdentityBundle":
        val_ok, err = validate_bundle_dict(data)
        if not val_ok:
            raise ValueError(f"Invalid IdentityBundle payload: {err}")

        sources = [
            SourceFaceRecord(
                source_id=s["source_id"],
                embedding=list(s["embedding"]),
                pose=dict(s["pose"]),
                quality=s["quality"],
                bbox=dict(s["bbox"]),
                is_synthetic=bool(s.get("is_synthetic", False)),
            )
            for s in data["sources"]
        ]

        excluded = [
            ExcludedSourceRecord(
                source_id=e["source_id"],
                reason=e["reason"],
                similarity=e.get("similarity", 0.0),
                details=e.get("details", ""),
            )
            for e in data.get("excluded_sources", [])
        ]

        angle_embeddings = {
            k: list(v) for k, v in data.get("angle_embeddings", {}).items()
        }

        return cls(
            schema_version=data["schema_version"],
            algorithm_version=data["algorithm_version"],
            identity_id=data["identity_id"],
            label=data.get("label", "unnamed"),
            created_at=data["created_at"],
            primary_embedding=[float(x) for x in data["primary_embedding"]],
            angle_embeddings=angle_embeddings,
            sources=sources,
            excluded_sources=excluded,
            metrics=dict(data.get("metrics", {})),
            bundle_hash=data["bundle_hash"],
        )

    @classmethod
    def from_json(cls, json_str: str) -> "IdentityBundle":
        try:
            data = json.loads(json_str)
        except Exception as exc:
            raise ValueError(f"Identity bundle is not valid JSON: {exc}") from exc
        return cls.from_dict(data)


def compute_bundle_hash(core_dict: Dict[str, Any]) -> str:
    """Compute deterministic SHA-256 over normalized canonical JSON representation."""
    cleaned = dict(core_dict)
    cleaned.pop("bundle_hash", None)
    cleaned.pop("identity_id", None)
    canonical = json.dumps(cleaned, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def validate_bundle_dict(data: Dict[str, Any]) -> Tuple[bool, Optional[str]]:
    """Validate structure, field constraints, dimensions, and hash integrity."""
    if not isinstance(data, dict):
        return False, "Bundle must be a JSON object"
    for req in (
        "schema_version",
        "algorithm_version",
        "identity_id",
        "created_at",
        "primary_embedding",
        "sources",
        "bundle_hash",
    ):
        if req not in data:
            return False, f"Missing required bundle field: {req}"

    if data["schema_version"] != SCHEMA_VERSION:
        return False, f"Unsupported schema_version: {data['schema_version']}"
    if data["algorithm_version"] != ALGORITHM_VERSION:
        return False, "Unsupported identity bundle algorithm"

    def embedding_ok(value):
        return (isinstance(value, list) and len(value) == 512
                and all(type(x) in (int, float) and -1 <= x <= 1 for x in value)
                and _unit_vector(value) is not None)

    if not embedding_ok(data["primary_embedding"]):
        return False, "primary_embedding must be a nonzero, finite 512-d vector"
    sources = data["sources"]
    if not isinstance(sources, list) or not sources:
        return False, "sources must contain at least one usable face"
    for source in sources:
        if not isinstance(source, dict) or not embedding_ok(source.get("embedding")):
            return False, "Invalid source face embedding"
        pose, bbox, quality = (source.get(key) for key in ("pose", "bbox", "quality"))
        if (not isinstance(source.get("source_id"), str)
                or not isinstance(bbox, dict) or not isinstance(pose, dict)
                or any(type(pose.get(axis)) not in (int, float)
                       or not -360 <= pose[axis] <= 360 for axis in ("yaw", "pitch", "roll"))
                or type(quality) not in (int, float) or not 0 <= quality <= 1):
            return False, "Invalid source face metadata"
    angles = data.get("angle_embeddings", {})
    if not isinstance(angles, dict) or any(
        key not in POSE_SECTORS or not embedding_ok(value) for key, value in angles.items()
    ):
        return False, "Invalid angle-specific identity embeddings"

    computed = compute_bundle_hash(data)
    if data["bundle_hash"] != computed:
        return False, f"bundle_hash mismatch: expected {computed}, got {data['bundle_hash']}"

    return True, None


# -----------------------------------------------------------------------------
# Builder
# -----------------------------------------------------------------------------

def build_identity_bundle(
    candidates: Sequence[Dict[str, Any]],
    label: str = "unnamed",
    min_quality: float = 0.25,
    top_k: int = 20,
) -> IdentityBundle:
    """Build an IdentityBundle from candidate face dictionaries.

    Each candidate dict should have:
    - 'source_id': str
    - 'embedding': 512-d float array
    - 'pose': dict(yaw, pitch, roll) or tuple
    - 'quality': float (0..1)
    - 'bbox': dict(x, y, w, h)
    - optional 'is_synthetic': bool
    - optional 'error_reason': str (if face detection failed or multiple faces detected)
    """
    valid_rows = []
    excluded: List[ExcludedSourceRecord] = []

    for item in candidates:
        sid = item.get("source_id", "unknown")
        if "error_reason" in item:
            reason = item["error_reason"]
            details = item.get("error_details", f"Source rejected: {reason}")
            excluded.append(ExcludedSourceRecord(sid, reason, 0.0, details))
            continue

        raw_emb = item.get("embedding")
        vec = _unit_vector(raw_emb)
        quality = float(item.get("quality", 0.0) or 0.0)
        pose_raw = item.get("pose") or {"yaw": 0.0, "pitch": 0.0, "roll": 0.0}
        if isinstance(pose_raw, (tuple, list)):
            pose = {
                "yaw": float(pose_raw[0]) if len(pose_raw) > 0 else 0.0,
                "pitch": float(pose_raw[1]) if len(pose_raw) > 1 else 0.0,
                "roll": float(pose_raw[2]) if len(pose_raw) > 2 else 0.0,
            }
        else:
            pose = {
                "yaw": float(pose_raw.get("yaw", 0.0)),
                "pitch": float(pose_raw.get("pitch", 0.0)),
                "roll": float(pose_raw.get("roll", 0.0)),
            }

        bbox = item.get("bbox") or {"x": 0.0, "y": 0.0, "w": 100.0, "h": 100.0}
        is_synthetic = bool(item.get("is_synthetic", False))

        if vec is None:
            excluded.append(
                ExcludedSourceRecord(
                    sid, "no_face_detected", 0.0, "Invalid or zero-norm embedding"
                )
            )
            continue

        if quality < min_quality:
            excluded.append(
                ExcludedSourceRecord(
                    sid,
                    "low_quality",
                    0.0,
                    f"Face quality score {quality:.2f} is below minimum {min_quality:.2f}",
                )
            )
            continue

        valid_rows.append(
            {
                "source_id": sid,
                "vector": vec,
                "pose": pose,
                "quality": quality,
                "bbox": bbox,
                "is_synthetic": is_synthetic,
                "weight": max(min(quality, 1.0), 1e-3) * (0.5 if is_synthetic else 1.0),
            }
        )

    if not valid_rows:
        empty_metrics = {
            "input_count": len(candidates),
            "kept_count": 0,
            "excluded_count": len(excluded),
            "consistency_score": 0.0,
            "pose_coverage": {k: 0 for k in POSE_SECTORS},
            "coverage_percentage": 0.0,
        }
        dummy_hash = hashlib.sha256(b"empty_bundle").hexdigest()
        return IdentityBundle(
            schema_version=SCHEMA_VERSION,
            algorithm_version=ALGORITHM_VERSION,
            identity_id=f"ident_{dummy_hash[:16]}",
            label=label,
            created_at=datetime.now(timezone.utc).isoformat(),
            primary_embedding=[0.0] * 512,
            angle_embeddings={},
            sources=[],
            excluded_sources=excluded,
            metrics=empty_metrics,
            bundle_hash=dummy_hash,
        )

    # Medoid-based outlier rejection
    vectors = np.stack([r["vector"] for r in valid_rows])
    similarities = vectors @ vectors.T

    real_indices = [i for i, r in enumerate(valid_rows) if not r["is_synthetic"]]
    pool = real_indices or list(range(len(valid_rows)))
    anchor_idx = max(pool, key=lambda i: float(np.median(similarities[i, pool])))
    anchor = vectors[anchor_idx]
    sims = vectors @ anchor

    real_sims = sims[pool]
    median_sim = float(np.median(real_sims))
    mad = float(np.median(np.abs(real_sims - median_sim)))
    threshold = max(0.40, median_sim - max(3.0 * mad, 0.10))

    passed_outlier = []
    for idx, row in enumerate(valid_rows):
        sim = float(sims[idx])
        if sim < threshold:
            excluded.append(
                ExcludedSourceRecord(
                    row["source_id"],
                    "outlier_dissimilar",
                    sim,
                    f"Similarity {sim:.3f} below medoid threshold {threshold:.3f}",
                )
            )
        else:
            row["similarity_to_anchor"] = sim
            passed_outlier.append(row)

    # Duplicate suppression (cosine >= 0.96 with very close pose)
    passed_outlier.sort(key=lambda r: (not r["is_synthetic"], r["quality"]), reverse=True)
    kept = []
    for row in passed_outlier:
        is_dup = False
        for old in kept:
            sim = float(row["vector"] @ old["vector"])
            yaw_diff = abs(row["pose"]["yaw"] - old["pose"]["yaw"])
            pitch_diff = abs(row["pose"]["pitch"] - old["pose"]["pitch"])
            if sim >= 0.96 and yaw_diff < 10.0 and pitch_diff < 10.0:
                is_dup = True
                excluded.append(
                    ExcludedSourceRecord(
                        row["source_id"],
                        "duplicate",
                        sim,
                        f"Duplicate of {old['source_id']} (similarity {sim:.3f})",
                    )
                )
                break
        if not is_dup:
            kept.append(row)
            if top_k and len(kept) >= top_k:
                break

    # Balance synthetic weight if present
    real_weight = sum(r["quality"] for r in kept if not r["is_synthetic"])
    syn_weight = sum(r["quality"] for r in kept if r["is_synthetic"])
    if real_weight > 0 and syn_weight > 0:
        factor = min(1.0, real_weight * 0.25 / syn_weight)
        for r in kept:
            if r["is_synthetic"]:
                r["weight"] *= factor

    # Compute primary consensus centroid
    weighted_sum = sum(r["vector"] * r["weight"] for r in kept)
    primary_vec = _unit_vector(weighted_sum)
    if primary_vec is None:
        primary_vec = kept[0]["vector"]

    # Compute angle-specific centroids
    angle_groups: Dict[str, List[Dict[str, Any]]] = {}
    pose_counts = {k: 0 for k in POSE_SECTORS}
    for r in kept:
        sec = get_pose_sector(r["pose"]["yaw"], r["pose"]["pitch"], r["pose"]["roll"])
        angle_groups.setdefault(sec, []).append(r)
        pose_counts[sec] += 1

    angle_embeddings: Dict[str, List[float]] = {}
    for sec, group in angle_groups.items():
        sec_sum = sum(item["vector"] * item["weight"] for item in group)
        sec_vec = _unit_vector(sec_sum)
        if sec_vec is not None:
            angle_embeddings[sec] = [round(float(x), 6) for x in sec_vec]

    covered_sectors = sum(1 for c in pose_counts.values() if c > 0)
    coverage_pct = round((covered_sectors / len(POSE_SECTORS)) * 100.0, 1)

    sources_records = [
        SourceFaceRecord(
            source_id=r["source_id"],
            embedding=[round(float(x), 6) for x in r["vector"]],
            pose=r["pose"],
            quality=r["quality"],
            bbox=r["bbox"],
            is_synthetic=r["is_synthetic"],
        )
        for r in kept
    ]

    consistency = float(np.mean([float(r["vector"] @ primary_vec) for r in kept]))

    metrics = {
        "input_count": len(candidates),
        "kept_count": len(kept),
        "excluded_count": len(excluded),
        "consistency_score": round(consistency, 4),
        "pose_coverage": pose_counts,
        "coverage_percentage": coverage_pct,
    }

    core_bundle = {
        "schema_version": SCHEMA_VERSION,
        "algorithm_version": ALGORITHM_VERSION,
        "label": label,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "primary_embedding": [round(float(x), 6) for x in primary_vec],
        "angle_embeddings": angle_embeddings,
        "sources": [s.to_dict() for s in sources_records],
        "excluded_sources": [e.to_dict() for e in excluded],
        "metrics": metrics,
    }

    bundle_hash = compute_bundle_hash(core_bundle)
    identity_id = f"ident_{bundle_hash[:16]}"

    return IdentityBundle(
        schema_version=SCHEMA_VERSION,
        algorithm_version=ALGORITHM_VERSION,
        identity_id=identity_id,
        label=label,
        created_at=core_bundle["created_at"],
        primary_embedding=core_bundle["primary_embedding"],
        angle_embeddings=angle_embeddings,
        sources=sources_records,
        excluded_sources=excluded,
        metrics=metrics,
        bundle_hash=bundle_hash,
    )


def estimate_pose_from_kps(kps: np.ndarray) -> Tuple[float, float, float]:
    """Estimate approximate (yaw, pitch, roll) from 5-point facial landmarks."""
    if kps is None or len(kps) < 5:
        return 0.0, 0.0, 0.0
    left_eye = np.asarray(kps[0], np.float32)
    right_eye = np.asarray(kps[1], np.float32)
    nose = np.asarray(kps[2], np.float32)
    mouth_left = np.asarray(kps[3], np.float32)
    mouth_right = np.asarray(kps[4], np.float32)

    eye_center = (left_eye + right_eye) / 2.0
    mouth_center = (mouth_left + mouth_right) / 2.0
    eye_dist = max(1.0, float(np.linalg.norm(right_eye - left_eye)))

    dx = float(nose[0] - eye_center[0])
    yaw = float(np.clip(dx / (eye_dist * 0.5) * 45.0, -90.0, 90.0))

    mid_y = (eye_center[1] + mouth_center[1]) / 2.0
    dy = float(nose[1] - mid_y)
    face_h = max(1.0, float(np.linalg.norm(mouth_center - eye_center)))
    pitch = float(np.clip(dy / (face_h * 0.5) * 45.0, -90.0, 90.0))

    d_eye = right_eye - left_eye
    roll = float(np.degrees(np.arctan2(d_eye[1], d_eye[0])))
    return round(yaw, 2), round(pitch, 2), round(roll, 2)


def build_identity_bundle_from_images(
    images: Sequence[Union[str, Path, np.ndarray]],
    label: str = "unnamed",
    detector=None,
    min_quality: float = 0.25,
    top_k: int = 20,
) -> IdentityBundle:
    """Build an IdentityBundle directly from source image files or arrays."""
    import cv2

    candidates = []
    for idx, item in enumerate(images):
        sid = Path(item).name if isinstance(item, (str, Path)) else f"image_{idx:03d}.png"
        img = cv2.imread(str(item)) if isinstance(item, (str, Path)) else item
        if img is None:
            candidates.append({"source_id": sid, "error_reason": "unreadable_image",
                               "error_details": "Image file could not be read or decoded"})
            continue

        if detector is None:
            # Fallback detector using InsightFace if available
            try:
                from insightface.app import FaceAnalysis
                app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "recognition"])
                app.prepare(ctx_id=0, det_size=(640, 640))
                detector = app
            except Exception as e:
                raise RuntimeError(f"No face detector available: {e}")

        faces = detector.get(img)
        if not faces:
            candidates.append({"source_id": sid, "error_reason": "no_face_detected",
                               "error_details": "No face found in source image"})
            continue

        # Mixed identity protection: check if there are multiple prominent faces
        if len(faces) > 1:
            boxes = [f.bbox for f in faces]
            areas = [(b[2] - b[0]) * (b[3] - b[1]) for b in boxes]
            sorted_indices = sorted(range(len(faces)), key=lambda i: areas[i], reverse=True)
            first_area, second_area = areas[sorted_indices[0]], areas[sorted_indices[1]]
            # If second face has significant area (> 25% of main face) and confident score:
            if second_area > 0.25 * first_area and getattr(faces[sorted_indices[1]], "det_score", 0.0) >= 0.50:
                candidates.append({
                    "source_id": sid,
                    "error_reason": "multiple_faces",
                    "error_details": f"Source image contains {len(faces)} faces; ambiguous identity rejected to avoid mixing people"
                })
                continue
            chosen_face = faces[sorted_indices[0]]
        else:
            chosen_face = faces[0]

        # Extract attributes
        emb = getattr(chosen_face, "normed_embedding", None)
        if emb is None and hasattr(chosen_face, "embedding"):
            emb = _unit_vector(chosen_face.embedding)

        kps = getattr(chosen_face, "kps", None)
        if kps is not None:
            pose = estimate_pose_from_kps(kps)
        elif getattr(chosen_face, "pose", None) is not None:
            pitch, yaw, roll = (float(v) for v in chosen_face.pose[:3])
            pose = yaw, pitch, roll
        else:
            pose = (0.0, 0.0, 0.0)

        b = chosen_face.bbox
        bbox = {"x": float(b[0]), "y": float(b[1]), "w": float(b[2] - b[0]), "h": float(b[3] - b[1])}
        quality = float(getattr(chosen_face, "det_score", 0.8) or 0.8)

        candidates.append({
            "source_id": sid,
            "embedding": emb,
            "pose": {"yaw": pose[0], "pitch": pose[1], "roll": pose[2]},
            "quality": quality,
            "bbox": bbox,
            "is_synthetic": False,
        })

    return build_identity_bundle(candidates, label=label, min_quality=min_quality, top_k=top_k)
