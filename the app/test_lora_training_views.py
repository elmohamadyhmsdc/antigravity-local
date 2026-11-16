"""Verify the mobile sample, caption, mask and trainer handoff on synthetic images."""
import base64
import os
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from lora_dataset import _body_evidence, detect_face_record_from_image, extract_face_and_body_crop
from mobile_api.artifact_jobs import extract_dataset, run_artifact, validate_artifact
from mobile_api.errors import ApiError
from mobile_api.testing import FakeBody, FakeFace, unit


class TrainingViewsTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.image = np.full((480, 320, 3), [35, 100, 200], np.uint8)
        self.path = str(self.root / 'source.jpg')
        cv2.imwrite(self.path, self.image)
        self.anchor = unit(1)
        self.face = FakeFace((60, 20, 100, 70), self.anchor)
        self.faces = SimpleNamespace(get=lambda image: [self.face])
        self.body = FakeBody((30, 0, 140, 380), (80, 43))
        self.bodies = SimpleNamespace(analyze=lambda image: [self.body])

    def record(self, view='original'):
        return detect_face_record_from_image(self.path, self.faces, self.anchor,
                                             body_analyzer=self.bodies, training_view=view)

    def test_group_photo_uses_only_associated_body(self):
        bystander = FakeFace((195, 20, 235, 70), unit(2))
        other_body = FakeBody((150, 0, 300, 470), (215, 43))
        self.faces.get = lambda image: [bystander, self.face]
        self.bodies.analyze = lambda image: [other_body, self.body]
        self.assertEqual(tuple(self.record()['body_bbox']), (30, 0, 140, 380))
        self.bodies.analyze = lambda image: [other_body]
        crop = extract_face_and_body_crop(self.record(), self.faces, restorer=None)
        self.assertIsNone(crop['body_crop'])
        self.assertIsNotNone(crop['face_crop'])

    def test_manual_body_without_face_and_conflicting_face(self):
        self.faces.get = lambda image: []
        self.assertIsNotNone(self.record('confirmed_body'))
        self.assertIsNone(self.record('body'))
        self.faces.get = lambda image: [FakeFace((60, 20, 100, 70), unit(8))]
        self.assertIsNone(self.record('confirmed_body'))
        self.faces.get = lambda image: [self.face, self.face]
        self.assertIsNone(self.record())

    def test_caption_uses_only_visible_joints(self):
        self.body.kpts[[5, 7, 9]] = [[50, 70], [70, 70], [70, 50]]
        self.body.kpt_scores[[5, 7, 9]] = 0.95
        self.assertIn('bent arm', _body_evidence(self.body, self.image.shape)[1])
        self.body.kpt_scores[9] = 0.1
        self.assertNotIn('bent arm', _body_evidence(self.body, self.image.shape)[1])

    def test_views_and_polygons_validated_together(self):
        params = {'trigger_word': 'sksdemo', 'anchor_embedding': base64.b64encode(self.anchor.tobytes()).decode()}
        job = {'type': 'build_lora_dataset', 'inputs': {'images': ['a'*64]}, 'params': params}
        for extra in [dict(training_views=[]), dict(training_views=['other']),
                      dict(training_views=['portrait'], training_outlines=[[0, 0, 1, 0, 1, 1]]),
                      dict(training_outlines=[None]), dict(training_views=['body'], training_outlines=[[0]*7]),
                      dict(training_views=['body'], training_outlines=[[float('nan')]*6])]:
            with self.subTest(extra=extra), self.assertRaises(ApiError):
                validate_artifact(dict(job, params=dict(params, **extra)), {'engines': {}})

    def test_bundle_survives_extraction_and_activates_spatial_loss(self):
        from lora_trainer import build_training_args
        # Use the real job writer and trainer args. Mock inference only.
        polygon = [.15, .08, .85, .08, .85, .92, .15, .92]
        params = dict(trigger_word='sksdemo', anchor_embedding=base64.b64encode(self.anchor.tobytes()).decode(),
                      training_views=['portrait', 'body', 'body', 'body', 'body'],
                      training_outlines=[None, polygon, None, [0]*6, None], enable_face_detailer=False)
        self.face.pose = [0, 65, 0]
        for i in range(5):
            (self.root / f'input.images.{i:04d}').write_bytes(Path(self.path).read_bytes())
        previous = self.root / 'dataset' / 'mobile' / '20_sksdemo person'
        previous.mkdir(parents=True)
        (previous / 'old.jpg').write_bytes(b'stale')
        ctx = SimpleNamespace(engines=SimpleNamespace(load=lambda: None, _face_app=self.faces, _body=self.bodies))
        with patch('lora_dataset.WD14Tagger', return_value=None), patch.dict(os.environ, AG_FLORENCE_CAPTIONS='0'):
            result = run_artifact({'type': 'build_lora_dataset', 'params': params}, self.root,
                                  lambda *args: None, lambda: False, ctx)
        self.assertEqual(result['image_count'], 5)
        with zipfile.ZipFile(self.root/'dataset.zip') as z:
            self.assertFalse(any(n.endswith('old.jpg') for n in z.namelist()))
            self.assertEqual(sum(n.endswith('_weighted.png') for n in z.namelist()), 1)
        folder = extract_dataset(self.root/'dataset.zip', self.root/'training')
        weighted = next(folder.glob('*_weighted.png'))
        pixels = cv2.imread(str(weighted), cv2.IMREAD_UNCHANGED)
        self.assertEqual(pixels.shape, (480, 320, 4))
        self.assertEqual((pixels[240, 160, 3], pixels[0, 0, 3]), (255, 64))
        self.assertLess(np.abs(pixels[0, 0, :3].astype(int) - self.image[0, 0]).max(), 5)
        self.assertIn('upper body shot of sksdemo person', weighted.with_suffix('.txt').read_text())
        self.assertIn('profile view', next(folder.glob('*_face.txt')).read_text())
        args = lambda: build_training_args(str(folder), 'out', 'model', 'base')
        self.assertIn('--alpha_mask', args())
        weighted.unlink()
        self.assertNotIn('--alpha_mask', args())


if __name__ == '__main__':
    unittest.main()
