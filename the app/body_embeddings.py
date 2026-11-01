"""
Phase 8 (roadmap section 7.5): visual embeddings and morphology of the exposed body regions NudeNet found,
so faceless photos can be matched to each other. DINOv2 ViT-S/14 (384-d) on the chest / lower-body patch plus the
measurable descriptors the roadmap lists: scale source, relative breast / buttocks span, areola pigmentation
contrast, bare-skin L*a*b* tone and dark-spot constellation (LoG).

Pure onnxruntime + numpy + cv2. Nothing is stored: the phone keeps the vectors, the PC keeps nothing.
Behind its own request flag (`return_body_embeddings`); OSNet (`reid_embedding`) is deliberately NOT here: it is
clothes-dependent and waits for the Phase 0 evidence (roadmap section 7.3).
"""

import base64
from pathlib import Path
from typing import Dict, List, Optional, Sequence

import cv2
import numpy as np

APP_DIR = Path(__file__).resolve().parent
MODEL_PATH = APP_DIR / "models" / "reid" / "dinov2_vits14.onnx"
EMBEDDING_DIM = 384
MODEL_VERSION = 1
KPT_VISIBLE = 0.3
MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# which NudeNet labels make a patch (roadmap 7.5: trigger of each half)
CHEST_LABELS = frozenset({"FEMALE_BREAST_EXPOSED", "MALE_BREAST_EXPOSED", "BELLY_EXPOSED"})
BREAST_LABELS = frozenset({"FEMALE_BREAST_EXPOSED", "MALE_BREAST_EXPOSED"})
LOWER_LABELS = frozenset({"BUTTOCKS_EXPOSED", "FEMALE_GENITALIA_EXPOSED", "MALE_GENITALIA_EXPOSED", "ANUS_EXPOSED"})
MIN_SCORE = 0.5            # a region below this does not make a patch
MIN_PATCH_PX = 32
MAX_MARKS = 12


def model_available(path: Path = MODEL_PATH) -> bool:
    return Path(path).is_file()


def encode_vector(vec: np.ndarray) -> str:
    return base64.b64encode(np.asarray(vec, dtype="<f4").tobytes()).decode("ascii")


