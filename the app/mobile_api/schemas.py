"""
Wire format helpers: turn engine objects into the JSON shapes in contract/openapi.yaml.

Embeddings are 512 x float32 little-endian, base64 (2732 chars, 2048 raw bytes); boxes are
{x, y, w, h} in pixels of the uploaded image; everything is plain Python numbers.
"""

import base64
import json
from dataclasses import dataclass
from typing import Any, Dict, Optional

import cv2
import numpy as np

import face_quality
import person_linking as pl
from analysis import FrameAnalysis, body_crop, face_crop

from . import EMBEDDING_DIM, EMBEDDING_MODEL_ID
from .errors import bad_request

FACE_CROP_MAX_PX = 256
BODY_CROP_MAX_HEIGHT = 384
CROP_JPEG_QUALITY = 85


# --- primitives ---------------------------------------------------------------

def encode_embedding(vec) -> str:
    v = np.asarray(vec, dtype="<f4").reshape(-1)
    if v.shape[0] != EMBEDDING_DIM:
        raise ValueError(f"embedding has {v.shape[0]} values, expected {EMBEDDING_DIM}")
    return base64.b64encode(v.tobytes()).decode("ascii")


def decode_embedding(text: str) -> np.ndarray:
    raw = base64.b64decode(text, validate=True)
    if len(raw) != EMBEDDING_DIM * 4:
        raise ValueError("embedding must be 512 float32 values")
    return np.frombuffer(raw, dtype="<f4").copy()


def py(value: Any) -> Any:
    """numpy scalars/arrays -> plain Python, recursively."""
    if isinstance(value, dict):
        return {k: py(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [py(v) for v in value]
    if isinstance(value, np.ndarray):
        return py(value.tolist())
    if isinstance(value, np.generic):
        return value.item()
    return value


def bbox_xywh(xyxy, ndigits: int = 1) -> Dict[str, float]:
    x1, y1, x2, y2 = [float(v) for v in xyxy[:4]]
    return {"x": round(x1, ndigits), "y": round(y1, ndigits),
            "w": round(x2 - x1, ndigits), "h": round(y2 - y1, ndigits)}


def jpeg_b64(img: Optional[np.ndarray], max_side: int, quality: int = CROP_JPEG_QUALITY) -> Optional[str]:
    if img is None or img.size == 0:
        return None
    h, w = img.shape[:2]
    scale = max_side / max(h, w)
    if scale < 1.0:
        img = cv2.resize(img, (max(1, int(w * scale)), max(1, int(h * scale))), interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return base64.b64encode(buf.tobytes()).decode("ascii") if ok else None


# --- analyze options ------------------------------------------------------------

@dataclass
class AnalyzeRequestOptions:
    """AnalyzeImageOptions (+ the engine-facing attributes analysis.analyze_frame reads)."""
    detect_bodies: bool = True
    min_face_quality: float = face_quality.DEFAULT_MIN_QUALITY
    body_score: float = 0.5
    return_crops: bool = True
    model_id: Optional[str] = None


def _number(opts: dict, key: str, default: float, lo: float, hi: float) -> float:
    value = opts.get(key, default)
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not lo <= float(value) <= hi:
        raise bad_request(f"options.{key} must be a number between {lo} and {hi}")
    return float(value)


def _flag(opts: dict, key: str, default: bool) -> bool:
    value = opts.get(key, default)
    if not isinstance(value, bool):
        raise bad_request(f"options.{key} must be true or false")
    return value


def parse_analyze_options(raw: Optional[str]) -> AnalyzeRequestOptions:
    if raw is None or not raw.strip():
        return AnalyzeRequestOptions()
    try:
        opts = json.loads(raw)
    except ValueError:
        raise bad_request("options is not valid JSON")
    if not isinstance(opts, dict):
        raise bad_request("options must be a JSON object")
    model_id = opts.get("model_id")
    if model_id is not None and not isinstance(model_id, str):
        raise bad_request("options.model_id must be a string")
    return AnalyzeRequestOptions(
        detect_bodies=_flag(opts, "detect_bodies", True),
        min_face_quality=_number(opts, "min_quality", face_quality.DEFAULT_MIN_QUALITY, 0.0, 1.0),
        body_score=_number(opts, "body_score", 0.5, 0.0, 1.0),
        return_crops=_flag(opts, "return_crops", True),
        model_id=model_id,
    )


# --- analyze response -----------------------------------------------------------

def face_json(face, q: Dict, passes: bool, img: np.ndarray, with_crop: bool) -> Dict:
    emb = face.normed_embedding
    return {
        "bbox": bbox_xywh(face.bbox),
        "kps": [[round(float(x), 1), round(float(y), 1)] for x, y in np.asarray(face.kps).reshape(-1, 2)],
        "det_score": round(float(face.det_score), 4),
        "embedding": encode_embedding(emb),
        "quality": py({k: q[k] for k in ("quality_score", "quality_version", "quality_parts", "det_score",
                                          "face_px", "sharpness", "embedding_norm", "pose")}),
        "passes_gate": bool(passes),
        "crop_jpeg": jpeg_b64(face_crop(img, face), FACE_CROP_MAX_PX) if (with_crop and passes) else None,
    }


def body_json(body, appearance, img: np.ndarray, with_crop: bool) -> Dict:
    kpts = None
    if body.kpts is not None and body.kpt_scores is not None:
        kpts = [[round(float(x), 1), round(float(y), 1), round(float(s), 3)]
                for (x, y), s in zip(body.kpts, body.kpt_scores)]
    return {
        "bbox": bbox_xywh(body.bbox),
        "score": round(float(body.score), 4),
        "kpts": kpts,
        "appearance": None if appearance is None else [round(float(v), 4) for v in appearance],
        "extent": None if body.kpt_scores is None else pl.body_extent(body.kpt_scores),
        "crop_jpeg": jpeg_b64(body_crop(img, body.bbox, BODY_CROP_MAX_HEIGHT), 10 ** 6) if with_crop else None,
    }


def analysis_to_response(result: FrameAnalysis, img: np.ndarray, options: AnalyzeRequestOptions,
                         model_id: str = EMBEDDING_MODEL_ID) -> Dict:
    """AnalyzeImageResponse. Faces without an embedding are impossible with the recognition model
    loaded, so every face is returned and pair indices stay valid."""
    faces = [face_json(f, q, p, img, options.return_crops)
             for f, q, p in zip(result.faces, result.quality, result.passes_gate)]
    bodies = [body_json(b, a, img, options.return_crops) for b, a in zip(result.bodies, result.appearances)]
    pairs = [{"face_index": int(fi), "body_index": int(bi), "score": round(float(s), 3)}
             for fi, bi, s in result.pairs]
    out = {"model_id": model_id, "image_w": int(result.image_w), "image_h": int(result.image_h),
           "faces": faces, "bodies": bodies, "pairs": pairs}
    if result.timings_ms:
        out["timings_ms"] = py(result.timings_ms)
    return out
