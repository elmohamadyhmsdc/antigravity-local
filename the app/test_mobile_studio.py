"""CPU-only Studio lifecycle and validation; never load GPU models or user data."""

import copy
import hashlib
import json
import shutil
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from fastapi.testclient import TestClient

from mobile_api.app import create_app
from mobile_api.reface_runner import match_boxes, run_reface
from mobile_api.schemas import encode_embedding
from mobile_api.testing import FakeFace, make_test_context, unit


class StudioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ag_studio_test_")
        self.ctx = make_test_context(Path(self.tmp.name), blob_cache_bytes=32)
        self.client = TestClient(create_app(self.ctx))
        self.device = self.ctx.auth.add_device("Phone")
        self.headers = {"Authorization": "Bearer " + self.device["token"]}
        self.input = b"photo-content"
        self.sha = hashlib.sha256(self.input).hexdigest()
        self.client.put("/v1/blobs/" + self.sha, content=self.input, headers=self.headers)
        self.body = dict(type="reface_image_v3", client_job_id="request-1", inputs={"target": self.sha},
                         params={"source_faces": [{"embedding": encode_embedding(unit(1)), "quality": 0.8}]})
        self.calls = []

        def run(job, directory, report, stopped):
            self.calls.append(job["client_job_id"])
            self.assertEqual((directory / "input.target").read_bytes(), self.input)
            report(0.5, "Rendering")
            (directory / "result.png").write_bytes(b"fake-png")
            return {"faces_swapped": 1}

        self.ctx.studio_jobs.runner = run

    def tearDown(self):
        self.ctx.studio_jobs.close()
        self.ctx.video_jobs.close()
        self.client.close()
        self.tmp.cleanup()

    def create(self, body=None):
        r = self.client.post("/v1/jobs", json=body or self.body, headers=self.headers)
        self.assertEqual(r.status_code, 201, r.text)
        return r.json()["job_id"]

    def wait(self, id, states=("completed", "failed")):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            job = self.client.get("/v1/jobs/" + id, headers=self.headers).json()
            if job["status"] in states:
                return job
            time.sleep(0.01)
        self.fail("Studio worker did not finish")

    def test_lifecycle_verified_result_sse_range_ack(self):
        id = self.create()
        self.assertEqual(self.wait(id)["status"], "completed")
        manifest = self.client.get(f"/v1/jobs/{id}/result", headers=self.headers).json()
        result = self.client.get(f"/v1/jobs/{id}/result/result.png", headers=self.headers)
        self.assertEqual(manifest["files"][0]["sha256"], hashlib.sha256(result.content).hexdigest())
        self.assertEqual(result.headers["content-type"], "image/png")
        partial = self.client.get(f"/v1/jobs/{id}/result/result.png", headers={**self.headers, "Range": "bytes=0-3"})
        self.assertEqual(partial.status_code, 206)
        self.assertEqual(partial.content, b"fake")
        events = self.client.get(f"/v1/jobs/{id}/events", headers=self.headers)
        self.assertIn('"status":"completed"', events.text)
        self.assertEqual(self.client.get(f"/v1/jobs/{id}/result/input.target", headers=self.headers).status_code, 404)
        self.assertEqual(self.client.delete(f"/v1/jobs/{id}", headers=self.headers).status_code, 204)
        self.assertFalse(self.ctx.workspace.job_dir(id).exists())


    def test_real_adapter_uses_embedding_sources_and_bbox_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            cv2.imencode('.png', np.zeros((80, 80, 3), np.uint8))[1].tofile(directory / 'input.target')
            seen = {}

            class Faceset:
                def __init__(self, name): self.faces = []
                def add_face(self, face): self.faces.append(face)

            class Engine:
                def __init__(self, **kwargs):
                    seen['config'] = kwargs
                    self.compositor = SimpleNamespace(_pool=None)
                def _detect(self, image, embeddings=False):
                    return [FakeFace((40, 40, 60, 60), unit(2)), FakeFace((0, 0, 20, 20), unit(1))]
                def reface_image_v3(self, target, faceset, selected, references):
                    seen.update(faces=faceset.faces, selected=selected, references=references)
                    path = directory / 'engine.png'
                    cv2.imwrite(str(path), np.ones((80, 80, 3), np.uint8))
                    return SimpleNamespace(success=True, output_path=str(path), faces_swapped=1)

            face_data = lambda path, embedding, pose, bbox, quality: SimpleNamespace(embedding=embedding, quality=quality, pose=pose)
            modules = {'reface_engine': SimpleNamespace(Faceset=Faceset, FaceData=face_data),
                       'reface_engine_v3': SimpleNamespace(RefaceEngineV3=Engine)}
            job = {'type': 'reface_image_v3', 'params': {'source_faces': [{'embedding': encode_embedding(unit(9)), 'quality': .8}],
                   'target_faces': [dict(x=0, y=0, w=20, h=20)]}}
            with patch.dict('sys.modules', modules):
                self.assertEqual(run_reface(job, directory, lambda *a, **k: None, lambda: False), {'faces_swapped': 1})
            self.assertEqual(seen['selected'], [1])
            np.testing.assert_allclose(seen['faces'][0].embedding, unit(9))
            self.assertIsNone(seen['config']['restorer'])  # use the engine's evaluated default
            self.assertTrue((directory / 'result.png').exists())
            self.assertNotIn('_engine', job)

    def test_video_pause_resume_keeps_all_parts_and_exact_frame_checkpoint(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'input.target').write_bytes(b'video')
            stopped = threading.Event()
            resumes = []

            class Faceset:
                def __init__(self, name): self.faces = []
                def add_face(self, face): self.faces.append(face)

            class Capture:
                def get(self, key): return 2 if key == cv2.CAP_PROP_FPS else 6
                def release(self): pass

            class Engine:
                def __init__(self, **kwargs): pass
                def reface_video_v3(self, target, faceset, **kwargs):
                    base = kwargs['resume_from_frame']
                    resumes.append(base)
                    if base == 0: stopped.set()
                    kwargs['progress_callback'](3, 6 - base)
                    path = directory / f'part-{base}.mp4'
                    path.write_bytes(b'part')
                    return SimpleNamespace(success=True, output_path=str(path), message='Rendered')

            modules = {'reface_engine': SimpleNamespace(Faceset=Faceset, FaceData=lambda *args: None),
                       'reface_engine_v3': SimpleNamespace(RefaceEngineV3=Engine)}
            job = {'type': 'reface_video_v3', 'params': {'source_faces': []}}
            def concatenate(command, **kwargs):
                Path(command[-1]).write_bytes(b'joined-parts')
                return SimpleNamespace(returncode=0)
            with patch.dict('sys.modules', modules), patch('mobile_api.reface_runner.cv2.VideoCapture', return_value=Capture()), \
                    patch('mobile_api.reface_runner.subprocess.run', side_effect=concatenate), patch('ffmpeg_utils.mux_audio', return_value=True):
                self.assertIsNone(run_reface(job, directory, lambda *a, **k: None, stopped.is_set))
                self.assertEqual(job['_frames_done'], 3)
                stopped.clear()
                meta = run_reface(job, directory, lambda *a, **k: None, stopped.is_set)
            self.assertEqual(resumes, [0, 3])
            self.assertEqual(meta['frames_done'], 6)
            self.assertEqual((directory / 'result.mp4').read_bytes(), b'joined-parts')
            self.assertEqual(len(job['_parts']), 2)

    def test_short_legacy_video_counts_unticked_frames_and_encodes_real_mp4(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory=Path(tmp)
            video=directory/'fixture.avi'
            writer=cv2.VideoWriter(str(video),cv2.VideoWriter_fourcc(*'MJPG'),10,(32,32))
            self.assertTrue(writer.isOpened())
            for index in range(4):writer.write(np.full((32,32,3),index*20,np.uint8))
            writer.release();shutil.copyfile(video,directory/'input.target')
            class Faceset:
                def __init__(self,name):self.faces=[]
                def add_face(self,face):self.faces.append(face)
            class Legacy:
                def __init__(self,**kwargs):pass
                def reface_video_with_faceset_v2(self,target,faceset,**kwargs):
                    # Exactly what V2 does below five frames: returns an AVI with no callback.
                    return SimpleNamespace(success=True,output_path=str(video))
            commands=[]
            def encode(command,**kwargs):
                commands.append(command)
                out=cv2.VideoWriter(command[-1],cv2.VideoWriter_fourcc(*'mp4v'),10,(32,32))
                for index in range(4):out.write(np.zeros((32,32,3),np.uint8))
                out.release();return SimpleNamespace(returncode=0)
            modules={'reface_engine':SimpleNamespace(Faceset=Faceset,FaceData=lambda *args:None),
                     'reface_engine_v3':SimpleNamespace(RefaceEngineV3=None),
                     'reface_engine_v2':SimpleNamespace(RefaceEngineV2=Legacy)}
            job={'type':'reface_video_v2','params':{'source_faces':[]}}
            with patch.dict('sys.modules',modules),patch('mobile_api.reface_runner.subprocess.run',side_effect=encode),patch('ffmpeg_utils.mux_audio',return_value=True):
                meta=run_reface(job,directory,lambda *a,**k:None,lambda:False)
            self.assertEqual(meta['frames_done'],4)
            self.assertIn('libx264',commands[0]);self.assertEqual((directory/'result.mp4').read_bytes()[4:8],b'ftyp')

    def test_idempotency_and_other_phone_ownership(self):
        id = self.create()
        self.assertEqual(self.create(), id)
        body = copy.deepcopy(self.body)
        body["params"]["restorer_weight"] = 0.2
        self.assertEqual(self.client.post("/v1/jobs", json=body, headers=self.headers).status_code, 409)
        self.wait(id)
        other = self.ctx.auth.add_device("Other")
        headers = {"Authorization": "Bearer " + other["token"]}
        for method, suffix in [("get", ""), ("get", "/events"), ("post", "/stop"), ("post", "/resume"),
                               ("get", "/result"), ("get", "/result/result.png"), ("delete", "")]:
            self.assertEqual(getattr(self.client, method)(f"/v1/jobs/{id}{suffix}", headers=headers).status_code, 404)
        self.assertEqual(self.calls, ["request-1"])

    def test_serial_queue_paused_resume_and_pinned_inputs(self):
        entered, release = threading.Event(), threading.Event()
        real = self.ctx.studio_jobs.runner

        def gated(job, directory, report, stopped):
            entered.set()
            release.wait(5)
            if stopped():
                return None
            return real(job, directory, report, stopped)

        self.ctx.studio_jobs.runner = gated
        first = self.create()
        self.assertTrue(entered.wait(5))
        second = self.create({**self.body, "client_job_id": "request-2"})
        self.assertEqual(self.ctx.gpu.busy().job_id, first)
        self.assertEqual(self.client.get(f"/v1/jobs/{second}", headers=self.headers).json()["status"], "queued")
        self.client.post(f"/v1/jobs/{second}/stop", headers=self.headers)
        self.client.post(f"/v1/jobs/{first}/stop", headers=self.headers)
        release.set()
        self.wait(first, ("paused",))
        # Evict the original blob; both jobs retain their own hardlink/copy.
        data = b"a" * 31
        self.client.put("/v1/blobs/" + hashlib.sha256(data).hexdigest(), content=data, headers=self.headers)
        self.assertFalse(self.ctx.workspace.has_blob(self.sha))
        self.client.post(f"/v1/jobs/{first}/resume", headers=self.headers)
        self.wait(first)
        self.client.post(f"/v1/jobs/{second}/resume", headers=self.headers)
        self.wait(second)
        self.assertEqual(self.calls, ["request-1", "request-2"])

    def test_invalid_inputs_and_nonfinite_identity_are_refused(self):
        for value in [[], "", {}, 1, None]:
            body = {**self.body, "params": {"source_faces": value}}
            self.assertEqual(self.client.post("/v1/jobs", json=body, headers=self.headers).status_code, 400)
        for params in [{"source_faces": []}, {"source_faces": self.body["params"]["source_faces"], "model_id": "other"},
                       {**self.body["params"], "target_faces": []}, {**self.body["params"], "end_time": 0},
                       {**self.body["params"], "dfm_model": "../../model"},
                       {**self.body["params"], "restorer_weight": True}]:
            status = self.client.post("/v1/jobs", json={**self.body, "params": params}, headers=self.headers).status_code
            self.assertIn(status, (400, 409))
        bad = unit(1)
        bad[0] = float("nan")
        params = {"source_faces": [{"embedding": encode_embedding(bad), "quality": 0.8}]}
        self.assertEqual(self.client.post("/v1/jobs", json={**self.body, "params": params}, headers=self.headers).status_code, 400)
        missing = self.client.post("/v1/jobs", json={**self.body, "inputs": {"target": "a" * 64}}, headers=self.headers)
        self.assertEqual(missing.status_code, 409)
        self.assertEqual(missing.json()["missing"], ["a" * 64])

    def test_bbox_matching_is_one_to_one_and_order_independent(self):
        a, b = FakeFace((0, 0, 20, 20), unit(1)), FakeFace((40, 40, 60, 60), unit(2))
        boxes = [dict(x=0, y=0, w=20, h=20)]
        self.assertEqual(match_boxes(boxes, [b, a]), [1])
        with self.assertRaises(ValueError):
            match_boxes(boxes * 2, [a])
        with self.assertRaises(ValueError):
            match_boxes(boxes, [b])

    def test_failure_is_reported_and_expiry_purges_private_workspace(self):
        def fail(*args):
            raise RuntimeError("private path must not leak")
        self.ctx.studio_jobs.runner = fail
        id = self.create()
        job = self.wait(id)
        self.assertEqual(job["status"], "failed")
        self.assertNotIn("private path", job["error"])
        self.ctx.studio_jobs.jobs[id]["touched"] -= 86401
        self.assertEqual(self.client.get(f"/v1/jobs/{id}", headers=self.headers).status_code, 404)
        self.assertFalse(self.ctx.workspace.job_dir(id).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