class DinoEmbedder:
    def __init__(self, model_path: Path = MODEL_PATH, providers: Optional[list] = None):
        if not Path(model_path).is_file():
            raise FileNotFoundError(f"DINOv2 model not installed: {model_path}")
        import onnxruntime as ort
        if providers is None:
            from body_detector import default_providers
            providers = default_providers()
        try:
            self.session = ort.InferenceSession(str(model_path), providers=providers)
        except Exception:      # a full GPU must not stop the scan
            self.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name

    @staticmethod
    def preprocess(patch_bgr: np.ndarray) -> np.ndarray:
        """Letterbox to a square (no stretching), 224 x 224, RGB, ImageNet normalisation -> (3, 224, 224)."""
        h, w = patch_bgr.shape[:2]
        side = max(h, w)
        square = cv2.copyMakeBorder(patch_bgr, (side - h) // 2, side - h - (side - h) // 2,
                                    (side - w) // 2, side - w - (side - w) // 2, cv2.BORDER_REFLECT)
        rgb = cv2.cvtColor(cv2.resize(square, (224, 224), interpolation=cv2.INTER_AREA), cv2.COLOR_BGR2RGB)
        return ((rgb.astype(np.float32) / 255.0 - MEAN) / STD).transpose(2, 0, 1)

    def embed(self, patches: Sequence[np.ndarray]) -> np.ndarray:
        """(n, 384) unit vectors."""
        if not len(patches):
            return np.zeros((0, EMBEDDING_DIM), dtype=np.float32)
        out = []
        for start in range(0, len(patches), 8):
            batch = np.stack([self.preprocess(p) for p in patches[start:start + 8]]).astype(np.float32)
            out.append(self.session.run(None, {self.input_name: batch})[0])
        vecs = np.concatenate(out).astype(np.float32)
        return vecs / np.maximum(np.linalg.norm(vecs, axis=1, keepdims=True), 1e-9)


# --- geometry ------------------------------------------------------------------------------------------------

def union_box(boxes: Sequence[Sequence[float]], pad: float, width: int, height: int):
    """Union of xyxy boxes, grown by `pad` of its size, clipped to the picture; None when too small."""
    if not boxes:
        return None
    x1, y1 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x2, y2 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    px, py = (x2 - x1) * pad, (y2 - y1) * pad
    x1, y1, x2, y2 = max(0, x1 - px), max(0, y1 - py), min(width, x2 + px), min(height, y2 + py)
    if x2 - x1 < MIN_PATCH_PX or y2 - y1 < MIN_PATCH_PX:
        return None
    return [int(x1), int(y1), int(x2), int(y2)]


def scale_for(body: Dict, shoulders: bool) -> Dict:
    """`kpts` scale (shoulder width for the chest half, hip width for the lower half) when those keypoints are
    visible, else the body box width with scale_source 'bbox' (close-ups): ratios are only compared between
    bodies sharing the same source (roadmap 7.5)."""
    ids = (5, 6) if shoulders else (11, 12)
    kpts, scores = body.get("kpts"), body.get("kpt_scores")
    if kpts is not None and scores is not None and all(scores[i] >= KPT_VISIBLE for i in ids):
        k = np.asarray(kpts, dtype=np.float64)
        width = float(np.linalg.norm(k[ids[0]] - k[ids[1]]))
        if width > 1.0:
            return {"scale_source": "kpts", "scale": width, "origin": ((k[5] + k[6]) / 2 if shoulders else (k[11] + k[12]) / 2)}
    bb = body["bbox"]
    return {"scale_source": "bbox", "scale": max(float(bb[2] - bb[0]), 1.0),
            "origin": np.array([(bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2], dtype=np.float64)}


# --- measurable descriptors ----------------------------------------------------------------------------------

def skin_mask(patch_bgr: np.ndarray) -> np.ndarray:
    """Bare skin in YCrCb (a conservative range): clothes and background are left out of the tone profile."""
    ycrcb = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2YCrCb)
    mask = cv2.inRange(ycrcb, (0, 133, 77), (255, 173, 127))
    return cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8)) > 0


def skin_tone_lab(patch_bgr: np.ndarray) -> Optional[List[float]]:
    mask = skin_mask(patch_bgr)
    if mask.sum() < 50:
        return None
    lab = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2LAB).reshape(-1, 3)[mask.reshape(-1)]
    l, a, b = np.median(lab, axis=0)
    # OpenCV 8-bit Lab -> L* 0..100, a*, b* centred on 0
    return [round(float(l) * 100 / 255, 2), round(float(a) - 128, 2), round(float(b) - 128, 2)]


def areola_contrast(patch_bgr: np.ndarray) -> Optional[float]:
    """Otsu split of the breast box: how much darker the pigmented cluster is than the surrounding skin (0..1)."""
    gray = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2GRAY)
    if gray.size < 400:
        return None
    thr, _ = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    dark, light = gray[gray <= thr], gray[gray > thr]
    if dark.size < 20 or light.size < 20:
        return None
    return round(float((light.mean() - dark.mean()) / 255.0), 4)


def micro_marks(patch_bgr: np.ndarray, box, origin, scale, limit: int = MAX_MARKS,
                exclude: Sequence[Sequence[float]] = ()) -> List[List[float]]:
    """Small dark spots on bare skin (difference of Gaussians), as [dx, dy, strength] from `origin` in units of
    `scale` - mole constellations, matched on the phone with a spatial tolerance."""
    gray = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
    mask = skin_mask(patch_bgr)
    if mask.sum() < 200:
        return []
    fine, coarse = cv2.GaussianBlur(gray, (0, 0), 2.0), cv2.GaussianBlur(gray, (0, 0), 5.0)
    response = np.where(cv2.erode(mask.astype(np.uint8), np.ones((9, 9), np.uint8)) > 0, coarse - fine, 0)
    for ex in exclude:      # the areola / genitalia themselves are not moles: leave the detected regions out
        pad_x, pad_y = (ex[2] - ex[0]) * 0.15, (ex[3] - ex[1]) * 0.15
        x1, y1 = int(max(0, ex[0] - pad_x - box[0])), int(max(0, ex[1] - pad_y - box[1]))
        x2, y2 = int(ex[2] + pad_x - box[0]), int(ex[3] + pad_y - box[1])
        if x2 > 0 and y2 > 0:
            response[y1:max(y2, 0), x1:max(x2, 0)] = 0
    peaks = (response == cv2.dilate(response, np.ones((9, 9), np.uint8))) & (response > 12)
    ys, xs = np.nonzero(peaks)
    order = np.argsort(-response[ys, xs])[:limit]
    marks = []
    for i in order:
        px, py = box[0] + xs[i], box[1] + ys[i]
        marks.append([round(float((px - origin[0]) / scale), 4), round(float((py - origin[1]) / scale), 4),
                      round(float(response[ys[i], xs[i]] / 255.0), 4)])
    return marks


