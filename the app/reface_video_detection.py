"""Recover faces from current pixels using detection and short, verified landmark tracks."""
import copy
import time
from collections import deque

import cv2
import numpy as np

from reface_tracking import iou, unit


def detect_faces(app, image, *, landmarks=False, fine=False):
    """Run only detection/recognition and the optional V2 pose/occlusion model."""
    from insightface.app.common import Face

    if fine:
        boxes, points = app.det_model.detect(image, input_size=[(128, 128), (1280, 1280)], max_num=0)
    else:
        boxes, points = app.det_model.detect(image, max_num=0, metric="default")
        if len(boxes) == 0:
            return detect_faces(app, image, landmarks=landmarks, fine=True)
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


def _copy_face(face):
    # InsightFace stores dynamic fields in a dict and does not support deepcopy.
    return type(face)(dict(face)) if isinstance(face, dict) else copy.copy(face)


def _region_faces(frame, detector, rect, roll=0.):
    """Detect in a current-frame crop and map all 2-D coordinates back to the video."""
    x0, y0, x1, y1 = rect
    if x1 - x0 < 32 or y1 - y0 < 32:
        return
    roi = frame[y0:y1, x0:x1]
    if roll:
        h, w = roi.shape[:2]
        rotation = cv2.getRotationMatrix2D((w * .5, h * .5), roll, 1.)
        roi = cv2.warpAffine(roi, rotation, (w, h), borderMode=cv2.BORDER_REPLICATE)
        inverse = cv2.invertAffineTransform(rotation)
    elif roi.shape == frame.shape:
        return
    else:
        inverse = np.eye(2, 3, dtype=np.float32)
    inverse[:, 2] += [x0, y0]
    for detected in detector(roi):
        face = _copy_face(detected)
        left, top, right, bottom = detected.bbox
        corners = np.float32([[[left, top], [right, top], [right, bottom], [left, bottom]]])
        corners = cv2.transform(corners, inverse)[0]
        face.bbox = np.r_[np.maximum(corners.min(0), 0),
                          np.minimum(corners.max(0), frame.shape[1::-1])].astype(np.float32)
        for name in ("kps", "landmark_3d_68", "landmark_2d_106"):
            points = getattr(detected, name, None)
            if points is not None:
                points = np.asarray(points, np.float32).copy()
                points[:, :2] = cv2.transform(points[None, :, :2], inverse)[0]
                setattr(face, name, points)
        if roll and getattr(face, "pose", None) is not None and face.kps is not None:
            face.pose = np.asarray(face.pose, np.float32).copy()
            eye_line = face.kps[1] - face.kps[0]
            face.pose[2] = np.degrees(np.arctan2(eye_line[1], eye_line[0]))
        yield face


