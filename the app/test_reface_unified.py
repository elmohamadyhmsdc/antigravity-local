"""One-pipeline/profile regressions; synthetic pixels, no model loading."""
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import cv2
import numpy as np

from reface_config import profile_defaults, profile_catalog
from reface import RefaceEngine
from reface_engine_v3 import RefaceEngineV3
from mobile_api.reface_runner import run_reface
from mobile_api.studio_jobs import validate_reface
from mobile_api.testing import FakeProbe, unit
from mobile_api.schemas import encode_embedding
from mobile_api.errors import ApiError


class UnifiedTests(unittest.TestCase):
    def test_profiles_configure_one_class_and_share_current_frame_pipeline(self):
        created = []
        def init(engine, **kwargs):
            created.append((type(engine), kwargs))
        with patch.object(RefaceEngineV3, '__init__', init):
            for profile in ('fast', 'balanced', 'detail'):
                engine = RefaceEngine(quality_profile=profile)
                self.assertEqual(engine.quality_profile, profile)
                self.assertIs(engine.render_frame.__func__, RefaceEngineV3.render_frame)
        self.assertEqual([kind for kind, _ in created], [RefaceEngine] * 3)
        self.assertEqual(created[0][1]['restorer'], 'none')
        self.assertFalse(created[0][1]['use_parser'])

    def test_automatic_model_selection_is_deterministic_and_reports_fallbacks(self):
        models = ['codeformer', 'gpen_bfr_512', 'gpen_bfr_1024']
        catalog = profile_catalog(models)
        self.assertEqual([catalog[p]['restorer'] for p in ('fast', 'balanced', 'detail')],
                         ['none', 'gpen_bfr_512', 'gpen_bfr_1024'])
        self.assertEqual(profile_defaults('detail', ['codeformer', 'gpen_bfr_512'])['restorer'], 'gpen_bfr_512')
        self.assertEqual(profile_defaults('balanced', ['codeformer'])['restorer'], 'codeformer')
        self.assertEqual(profile_defaults('balanced', [])['restorer'], 'none')
        with self.assertRaises(ValueError):
            profile_defaults('v2', models)

    def test_explicit_restoration_and_parser_override_profile_defaults(self):
        seen = {}
        with patch.object(RefaceEngineV3, '__init__', lambda engine, **kw: seen.update(kw)):
            RefaceEngine(quality_profile='fast', restorer='gpen_bfr_1024', use_parser=True)
        self.assertEqual(seen['restorer'], 'gpen_bfr_1024')
        self.assertEqual(seen['restore_size'], 1024)
        self.assertTrue(seen['use_parser'])

    def test_fast_masking_does_not_load_an_unused_parser_and_keeps_occlusion(self):
        from face_masking import FaceMasker
        with tempfile.TemporaryDirectory() as tmp:
            parser, occluder = Path(tmp)/'parser.onnx', Path(tmp)/'occluder.onnx'
            parser.write_bytes(b'fake'); occluder.write_bytes(b'fake')
            session = SimpleNamespace(get_inputs=lambda:[SimpleNamespace(name='pixels',shape=[1,3,256,256])])
            with patch('face_masking._parser_session_with_argmax') as load_parser, \
                 patch('face_masking._make_session', return_value=session) as load_session:
                masker = FaceMasker(parser_path=str(parser), occluder_path=str(occluder),
                                    load_parser=False, load_occluder=True)
            load_parser.assert_not_called()
            load_session.assert_called_once()
            self.assertIsNone(masker.parser)
            self.assertIs(masker.occluder, session)

    def test_trained_identity_uses_same_engine_with_restoration_disabled(self):
        seen = {}
        with patch.object(RefaceEngineV3, '__init__', lambda engine, **kw: seen.update(kw)):
            RefaceEngine(dfm_path='test-model.dfm', restorer='codeformer')
        self.assertEqual(seen['restorer'], 'none')
        self.assertEqual(seen['dfm_path'], 'test-model.dfm')

    def test_canonical_photo_and_video_validation_and_legacy_compatibility(self):
        caps = FakeProbe().snapshot()
        params = dict(source_faces=[dict(embedding=encode_embedding(unit(1)), quality=.8)])
        for kind in ('reface_image', 'reface_video'):
            for profile in ('fast', 'balanced', 'detail'):
                validate_reface(dict(type=kind, inputs={'target':'a'*64},
                    params={**params, 'quality_profile':profile}), caps)
        for kind in ('reface_image_v2', 'reface_image_v3'):
            validate_reface(dict(type=kind, inputs={'target':'a'*64}, params=params), caps)
        for value in ('v1', True, None):
            with self.assertRaises(ApiError):
                validate_reface(dict(type='reface_image', inputs={'target':'a'*64},
                    params={**params, 'quality_profile':value}), caps)
        validate_reface(dict(type='reface_video', inputs={'target':'a'*64},
            params=dict(source_faces=[], dfm_model='RTM_WF_224', quality_profile='balanced')), caps)
        caps['engines']['reface'] = False
        with self.assertRaises(ApiError):
            validate_reface(dict(type='reface_image', inputs={'target':'a'*64}, params=params), caps)

    def test_mobile_adapter_calls_canonical_photo_method_and_reports_actual_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            target = directory/'input.target'
            cv2.imencode('.png', np.zeros((32,32,3), np.uint8))[1].tofile(target)
            seen = {}
            class Engine:
                def __init__(self, **kwargs):
                    seen.update(kwargs)
                def reface_image(self, path, faceset, selected, references):
                    seen['selection'] = (selected, references)
                    output = directory/'photo.png'
                    cv2.imwrite(str(output), np.ones((32,32,3), np.uint8))
                    return SimpleNamespace(success=True, output_path=str(output), faces_swapped=1,
                        details={'settings':{'engine':'reface','quality_profile':'fast','restorer':'none'}})
            job = dict(type='reface_image', params=dict(source_faces=[], quality_profile='fast'))
            with patch('reface.RefaceEngine', Engine):
                meta = run_reface(job, directory, lambda *a, **k:None, lambda:False)
            self.assertEqual(seen['quality_profile'], 'fast')
            self.assertIsNone(seen['use_parser'])
            self.assertEqual(seen['selection'], (None, None))
            self.assertEqual(meta['settings']['engine'], 'reface')
            self.assertEqual(meta['settings']['restorer'], 'none')
            self.assertTrue((directory/'result.png').exists())

    def test_mobile_canonical_video_uses_unified_method_and_keeps_all_frames(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory/'input.target').write_bytes(b'video')
            seen = {}
            class Capture:
                def get(self, key): return 2 if key == cv2.CAP_PROP_FPS else 6
                def release(self): pass
            class Engine:
                def __init__(self, **kwargs): seen.update(kwargs)
                def reface_video(self, target, faceset, **kwargs):
                    seen.update(kwargs)
                    kwargs['progress_callback'](6,6)
                    output = directory/'part.mp4'
                    output.write_bytes(b'part')
                    return SimpleNamespace(success=True, output_path=str(output), faces_swapped=6,
                        details={'frames_done':6,'faces_swapped':6,'settings':{'engine':'reface'}})
            job = dict(type='reface_video', params=dict(source_faces=[], quality_profile='balanced',
                target_embeddings=[encode_embedding(unit(1))], target_indices=[0]))
            with patch('reface.RefaceEngine', Engine), patch('mobile_api.reface_runner.cv2.VideoCapture',return_value=Capture()), \
                 patch('reface_video_io.validate_video'), patch('ffmpeg_utils.mux_audio',return_value=True):
                meta = run_reface(job, directory, lambda *a, **k:None, lambda:False)
            self.assertEqual(meta['engine'], 'reface')
            self.assertEqual(meta['frames_done'], 6)
            self.assertEqual(seen['target_face_indices'], [0])
            self.assertEqual(seen['resume_from_frame'], 0)
            self.assertFalse(seen['finalize'])
            np.testing.assert_allclose(seen['target_face_embeddings'][0], unit(1))


if __name__ == '__main__':
    unittest.main(verbosity=2)
