"""Inference process failure/recovery checks. No GPU or downloads."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

import cv2
import numpy as np
from fastapi.testclient import TestClient
from mobile_api.app import create_app
from mobile_api.engines import InsightEngines
from mobile_api.scan_worker import ScanWorker, PREFIX, encode_result, decode_result
from mobile_api.testing import make_test_context, FakeEngines
from analysis import AnalyzeOptions


class WorkerTests(unittest.TestCase):
    def test_pose_worker_preserves_signed_angles_and_track_embeddings(self):
        face = {'bbox': [5, 5, 60, 60], 'kps': [[1, 2]] * 5, 'det_score': .9,
                'pose': [7, -48, -12], 'normed_embedding': [1.0] + [0.0] * 511}
        script = ("import sys,json\nfor line in sys.stdin:\n"
                  " assert json.loads(line)['type']=='pose_faces'\n"
                  f" print({PREFIX!r}+json.dumps({{'faces': [{face!r}]}}),flush=True)")
        worker = ScanWorker(command=[sys.executable, '-u', '-c', script], timeout=5)
        self.addCleanup(worker.close)
        result, = worker.pose_faces(np.zeros((64, 64, 3), dtype=np.uint8))
        process = worker.process
        self.assertEqual(result.pose, [7, -48, -12])
        np.testing.assert_array_equal(result.embedding, result.normed_embedding)
        np.testing.assert_array_equal(result.bbox, [5, 5, 60, 60])
        worker.close()
        self.assertIsNotNone(process.poll())

    def test_native_style_exit_keeps_api_and_pairing_alive_then_recreates_worker(self):
        with tempfile.TemporaryDirectory() as tmp:
            engines = InsightEngines()
            engines._scan_worker = ScanWorker(command=[sys.executable, '-c', 'import os; os._exit(23)'], timeout=5)
            ctx = make_test_context(Path(tmp), engines=engines)
            with TestClient(create_app(ctx)) as client:
                device = ctx.auth.add_device('Fixture')
                headers = {'Authorization':'Bearer '+device['token']}
                image = np.zeros((480,640,3),np.uint8)
                payload = cv2.imencode('.jpg',image)[1].tobytes()
                response = client.post('/v1/analyze/image',headers=headers,
                    files={'image':('photo.jpg',payload,'image/jpeg')})
                self.assertEqual(response.status_code,503,response.text)
                self.assertTrue(response.json()['error']['retryable'])
                self.assertEqual(client.get('/v1/health').status_code,200)
                self.assertIsNotNone(ctx.auth.authenticate(device['token']))
                fixture = encode_result(FakeEngines().analyze(image,AnalyzeOptions()))
                script = "import sys,json\nfor line in sys.stdin:\n print("+repr(PREFIX)+"+json.dumps({'result':"+repr(fixture)+"}),flush=True)"
                engines._scan_worker.command = [sys.executable,'-u','-c',script]
                response = client.post('/v1/analyze/image',headers=headers,
                    files={'image':('photo.jpg',payload,'image/jpeg')})
                self.assertEqual(response.status_code,200,response.text)
                self.assertTrue(response.json()['faces'])
                process = engines._scan_worker.process
            self.assertIsNotNone(process.poll(),'Server shutdown must stop its worker')

    def test_anime_recovery_uses_worker_and_preserves_structured_errors(self):
        from mobile_api.errors import ApiError
        fixture = json.loads((Path(__file__).parent / 'mobile_api' / 'contract' / 'fixtures' /
                              'TargetedAnalysisResponse.anime_face.json').read_text())['detections']
        script = ("import sys,json\nfor i,line in enumerate(sys.stdin):\n "
                  "request=json.loads(line)\n "
                  "assert request['type']=='anime_face'\n "
                  "reply={'api_error':{'status':503,'code':'model_missing','message':'Fixture model missing'}} if i==0 else "
                  + repr({'detections': fixture}) + "\n print(" + repr(PREFIX) + "+json.dumps(reply),flush=True)")
        # repr(None/True) is valid Python; this script never imports inference models.
        worker = ScanWorker(command=[sys.executable, '-u', '-c', script], timeout=5)
        self.addCleanup(worker.close)
        engines = InsightEngines()
        engines._scan_worker = worker
        image = np.zeros((64, 64, 3), np.uint8)
        with self.assertRaises(ApiError) as error:
            engines.targeted_analyze(image, 'anime_face', dict(x=.1, y=.1, w=.5, h=.5))
        self.assertEqual(error.exception.code, 'model_missing')
        process = worker.process
        result = engines.targeted_analyze(image, 'anime_face')
        self.assertEqual(result, fixture)
        self.assertIs(worker.process, process)

    def test_json_transport_preserves_analysis_and_crops(self):
        from mobile_api.schemas import analysis_to_response, AnalyzeRequestOptions
        image = np.zeros((480,640,3),np.uint8)
        result = FakeEngines().analyze(image,AnalyzeOptions())
        restored = decode_result(json.loads(json.dumps(encode_result(result))))
        self.assertEqual(analysis_to_response(result,image,AnalyzeRequestOptions()),
                         analysis_to_response(restored,image,AnalyzeRequestOptions()))

    def test_json_transport_preserves_outlines(self):
        image = np.zeros((480, 640, 3), np.uint8)
        result = FakeEngines().analyze(image, AnalyzeOptions(outlines=True))
        self.assertTrue(len(result.face_outlines) > 0)
        self.assertIsNone(result.face_outlines[1])
        self.assertIsNotNone(result.face_outlines[0])

        restored = decode_result(json.loads(json.dumps(encode_result(result))))
        self.assertEqual(len(restored.face_outlines), len(result.face_outlines))
        self.assertIsNone(restored.face_outlines[1])
        np.testing.assert_allclose(restored.face_outlines[0], result.face_outlines[0])
        self.assertEqual(len(restored.body_outlines), len(result.body_outlines))
        np.testing.assert_allclose(restored.body_outlines[0], result.body_outlines[0])


if __name__ == '__main__': unittest.main(verbosity=2)
