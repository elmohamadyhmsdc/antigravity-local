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

    def test_json_transport_preserves_analysis_and_crops(self):
        from mobile_api.schemas import analysis_to_response, AnalyzeRequestOptions
        image = np.zeros((480,640,3),np.uint8)
        result = FakeEngines().analyze(image,AnalyzeOptions())
        restored = decode_result(json.loads(json.dumps(encode_result(result))))
        self.assertEqual(analysis_to_response(result,image,AnalyzeRequestOptions()),
                         analysis_to_response(restored,image,AnalyzeRequestOptions()))


if __name__ == '__main__': unittest.main(verbosity=2)
