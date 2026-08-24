"""
Antigravity Local - LoRA dataset builder

Turns a person's saved face records into a face+body training set for
sd-scripts, reusing the app's existing face restoration and person
segmentation building blocks. Runs in the main venv (Python 3.13) —
no torch/diffusers dependency, only onnxruntime + cv2 + mediapipe,
all already installed there.
"""

import os
from pathlib import Path
from typing import Dict, Optional

import cv2
import numpy as np

from face_restore import FaceRestorer
from mask_utils import get_person_bbox

QUALITY_THRESHOLD = 0.6  # matches database.py / reface_engine_v3.py convention

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def _is_image_source(source_path: str) -> bool:
    return Path(source_path).suffix.lower() in IMAGE_EXTENSIONS


def extract_face_and_body_crop(face_record: Dict, face_app, restorer: Optional[FaceRestorer] = None) -> Dict:
    """
    Given one face record (as stored in database.py's faces.json) and an
    insightface FaceAnalysis instance, return:
        {
            "face_crop": np.ndarray (BGR) or None,
            "body_crop": np.ndarray (BGR) or None,
            "skipped_body": bool,   # True if no body crop could be produced
            "restored": bool,       # True if CodeFormer restoration ran
        }

    Video-sourced faces (source_path is a video file) always skip the body
    crop: face_miner.py tracks a frame_number during mining, but
    database.py's add_face() never persists it, so the exact source frame
    cannot be re-seeked after the fact. Falls back to the already-saved
    face-only crop (image_path) in that case, and whenever the source image
    is missing or unreadable.
    """
    if restorer is None:
        restorer = FaceRestorer(model_name="codeformer", weight=0.5)

    source_path = face_record.get("source_path", "")
    quality_score = float(face_record.get("quality_score", 0.0))
    result = {"face_crop": None, "body_crop": None, "skipped_body": True, "restored": False}

    source_image = None
    if source_path and _is_image_source(source_path) and os.path.exists(source_path):
        source_image = cv2.imread(source_path)

    if source_image is None:
        # Fall back to the already-saved face crop; no body crop possible.
        saved_crop_path = face_record.get("image_path")
        if saved_crop_path and os.path.exists(saved_crop_path):
            face_crop = cv2.imread(saved_crop_path)
        else:
            face_crop = None
        if face_crop is not None and quality_score < QUALITY_THRESHOLD:
            face_crop = restorer.enhance(face_crop)
            result["restored"] = restorer.available
        result["face_crop"] = face_crop
        return result

    h, w = source_image.shape[:2]
    bx, by = int(face_record.get("bbox_x") or 0), int(face_record.get("bbox_y") or 0)
    bw, bh = int(face_record.get("bbox_width") or 0), int(face_record.get("bbox_height") or 0)
    x1, y1 = max(0, bx), max(0, by)
    x2, y2 = min(w, bx + bw), min(h, by + bh)

    face_crop = source_image[y1:y2, x1:x2].copy() if x2 > x1 and y2 > y1 else None
    if face_crop is not None and quality_score < QUALITY_THRESHOLD:
        face_crop = restorer.enhance(face_crop)
        result["restored"] = restorer.available
    result["face_crop"] = face_crop

    person_bbox = get_person_bbox(source_image, face_app)
    if person_bbox is not None:
        px1, py1, px2, py2 = person_bbox
        body_crop = source_image[py1:py2, px1:px2].copy() if px2 > px1 and py2 > py1 else None
        if body_crop is not None:
            result["body_crop"] = body_crop
            result["skipped_body"] = False

    return result


WD14_MODEL_PATH = Path(__file__).parent / "models" / "wd14_tagger_model.onnx"
WD14_TAGS_PATH = Path(__file__).parent / "models" / "wd14_tagger_tags.csv"

QUALITY_FLAG_TAGS = ("low quality", "blurry", "old photo")
BLUR_LAPLACIAN_THRESHOLD = 100.0  # below this variance, treat the crop as blurry


