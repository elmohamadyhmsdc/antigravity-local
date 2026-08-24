from pathlib import Path

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import ImageSegmenter, ImageSegmenterOptions
from PIL import Image

from undress_core import build_inpaint_mask

_SELFIE_SEGMENTER_MODEL = Path(__file__).parent / "models" / "selfie_segmenter.tflite"

def generate_body_mask(image_pil, face_app):
    """
    Generates an inpainting mask for the body.
    White = Area to Inpaint (Body/Clothes).
    Black = Keep (Face, Background).
    """
    image_np = np.array(image_pil)

    person_mask_uint8 = np.zeros((h, w), np.uint8)
    if _SELFIE_SEGMENTER_MODEL.exists():
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_np)
        options = ImageSegmenterOptions(
            base_options=BaseOptions(model_asset_path=str(_SELFIE_SEGMENTER_MODEL)),
            output_confidence_masks=True,
        )
        with ImageSegmenter.create_from_options(options) as segmenter:
            result = segmenter.segment(mp_image)
            confidence_mask = result.confidence_masks[0].numpy_view()
        person_mask_uint8 = (np.squeeze(confidence_mask) > 0.5).astype(np.uint8) * 255
    else:
        # Legacy solutions API — only present on older mediapipe wheels (venv_ai).
        # Main venv 0.10.35 ships Tasks only; skip rather than crash import-time.
        import mediapipe.python.solutions.selfie_segmentation as mp_selfie_segmentation_sol

        with mp_selfie_segmentation_sol.SelfieSegmentation(model_selection=1) as selfie_segmentation:
            results = selfie_segmentation.process(image_np)
            person_mask_uint8 = (results.segmentation_mask > 0.5).astype(np.uint8) * 255

    image_bgr = cv2.cvtColor(image_np, cv2.COLOR_RGB2BGR)
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
    codebase). Uses MediaPipe's Tasks API (ImageSegmenter). If the selfie
    segmenter model hasn't been downloaded yet, falls back to the face box alone.
    """
    image_np = np.asarray(image_bgr)
    h, w = image_np.shape[:2]

    person_box = None
    if _SELFIE_SEGMENTER_MODEL.exists():
        image_rgb = cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
        options = ImageSegmenterOptions(
            base_options=BaseOptions(model_asset_path=str(_SELFIE_SEGMENTER_MODEL)),
            output_confidence_masks=True,
        )
        with ImageSegmenter.create_from_options(options) as segmenter:
            result = segmenter.segment(mp_image)
            confidence_mask = result.confidence_masks[0].numpy_view()
        # numpy_view() can return (H, W, 1) rather than (H, W) depending on
        # the model - squeeze to 2D so np.where() yields exactly (ys, xs).
        person_mask = np.squeeze(confidence_mask) > 0.5

        ys, xs = np.where(person_mask)
        if len(xs) > 0:
            person_box = (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))
    else:
        print(f"[PERSON_BBOX] {_SELFIE_SEGMENTER_MODEL} not found; using face box only (no body crop)")

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