# --- per image -----------------------------------------------------------------------------------------------

def analyse_body(img_bgr: np.ndarray, body: Dict, regions: Sequence[Dict], embedder) -> Dict:
    """chest / buttocks embeddings + morphology for one body from the regions assigned to it."""
    h, w = img_bgr.shape[:2]
    chest = [r["bbox"] for r in regions if r["label"] in CHEST_LABELS and r["score"] >= MIN_SCORE]
    lower = [r["bbox"] for r in regions if r["label"] in LOWER_LABELS and r["score"] >= MIN_SCORE]
    breasts = [r["bbox"] for r in regions if r["label"] in BREAST_LABELS and r["score"] >= MIN_SCORE]
    buttocks = [r["bbox"] for r in regions if r["label"] == "BUTTOCKS_EXPOSED" and r["score"] >= MIN_SCORE]
    result: Dict = {"chest_embedding": None, "buttocks_embedding": None, "morphology": None}
    morphology: Dict = {}
    patches, slots = [], []

    chest_box = union_box(chest, 0.15, w, h)
    if chest_box:
        patch = img_bgr[chest_box[1]:chest_box[3], chest_box[0]:chest_box[2]]
        patches.append(patch)
        slots.append("chest_embedding")
        sc = scale_for(body, shoulders=True)
        morphology.update(scale_source=sc["scale_source"])
        breast_box = union_box(breasts, 0.0, w, h)
        if breast_box:
            morphology["breast_span_ratio"] = round((breast_box[2] - breast_box[0]) / sc["scale"], 4)
            morphology["areola_contrast"] = areola_contrast(img_bgr[breast_box[1]:breast_box[3], breast_box[0]:breast_box[2]])
        morphology["skin_tone_lab"] = skin_tone_lab(patch)
        morphology["micro_marks"] = micro_marks(patch, chest_box, sc["origin"], sc["scale"], exclude=breasts)

    lower_box = union_box(lower, 0.15, w, h)
    if lower_box:
        patch = img_bgr[lower_box[1]:lower_box[3], lower_box[0]:lower_box[2]]
        patches.append(patch)
        slots.append("buttocks_embedding")
        sc = scale_for(body, shoulders=False)
        if "scale_source" in morphology and morphology["scale_source"] != sc["scale_source"]:
            morphology["lower_scale_source"] = sc["scale_source"]
        else:
            morphology.setdefault("scale_source", sc["scale_source"])
        buttocks_box = union_box(buttocks, 0.0, w, h)
        if buttocks_box:
            morphology["buttocks_span_ratio"] = round((buttocks_box[2] - buttocks_box[0]) / sc["scale"], 4)
        morphology.setdefault("skin_tone_lab", skin_tone_lab(patch))

    if patches:
        for slot, vec in zip(slots, embedder.embed(patches)):
            result[slot] = encode_vector(vec)
        result["morphology"] = morphology
    return result


def analyse_bodies(img_bgr: np.ndarray, bodies: Sequence[Dict], regions: Sequence[Dict], embedder) -> List[Dict]:
    """One entry per body (all None for a body with no exposed region)."""
    out = []
    for i, body in enumerate(bodies):
        mine = [r for r in regions if r.get("body_index") == i]
        out.append(analyse_body(img_bgr, body, mine, embedder) if mine else
                   {"chest_embedding": None, "buttocks_embedding": None, "morphology": None})
    return out
