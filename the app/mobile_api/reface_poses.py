"""Audit the selected input before any Reface swap."""

import json
import logging
import math

import cv2
import numpy as np

from .errors import ApiError, bad_request
from .media_decode import DecoderProcess, IsolatedCapture
from .reface_runner import match_boxes
from .schemas import decode_embedding

TYPE = "measure_reface_poses"
RESULT = "reface_poses.json"
POSE_STEPS = (15, 15, 25)
log = logging.getLogger("mobile_api")


def validate_measurement(body, caps, validate_targets):
    params, slots = body.get("params"), body.get("inputs")
    if not isinstance(params, dict) or not isinstance(slots, dict) or set(slots) != {"target"}:
        raise bad_request("An input and pose measurement options are required.")
    kind = params.get("media_kind")
    if kind not in ("image", "video"):
        raise bad_request("Choose a photo or video to measure.")
    allowed = {"media_kind", "target_faces"} if kind == "image" else {
        "media_kind", "start_time", "end_time", "target_embeddings", "target_indices"}
    if set(params) - allowed:
        raise bad_request("An unsupported pose measurement option was supplied.")
    for key in ("start_time", "end_time"):
        if key in params and (type(params[key]) not in (float, int) or not 0 <= params[key] <= 86400):
            raise bad_request("Choose a valid video trim.")
    if "end_time" in params and params["end_time"] <= params.get("start_time", 0):
        raise bad_request("The trim end must be after the start.")
    validate_targets(f"reface_{kind}", params)
    if not caps["engines"].get("reface_pose_review"):
        raise ApiError(409, "engine_unavailable", "Face pose measurement is unavailable on this PC.")


def pose_cell(pose):
    return tuple(math.floor(value / size + .5) for value, size in zip(pose, POSE_STEPS))


class PoseAudit:
    def __init__(self, first, end, fps):
        self.next_frame = first
        self.total = end - first
        self.fps = fps
        self.decoded = self.unreadable = self.no_pose_frames = self.unmeasured_faces = 0
        self.poses = {}

    def record(self, frame_number, faces):
        if faces is None:
            self.unreadable += 1
        else:
            self.decoded += 1
            measured = 0
            for face in faces:
                raw = getattr(face, "pose", None)
                width, height = face.bbox[2:4] - face.bbox[:2]
                if raw is None or len(raw) < 3 or min(width, height) < 40:
                    self.unmeasured_faces += 1
                    continue
                pitch, yaw, roll = map(float, raw[:3])
                pose = (yaw, pitch, roll)
                if not all(math.isfinite(v) and abs(v) <= 180 for v in pose):
                    self.unmeasured_faces += 1
                    continue
                measured += 1
                cell = pose_cell(pose)
                old = self.poses.get(cell)
                quality = float(face.det_score) * min(width, height)
                count = (old[1]["count"] if old else 0) + 1
                low = [min(a, b) for a, b in zip(old[1]["minimum"], pose)] if old else list(pose)
                high = [max(a, b) for a, b in zip(old[1]["maximum"], pose)] if old else list(pose)
                if old is None or quality > old[0]:
                    self.poses[cell] = (quality, dict(zip(("yaw", "pitch", "roll"), map(lambda v: round(v, 2), pose)),
                        count=count, frame=frame_number,
                        timestamp_ms=round(frame_number * 1000 / self.fps)))
                else:
                    old[1]["count"] = count
                self.poses[cell][1].update(minimum=low, maximum=high)
            if measured == 0:
                self.no_pose_frames += 1
        self.next_frame = frame_number + 1

    def result(self):
        return dict(total_frames=self.total, decoded_frames=self.decoded,
                    unreadable_frames=self.unreadable, frames_without_pose=self.no_pose_frames,
                    faces_without_pose=self.unmeasured_faces,
                    poses=sorted((entry for _, entry in self.poses.values()),
                                 key=lambda entry: (-entry["count"], entry["frame"])))


def run_measurement(job, directory, report, stopped, *, max_side, load_detector=None,
                    capture_factory=IsolatedCapture):
    from .scan_worker import ScanWorker
    from reface_selection import FaceSelector
    from reface_tracking import FaceTracker

    params = job["params"]
    target = directory / "input.target"
    video = params["media_kind"] == "video"
    capture = capture_factory(str(target), max_side) if video else None
    worker = None
    try:
        if video:
            fps = float(capture.get(cv2.CAP_PROP_FPS))
            total = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
            if not math.isfinite(fps) or not 0 < fps <= 1000 or total <= 0:
                raise ValueError("The video has no readable frame count.")
            first = round(params.get("start_time", 0) * fps)
            end = min(total, round(params["end_time"] * fps)) if "end_time" in params else total
        else:
            fps, first, end = 1, 0, 1
        if end <= first:
            raise ValueError("The requested range contains no frames.")
        audit = job.setdefault("_pose_audit", PoseAudit(first, end, fps))
        if load_detector is None:
            worker = ScanWorker(log.info)
            detect = worker.pose_faces
        else:
            detect = load_detector()
        refs = params.get("target_embeddings")
        selector = job.get("_pose_selector")
        tracker = job.get("_pose_tracker")
        if refs and selector is None:
            selector = job["_pose_selector"] = FaceSelector(
                [decode_embedding(v) for v in refs], params["target_indices"])
            tracker = job["_pose_tracker"] = FaceTracker()
        previous = job.get("_pose_previous")
        for index in range(audit.next_frame, end):
            if stopped():
                return None
            if capture is not None:
                capture.set(cv2.CAP_PROP_POS_FRAMES, index)
                ok, frame = capture.read()
                if not ok or frame is None:
                    audit.record(index, None)
                    report(min(.99, (index - first + 1) / audit.total), "Unreadable video frame",
                           frames_done=index - first + 1, last_frame=index, details={"total_frames": audit.total})
                    continue
            else:
                if target.stat().st_size > 32 * 1024 * 1024:
                    raise ValueError("The photo is too large to measure.")
                decoder = DecoderProcess()
                try:
                    frame = decoder.image(target.read_bytes(), max_side)
                finally:
                    decoder.close()
            faces = detect(frame)
            if selector is not None:
                small = cv2.resize(frame, (32, 18), interpolation=cv2.INTER_AREA).astype(np.float32)
                if previous is not None and float(np.abs(previous - small).mean()) > 65:
                    tracker.clear()
                    selector.reset()
                previous = job["_pose_previous"] = small
                ids = tracker.update(faces, .5, False)
                faces = [face for face, track in zip(faces, ids)
                         if selector.wants(track, index, lambda face=face: face.normed_embedding)]
            elif "target_faces" in params:
                faces = [faces[i] for i in match_boxes(params["target_faces"], faces)]
            audit.record(index, faces)
            done = index - first + 1
            if done == 1 or done % 4 == 0 or done == audit.total:
                report(min(.99, done / audit.total), f"Measuring face angles ({done}/{audit.total})",
                       frames_done=done, last_frame=index, details={"total_frames": audit.total})
        result = audit.result()
        (directory / RESULT).write_text(json.dumps(result, allow_nan=False), encoding="utf-8")
        for name in ("_pose_audit", "_pose_previous", "_pose_selector", "_pose_tracker"):
            job.pop(name, None)
        return {"total_frames": audit.total, "decoded_frames": audit.decoded}
    finally:
        try:
            if worker is not None:
                worker.close()
        finally:
            if capture is not None:
                capture.release()
