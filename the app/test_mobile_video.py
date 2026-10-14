"""CPU-only video lifecycle, ownership, retry and frame-sampling tests. No model downloads."""

import hashlib
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path

import cv2
import numpy as np
from fastapi.testclient import TestClient

from mobile_api.app import create_app
from mobile_api.testing import make_test_context


class Capture:
    """Six frames at 2 fps, including a face/body on every sampled frame."""
    def __init__(self, path):
        self.position = 0

    def isOpened(self):
        return True

    def get(self, prop):
        return 2 if prop == cv2.CAP_PROP_FPS else 6

    def set(self, prop, value):
        self.position = int(value)

    def read(self):
        return True, np.full((480, 640, 3), self.position * 10, np.uint8)

    def release(self):
        pass


class VideoTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ag_video_test_")
        self.ctx = make_test_context(Path(self.tmp.name))
        self.app = create_app(self.ctx)
        self.ctx.video_jobs.capture = Capture
        self.client = TestClient(self.app)
        self.device = self.ctx.auth.add_device("Phone")
        self.headers = {"Authorization": "Bearer " + self.device["token"]}
        data = b"fake-video-content"
        self.sha = hashlib.sha256(data).hexdigest()
        self.client.put("/v1/blobs/" + self.sha, content=data, headers=self.headers)
        self.body = {"type": "analyze_video", "params": {"frame_interval": 1},
                     "inputs": {"video": self.sha}, "client_job_id": "phone-attempt-1"}

    def tearDown(self):
        self.ctx.video_jobs.close()
        self.client.close()
        self.tmp.cleanup()

    def create(self, body=None):
        result = self.client.post("/v1/jobs", json=body or self.body, headers=self.headers)
        self.assertEqual(result.status_code, 201, result.text)
        return result.json()["job_id"]

    def wait(self, job_id, states=("completed", "failed")):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            job = self.client.get("/v1/jobs/" + job_id, headers=self.headers).json()
            if job["status"] in states:
                return job
            time.sleep(0.01)
        self.fail("Video worker did not finish")

    def test_full_lifecycle_and_result_integrity(self):
        job_id = self.create()
        job = self.wait(job_id)
        self.assertEqual(job["status"], "completed", job)
        self.assertEqual(job["frames_done"], 3)
        result = self.client.get(f"/v1/jobs/{job_id}/result", headers=self.headers).json()
        content = self.client.get(f"/v1/jobs/{job_id}/result/detections.ndjson", headers=self.headers).content
        self.assertEqual(hashlib.sha256(content).hexdigest(), result["files"][0]["sha256"])
        lines = [json.loads(line) for line in content.splitlines()]
        self.assertEqual([x["frame_number"] for x in lines], [0, 2, 4])
        self.assertEqual([x["timestamp_ms"] for x in lines], [0, 1000, 2000])
        self.assertIsNotNone(lines[0]["faces"][0]["crop_jpeg"])
        partial = self.client.get(f"/v1/jobs/{job_id}/result/detections.ndjson",
                                  headers={**self.headers, "Range": "bytes=0-9"})
        self.assertEqual(partial.status_code, 206)
        self.assertEqual(partial.content, content[:10])
        self.assertEqual(self.client.delete(f"/v1/jobs/{job_id}", headers=self.headers).status_code, 204)
        self.assertFalse(self.ctx.workspace.job_dir(job_id).exists())

    def test_repeated_create_is_idempotent_and_conflicts_are_refused(self):
        job_id = self.create()
        self.assertEqual(self.create(), job_id)
        body = {**self.body, "params": {"frame_interval": 2}}
        self.assertEqual(self.client.post("/v1/jobs", json=body, headers=self.headers).status_code, 409)
        self.wait(job_id)
        self.assertEqual(len(self.ctx.engines.calls), 3)

    def test_other_device_cannot_read_control_download_or_delete(self):
        job_id = self.create()
        other = self.ctx.auth.add_device("Another phone")
        headers = {"Authorization": "Bearer " + other["token"]}
        for method, suffix in [("get", ""), ("post", "/stop"), ("post", "/resume"),
                               ("get", "/result"), ("get", "/result/detections.ndjson"), ("delete", "")]:
            self.assertEqual(getattr(self.client, method)(f"/v1/jobs/{job_id}{suffix}", headers=headers).status_code, 404)
        self.assertEqual(self.client.get("/v1/jobs", headers=headers).json(), {"jobs": []})
        self.assertEqual(self.client.get(f"/v1/jobs/{job_id}").status_code, 401)

    def test_missing_blob_and_bad_options(self):
        body = {**self.body, "inputs": {"video": "a" * 64}}
        response = self.client.post("/v1/jobs", json=body, headers=self.headers)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["missing"], ["a" * 64])
        for params in [{"frame_interval": 0}, {"start_frame": -1}, {"detect_bodies": 1}, {"min_quality": 2}]:
            self.assertEqual(self.client.post("/v1/jobs", json={**self.body, "params": params}, headers=self.headers).status_code, 400)
        self.assertEqual(self.client.post("/v1/jobs", json={**self.body, "params": {"model_id": "other"}}, headers=self.headers).status_code, 409)

    def test_resume_starts_at_phone_checkpoint(self):
        job_id = self.create({**self.body, "params": {"start_frame": 3}})
        self.assertEqual(self.wait(job_id)["status"], "completed")
        content = self.client.get(f"/v1/jobs/{job_id}/result/detections.ndjson", headers=self.headers).text
        self.assertEqual([json.loads(line)["frame_number"] for line in content.splitlines()], [4])

    def test_pause_resume_and_gpu_exclusion(self):
        entered, release = threading.Event(), threading.Event()
        original = self.ctx.engines.analyze
        def gated(img, options):
            entered.set()
            release.wait(5)
            return original(img, options)
        self.ctx.engines.analyze = gated
        job_id = self.create()
        self.assertTrue(entered.wait(5))
        try:
            self.assertEqual(self.ctx.gpu.busy().job_id, job_id)
            blocked = self.client.post("/v1/jobs", json={**self.body, "client_job_id": "second"}, headers=self.headers)
            self.assertEqual(blocked.status_code, 503)
            self.assertEqual(self.client.delete(f"/v1/jobs/{job_id}", headers=self.headers).status_code, 409)
            self.client.post(f"/v1/jobs/{job_id}/stop", headers=self.headers)
        finally:
            release.set()
        self.assertEqual(self.wait(job_id, ("paused",))["status"], "paused")
        self.ctx.video_jobs.threads[job_id].join(5)
        self.client.post(f"/v1/jobs/{job_id}/resume", headers=self.headers)
        self.assertEqual(self.wait(job_id)["status"], "completed")
        content = self.client.get(f"/v1/jobs/{job_id}/result/detections.ndjson", headers=self.headers).text
        self.assertEqual([json.loads(line)["frame_number"] for line in content.splitlines()], [0, 2, 4])

    def test_expired_jobs_are_purged(self):
        job_id = self.create()
        self.wait(job_id)
        self.ctx.video_jobs.threads[job_id].join(5)
        self.ctx.video_jobs.jobs[job_id]["touched"] = time.time() - 86401
        self.assertEqual(self.client.get(f"/v1/jobs/{job_id}", headers=self.headers).status_code, 404)
        self.assertFalse(self.ctx.workspace.job_dir(job_id).exists())

    def test_real_video_decoder_and_stateless_workspace(self):
        path = Path(self.tmp.name) / "sample.avi"
        writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"MJPG"), 2, (640, 480))
        self.assertTrue(writer.isOpened())
        for frame in range(6):
            writer.write(np.full((480, 640, 3), frame * 10, np.uint8))
        writer.release()
        data = path.read_bytes()
        sha = hashlib.sha256(data).hexdigest()
        self.client.put("/v1/blobs/" + sha, content=data, headers=self.headers)
        self.ctx.video_jobs.capture = cv2.VideoCapture
        job_id = self.create({**self.body, "inputs": {"video": sha}})
        job = self.wait(job_id)
        self.assertEqual((job["status"], job["frames_done"]), ("completed", 3))
        import sys
        self.assertNotIn("database", sys.modules)

    def test_job_input_survives_blob_eviction(self):
        entered, release = threading.Event(), threading.Event()
        original = self.ctx.engines.analyze
        def gated(img, opts):
            entered.set()
            release.wait(5)
            return original(img, opts)
        self.ctx.engines.analyze = gated
        job_id = self.create()
        self.assertTrue(entered.wait(5))
        self.ctx.workspace.blob_cache_bytes = 0
        self.ctx.workspace.evict()
        self.assertFalse(self.ctx.workspace.has_blob(self.sha))
        self.assertTrue((self.ctx.workspace.job_dir(job_id) / "input.video").exists())
        release.set()
        self.assertEqual(self.wait(job_id)["status"], "completed")


if __name__ == "__main__":
    unittest.main()
