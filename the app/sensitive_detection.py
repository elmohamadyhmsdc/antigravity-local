"""Exposed / covered body-part regions (roadmap section 8) with NudeNet 640m.

Pure onnxruntime + numpy + cv2 like the body models. Two halves:

* `SensitiveDetector` - model I/O (letterbox as NudeNet does: pad bottom/right to a square, resize
  to 640, RGB / 255), YOLOv8 decode, NMS. Raw pixels in, regions out.
* `assign_regions_to_bodies` - pure: which body a region belongs to (no model, unit-tested on CPU).

Nothing here stores an image or a crop. The phone keeps the region rows; the PC keeps nothing.
"""

import os
from pathlib import Path
from typing import Dict, List, Optional, Sequence

import cv2
import numpy as np

APP_DIR = Path(__file__).resolve().parent
MODEL_PATH = APP_DIR / "models" / "sensitive" / "640m.onnx"
MODEL_VERSION = 1            # bump when the model or the decode changes: the phone rescans regions
INPUT_SIZE = 640
DECODE_MIN_SCORE = 0.20      # NudeNet's own decode floor
NMS_SCORE = 0.25
NMS_IOU = 0.45

# Class order of the installed 640m.onnx (read from its metadata 'names').
LABELS = (
    "FEMALE_GENITALIA_COVERED", "FACE_FEMALE", "BUTTOCKS_EXPOSED", "FEMALE_BREAST_EXPOSED",
    "FEMALE_GENITALIA_EXPOSED", "MALE_BREAST_EXPOSED", "ANUS_EXPOSED", "FEET_EXPOSED",
    "BELLY_COVERED", "FEET_COVERED", "ARMPITS_COVERED", "ARMPITS_EXPOSED", "FACE_MALE",
    "BELLY_EXPOSED", "MALE_GENITALIA_EXPOSED", "ANUS_COVERED", "FEMALE_BREAST_COVERED",
    "BUTTOCKS_COVERED",
)

# The roadmap's short names -> the real labels (roadmap section 8.1).
SHORT_NAMES = {
    "exposed_breast": ("FEMALE_BREAST_EXPOSED", "MALE_BREAST_EXPOSED"),
    "exposed_belly": ("BELLY_EXPOSED",),
    "exposed_buttocks": ("BUTTOCKS_EXPOSED",),
    "exposed_genitalia": ("FEMALE_GENITALIA_EXPOSED", "MALE_GENITALIA_EXPOSED"),
    "exposed_anus": ("ANUS_EXPOSED",),
}

# Labels that make a file `isSensitive` (roadmap 8.4): exposed genitals, anus, female breast, buttocks.
SENSITIVE_LABELS = frozenset({
    "FEMALE_GENITALIA_EXPOSED", "MALE_GENITALIA_EXPOSED", "ANUS_EXPOSED",
    "FEMALE_BREAST_EXPOSED", "BUTTOCKS_EXPOSED",
})

# Not returned: faces are the face pipeline's job.
SKIPPED_LABELS = frozenset({"FACE_FEMALE", "FACE_MALE"})

CHEST_LABELS = frozenset({"FEMALE_BREAST_EXPOSED", "MALE_BREAST_EXPOSED", "FEMALE_BREAST_COVERED"})
BELLY_LABELS = frozenset({"BELLY_EXPOSED", "BELLY_COVERED"})
PELVIC_LABELS = frozenset({"FEMALE_GENITALIA_EXPOSED", "FEMALE_GENITALIA_COVERED", "MALE_GENITALIA_EXPOSED",
                           "ANUS_EXPOSED", "ANUS_COVERED", "BUTTOCKS_EXPOSED", "BUTTOCKS_COVERED"})

KPT_VISIBLE = 0.3   # same as person_linking.KPT_VISIBLE


def model_available(path: Path = MODEL_PATH) -> bool:
    return Path(path).is_file()


class SensitiveDetector:
    def __init__(self, model_path: Path = MODEL_PATH, providers: Optional[list] = None):
        if not Path(model_path).is_file():
            raise FileNotFoundError(f"NudeNet model not installed: {model_path}")
        import onnxruntime as ort
        if providers is None:
            from body_detector import default_providers
            providers = default_providers()
        try:
            self.session = ort.InferenceSession(str(model_path), providers=providers)
        except Exception:  # a full GPU must not stop the scan
            self.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name

    def detect(self, img_bgr: np.ndarray) -> List[Dict]:
        """Regions in image pixels: {label, exposed, score, bbox: [x1, y1, x2, y2]}."""
        h, w = img_bgr.shape[:2]
        side = max(h, w)
        padded = cv2.copyMakeBorder(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB), 0, side - h, 0, side - w,
                                    cv2.BORDER_CONSTANT, value=(0, 0, 0))
        blob = cv2.resize(padded, (INPUT_SIZE, INPUT_SIZE)).astype(np.float32) / 255.0
        blob = np.ascontiguousarray(blob.transpose(2, 0, 1)[None])
        out = self.session.run(None, {self.input_name: blob})[0]
        return decode_output(out, side / INPUT_SIZE, w, h)