class WD14Tagger:
    """Thin ONNX wrapper around the WD14 tagger (SmilingWolf/wd-v1-4-moat-tagger-v2).
    Runs in the main venv via onnxruntime-gpu, same as face_restore.py's models."""

    def __init__(self, model_path: Path = WD14_MODEL_PATH, tags_path: Path = WD14_TAGS_PATH, threshold: float = 0.35):
        self.available = False
        self.threshold = threshold
        self.session = None
        self.tag_names = []
        if not model_path.exists() or not tags_path.exists():
            print(f"[TAGGER] model or tags file missing ({model_path}, {tags_path}); auto-tagging disabled")
            return
        try:
            import onnxruntime as ort
            import csv

            so = ort.SessionOptions()
            self.session = ort.InferenceSession(str(model_path), sess_options=so,
                                                 providers=["CUDAExecutionProvider", "CPUExecutionProvider"])
            self._input_name = self.session.get_inputs()[0].name
            self._input_size = self.session.get_inputs()[0].shape[1]  # NHWC, e.g. 448
            with open(tags_path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                self.tag_names = [row["name"] for row in reader]
            self.available = True
            print(f"[TAGGER] WD14 loaded ({len(self.tag_names)} tags)")
        except Exception as e:
            print(f"[TAGGER] failed to load: {e}")
            self.session = None

    def tag(self, image_bgr: np.ndarray, max_tags: int = 15) -> list:
        """Returns a list of tag strings above threshold, sorted by confidence."""
        if not self.available or image_bgr is None:
            return []
        try:
            size = self._input_size
            img = cv2.resize(image_bgr, (size, size), interpolation=cv2.INTER_AREA)
            img = img.astype(np.float32)[None, ...]  # NHWC, BGR (model was trained on BGR-order arrays)
            probs = self.session.run(None, {self._input_name: img})[0][0]
            tagged = [(self.tag_names[i], float(p)) for i, p in enumerate(probs) if p >= self.threshold]
            tagged.sort(key=lambda t: t[1], reverse=True)
            return [t[0].replace("_", " ") for t in tagged[:max_tags]]
        except Exception as e:
            print(f"[TAGGER] tagging failed: {e}")
            return []


def _is_blurry(image_bgr: np.ndarray) -> bool:
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < BLUR_LAPLACIAN_THRESHOLD


def build_caption(image_bgr: np.ndarray, trigger_word: str, quality_score: float, tagger: Optional[WD14Tagger] = None) -> str:
    """
    Builds the caption using the idea.txt trick: trigger word + class first,
    then descriptive tags, then explicit quality-flag tags for low-quality or
    blurry sources so the LoRA learns those are photo defects, not identity.
    """
    parts = [f"{trigger_word} person"]

    if tagger is not None and tagger.available:
        parts.extend(tagger.tag(image_bgr))

    quality_flags = []
    if quality_score < QUALITY_THRESHOLD:
        quality_flags.append("low quality")
    if _is_blurry(image_bgr):
        quality_flags.append("blurry")
    parts.extend(quality_flags)

    return ", ".join(parts)


import re
import uuid

from database import get_faces_by_person, set_person_lora_info, get_person_lora_info

MIN_IMAGES_WARN = 15
MIN_IMAGES_BLOCK = 5
DEFAULT_REPEATS = 20


def _slugify(name: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", name).strip("_").lower()
    return slug or "person"


def _get_or_create_trigger_word(person_id: int) -> str:
    info = get_person_lora_info(person_id)
    if info.get("trigger_word"):
        return info["trigger_word"]
    trigger = f"sks{person_id}{uuid.uuid4().hex[:4]}"
    set_person_lora_info(person_id, trigger_word=trigger)
    return trigger


def _write_dataset_records(face_records, trigger_word: str, slug: str, output_root: Path, repeats: int,
                            face_app, restorer: FaceRestorer, tagger: "WD14Tagger") -> Dict:
    """Shared write loop: turns a list of face-record-shaped dicts (either pulled
    from the database or synthesized fresh by detect_face_record_from_image)
    into the sd-scripts folder layout. Both build_dataset() and
    build_dataset_from_uploads() call this after assembling their records."""
    dataset_dir = Path(output_root) / slug / f"{repeats}_{trigger_word} person"
    dataset_dir.mkdir(parents=True, exist_ok=True)

    image_count = 0
    skipped_body_count = 0

    for i, face in enumerate(face_records):
        extracted = extract_face_and_body_crop(face, face_app, restorer=restorer)
        if extracted["skipped_body"]:
            skipped_body_count += 1

        for kind, crop in (("face", extracted["face_crop"]), ("body", extracted["body_crop"])):
            if crop is None:
                continue
            stem = f"{slug}_{i:04d}_{kind}"
            img_path = dataset_dir / f"{stem}.jpg"
            cv2.imwrite(str(img_path), crop)

            caption = build_caption(crop, trigger_word=trigger_word,
                                     quality_score=float(face.get("quality_score", 0.0)), tagger=tagger)
            (dataset_dir / f"{stem}.txt").write_text(caption, encoding="utf-8")
            image_count += 1

    warning = None
    blocked = False
    if image_count < MIN_IMAGES_BLOCK:
        blocked = True
        warning = f"Only {image_count} images available; need at least {MIN_IMAGES_BLOCK} to train."
    elif image_count < MIN_IMAGES_WARN:
        warning = f"Only {image_count} images available; {MIN_IMAGES_WARN}+ is recommended for a good LoRA."

    return {
        "dataset_dir": str(dataset_dir),
        "image_count": image_count,
        "skipped_body_count": skipped_body_count,
        "warning": warning,
        "blocked": blocked,
    }


def build_dataset(person_id: int, person_name: str, face_app, output_root: Path = None,
                   repeats: int = DEFAULT_REPEATS, restorer: Optional[FaceRestorer] = None,
                   tagger: Optional["WD14Tagger"] = None) -> Dict:
    """
    Builds an sd-scripts-compatible dataset for one person from faces already
    mined into the gallery database (database.py's get_faces_by_person):
        {output_root}/{slug}/{repeats}_{trigger} person/*.jpg + *.txt

    Returns {"dataset_dir": str, "image_count": int, "skipped_body_count": int,
             "warning": Optional[str], "blocked": bool}
    """
    if output_root is None:
        output_root = Path(__file__).parent / "lora_datasets"
    if restorer is None:
        restorer = FaceRestorer(model_name="codeformer", weight=0.5)
    if tagger is None:
        tagger = WD14Tagger()

    trigger_word = _get_or_create_trigger_word(person_id)
    slug = _slugify(person_name)
    faces = get_faces_by_person(person_id)
    return _write_dataset_records(faces, trigger_word, slug, output_root, repeats, face_app, restorer, tagger)


def detect_face_record_from_image(image_path: str, face_app) -> Optional[Dict]:
    """
    Runs face detection directly on an image that was NOT pre-mined into the
    gallery database (e.g. freshly uploaded, like Reface V2's "Upload New"
    source mode) and returns a face-record-shaped dict compatible with
    extract_face_and_body_crop(). Uses the same quality-score formula as
    face_miner.py's detect_faces() (det_score weighted by face-size ratio),
    so quality-based restoration/captioning behaves identically either way.
    Returns None if the image can't be read or no face is found in it.
    """
    image = cv2.imread(image_path)
    if image is None:
        return None
    faces = face_app.get(image)
    if not faces:
        return None

    main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    x1, y1, x2, y2 = main_face.bbox.astype(int)
    width, height = int(x2 - x1), int(y2 - y1)

    confidence = float(main_face.det_score)
    img_area = image.shape[0] * image.shape[1]
    size_ratio = (width * height) / img_area if img_area > 0 else 0
    quality_score = min(confidence * (1 + size_ratio * 2), 1.0)

    return {
        "source_path": image_path,
        "bbox_x": int(x1), "bbox_y": int(y1), "bbox_width": width, "bbox_height": height,
        "quality_score": quality_score,
        "image_path": image_path,
    }


def build_dataset_from_uploads(image_paths, person_id: int, person_name: str, face_app,
                                output_root: Path = None, repeats: int = DEFAULT_REPEATS,
                                restorer: Optional[FaceRestorer] = None, tagger: Optional["WD14Tagger"] = None) -> Dict:
    """
    Builds an sd-scripts-compatible dataset directly from a list of uploaded
    image paths, without requiring those photos to already be mined into the
    gallery database first - mirrors the Reface V2 page's "Upload New" source
    mode. person_id only needs a person record for trigger_word/lora_path
    bookkeeping (create one on the fly with database.add_person() if the
    character doesn't already exist as a gallery person).

    Returns the same shape as build_dataset(), plus "skipped_no_face_count"
    for uploaded images where no face could be detected at all.
    """
    if output_root is None:
        output_root = Path(__file__).parent / "lora_datasets"
    if restorer is None:
        restorer = FaceRestorer(model_name="codeformer", weight=0.5)
    if tagger is None:
        tagger = WD14Tagger()

    trigger_word = _get_or_create_trigger_word(person_id)
    slug = _slugify(person_name)

    records = []
    skipped_no_face = 0
    for path in image_paths:
        record = detect_face_record_from_image(path, face_app)
        if record is None:
            skipped_no_face += 1
            continue
        records.append(record)

    result = _write_dataset_records(records, trigger_word, slug, output_root, repeats, face_app, restorer, tagger)
    result["skipped_no_face_count"] = skipped_no_face
    return result
