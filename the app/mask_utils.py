from pathlib import Path
from typing import Optional, Sequence

import cv2
import numpy as np
from PIL import Image

from undress_core import build_inpaint_mask

_RMBG_MODEL_PATH = Path(__file__).parent / "models" / "rmbg.onnx"
_SELFIE_SEGMENTER_MODEL = Path(__file__).parent / "models" / "selfie_segmenter.tflite"

_RMBG_SESSION = None
_RMBG_FAILED = False


def _get_rmbg_session():
    """Lazily loads the RMBG 1.4 ONNX session (CUDA, else CPU). A failed load is not retried."""
    global _RMBG_SESSION, _RMBG_FAILED
    if _RMBG_SESSION is not None or _RMBG_FAILED:
        return _RMBG_SESSION
    if not _RMBG_MODEL_PATH.exists():
        return None
    try:
        from cuda_dll_dirs import add_nvidia_dll_dirs
        add_nvidia_dll_dirs()
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        _RMBG_SESSION = ort.InferenceSession(
            str(_RMBG_MODEL_PATH),
            sess_options=so,
            providers=["CUDAExecutionProvider", "CPUExecutionProvider"],
        )
        return _RMBG_SESSION
    except Exception as e:
        _RMBG_FAILED = True
        print(f"[RMBG] Failed to load RMBG session: {e}")
        return None


def rmbg_input(image_rgb: np.ndarray) -> np.ndarray:
    """RMBG 1.4 preprocessing: RGB, 1024x1024, x/255 - 0.5 (std 1.0), NCHW float32.
    ImageNet mean/std here makes the model call 75-99 % of a photo foreground."""
    resized = cv2.resize(image_rgb, (1024, 1024), interpolation=cv2.INTER_LINEAR)
    return np.ascontiguousarray((resized.astype(np.float32) / 255.0 - 0.5).transpose(2, 0, 1)[None])


def rmbg_mask(raw: np.ndarray, w: int, h: int) -> np.ndarray:
    """RMBG 1.4 postprocessing: min-max normalise, back to (h, w), threshold at 0.5."""
    raw = raw.astype(np.float32)
    lo, hi = float(raw.min()), float(raw.max())
    norm = (raw - lo) / (hi - lo) if hi - lo > 1e-6 else np.zeros_like(raw)
    return (cv2.resize(norm, (w, h), interpolation=cv2.INTER_LINEAR) > 0.5).astype(np.uint8) * 255


def keep_person(mask: np.ndarray, anchor_box: Optional[Sequence[float]]) -> np.ndarray:
    """RMBG keeps every salient object. Keep the foreground of the person whose face is
    `anchor_box`: components touching the face box, plus sizeable ones in the column below
    it (a held object can split the legs off the torso). No anchor, or nothing touching it,
    leaves the mask unchanged."""
    if anchor_box is None or not mask.any():
        return mask
    h, w = mask.shape[:2]
    x1, y1, x2, y2 = [int(round(float(v))) for v in anchor_box[:4]]
    fw = max(1, x2 - x1)
    count, labels, stats, _ = cv2.connectedComponentsWithStats((mask > 0).astype(np.uint8), connectivity=8)
    in_face = np.unique(labels[max(0, y1):max(0, min(h, y2)), max(0, x1):max(0, min(w, x2))])
    col_lo, col_hi = (x1 + x2) / 2 - 2.5 * fw, (x1 + x2) / 2 + 2.5 * fw
    keep = np.zeros(count, bool)
    keep[in_face] = True
    keep[0] = False
    if not keep.any():
        return mask
    for i in range(1, count):
        cx, cy, cw, ch, area = stats[i]
        if area >= 0.01 * h * w and cy + ch > y1 and cx < col_hi and cx + cw > col_lo:
            keep[i] = True
    return np.where(keep[labels], 255, 0).astype(np.uint8)


