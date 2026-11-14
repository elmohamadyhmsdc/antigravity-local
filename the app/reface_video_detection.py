"""Current-frame face recovery; never reuse an old face or rendered frame."""
import copy

import cv2
import numpy as np

from reface_tracking import iou


def detect_faces(app, image, *, landmarks=False):
    """Run only detection/recognition and the optional V2 pose/occlusion model."""
    from insightface.app.common import Face

    boxes, points = app.det_model.detect(image, max_num=0, metric="default")
    if len(boxes) == 0:
        boxes, points = app.det_model.detect(image, input_size=[(128, 128), (1280, 1280)], max_num=0)
    faces = []
    for index, box in enumerate(boxes):
        face = Face(bbox=box[:4], kps=points[index] if points is not None else None, det_score=box[4])
        faces.append(face)
    recognition = app.models.get("recognition")
    if recognition is not None:
        # The ArcFace model accepts a batch of crops. Keep current-frame identity
        # checks while reducing separate inference calls in multi-face frames.
        batch = (1 < len(faces) <= 8 and callable(getattr(recognition, "get_feat", None))
                 and all(face.kps is not None for face in faces))
        if batch:
            from insightface.utils.face_align import norm_crop
            try:
                crops = [norm_crop(image, landmark=face.kps, image_size=recognition.input_size[0])
                         for face in faces]
                embeddings = np.asarray(recognition.get_feat(crops))
                if embeddings.shape != (len(faces), 512) or not np.isfinite(embeddings).all():
                    raise ValueError("Unexpected recognition batch output")
                for face, embedding in zip(faces, embeddings):
                    face.embedding = embedding
            except Exception as error:
                # Some recognizer exports only accept a single crop.
                if "out of memory" in str(error).lower():
                    raise
                batch = False
        if not batch:
            for face in faces:
                recognition.get(image, face)
    landmark_model = app.models.get("landmark_3d_68") if landmarks else None
    if landmark_model is not None:
        for face in faces:
            landmark_model.get(image, face)
    return faces


class VideoFaceRecovery:
    """Retry a missed person's expanded region using this frame's real pixels.

    Only current detections passing the caller's identity check can be returned.
    Keep search regions for three misses and discard them at a scene cut.
    """

    def __init__(self):
        self.previous = []
        self.scene = None
        self.recovered = 0
        self.scene_changed = False

    def detect(self, frame, detector, accepts=lambda face: True):
        scene = cv2.resize(frame, (32, 18), interpolation=cv2.INTER_AREA).astype(np.float32)
        self.scene_changed = self.scene is not None and float(np.mean(np.abs(self.scene - scene))) > 65
        if self.scene_changed:
            self.previous.clear()
        self.scene = scene
        faces = list(detector(frame))
        selected = [face for face in faces if accepts(face)]
        pending = []
        height, width = frame.shape[:2]
        for previous, misses in self.previous:
            box = np.asarray(previous.bbox, np.float64)
            if any(iou(box, face.bbox) >= .15 for face in selected):
                continue
            size = np.maximum(box[2:] - box[:2], 1)
            margin = size * (.6 + misses * .2)
            vel = getattr(previous, "_vel", None)
            shift = (np.asarray(vel, np.float64) * (misses + 1)) if vel is not None else np.zeros(2)
            center = (box[:2] + box[2:]) / 2.0 + shift
            half = (size / 2.0) + margin
            x0, y0 = np.maximum(0, np.floor(center - half)).astype(int)
            x1, y1 = np.minimum([width, height], np.ceil(center + half)).astype(int)
            found = False
            if x1 - x0 >= 32 and y1 - y0 >= 32 and (x0, y0, x1, y1) != (0, 0, width, height):
                for candidate in detector(frame[y0:y1, x0:x1]):
                    # InsightFace.Face is a dict with dynamic attributes; deepcopy
                    # mistakes its missing __setstate__ for an actual method.
                    candidate = type(candidate)(dict(candidate)) if isinstance(candidate, dict) else copy.deepcopy(candidate)
                    candidate.bbox = np.asarray(candidate.bbox, np.float32) + [x0, y0, x0, y0]
                    for name in ("kps", "landmark_3d_68", "landmark_2d_106"):
                        points = getattr(candidate, name, None)
                        if points is not None:
                            points = np.asarray(points, np.float32).copy()
                            points[:, :2] += [x0, y0]
                            setattr(candidate, name, points)
                    if iou(box, candidate.bbox) < .15 or not accepts(candidate):
                        continue
                    if any(iou(candidate.bbox, face.bbox) >= .3 for face in selected):
                        continue
                    # Replace an uncertain full-frame detection at the same box.
                    faces = [face for face in faces if iou(candidate.bbox, face.bbox) < .3]
                    faces.append(candidate)
                    selected.append(candidate)
                    self.recovered += 1
                    found = True
            if not found and misses < 2:
                pending.append((previous, misses + 1))
        updated_prev = []
        for face in selected:
            face_box = np.asarray(face.bbox, np.float64)
            face_center = (face_box[:2] + face_box[2:]) / 2.0
            match = next((p for p, _ in self.previous if iou(face_box, p.bbox) >= 0.2), None)
            if match is not None:
                p_center = (np.asarray(match.bbox[:2], np.float64) + np.asarray(match.bbox[2:], np.float64)) / 2.0
                face._vel = face_center - p_center
            else:
                face._vel = getattr(face, "_vel", np.zeros(2))
            updated_prev.append((face, 0))
        self.previous = (updated_prev + pending)[:16]
        return faces
