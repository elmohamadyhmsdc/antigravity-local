"""
Roadmap Phase 7 (optional): garment tags for a body, from the WD14 tagger that is already installed
(models/wd14_tagger_model.onnx). The tagger is anime-trained, so these scores are raw evidence stored on the
phone for the user's own labelling - NO tag is a filter until its precision on real photos has been measured
(docs/body-pose-and-clothing-filters-roadmap.md section 5.4).

Pure helpers (`crop_for_body`, `select_scores`) work on arrays and plain dicts, so they are tested on the CPU
without a model; `GarmentTagger` is the thin onnxruntime wrapper that shares `lora_dataset.WD14Tagger`'s session.
"""

from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np

# Bumped when the vocabulary or the crop / scoring changes; the phone re-asks rows below it.
GARMENT_VERSION = 1

MIN_SCORE = 0.15      # nothing below this is worth storing
MAX_TAGS_PER_BODY = 24
MIN_CROP_SIDE = 32    # px; a smaller body is not tagged
CROP_PAD = 0.05

# WD14 (danbooru) tag -> garment category. Only tags the installed tag file really has are used.
VOCABULARY: Dict[str, str] = {
    **{t: "upper" for t in ("t-shirt", "shirt", "collared_shirt", "polo_shirt", "hoodie", "tank_top", "crop_top",
                            "sweater", "turtleneck", "cardigan", "vest", "sports_bra")},
    **{t: "outerwear" for t in ("jacket", "blazer", "coat", "trench_coat", "denim_jacket", "leather_jacket",
                                "track_jacket")},
    **{t: "lower" for t in ("jeans", "pants", "shorts", "short_shorts", "denim_shorts", "skirt", "miniskirt",
                            "pleated_skirt", "leggings", "sweatpants")},
    **{t: "full_body" for t in ("suit", "dress", "jumpsuit", "one-piece_swimsuit", "bikini", "swimsuit",
                                "swim_trunks")},
    **{t: "pattern" for t in ("striped", "plaid", "polka_dot")},
    **{t: "accessory" for t in ("hat", "baseball_cap", "beanie", "hood", "hood_up", "sunglasses", "glasses",
                                "necktie", "scarf", "bag", "handbag", "backpack")},
    **{t: "footwear" for t in ("sneakers", "boots", "high_heels", "sandals", "barefoot")},
}


def crop_for_body(img_bgr: np.ndarray, bbox_xyxy: Sequence[float]) -> Optional[np.ndarray]:
    """The body box with a small margin, clamped to the image; None when it is too small to tag."""
    h, w = img_bgr.shape[:2]
    x1, y1, x2, y2 = (float(v) for v in bbox_xyxy)
    pad_x, pad_y = (x2 - x1) * CROP_PAD, (y2 - y1) * CROP_PAD
    ix1, iy1 = max(0, int(round(x1 - pad_x))), max(0, int(round(y1 - pad_y)))
    ix2, iy2 = min(w, int(round(x2 + pad_x))), min(h, int(round(y2 + pad_y)))
    if ix2 - ix1 < MIN_CROP_SIDE or iy2 - iy1 < MIN_CROP_SIDE:
        return None
    return img_bgr[iy1:iy2, ix1:ix2]


def select_scores(names: Sequence[str], probs: Sequence[float],
                  vocabulary: Optional[Dict[str, str]] = None) -> List[Dict]:
    """Vocabulary tags at or above MIN_SCORE, best first: [{tag, category, score}] (score rounded to 4 places)."""
    vocabulary = VOCABULARY if vocabulary is None else vocabulary
    out = [{"tag": name, "category": vocabulary[name], "score": round(float(p), 4)}
           for name, p in zip(names, probs) if name in vocabulary and float(p) >= MIN_SCORE]
    out.sort(key=lambda t: (-t["score"], t["tag"]))
    return out[:MAX_TAGS_PER_BODY]


class GarmentTagger:
    """Reads the vocabulary's probabilities from a loaded `WD14Tagger` (one forward pass per body crop)."""

    def __init__(self, tagger=None):
        if tagger is None:
            from lora_dataset import WD14Tagger
            tagger = WD14Tagger()
        self._tagger = tagger
        self.available = bool(getattr(tagger, "available", False))

    def tag_crop(self, crop_bgr: np.ndarray) -> List[Dict]:
        if not self.available:
            return []
        import cv2
        t = self._tagger
        size = t._input_size
        img = cv2.resize(crop_bgr, (size, size), interpolation=cv2.INTER_AREA).astype(np.float32)[None, ...]
        probs = t.session.run(None, {t._input_name: img})[0][0]
        return select_scores(t.tag_names, probs)

    def tag_bodies(self, img_bgr: np.ndarray, bodies: Sequence[Dict]) -> List[List[Dict]]:
        """One tag list per body (an empty list for a body too small to tag), in order."""
        out: List[List[Dict]] = []
        for b in bodies:
            crop = crop_for_body(img_bgr, b["bbox"])
            out.append([] if crop is None else self.tag_crop(crop))
        return out


def model_available() -> bool:
    from lora_dataset import WD14_MODEL_PATH, WD14_TAGS_PATH
    return WD14_MODEL_PATH.exists() and WD14_TAGS_PATH.exists()
