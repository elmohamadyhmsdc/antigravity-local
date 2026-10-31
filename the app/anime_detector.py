"""Anime / Cartoon Face Detector using YOLOv8 ONNX (deepghs/anime_face_detection).

Implements letterboxing, output decoding with geometry gates (aspect-ratio & min size),
NMS, and coordinate transformation back to the original image space.
"""
from __future__ import annotations

import os
from typing import List, Tuple, Dict, Any, Optional

import cv2
import numpy as np
import onnxruntime as ort

try:
    import cuda_dll_dirs
    cuda_dll_dirs.add_nvidia_dll_dirs()
except ImportError:
    pass

MIN_FACE_AR = 0.35
MAX_FACE_AR = 1.8
MIN_FACE_PX = 20.0
DEFAULT_CONF = 0.55
DEFAULT_IOU = 0.45
DEFAULT_SIZE = 640
PAD_NORM = 114.0 / 255.0


def letterbox(img: np.ndarray, target_size: int = DEFAULT_SIZE) -> Tuple[np.ndarray, float, int, int]:
    """Scale image maintaining aspect ratio and center-pad to (target_size, target_size).

    Returns:
        canvas: (target_size, target_size, 3) uint8 image with 114 border padding.
        scale: float scaling factor.
        pad_x: horizontal padding offset.
        pad_y: vertical padding offset.
    """
    h, w = img.shape[:2]
    scale = min(target_size / float(w), target_size / float(h))
    nw = max(1, int(round(w * scale)))
    nh = max(1, int(round(h * scale)))
    pad_x = (target_size - nw) // 2
    pad_y = (target_size - nh) // 2

    resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_LINEAR)
    canvas = np.full((target_size, target_size, 3), 114, dtype=np.uint8)
    canvas[pad_y:pad_y + nh, pad_x:pad_x + nw] = resized
    return canvas, scale, pad_x, pad_y


def decode_yolo(output: Any, score_thresh: float = DEFAULT_CONF) -> Tuple[List[List[float]], List[float]]:
    """Decode YOLOv8 output matrix [1, 4+nc, N] or [1, N, 4+nc] to letterbox-space boxes [x1,y1,x2,y2].

    Applies aspect ratio and minimum size geometry filters to drop text banners and UI graphics.
    """
    mat = np.asarray(output)
    if mat.ndim == 3:
        mat = mat[0]
    elif mat.ndim != 2:
        return [], []

    dim0, dim1 = mat.shape
    # Determine layout: channel-major (channels in [5, 64] and dim1 > dim0) vs anchor-major
    channel_major = (5 <= dim0 <= 64) and (dim1 < 5 or dim1 >= dim0)
    channels = dim0 if channel_major else dim1
    anchors = dim1 if channel_major else dim0

    if channels < 5:
        return [], []

    boxes: List[List[float]] = []
    scores: List[float] = []

    for j in range(anchors):
        if channel_major:
            s = float(mat[4, j])
            for c in range(5, channels):
                s = max(s, float(mat[c, j]))
        else:
            s = float(mat[j, 4])
            for c in range(5, channels):
                s = max(s, float(mat[j, c]))

        if s < score_thresh:
            continue

        if channel_major:
            cx = float(mat[0, j])
            cy = float(mat[1, j])
            w = float(mat[2, j])
            h = float(mat[3, j])
        else:
            cx = float(mat[j, 0])
            cy = float(mat[j, 1])
            w = float(mat[j, 2])
            h = float(mat[j, 3])

        if w <= 0.0 or h <= 0.0:
            continue

        # Face-plausibility gate: drawn faces are roughly square.
        ar = w / h
        if ar < MIN_FACE_AR or ar > MAX_FACE_AR:
            continue
        if w < MIN_FACE_PX or h < MIN_FACE_PX:
            continue

        x1 = cx - w / 2.0
        y1 = cy - h / 2.0
        x2 = cx + w / 2.0
        y2 = cy + h / 2.0

        boxes.append([x1, y1, x2, y2])
        scores.append(s)

    return boxes, scores


class AnimeFaceDetector:
    """YOLOv8 Anime Face Detector using ONNX Runtime with CUDA and CPU fallback."""

    def __init__(self, model_path: str):
        if not os.path.exists(model_path):
            raise FileNotFoundError(f"Anime face detection model not found: {model_path}")

        providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        available = ort.get_available_providers()
        chosen = [p for p in providers if p in available]
        if not chosen:
            chosen = ["CPUExecutionProvider"]

        opts = ort.SessionOptions()
        opts.enable_mem_pattern = True
        self.session = ort.InferenceSession(model_path, sess_options=opts, providers=chosen)
        self.input_name = self.session.get_inputs()[0].name
        
        # Check input size if statically defined
        shape = self.session.get_inputs()[0].shape
        self.size = DEFAULT_SIZE
        if len(shape) >= 4 and isinstance(shape[2], int) and shape[2] > 0:
            self.size = shape[2]

    def detect(
        self,
        img: np.ndarray,
        score_thresh: float = DEFAULT_CONF,
        iou_thresh: float = DEFAULT_IOU,
    ) -> List[Dict[str, Any]]:
        """Detect anime faces in an image (BGR or RGB).

        Returns:
            list of dicts with 'bbox': [x1, y1, x2, y2] in original image pixels, and 'score': float.
        """
        orig_h, orig_w = img.shape[:2]
        canvas, scale, pad_x, pad_y = letterbox(img, self.size)

        # Preprocessing: BGR/RGB uint8 -> RGB float32 [0..1] CHW
        # Assuming input is BGR as standard in OpenCV, or RGB
        # YOLOv8 standard: RGB / 255.0
        blob = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB) if canvas.ndim == 3 else canvas
        blob = blob.astype(np.float32) / 255.0
        blob = np.transpose(blob, (2, 0, 1))  # (3, H, W)
        blob = np.expand_dims(blob, axis=0)  # (1, 3, H, W)

        raw_out = self.session.run(None, {self.input_name: blob})
        boxes, scores = decode_yolo(raw_out[0], score_thresh=score_thresh)

        if not boxes:
            return []

        # Convert to format required by cv2.dnn.NMSBoxes: [x, y, w, h]
        cv_boxes = []
        for b in boxes:
            cv_boxes.append([int(b[0]), int(b[1]), int(b[2] - b[0]), int(b[3] - b[1])])

        indices = cv2.dnn.NMSBoxes(cv_boxes, scores, score_thresh, iou_thresh)
        if len(indices) == 0:
            return []

        kept_indices = indices.flatten() if hasattr(indices, "flatten") else [i[0] for i in indices]

        results = []
        for idx in kept_indices:
            b = boxes[idx]
            s = scores[idx]

            # Undo letterbox padding and scaling
            x1 = max(0.0, min(float(orig_w), (b[0] - pad_x) / scale))
            y1 = max(0.0, min(float(orig_h), (b[1] - pad_y) / scale))
            x2 = max(0.0, min(float(orig_w), (b[2] - pad_x) / scale))
            y2 = max(0.0, min(float(orig_h), (b[3] - pad_y) / scale))

            if x2 > x1 and y2 > y1:
                results.append({
                    "bbox": [round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1)],
                    "score": round(float(s), 4),
                })

        return results