class VideoFaceRecovery:
    """Search missed regions and bridge brief detector gaps with current identity evidence."""

    def __init__(self, recognition=None):
        self.previous = []
        self.scene = None
        self.gray = None
        self.recognition = recognition
        self.recovered = 0
        self.scene_changed = False
        self.missing = False
        self.miss_streak = 0
        self.lost_vectors = []

    def _flow_face(self, gray, previous, shift):
        """Track five landmarks in raw frames, checking forward/backward agreement."""
        from insightface.app.common import Face

        points = np.asarray(previous.kps, np.float32)
        box = np.asarray(previous.bbox, np.float32)
        size = box[2:] - box[:2]
        if (points.shape != (5, 2) or not np.isfinite(points).all()
                or not np.isfinite(box).all() or min(size) < 16):
            return None
        h, w = gray.shape
        x0, y0 = np.maximum(0, np.floor(box[:2] + np.minimum(shift, 0) - size)).astype(int)
        x1, y1 = np.minimum([w, h], np.ceil(box[2:] + np.maximum(shift, 0) + size)).astype(int)
        if x1 - x0 < 24 or y1 - y0 < 24:
            return None
        old = self.gray[y0:y1, x0:x1]
        new = gray[y0:y1, x0:x1]
        origin = np.float32([x0, y0])
        start = (points - origin).reshape(-1, 1, 2)
        options = dict(winSize=(21, 21), maxLevel=3)
        moved, ok, error = cv2.calcOpticalFlowPyrLK(old, new, start, None, **options)
        if moved is None or not np.isfinite(moved).all():
            return None
        back, reverse_ok, _ = cv2.calcOpticalFlowPyrLK(new, old, moved, None, **options)
        if back is None:
            return None
        good = ((ok.ravel() != 0) & (reverse_ok.ravel() != 0) & (error.ravel() < 30)
                & (np.linalg.norm((back - start)[:, 0], axis=1) <= np.clip(max(size) * .025, 1., 4.)))
        if good.sum() < 4:
            return None
        current = moved[:, 0] + origin
        matrix, inliers = cv2.estimateAffinePartial2D(
            points[good], current[good], ransacReprojThreshold=float(np.clip(max(size) * .06, 2., 8.)))
        if matrix is None or inliers.sum() < 4 or not .7 <= np.linalg.norm(matrix[:, 0]) <= 1.4:
            return None
        trusted = np.flatnonzero(good)[inliers.ravel().astype(bool)]
        kps = cv2.transform(points[None], matrix)[0]
        kps[trusted] = current[trusted]
        if not ((kps >= 0).all() and (kps < [w, h]).all()):
            return None
        corners = box[[0, 1, 2, 1, 2, 3, 0, 3]].reshape(1, 4, 2)
        corners = cv2.transform(corners, matrix)[0]
        bounds = np.r_[np.maximum(corners.min(0), 0), np.minimum(corners.max(0), [w, h])]
        return Face(kps=kps, bbox=bounds.astype(np.float32))

    def detect(self, frame, detector, accepts=lambda face: True, profile_candidate=None,
               *, fine_detector=None, initial_faces=None):
        scene = cv2.resize(frame, (32, 18), interpolation=cv2.INTER_AREA).astype(np.float32)
        self.scene_changed = self.scene is not None and float(np.mean(np.abs(self.scene - scene))) > 65
        if self.gray is not None and self.gray.shape != frame.shape[:2]:
            self.scene_changed = True
        if self.scene_changed:
            self.previous.clear()
            self.gray = None
            self.miss_streak = 0
            self.lost_vectors.clear()
        self.scene = scene
        faces = list(detector(frame) if initial_faces is None else initial_faces)
        standard_found_faces = bool(faces)
        selected = [face for face in faces if accepts(face)]
        selected_ids = {id(face) for face in selected}
        profiles = ([f for f in faces if id(f) not in selected_ids and profile_candidate(f)]
                    if profile_candidate else [])
        pending = []
        missing_tracks = []
        height, width = frame.shape[:2]
        can_verify = callable(getattr(self.recognition, "get", None))
        gray = None
        matched = {}
        for previous, misses in self.previous:
            box = np.asarray(previous.bbox, np.float64)
            size = np.maximum(box[2:] - box[:2], 1)
            margin = size * (.6 + misses * .2)
            vel = getattr(previous, "_vel", None)
            shift = (np.asarray(vel, np.float64) * (misses + 1)) if vel is not None else np.zeros(2)
            predicted = box + np.tile(shift, 2)
            last_center = (box[:2] + box[2:]) * .5
            center = last_center + shift
            previous_vector = unit(getattr(previous, "embedding", None))

            def same_profile(face):
                current = unit(getattr(face, "embedding", None))
                return (current is not None and previous_vector is not None
                        and float(previous_vector @ current) >= .55)

            def eligible(face):
                return accepts(face) or (profile_candidate is not None
                                         and same_profile(face) and profile_candidate(face))

            def match_score(face):
                current = unit(getattr(face, "embedding", None))
                overlap = iou(box, face.bbox)
                if current is None or previous_vector is None:
                    return overlap if overlap >= .15 else 0.
                similarity = float(previous_vector @ current)
                if similarity < .25:
                    return 0.
                # Use the prediction only when the current identity supports it.
                if similarity >= .4:
                    overlap = max(overlap, iou(predicted, face.bbox))
                if overlap >= .15:
                    return overlap * (1 + similarity)
                # A fast translation or reversal can clear both boxes. Accept a
                # nearby match only with strong identity and keep its score below
                # any overlapping match.
                if similarity >= .65:
                    middle = (np.asarray(face.bbox[:2]) + face.bbox[2:]) * .5
                    travel = min(np.linalg.norm((middle - center) / size),
                                 np.linalg.norm((middle - last_center) / size))
                    if travel <= 1.25:
                        return .1 / (1 + travel)
                return 0.

            available = [f for f in selected if id(f) not in matched]
            available.extend(f for f in profiles if id(f) not in matched and same_profile(f))
            best = max(available, key=match_score, default=None)
            if best is not None and match_score(best) > 0:
                matched[id(best)] = previous, misses
                if id(best) not in selected_ids:
                    selected.append(best)
                    selected_ids.add(id(best))
                continue
            half = (size / 2.0) + margin
            x0, y0 = np.maximum(0, np.floor(center - half)).astype(int)
            x1, y1 = np.minimum([width, height], np.ceil(center + half)).astype(int)
            def search(rect, roll=0.):
                recovered = []
                for candidate in _region_faces(frame, detector, rect, roll):
                    score = match_score(candidate)
                    if score <= 0 or not eligible(candidate):
                        continue
                    if any(iou(candidate.bbox, face.bbox) >= .3 for face in selected):
                        continue
                    recovered.append((score, candidate))
                return recovered

            rect = (x0, y0, x1, y1)
            recovered = search(rect)
            if not recovered:
                # Include room to turn back on either side of the last observation.
                lo = np.maximum(0, np.floor(np.minimum(box[:2], predicted[:2]) - size)).astype(int)
                hi = np.minimum([width, height], np.ceil(np.maximum(box[2:], predicted[2:]) + size)).astype(int)
                wider = (*lo, *hi)
                points = getattr(previous, "kps", None)
                roll = 0.
                if points is not None and np.shape(points) == (5, 2):
                    eye_line = np.subtract(points[1], points[0])
                    angle = float(np.degrees(np.arctan2(eye_line[1], eye_line[0])))
                    if abs(angle) >= 22:
                        roll = angle
                if roll or np.max(np.abs(shift) / size) >= .35:
                    if roll or wider != rect:
                        recovered = search(wider, roll)
            # If detection missed even in the ROI, LK can follow eyes, nose and
            # mouth through a couple of blurred frames. Always re-embed the raw
            # current crop and compare with the last detector-confirmed identity.
            depth = getattr(previous, "_flow_depth", 0) or 0
            if (not recovered and misses == 0 and depth < 2 and can_verify
                    and self.gray is not None and previous_vector is not None):
                if gray is None:
                    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                candidate = self._flow_face(gray, previous, shift)
                if candidate is not None and not any(iou(candidate.bbox, f.bbox) >= .3 for f in faces):
                    anchor = getattr(previous, "_flow_anchor", None)
                    if anchor is None:
                        anchor = previous_vector
                    self.recognition.get(frame, candidate)
                    current = unit(candidate.embedding)
                    if current is not None and float(anchor @ current) >= .50 and eligible(candidate):
                        candidate._flow_anchor = anchor
                        candidate._flow_depth = depth + 1
                        recovered.append((float(anchor @ current), candidate))
            # The first sharp tilt may have the opposite sign to the last pose.
            # Try another orientation only on a changed, textured face region
            # after both ordinary recovery and verified tracking have failed.
            if not recovered and misses == 0 and self.gray is not None:
                if gray is None:
                    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
                bx, by, ex, ey = np.clip(box, 0, [width,height,width,height]).astype(int)
                patch = gray[by:ey, bx:ex]
                before = self.gray[by:ey, bx:ex]
                if patch.size and patch.std() > 8 and cv2.norm(patch, before, cv2.NORM_L1) > 4 * patch.size:
                    for angle in ((-roll,) if roll else (45., -45.)):
                        recovered = search(wider, angle)
                        if recovered:
                            break
            if recovered:
                _, candidate = max(recovered, key=lambda item: item[0])
                # Only replace an overlapping detection associated with this track.
                faces = [f for f in faces if iou(candidate.bbox, f.bbox) < .3 or match_score(f) <= 0]
                faces.append(candidate)
                selected.append(candidate)
                matched[id(candidate)] = previous, misses
                self.recovered += 1
            else:
                missing_tracks.append(previous)
                if misses < 2:
                    pending.append((previous, misses + 1))

        # A second selected person still on screen must not suppress the search
        # for a lost one once the short-lived spatial prediction expires.
        if fine_detector is not None:
            wanted = [(v, ttl - 1) for v, ttl in self.lost_vectors if ttl > 1]
            for lost in missing_tracks:
                v = unit(getattr(lost, "embedding", None))
                if v is not None and not any(float(v @ other) >= .55 for other, _ in wanted):
                    wanted.append((v, 16))
            seen = [v for f in selected if (v := unit(getattr(f, "embedding", None))) is not None]
            self.lost_vectors = [(v, ttl) for v, ttl in wanted
                                 if not any(float(v @ other) >= .55 for other in seen)][:16]
        self.missing = not selected or bool(missing_tracks or self.lost_vectors)
        # An empty standard pass already ran at extra scales. When only a
        # bystander was found, also search away from stale track predictions.
        if (self.missing and standard_found_faces and fine_detector is not None
                and (self.miss_streak < 2 or self.miss_streak % 4 == 0)):
            for candidate in fine_detector(frame):
                if not accepts(candidate) or any(iou(candidate.bbox, f.bbox) >= .3 for f in faces):
                    continue
                faces.append(candidate)
                selected.append(candidate)
                self.recovered += 1
                vector = unit(getattr(candidate, "embedding", None))
                if vector is not None:
                    self.lost_vectors = [(v, ttl) for v, ttl in self.lost_vectors if float(v @ vector) < .55]
                if missing_tracks and vector is not None:
                    def similarity(old):
                        previous_vector = unit(getattr(old, "embedding", None))
                        return float(vector @ previous_vector) if previous_vector is not None else -1.
                    best = max(missing_tracks, key=similarity)
                    if similarity(best) >= .55:
                        missing_tracks = [f for f in missing_tracks if f is not best]
                        pending = [(f, age) for f, age in pending if f is not best]
            self.missing = not selected or bool(missing_tracks or self.lost_vectors)
        self.miss_streak = self.miss_streak + 1 if self.missing else 0
        updated_prev = []
        for face in selected:
            face_box = np.asarray(face.bbox, np.float64)
            face_center = (face_box[:2] + face_box[2:]) / 2.0
            match = matched.get(id(face))
            if match is not None:
                previous, misses = match
                p_center = (np.asarray(previous.bbox[:2], np.float64) + np.asarray(previous.bbox[2:], np.float64)) / 2.0
                face._vel = (face_center - p_center) / (misses + 1)
            else:
                face._vel = getattr(face, "_vel", np.zeros(2))
            # The render tracker smooths its own landmarks after this call.
            # Optical flow starts on the observed pixels before that smoothing.
            observed = _copy_face(face)
            updated_prev.append((observed, 0))
        self.previous = (updated_prev + pending)[:16]
        if gray is None and can_verify and updated_prev:
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        self.gray = gray if updated_prev else None
        return faces

    def locate_clip(self, frames, detector, accepts, profile_candidate, fine_detector=None):
        """Yield frames in order. Revisit short unresolved gaps from a later verified face."""
        waiting = deque()
        for frame in frames:
            before = self.recovered
            started = time.perf_counter()
            faces = self.detect(frame, detector, accepts, profile_candidate, fine_detector=fine_detector)
            elapsed = (time.perf_counter() - started) * 1000
            item = [frame, faces, self.recovered - before, elapsed]
            if self.scene_changed:
                while waiting:
                    yield waiting.popleft()
            if self.missing:
                # Keep at most four original frames, and less for 4K/8K inputs.
                limit = min(4, (48 << 20) // frame.nbytes)
                waiting.append(item)
                while len(waiting) > limit:
                    yield waiting.popleft()
                continue
            if waiting:
                anchors = [f for f in faces if accepts(f) and not getattr(f, "_flow_depth", 0)]
                if anchors:
                    reverse = VideoFaceRecovery(self.recognition)
                    seeds = [_copy_face(f) for f in anchors]
                    for seed in seeds:
                        seed._vel = np.zeros(2)
                    reverse.detect(frame, detector, accepts, initial_faces=seeds)
                    for earlier in reversed(waiting):
                        raw, known, _, _ = earlier
                        started = time.perf_counter()
                        # Copy detection fields so reverse velocity never affects
                        # forward tracking. Never replace another person's box.
                        cached = [_copy_face(f) for f in known]
                        candidates = reverse.detect(raw, detector, accepts, initial_faces=cached)
                        for candidate in candidates:
                            if accepts(candidate) and not any(iou(candidate.bbox, f.bbox) >= .3 for f in known):
                                known.append(candidate)
                                earlier[2] += 1
                        earlier[3] += (time.perf_counter() - started) * 1000
                while waiting:
                    yield waiting.popleft()
            yield item
        yield from waiting
