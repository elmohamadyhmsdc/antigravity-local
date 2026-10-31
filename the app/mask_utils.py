from pathlib import Path
from typing import Optional, Tuple

import cv2
import numpy as np
from PIL import Image

from undress_core import build_inpaint_mask

_RMBG_MODEL_PATH = Path(__file__).parent / "models" / "rmbg.onnx"
_SELFIE_SEGMENTER_MODEL = Path(__file__).parent / "models" / "selfie_segmenter.tflite"

_RMBG_SESSION = None


def _get_rmbg_session():
    """Lazily loads RMBG 1.4 ONNX session with CUDA GPU acceleration."""
    global _RMBG_SESSION
    if _RMBG_SESSION is not None:
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
        print(f"[RMBG] Failed to load RMBG session: {e}")
        return None


def get_segmentation_mask(image_np: np.ndarray) -> np.ndarray:
    """
    Computes a binary segmentation mask for the foreground person/subject.
    Input: image_np (H, W, 3) in RGB or BGR.
    Output: uint8 array of shape (H, W) where 255 is foreground (person).
    Prefers RMBG 1.4 (ONNX) if available, with graceful fallback to MediaPipe.
    """
    h, w = image_np.shape[:2]
    sess = _get_rmbg_session()
    if sess is not None:
        try:
            resized = cv2.resize(image_np, (1024, 1024), interpolation=cv2.INTER_LINEAR)
            rgb = resized.astype(np.float32) / 255.0
            mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
            std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
            norm = (rgb - mean) / std
            blob = norm.transpose(2, 0, 1)[None].astype(np.float32)

            out = sess.run(None, {"input": blob})[0]
            mask = cv2.resize(out[0, 0], (w, h), interpolation=cv2.INTER_LINEAR)
            return (mask > 0.5).astype(np.uint8) * 255
        except Exception as e:
            print(f"[RMBG] Inference failed, falling back: {e}")

    # Fallback to MediaPipe
    if _SELFIE_SEGMENTER_MODEL.exists():
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions
        from mediapipe.tasks.python.vision import ImageSegmenter, ImageSegmenterOptions

        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_np)
        options = ImageSegmenterOptions(
            base_options=BaseOptions(model_asset_path=str(_SELFIE_SEGMENTER_MODEL)),
            output_confidence_masks=True,
        )
        with ImageSegmenter.create_from_options(options) as segmenter:
            result = segmenter.segment(mp_image)
            confidence_mask = result.confidence_masks[0].numpy_view()
        return (np.squeeze(confidence_mask) > 0.5).astype(np.uint8) * 255
    else:
        try:
            import mediapipe.python.solutions.selfie_segmentation as mp_selfie_segmentation_sol
            with mp_selfie_segmentation_sol.SelfieSegmentation(model_selection=1) as selfie_segmentation:
                results = selfie_segmentation.process(image_np)
                return (results.segmentation_mask > 0.5).astype(np.uint8) * 255
        except Exception:
            return np.zeros((h, w), np.uint8)


def generate_body_mask(image_pil, face_app):
    """
    Generates an inpainting mask for the body.
    White = Area to Inpaint (Body/Clothes).
    Black = Keep (Face, Background).
    """
    image_np = np.array(image_pil)
    person_mask_uint8 = get_segmentation_mask(image_np)

    image_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR) if len(image_np.shape) == 3 else image_np
    faces = face_app.get(image_bgr)
    if not faces:
        return Image.fromarray(person_mask_uint8)

    main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
    bbox = main_face.bbox.astype(int)
    return Image.fromarray(build_inpaint_mask(person_mask_uint8, bbox))


def get_person_bbox(image_bgr, face_app, margin_ratio: float = 0.08):
    """
    Returns (x1, y1, x2, y2) bounding the full person (segmentation mask
    unioned with the detected face box), or None if no person/face is found.

    Expects a BGR numpy array (OpenCV convention, matching the rest of this
    codebase). Uses RMBG 1.4 (or MediaPipe fallback).
    """
    image_np = np.asarray(image_bgr)
    h, w = image_np.shape[:2]

    person_mask = get_segmentation_mask(image_np) > 127
    person_box = None
    ys, xs = np.where(person_mask)
    if len(xs) > 0:
        person_box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))

    faces = face_app.get(image_np)
    face_box = None
    if faces:
        main_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
        fx1, fy1, fx2, fy2 = main_face.bbox.astype(int)
        face_box = (fx1, fy1, fx2, fy2)

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
