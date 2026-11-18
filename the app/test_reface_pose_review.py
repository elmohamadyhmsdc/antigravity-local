import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import cv2
import numpy as np

from lora_generate import angle_description
from mobile_api.artifact_jobs import validate_artifact
from mobile_api.errors import ApiError
from mobile_api.reface_poses import RESULT, run_measurement, validate_measurement
from mobile_api.studio_jobs import validate_reface_targets


class PoseReviewTests(unittest.TestCase):
    def test_audit_visits_each_frame_in_trim_including_rare_angles_and_read_errors(self):
        reads = []

        class Capture:
            def get(self, prop):
                return 10 if prop == cv2.CAP_PROP_FPS else 12

            def set(self, _, index):
                self.index = index

            def read(self):
                reads.append(self.index)
                return self.index != 4, np.full((80, 80, 3), self.index, dtype=np.uint8)

            def release(self):
                pass

        def detect(frame):
            index = int(frame[0, 0, 0])
            pose = (6, 52, -16) if index == 5 else (0, -45, 0)
            return [SimpleNamespace(
                pose=None if index == 6 else pose,
                bbox=np.array([0, 0, 70, 70]), det_score=.9)]

        job = {"params": {"media_kind": "video", "start_time": .2, "end_time": .8}}
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def run(stopped):
                return run_measurement(
                    job, root, lambda *args, **kwargs: None, stopped, max_side=800,
                    load_detector=lambda: detect, capture_factory=lambda *_: Capture(),
                )
            self.assertIsNone(run(lambda: len(reads) >= 2))
            self.assertFalse((root / RESULT).exists())
            run(lambda: False)
            report = json.loads((root / RESULT).read_text(encoding="utf-8"))
        self.assertEqual(reads, [2, 3, 4, 5, 6, 7])
        self.assertEqual(report["total_frames"], 6)
        self.assertEqual(report["decoded_frames"], 5)
        self.assertEqual(report["unreadable_frames"], 1)
        self.assertEqual(report["frames_without_pose"], 1)
        self.assertEqual(report["faces_without_pose"], 1)
        self.assertEqual(
            [(row["yaw"], row["pitch"], row["roll"], row["count"], row["timestamp_ms"])
             for row in report["poses"]],
            [(-45, 0, 0, 3, 200), (52, 6, -16, 1, 500)],
        )

    def test_audit_contract_rejects_mismatched_selections_and_trim(self):
        caps = {"engines": {"reface_pose_review": True}}
        body = {"inputs": {"target": "a" * 64},
                "params": {"media_kind": "video", "start_time": 1, "end_time": 3}}
        validate_measurement(body, caps, validate_reface_targets)
        for extra in ({"end_time": 0}, {"target_faces": []}, {"target_indices": [0]}):
            with self.assertRaises(ApiError):
                validate_measurement(
                    dict(body, params=dict(body["params"], **extra)), caps, validate_reface_targets)

    def test_pose_prompts_keep_yaw_sign_roll_and_resume_offset(self):
        poses = [{"yaw": -50, "pitch": 20, "roll": -10}, {"yaw": 46, "pitch": -20, "roll": 25}]
        params = {"trigger_word": "testface", "base_checkpoint": "test", "num_images": 2, "head_poses": poses}
        caps = {"engines": {"lora_generate": True}, "lora_base_checkpoints": ["test"]}
        body = {"type": "generate_lora_images", "params": params, "inputs": {"lora": "a" * 64}}
        validate_artifact(body, caps)
        self.assertIn("left", angle_description(params, (), 0, False))
        resumed = angle_description(dict(params, angle_offset=1), (), 0, False)
        self.assertIn("right", resumed)
        self.assertIn("down by 20", resumed)
        self.assertIn("clockwise by 25", resumed)
        with self.assertRaises(ApiError):
            validate_artifact(dict(body, params=dict(params, angles=["frontal", "profile"])), caps)


if __name__ == "__main__":
    unittest.main()
