"""Tests for POST /v1/analyze/targeted endpoint."""
import json
import unittest
import numpy as np

import test_mobile_api_contract as contract


class TargetedTests(unittest.TestCase):
    def test_targeted_requires_auth(self):
        with contract.Env() as env:
            files = {'image': ('photo.jpg', contract.jpeg_bytes(), 'image/jpeg')}
            res = env.client.post('/v1/analyze/targeted', files=files, data={'target_kind': 'body'})
            self.assertEqual(res.status_code, 401)

    def test_targeted_validates_kind(self):
        with contract.Env() as env:
            files = {'image': ('photo.jpg', contract.jpeg_bytes(), 'image/jpeg')}
            res = env.client.post(
                '/v1/analyze/targeted',
                files=files,
                data={'target_kind': 'invalid_kind'},
                headers=env.auth
            )
            self.assertEqual(res.status_code, 400)

    def test_targeted_body_detection(self):
        with contract.Env() as env:
            env.ctx.engines.compute_targeted = lambda img, kind, roi, prompt: [
                {
                    "bbox": {"x": 0.1, "y": 0.2, "w": 0.3, "h": 0.5},
                    "score": 0.92,
                    "label": "person",
                    "outline": [[0.1, 0.2], [0.4, 0.2], [0.4, 0.7]],
                    "keypoints": [[0.2, 0.25, 0.9]],
                }
            ]
            files = {'image': ('photo.jpg', contract.jpeg_bytes(), 'image/jpeg')}
            res = env.client.post(
                '/v1/analyze/targeted',
                files=files,
                data={'target_kind': 'body'},
                headers=env.auth
            )
            self.assertEqual(res.status_code, 200, res.text)
            body = res.json()
            self.assertEqual(body['target_kind'], 'body')
            self.assertEqual(len(body['detections']), 1)
            self.assertEqual(body['detections'][0]['label'], 'person')
            self.assertIn('bbox', body['detections'][0])

    def test_targeted_with_roi_fallback(self):
        with contract.Env() as env:
            # When compute_targeted returns empty, the endpoint returns the fallback container for the ROI
            env.ctx.engines.compute_targeted = lambda img, kind, roi, prompt: []
            files = {'image': ('photo.jpg', contract.jpeg_bytes(), 'image/jpeg')}
            roi = json.dumps({"x": 0.2, "y": 0.3, "w": 0.4, "h": 0.4})
            res = env.client.post(
                '/v1/analyze/targeted',
                files=files,
                data={'target_kind': 'area', 'roi': roi},
                headers=env.auth
            )
            self.assertEqual(res.status_code, 200, res.text)
            body = res.json()
            self.assertEqual(body['target_kind'], 'area')
            self.assertEqual(len(body['detections']), 1)
            self.assertEqual(body['detections'][0]['label'], 'custom')
            self.assertEqual(body['detections'][0]['bbox']['x'], 0.2)


if __name__ == '__main__':
    unittest.main()
