"""CPU-only video lifecycle, ownership, retry and frame-sampling tests. No model downloads."""

import hashlib
import base64
import json
import tempfile
import threading
import time
import unittest
from dataclasses import replace
from pathlib import Path

import cv2
import numpy as np
from fastapi.testclient import TestClient

from mobile_api.app import create_app
from mobile_api.testing import make_test_context
from mobile_api.media_decode import IsolatedCapture
from mobile_api.video_sampling import adaptive_interval
from mobile_api.workspace import Workspace


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
    def test_duration_aware_sampling_keeps_short_clips_dense_and_long_videos_sparse(self):
        self.assertEqual(adaptive_interval(20), 0.5)
        self.assertEqual(adaptive_interval(60), 0.5)
        self.assertEqual(adaptive_interval(40 * 60), 5)
        self.assertEqual(adaptive_interval(2 * 3600), 10)
        self.assertEqual(adaptive_interval(0), 1)

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
        preview = cv2.imdecode(np.frombuffer(base64.b64decode(job['preview_jpeg']), np.uint8), cv2.IMREAD_COLOR)
        self.assertLessEqual(max(preview.shape[:2]), 480)
        self.assertEqual(job['preview_timestamp_ms'], 2000)
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
        self.assertFalse(self.ctx.workspace.has_blob(self.sha))
        self.assertFalse(self.ctx.workspace.job_dir(job_id).exists())

    def test_live_batches_are_verified_owned_and_recovered_after_restart(self):
        entered, release = threading.Event(), threading.Event()
        class LongCapture(Capture):
            def get(self, prop):
                return 2 if prop == cv2.CAP_PROP_FPS else 36
            def read(self):
                return True, np.full((480, 640, 3), (self.position * 10) % 256, np.uint8)
        self.ctx.video_jobs.capture = LongCapture
        original = self.ctx.engines.analyze
        calls = 0
        def gated(img, opts):
            nonlocal calls
            calls += 1
            if calls == 9:
                entered.set()
                release.wait(10)
            return original(img, opts)
        self.ctx.engines.analyze = gated
        job_id = self.create()
        self.assertTrue(entered.wait(10))
        endpoint = f'/v1/jobs/{job_id}/frames'
        try:
            response = self.client.get(endpoint, params={'cursor': 0, 'limit': 2}, headers=self.headers)
            self.assertEqual(response.status_code, 200, response.text)
            batch = response.json()
            self.assertFalse(batch['completed'])
            self.assertTrue(batch['has_more'])
            self.assertEqual(hashlib.sha256(batch['ndjson'].encode()).hexdigest(), batch['sha256'])
            self.assertEqual([json.loads(x)['frame_number'] for x in batch['ndjson'].splitlines()], [0, 2])
            self.assertEqual(batch['next_cursor'], len(batch['ndjson'].encode()))
            self.assertEqual(self.client.get(endpoint, params={'cursor': 1}, headers=self.headers).status_code, 400)
            self.assertEqual(self.client.get(endpoint).status_code, 401)
            other = self.ctx.auth.add_device('Other')
            self.assertEqual(self.client.get(endpoint,
                headers={'Authorization': 'Bearer ' + other['token']}).status_code, 404)
            self.client.post(f'/v1/jobs/{job_id}/stop', headers=self.headers)
        finally:
            release.set()
        self.assertEqual(self.wait(job_id, ('paused', 'failed'))['status'], 'paused')
        self.ctx.video_jobs.close()
        # Simulate a process dying midway through the next NDJSON write.
        path = self.ctx.workspace.job_dir(job_id) / 'detections.ndjson'
        before = path.stat().st_size
        with open(path, 'ab') as output:
            output.write(b'{"frame_number":')
        self.ctx.engines.analyze = original
        workspace = Workspace(self.ctx.workspace.root)
        workspace.prepare(wipe=False)
        self.ctx = replace(self.ctx, workspace=workspace)
        self.client.close()
        self.app = create_app(self.ctx)
        self.ctx.video_jobs.capture = LongCapture
        self.client = TestClient(self.app)
        restored = self.client.get(f'/v1/jobs/{job_id}', headers=self.headers).json()
        self.assertEqual(restored['status'], 'paused', restored)
        self.assertEqual(restored['frames_done'], 9)
        self.assertEqual(workspace._job_inputs[job_id], {self.sha})
        self.assertEqual(path.stat().st_size, before)
        self.assertEqual(self.create(), job_id, 'Persistent client request ID must survive a PC restart')
        self.client.post(f'/v1/jobs/{job_id}/resume', headers=self.headers)
        self.assertEqual(self.wait(job_id)['frames_done'], 18)
        self.ctx.video_jobs.threads[job_id].join(5)
        frames = [json.loads(line)['frame_number'] for line in path.read_bytes().splitlines()]
        self.assertEqual(frames, list(range(0, 36, 2)))
        cursor = 0
        received = []
        while True:
            batch = self.client.get(endpoint, params={'cursor': cursor}, headers=self.headers).json()
            received.extend(json.loads(line)['frame_number'] for line in batch['ndjson'].splitlines())
            cursor = batch['next_cursor']
            if batch['completed']:
                break
        self.assertEqual(received, frames)

    def test_completed_unacknowledged_video_survives_restart_until_ack(self):
        job_id = self.create()
        self.assertEqual(self.wait(job_id)['status'], 'completed')
        self.ctx.video_jobs.close()
        self.ctx = replace(self.ctx)
        self.client.close()
        self.app = create_app(self.ctx)
        self.client = TestClient(self.app)
        self.assertEqual(self.client.get(f'/v1/jobs/{job_id}', headers=self.headers).json()['status'], 'completed')
        self.assertEqual(self.client.get(f'/v1/jobs/{job_id}/result', headers=self.headers).status_code, 200)
        self.assertEqual(self.client.delete(f'/v1/jobs/{job_id}', headers=self.headers).status_code, 204)

    def test_adaptive_grid_survives_restart_and_does_not_retarget_mid_video(self):
        entered, release = threading.Event(), threading.Event()
        class LongCapture(Capture):
            def get(self, prop):
                return 2 if prop == cv2.CAP_PROP_FPS else 4800
            def read(self):
                return True, np.full((480, 640, 3), self.position % 256, np.uint8)
        original = self.ctx.engines.analyze
        def gated(img, opts):
            entered.set()
            release.wait(10)
            return original(img, opts)
        self.ctx.video_jobs.capture = LongCapture
        self.ctx.engines.analyze = gated
        job_id = self.create({**self.body, 'params': {'sampling_mode': 'adaptive'}})
        self.assertTrue(entered.wait(10))
        try:
            status = self.client.get(f'/v1/jobs/{job_id}', headers=self.headers).json()
            self.assertEqual(status['details']['frame_interval'], 5)
            self.client.post(f'/v1/jobs/{job_id}/stop', headers=self.headers)
        finally:
            release.set()
        self.assertEqual(self.wait(job_id, ('paused', 'failed'))['status'], 'paused')
        self.ctx.video_jobs.close()
        self.ctx.engines.analyze = original
        self.ctx = replace(self.ctx)
        self.client.close()
        self.app = create_app(self.ctx)
        class ChangedMetadata(LongCapture):
            def get(self, prop):
                return 2 if prop == cv2.CAP_PROP_FPS else 100
        self.ctx.video_jobs.capture = ChangedMetadata
        self.client = TestClient(self.app)
        self.client.post(f'/v1/jobs/{job_id}/resume', headers=self.headers)
        status = self.wait(job_id)
        self.assertEqual(status['status'], 'completed', status)
        self.ctx.video_jobs.threads[job_id].join(5)
        path = self.ctx.workspace.job_dir(job_id) / 'detections.ndjson'
        self.assertEqual([json.loads(x)['frame_number'] for x in path.read_bytes().splitlines()], list(range(0, 100, 10)))

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
        self.ctx.video_jobs.capture = IsolatedCapture
        job_id = self.create({**self.body, "inputs": {"video": sha}})
        job = self.wait(job_id)
        self.assertEqual((job["status"], job["frames_done"]), ("completed", 3))
        import sys
        self.assertNotIn("database", sys.modules)

    def test_corrupt_sample_is_skipped_and_other_results_survive(self):
        class CorruptCapture(Capture):
            def read(self):
                return (False, None) if self.position == 2 else super().read()
        self.ctx.video_jobs.capture = CorruptCapture
        job_id = self.create()
        job = self.wait(job_id)
        self.assertEqual(job['status'], 'completed', job)
        self.assertEqual(job['details']['skipped_frames'], 1)
        content = self.client.get(f'/v1/jobs/{job_id}/result/detections.ndjson', headers=self.headers).text
        self.assertEqual([json.loads(line)['frame_number'] for line in content.splitlines()], [0, 4])

    def test_no_readable_frames_is_a_clear_file_error_and_api_stays_up(self):
        class CorruptCapture(Capture):
            def read(self):
                return False, None
        self.ctx.video_jobs.capture = CorruptCapture
        job = self.wait(self.create())
        self.assertEqual(job['status'], 'failed')
        self.assertIn('No sampled video frames', job['error'])
        self.assertEqual(self.client.get('/v1/health').status_code, 200)

    def test_resource_pressure_mid_video_pauses_then_resumes_without_repeating_frames(self):
        original = self.ctx.engines.analyze
        def pressure(img, opts):
            result = original(img, opts)
            self.ctx.gpu.resource_check = lambda: ['Free system RAM is too low.']
            return result
        self.ctx.engines.analyze = pressure
        job_id = self.create()
        job = self.wait(job_id, ('paused', 'failed'))
        self.assertEqual(job['status'], 'paused', job)
        self.assertEqual(job['frames_done'], 1)
        self.ctx.video_jobs.threads[job_id].join(5)
        self.ctx.gpu.resource_check = lambda: []
        self.ctx.engines.analyze = original
        self.client.post(f'/v1/jobs/{job_id}/resume', headers=self.headers)
        self.assertEqual(self.wait(job_id)['frames_done'], 3)

    def test_temporary_inference_failure_pauses_at_the_uncommitted_frame(self):
        from mobile_api.errors import ApiError
        self.ctx.engines.fail_with = ApiError(503, 'engine_unavailable', 'Worker stopped', retryable=True)
        job_id = self.create()
        job = self.wait(job_id, ('paused', 'failed'))
        self.assertEqual(job['status'], 'paused', job)
        self.assertEqual(job['frames_done'], 0)
        self.ctx.video_jobs.threads[job_id].join(5)
        self.ctx.engines.fail_with = None
        self.client.post(f'/v1/jobs/{job_id}/resume', headers=self.headers)
        self.assertEqual(self.wait(job_id)['frames_done'], 3)

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