def get_segmentation_mask(image_rgb: np.ndarray, anchor_box: Optional[Sequence[float]] = None) -> np.ndarray:
    """
    Binary foreground mask, uint8 (H, W), 255 = person.
    image_rgb: (H, W, 3) **RGB** uint8. anchor_box: the person's face (x1, y1, x2, y2), used to
    drop other salient objects. RMBG 1.4 when available, else MediaPipe's selfie segmenter.
    """
    h, w = image_rgb.shape[:2]
    sess = _get_rmbg_session()
    if sess is not None:
        try:
            out = sess.run(None, {sess.get_inputs()[0].name: rmbg_input(image_rgb)})[0]
            return keep_person(rmbg_mask(out[0, 0], w, h), anchor_box)
        except Exception as e:
            print(f"[RMBG] Inference failed, falling back: {e}")

    try:
        if _SELFIE_SEGMENTER_MODEL.exists():
            import mediapipe as mp
            from mediapipe.tasks.python import BaseOptions
            from mediapipe.tasks.python.vision import ImageSegmenter, ImageSegmenterOptions

            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(image_rgb))
            options = ImageSegmenterOptions(
                # A buffer, not a path: mediapipe mangles absolute Windows paths.
                base_options=BaseOptions(model_asset_buffer=_SELFIE_SEGMENTER_MODEL.read_bytes()),
                output_confidence_masks=True,
            )
            with ImageSegmenter.create_from_options(options) as segmenter:
                result = segmenter.segment(mp_image)
                confidence_mask = result.confidence_masks[0].numpy_view()
            mask = (np.squeeze(confidence_mask) > 0.5).astype(np.uint8) * 255
        else:
            import mediapipe.python.solutions.selfie_segmentation as mp_selfie_segmentation_sol
            with mp_selfie_segmentation_sol.SelfieSegmentation(model_selection=1) as selfie_segmentation:
                results = selfie_segmentation.process(image_rgb)
                mask = (results.segmentation_mask > 0.5).astype(np.uint8) * 255
        return keep_person(mask, anchor_box)
    except Exception as e:
        print(f"[MASK] no person segmenter available ({e}); using the face box only")
        return np.zeros((h, w), np.uint8)


def _main_face_box(faces):
    if not faces:
        return None
    main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    return tuple(int(v) for v in main_face.bbox[:4])


def generate_body_mask(image_pil, face_app):
    """
    Generates an inpainting mask for the body.
    White = Area to Inpaint (Body/Clothes).
    Black = Keep (Face, Background).
    """
    image_rgb = np.array(image_pil.convert("RGB"))
    face_box = _main_face_box(face_app.get(cv2.cvtColor(image_rgb, cv2.COLOR_RGB2BGR)))
    person_mask_uint8 = get_segmentation_mask(image_rgb, face_box)
    if face_box is None:
        return Image.fromarray(person_mask_uint8)
    return Image.fromarray(build_inpaint_mask(person_mask_uint8, np.array(face_box)))


def get_person_bbox(image_bgr, face_app, margin_ratio: float = 0.08):
    """
    Returns (x1, y1, x2, y2) bounding the full person (segmentation mask
    unioned with the detected face box), or None if no person/face is found.

    Expects a BGR numpy array (OpenCV convention, matching the rest of this
    codebase). Uses RMBG 1.4 (or the MediaPipe fallback) on the RGB image, keeping
    only the foreground attached to the largest face.
    """
    image_bgr = np.asarray(image_bgr)
    h, w = image_bgr.shape[:2]

    face_box = _main_face_box(face_app.get(image_bgr))
    person_mask = get_segmentation_mask(cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB), face_box) > 127
    person_box = None
    ys, xs = np.where(person_mask)
    if len(xs) > 0:
        person_box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

    if person_box is None and face_box is None:
        return None
    if person_box is None:
        x1, y1, x2, y2 = face_box
    elif face_box is None:
        x1, y1, x2, y2 = person_box
    else:
        x1 = min(person_box[0], face_box[0])
        y1 = min(person_box[1], face_box[1])
        x2 = max(person_box[2], face_box[2])
        y2 = max(person_box[3], face_box[3])

    box_w, box_h = x2 - x1, y2 - y1
    mx, my = int(box_w * margin_ratio), int(box_h * margin_ratio)
    x1 = max(0, x1 - mx)
    y1 = max(0, y1 - my)
    x2 = min(w, x2 + mx)
    y2 = min(h, y2 + my)

    return (x1, y1, x2, y2)
