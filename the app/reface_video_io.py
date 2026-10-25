"""Decode verification for rendered parts and published Reface videos."""
from pathlib import Path
import cv2
import numpy as np


def validate_video(path, expected_frames=None, expected_fps=None):
    path = Path(path)
    if not path.exists() or path.stat().st_size <= 0:
        raise ValueError("The encoder did not produce a video")
    cap = cv2.VideoCapture(str(path))
    try:
        if not cap.isOpened():
            raise ValueError("The rendered video cannot be opened")
        fps = float(cap.get(cv2.CAP_PROP_FPS))
        if not np.isfinite(fps) or fps <= 0:
            raise ValueError("The rendered video has no valid frame rate")
        if expected_fps is not None and abs(fps - expected_fps) > max(.02, expected_fps * .001):
            raise ValueError("The rendered video frame rate changed")
        count, shape = 0, None
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if frame is None or not frame.size:
                raise ValueError("The rendered video contains an invalid frame")
            if shape is not None and frame.shape != shape:
                raise ValueError("The rendered video dimensions changed")
            shape = frame.shape
            count += 1
        if not count or (expected_frames is not None and count != expected_frames):
            raise ValueError(f"The rendered video has {count} frames; expected {expected_frames}")
        return dict(frames=count, fps=fps, duration=count / fps)
    finally:
        cap.release()
