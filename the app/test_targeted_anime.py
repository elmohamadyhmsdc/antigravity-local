"""Model-free anime ROI recovery, coordinate mapping and identity checks."""
import base64
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from mobile_api.errors import ApiError
from mobile_api.targeted_anime import analyze_anime_face


class TargetedAnimeTests(unittest.TestCase):
    def setUp(self):
        self.img = np.full((400, 800, 3), 160, np.uint8)
        self.roi = dict(x=.25, y=.25, w=.25, h=.5)
        self.hits = []
        self.seen = []
        def detect(crop, **kwargs):
            self.seen.append((crop.shape, kwargs))
            return self.hits
        self.detector = SimpleNamespace(detect=detect, detect_multiscale=detect)
        self.embedder = SimpleNamespace(embed_crop=lambda crop: np.eye(1, 768, dtype=np.float32)[0])
        self.detector_patch = patch('analysis.get_anime_detector', return_value=self.detector)
        self.embedder_patch = patch('analysis.get_ccip_embedder', return_value=self.embedder)
        self.detector_patch.start()
        self.embedder_patch.start()
        self.addCleanup(self.detector_patch.stop)
        self.addCleanup(self.embedder_patch.stop)

    def test_missed_face_keeps_explicit_box_and_extracts_real_ccip_and_crop(self):
        result = analyze_anime_face(self.img, self.roi)
        self.assertEqual(len(result), 1)
        face = result[0]
        self.assertEqual(face['bbox'], self.roi)
        self.assertTrue(face['manual'])
        self.assertEqual(face['score'], 0)
        self.assertEqual(face['embedding_model_id'], 'ccip-caformer24@1')
        vector = np.frombuffer(base64.b64decode(face['embedding']), dtype='<f4')
        self.assertEqual(vector.shape, (768,))
        self.assertAlmostEqual(np.linalg.norm(vector), 1)
        crop = cv2.imdecode(np.frombuffer(base64.b64decode(face['crop_jpeg']), np.uint8), cv2.IMREAD_COLOR)
        self.assertEqual(crop.shape[:2], (200, 200))
        self.assertEqual(self.seen[0][0], (200, 200, 3))

    def test_refined_box_maps_back_to_full_image(self):
        self.hits = [dict(bbox=[20, 30, 180, 170], score=.88)]
        face = analyze_anime_face(self.img, self.roi)[0]
        self.assertFalse(face['manual'])
        self.assertEqual(face['bbox'], dict(x=220/800, y=130/400, w=160/800, h=140/400))

    def test_a_tiny_bystander_does_not_replace_the_selected_face(self):
        self.hits = [dict(bbox=[0, 0, 20, 20], score=.99)]
        face = analyze_anime_face(self.img, self.roi)[0]
        self.assertTrue(face['manual'])
        self.assertEqual(face['bbox'], self.roi)

    def test_full_image_never_invents_a_face(self):
        self.assertEqual(analyze_anime_face(self.img), [])
        self.hits = [dict(bbox=[20, 30, 180, 170], score=.6)]
        self.assertEqual(analyze_anime_face(self.img), [])

    def test_invalid_identity_cannot_be_saved_as_a_face(self):
        self.embedder.embed_crop = lambda crop: np.full(768, np.nan, np.float32)
        with self.assertRaises(ApiError):
            analyze_anime_face(self.img, self.roi)

    def test_missing_model_and_tiny_selection_are_explicit_errors(self):
        with patch('analysis.get_ccip_embedder', return_value=None):
            with self.assertRaises(ApiError) as missing:
                analyze_anime_face(self.img, self.roi)
        self.assertEqual(missing.exception.code, 'model_missing')
        with self.assertRaises(ApiError) as tiny:
            analyze_anime_face(self.img, dict(x=0, y=0, w=.001, h=.001))
        self.assertEqual(tiny.exception.status, 400)


if __name__ == '__main__':
    unittest.main()