def decode_output(output: np.ndarray, factor: float, width: int, height: int) -> List[Dict]:
    """YOLOv8 head (1, 4 + classes, anchors) -> regions after NMS. Pure numpy/cv2."""
    rows = np.transpose(np.squeeze(output, 0))          # (anchors, 4 + classes)
    scores = rows[:, 4:4 + len(LABELS)]
    class_ids = scores.argmax(axis=1)
    best = scores[np.arange(len(rows)), class_ids]
    keep = best >= DECODE_MIN_SCORE
    if not keep.any():
        return []
    rows, class_ids, best = rows[keep], class_ids[keep], best[keep]
    cx, cy, bw, bh = rows[:, 0], rows[:, 1], rows[:, 2], rows[:, 3]
    boxes = np.stack([(cx - bw / 2) * factor, (cy - bh / 2) * factor, bw * factor, bh * factor], axis=1)
    picked = cv2.dnn.NMSBoxes(boxes.tolist(), best.tolist(), NMS_SCORE, NMS_IOU)
    regions = []
    for i in np.array(picked).reshape(-1):
        label = LABELS[int(class_ids[i])]
        if label in SKIPPED_LABELS:
            continue
        x, y, w, h = boxes[i]
        x1, y1 = max(0.0, float(x)), max(0.0, float(y))
        x2, y2 = min(float(width), float(x + w)), min(float(height), float(y + h))
        if x2 <= x1 or y2 <= y1:
            continue
        regions.append({"label": label, "exposed": label.endswith("_EXPOSED"), "score": float(best[i]),
                        "bbox": [x1, y1, x2, y2]})
    regions.sort(key=lambda r: -r["score"])
    return regions


# --- region -> body ----------------------------------------------------------------

def _overlap(region_box: Sequence[float], body_box: Sequence[float]) -> float:
    ix1, iy1 = max(region_box[0], body_box[0]), max(region_box[1], body_box[1])
    ix2, iy2 = min(region_box[2], body_box[2]), min(region_box[3], body_box[3])
    return max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)


def _torso_axis(kpts, scores):
    """(shoulder_mid, hip_mid, torso_len) when both shoulders and both hips are visible, else None."""
    if kpts is None or scores is None:
        return None
    if any(float(scores[i]) < KPT_VISIBLE for i in (5, 6, 11, 12)):
        return None
    k = np.asarray(kpts, dtype=np.float64)
    shoulders, hips = (k[5] + k[6]) / 2, (k[11] + k[12]) / 2
    length = float(np.linalg.norm(hips - shoulders))
    return (shoulders, hips, length) if length > 1.0 else None


def plausible_on_torso(label: str, centre, axis) -> bool:
    """Chest labels sit between the shoulders and the hips, pelvic labels near the hips.
    Projected on the shoulder->hip axis so a lying body works too."""
    shoulders, hips, length = axis
    direction = (hips - shoulders) / length
    rel = np.asarray(centre, dtype=np.float64) - shoulders
    t = float(rel @ direction) / length                       # 0 = shoulders, 1 = hips
    lateral = abs(float(rel @ np.array([-direction[1], direction[0]]))) / length
    if lateral > 1.2:
        return False
    if label in CHEST_LABELS:
        return -0.15 <= t <= 0.95
    if label in BELLY_LABELS:
        return 0.15 <= t <= 1.15
    if label in PELVIC_LABELS:
        return 0.6 <= t <= 1.7
    return True


def assign_regions_to_bodies(regions: Sequence[Dict], bodies: Sequence[Dict]) -> List[Optional[int]]:
    """body index per region (None when no body fits).

    `bodies`: dicts with `bbox` (x1, y1, x2, y2 pixels) and optional `kpts` (17 x 2) / `kpt_scores`.
    The region centre must lie inside the body box. Bodies whose torso keypoints are visible must find
    the region plausible; on close-ups without torso keypoints containment plus overlap decides.
    Ties go to the largest overlap."""
    axes = [_torso_axis(b.get("kpts"), b.get("kpt_scores")) for b in bodies]
    result: List[Optional[int]] = []
    for region in regions:
        box = region["bbox"]
        centre = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
        candidates = []
        for i, body in enumerate(bodies):
            bb = body["bbox"]
            if not (bb[0] <= centre[0] <= bb[2] and bb[1] <= centre[1] <= bb[3]):
                continue
            if axes[i] is not None and not plausible_on_torso(region["label"], centre, axes[i]):
                continue
            area = (bb[2] - bb[0]) * (bb[3] - bb[1])
            # largest overlap; on a tie the tighter body (a nested box is the more specific owner)
            candidates.append((round(_overlap(box, bb), 3), -area, -i, i))
        result.append(max(candidates)[3] if candidates else None)
    return result


def detect_for_bodies(detector: SensitiveDetector, img_bgr: np.ndarray, bodies: Sequence[Dict]) -> List[Dict]:
    """Regions with `body_index` filled in (None when unattached)."""
    regions = detector.detect(img_bgr)
    for region, index in zip(regions, assign_regions_to_bodies(regions, bodies)):
        region["body_index"] = index
    return regions


def env_model_path() -> Path:
    return Path(os.environ.get("AG_SENSITIVE_MODEL", MODEL_PATH))
