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
from analysis import AnalyzeOptions, FrameAnalysis, body_crop, face_crop
from outlines import encode_outline

from . import EMBEDDING_DIM, EMBEDDING_MODEL_ID
from .errors import bad_request

CHARACTER_FACE_MODEL_ID = "ccip-caformer24@1"  # 768 x float32 little-endian, unit length
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
    detect_characters: bool = False
    return_outlines: bool = False
    faceless_characters: bool = True
    force_kind: Optional[str] = None
    # (kind, part, (x1, y1, x2, y2) normalised, timestamp_ms or None)
    kind_overrides: tuple = ()
    return_sensitive: bool = False   # roadmap section 8; off = the response is byte-identical to before
    return_body_embeddings: bool = False   # roadmap 7.5 (Phase 8); implies the regions are computed

    def engine_options(self, timestamp_ms: Optional[int] = None, tolerance_ms: int = 0) -> AnalyzeOptions:
        """What analysis.analyze_frame needs. In a video only the corrections made near
        this frame's time apply; a correction without a time applies to every frame."""
        overrides = tuple((kind, part, box) for kind, part, box, ts in self.kind_overrides
                          if ts is None or timestamp_ms is None or abs(ts - timestamp_ms) <= tolerance_ms)
        return AnalyzeOptions(min_face_quality=self.min_face_quality, detect_characters=self.detect_characters,
                              detect_bodies=self.detect_bodies, body_score=self.body_score,
                              outlines=self.return_outlines, faceless_characters=self.faceless_characters,
                              force_kind=self.force_kind, kind_overrides=overrides,
                              sensitive=self.return_sensitive, body_embeddings=self.return_body_embeddings)


MAX_KIND_OVERRIDES = 4096
KINDS = ("person", "character")


def _kind_overrides(opts: dict) -> tuple:
    raw = opts.get("kind_overrides", [])
    if not isinstance(raw, list) or len(raw) > MAX_KIND_OVERRIDES:
        raise bad_request(f"options.kind_overrides must be a list of at most {MAX_KIND_OVERRIDES} corrections")
    out = []
    for i, item in enumerate(raw):
        where = f"options.kind_overrides[{i}]"
        if not isinstance(item, dict) or item.get("kind") not in KINDS or item.get("part") not in ("face", "body"):
            raise bad_request(f"{where} needs kind 'person' | 'character' and part 'face' | 'body'")
        box = item.get("box")
        if (not isinstance(box, list) or len(box) != 4
                or any(isinstance(v, bool) or not isinstance(v, (int, float)) for v in box)):
            raise bad_request(f"{where}.box must be [x, y, w, h] in 0..1")
        x, y, w, h = (float(v) for v in box)
        if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < w <= 1 and 0 < h <= 1):
            raise bad_request(f"{where}.box must be [x, y, w, h] in 0..1")
        ts = item.get("timestamp_ms")
        if ts is not None and (isinstance(ts, bool) or not isinstance(ts, int) or ts < 0):
            raise bad_request(f"{where}.timestamp_ms must be a non-negative integer")
        out.append((item["kind"], item["part"], (x, y, min(1.0, x + w), min(1.0, y + h)), ts))
    return tuple(out)


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
        detect_characters=_flag(opts, "detect_characters", False),
        min_face_quality=_number(opts, "min_quality", face_quality.DEFAULT_MIN_QUALITY, 0.0, 1.0),
        body_score=_number(opts, "body_score", 0.5, 0.0, 1.0),
        return_crops=_flag(opts, "return_crops", True),
        model_id=model_id,
        return_outlines=_flag(opts, "return_outlines", False),
        faceless_characters=_flag(opts, "faceless_characters", True),
        force_kind=_force_kind(opts),
        kind_overrides=_kind_overrides(opts),
        return_sensitive=_flag(opts, "return_sensitive", False),
        return_body_embeddings=_flag(opts, "return_body_embeddings", False),
    )


