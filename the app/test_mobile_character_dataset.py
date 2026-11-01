"""CPU-only character dataset adapter tests with fake detectors and generators."""
import base64
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from mobile_api.artifact_jobs import dataset_anchor, run_artifact, validate_artifact
from mobile_api.errors import ApiError
from lora_dataset import detect_character_record_from_image, extract_face_and_body_crop


def vector(dim, index=0):
    result = np.zeros(dim, dtype='<f4')
    result[index] = 1
    return result


def encoded(value):
    return base64.b64encode(value.tobytes()).decode('ascii')


class CharacterDatasetTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.image = np.zeros((200, 300, 3), np.uint8)
        self.image[:, :150] = (20, 40, 210)
        self.image[:, 150:] = (210, 40, 20)
        self.path = self.root / 'photo.jpg'
        cv2.imwrite(str(self.path), self.image)
        self.faces = [{'bbox': [35, 40, 70, 75], 'score': .9},
                      {'bbox': [205, 40, 240, 75], 'score': .95}]
        self.detector = SimpleNamespace(detect=lambda image, score_thresh: self.faces)
        self.embedder = SimpleNamespace(embed_crop=lambda crop: vector(768, 0 if crop[:, :, 2].mean() > crop[:, :, 0].mean() else 1))
        self.bodies = SimpleNamespace(analyze=lambda image: [
            SimpleNamespace(bbox=np.array([15, 20, 110, 190]), score=.9),
            SimpleNamespace(bbox=np.array([180, 20, 280, 190]), score=.9)])

    def test_anchor_model_and_dimension_validation(self):
        human = {'anchor_embedding': encoded(vector(512))}
        char = {'identity_model_id': 'ccip-caformer24@1', 'anchor_embedding': encoded(vector(768))}
        self.assertEqual(dataset_anchor(human)[0], 'buffalo_l@1')
        self.assertEqual(dataset_anchor(char)[0], 'ccip-caformer24@1')
        for bad in [dict(char, anchor_embedding=human['anchor_embedding']),
                    dict(human, identity_model_id='unknown'),
                    dict(char, anchor_embedding=encoded(np.full(768, np.nan, dtype='<f4'))),
                    dict(char, anchor_embedding=encoded(np.zeros(768, dtype='<f4')))]:
            with self.assertRaises((ValueError, KeyError)):
                dataset_anchor(bad)
        caps = {'engines': {}, 'lora_base_checkpoints': []}
        body = {'type':'build_lora_dataset','params':dict(char, trigger_word='skshero'), 'inputs':{'images':['x']}}
        validate_artifact(body, caps)
        body['params']['anchor_embedding'] = human['anchor_embedding']
        with self.assertRaises(ApiError): validate_artifact(body, caps)

    def test_selected_character_uses_associated_body_not_largest_or_first(self):
        record = detect_character_record_from_image(self.path, self.detector, self.embedder, self.bodies, vector(768, 1))
        self.assertGreater(record['body_bbox'][0], 150)
        crops = extract_face_and_body_crop(record, None)
        self.assertIsNotNone(crops['face_crop'])
        self.assertIsNotNone(crops['body_crop'])
        self.assertGreater(crops['body_crop'][:, :, 0].mean(), crops['body_crop'][:, :, 2].mean())
        self.assertFalse(crops['restored'])
        self.assertIsNone(detect_character_record_from_image(self.path, self.detector, self.embedder, self.bodies, vector(768, 2)))

    def test_ambiguous_or_missing_character_never_guesses(self):
        equal = SimpleNamespace(embed_crop=lambda crop: vector(768))
        self.assertIsNone(detect_character_record_from_image(self.path, self.detector, equal, self.bodies, vector(768)))
        self.assertIsNone(detect_character_record_from_image(self.path, SimpleNamespace(detect=lambda *a, **k: []), equal, self.bodies, vector(768)))

    def test_mobile_dataset_uses_ccip_and_does_not_load_human_face_engine(self):
        import analysis
        inputs = self.root / 'input.images.0'
        inputs.write_bytes(self.path.read_bytes())
        engines = SimpleNamespace(_face_app=None, _body=self.bodies)
        calls = []
        engines.load = lambda **kwargs: calls.append(kwargs)
        job = {'type':'build_lora_dataset', 'params':{'trigger_word':'skshero', 'identity_model_id':'ccip-caformer24@1', 'anchor_embedding':encoded(vector(768, 1))}}
        def writer(records, trigger, slug, root, repeats, face_app, restorer, tagger, progress):
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]['identity_kind'], 'character')
            self.assertIsNone(face_app)
            self.assertIsNone(restorer)
            folder = root / 'dataset'; folder.mkdir(parents=True)
            (folder / 'image.jpg').write_bytes(b'image')
            return {'blocked':False, 'dataset_dir':str(folder), 'image_count':1}
        with patch.object(analysis, 'get_anime_detector', return_value=self.detector), patch.object(analysis, 'get_ccip_embedder', return_value=self.embedder), patch('lora_dataset._write_dataset_records', side_effect=writer), patch('lora_dataset.WD14Tagger'):
            result = run_artifact(job, self.root, lambda *a, **k: None, lambda: False, SimpleNamespace(engines=engines))
        self.assertEqual(calls, [{'faces':False}])
        self.assertEqual(result['identity_model_id'], 'ccip-caformer24@1')
        self.assertTrue((self.root / 'dataset.zip').exists())

    def test_missing_character_models_fail_explicitly(self):
        import analysis
        (self.root / 'input.images.0').write_bytes(self.path.read_bytes())
        engines = SimpleNamespace(load=lambda **kwargs: None)
        job = {'type':'build_lora_dataset', 'params':{'trigger_word':'skshero', 'identity_model_id':'ccip-caformer24@1', 'anchor_embedding':encoded(vector(768))}}
        with patch.object(analysis, 'get_anime_detector', return_value=None), patch.object(analysis, 'get_ccip_embedder', return_value=None):
            with self.assertRaisesRegex(ValueError, 'unavailable'):
                run_artifact(job, self.root, lambda *a, **k: None, lambda: False, SimpleNamespace(engines=engines))

    def test_training_and_generation_use_dataset_and_lora_without_human_verification(self):
        import zipfile
        dataset = self.root / 'input.dataset'
        with zipfile.ZipFile(dataset, 'w') as archive:
            for index in range(5):
                archive.writestr(f'20_skshero person/{index}.jpg', b'image')
                archive.writestr(f'20_skshero person/{index}.txt', b'skshero person')
        params = {'trigger_word':'skshero', 'base_checkpoint':'sd15_test', 'identity_model_id':'ccip-caformer24@1'}
        caps = {'engines': {'lora_train':True, 'lora_generate':True}, 'lora_base_checkpoints':['sd15_test']}
        train = {'type':'train_lora', 'params':params, 'inputs':{'dataset':'blob'}}
        generate = {'type':'generate_lora_images', 'params':dict(params, num_images=1, prompt='A fully clothed illustrated character'), 'inputs':{'lora':'blob'}}
        validate_artifact(train, caps)
        validate_artifact(generate, caps)
        engines = SimpleNamespace(unload=lambda: None)
        def fake_process(command, directory, stopped, line, **kwargs):
            if kwargs.get('stdin') is None:
                (directory/'training-output'/'character.safetensors').write_bytes(b'weights')
            else:
                (directory/'generated'/'result.png').write_bytes(b'image')
            return 0
        with patch('mobile_api.artifact_jobs.run_process', side_effect=fake_process):
            trained = run_artifact(train, self.root, lambda *a, **k: None, lambda: False, SimpleNamespace(engines=engines))
            (self.root/'input.lora').write_bytes((self.root/'lora.safetensors').read_bytes())
            generated = run_artifact(generate, self.root, lambda *a, **k: None, lambda: False, SimpleNamespace(engines=engines))
        self.assertEqual(trained['identity_model_id'], 'ccip-caformer24@1')
        self.assertEqual(generated['identity_model_id'], 'ccip-caformer24@1')
        self.assertEqual(generated['image_count'], 1)
        self.assertTrue((self.root/'portraits.zip').exists())

    def test_character_defaults_preserve_illustration_and_user_overrides(self):
        from lora_generate import generation_prompts, DEFAULT_PROMPT_TEMPLATE, DEFAULT_NEGATIVE_PROMPT
        human, human_negative, _ = generation_prompts({'trigger_word':'skshero'})
        self.assertEqual(human, DEFAULT_PROMPT_TEMPLATE.format(trigger='skshero'))
        self.assertEqual(human_negative, DEFAULT_NEGATIVE_PROMPT)
        request = {'trigger_word':'skshero', 'identity_model_id':'ccip-caformer24@1'}
        prompt, negative, angles = generation_prompts(request)
        self.assertIn('illustrated', prompt)
        self.assertNotIn('anime', negative)
        self.assertTrue(all('skin texture' not in angle for angle in angles))
        explicit = dict(request, prompt='Fully clothed character in a garden', negative_prompt='blur')
        self.assertEqual(generation_prompts(explicit)[:2], (explicit['prompt'], explicit['negative_prompt']))
        self.assertEqual(generation_prompts(dict(request, negative_prompt=''))[1], '')


if __name__ == '__main__':
    unittest.main()