def _force_kind(opts: dict) -> Optional[str]:
    value = opts.get("force_kind")
    if value is not None and value not in KINDS:
        raise bad_request("options.force_kind must be 'person', 'character' or null")
    return value


# --- analyze response -----------------------------------------------------------

def face_json(face, q: Dict, passes: bool, img: np.ndarray, with_crop: bool,
              outline: Optional[Any] = None, return_outlines: bool = False, forced: bool = False) -> Dict:
    emb = face.normed_embedding
    d = {
        "bbox": bbox_xywh(face.bbox),
        "kps": [[round(float(x), 1), round(float(y), 1)] for x, y in np.asarray(face.kps).reshape(-1, 2)],
        "det_score": round(float(face.det_score), 4),
        "embedding": encode_embedding(emb),
        "quality": py({k: q[k] for k in ("quality_score", "quality_version", "quality_parts", "det_score",
                                          "face_px", "sharpness", "embedding_norm", "pose")}),
        "passes_gate": bool(passes),
        "crop_jpeg": jpeg_b64(face_crop(img, face), FACE_CROP_MAX_PX) if (with_crop and passes) else None,
    }
    if return_outlines:
        d["outline"] = encode_outline(outline) if outline is not None else None
    if forced:
        d["forced"] = True  # the user said this is a person: not a drawing, whatever it looks like
    return d


def body_json(body, appearance, img: np.ndarray, with_crop: bool,
              outline: Optional[Any] = None, return_outlines: bool = False) -> Dict:
    kpts = None
    if body.kpts is not None and body.kpt_scores is not None:
        kpts = [[round(float(x), 1), round(float(y), 1), round(float(s), 3)]
                for (x, y), s in zip(body.kpts, body.kpt_scores)]
    d = {
        "bbox": bbox_xywh(body.bbox),
        "score": round(float(body.score), 4),
        "kpts": kpts,
        "appearance": None if appearance is None else [round(float(v), 4) for v in appearance],
        "extent": None if body.kpt_scores is None else pl.body_extent(body.kpt_scores),
        "crop_jpeg": jpeg_b64(body_crop(img, body.bbox, BODY_CROP_MAX_HEIGHT), 10 ** 6) if with_crop else None,
    }
    if return_outlines:
        d["outline"] = encode_outline(outline) if outline is not None else None
    return d


def character_json(c, img: np.ndarray, with_crop: bool, return_outlines: bool = False) -> Dict:
    """A drawn figure shaped like a person: the whole figure plus an optional `face`
    (anime face box, CCIP embedding, crop) and an optional `body` (box, keypoints,
    outfit descriptor, crop). `descriptor` stays for phones that only know the figure."""
    face = None
    if getattr(c, "face_bbox", None) is not None:
        face = {"bbox": bbox_xywh(c.face_bbox), "score": round(float(c.face_score), 4),
                "embedding_model_id": CHARACTER_FACE_MODEL_ID,
                "embedding": None if c.face_embedding is None
                else base64.b64encode(np.asarray(c.face_embedding, dtype="<f4").tobytes()).decode("ascii"),
                "crop_jpeg": jpeg_b64(body_crop(img, c.face_bbox, FACE_CROP_MAX_PX),
                                      FACE_CROP_MAX_PX) if with_crop else None}
    body = None
    if getattr(c, "body_bbox", None) is not None:
        kpts = None
        if c.body_kpts is not None and c.body_kpt_scores is not None:
            kpts = [[round(float(x), 1), round(float(y), 1), round(float(s), 3)]
                    for (x, y), s in zip(c.body_kpts, c.body_kpt_scores)]
        body = {"bbox": bbox_xywh(c.body_bbox), "score": round(float(c.body_score), 4), "kpts": kpts,
                "appearance": None if c.body_appearance is None
                else [round(float(v), 4) for v in c.body_appearance],
                "extent": None if c.body_kpt_scores is None else pl.body_extent(c.body_kpt_scores),
                "crop_jpeg": jpeg_b64(body_crop(img, c.body_bbox, BODY_CROP_MAX_HEIGHT),
                                      10 ** 6) if with_crop else None}
        if return_outlines:
            shape = getattr(c, "body_outline", None)
            body["outline"] = encode_outline(shape) if shape is not None else None
    return {"bbox": bbox_xywh(c.bbox), "score": round(float(c.score), 4), "model_id": c.model_id,
            "descriptor": [round(float(v), 6) for v in c.descriptor],
            "crop_jpeg": jpeg_b64(body_crop(img, c.bbox, BODY_CROP_MAX_HEIGHT), 10 ** 6) if with_crop else None,
            "face": face, "body": body}


def analysis_to_response(result: FrameAnalysis, img: np.ndarray, options: AnalyzeRequestOptions,
                         model_id: str = EMBEDDING_MODEL_ID) -> Dict:
    """AnalyzeImageResponse. Faces without an embedding are impossible with the recognition model
    loaded, so every face is returned and pair indices stay valid."""
    ret_out = getattr(options, "return_outlines", False)
    f_outs = getattr(result, "face_outlines", [])
    b_outs = getattr(result, "body_outlines", [])

    forced = getattr(result, "forced", None) or []
    faces = [
        face_json(
            f, q, p, img, options.return_crops,
            outline=f_outs[i] if i < len(f_outs) else None,
            return_outlines=ret_out,
            forced=bool(forced[i]) if i < len(forced) else False,
        )
        for i, (f, q, p) in enumerate(zip(result.faces, result.quality, result.passes_gate))
    ]
    bodies = [
        body_json(
            b, a, img, options.return_crops,
            outline=b_outs[i] if i < len(b_outs) else None,
            return_outlines=ret_out,
        )
        for i, (b, a) in enumerate(zip(result.bodies, result.appearances))
    ]
    if getattr(options, "return_body_embeddings", False):
        extras = getattr(result, "body_embeddings", None) or []
        for i, body in enumerate(bodies):
            e = extras[i] if i < len(extras) else {}
            body["chest_embedding"] = e.get("chest_embedding")
            body["buttocks_embedding"] = e.get("buttocks_embedding")
            body["morphology"] = e.get("morphology")
    pairs = [{"face_index": int(fi), "body_index": int(bi), "score": round(float(s), 3)}
             for fi, bi, s in result.pairs]
    out = {"model_id": model_id, "image_w": int(result.image_w), "image_h": int(result.image_h),
           "faces": faces, "bodies": bodies, "pairs": pairs}
    out["characters"] = [character_json(c, img, options.return_crops, ret_out) for c in result.characters]
    if getattr(options, "return_body_embeddings", False):
        extras = getattr(result, "character_body_embeddings", None) or []
        for i, character in enumerate(out["characters"]):
            if character.get("body") is None:
                continue
            e = (extras[i] if i < len(extras) else None) or {}
            character["body"]["chest_embedding"] = e.get("chest_embedding")
            character["body"]["buttocks_embedding"] = e.get("buttocks_embedding")
            character["body"]["morphology"] = e.get("morphology")
    if getattr(options, "return_sensitive", False):
        out["sensitive_regions"] = [sensitive_region_json(r) for r in (getattr(result, "sensitive", None) or [])]
    if result.timings_ms:
        out["timings_ms"] = py(result.timings_ms)
    return out


def sensitive_region_json(region: Dict) -> Dict:
    """SensitiveRegion: pixel box like every other bbox on the wire; body_index null when unattached."""
    index = region.get("body_index")
    out = {"label": str(region["label"]), "exposed": bool(region["exposed"]),
           "score": round(float(region["score"]), 4), "bbox": bbox_xywh(region["bbox"]),
           "body_index": None if index is None else int(index)}
    if region.get("character_index") is not None:
        out["character_index"] = int(region["character_index"])   # the region is on a drawn character's body
    return out
