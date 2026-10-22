"""CPU-only artifact job validation, private inputs and safe dataset extraction."""

import hashlib
import io
import tempfile
import time
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
from fastapi.testclient import TestClient

from mobile_api.app import create_app
from mobile_api.artifact_jobs import extract_dataset, validate_artifact
from mobile_api.errors import ApiError
from mobile_api.schemas import encode_embedding
from mobile_api.testing import make_test_context, unit


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='ag_artifact_test_')
        self.ctx=make_test_context(Path(self.tmp.name))
        self.client=TestClient(create_app(self.ctx))
        self.device=self.ctx.auth.add_device('Phone')
        self.headers={'Authorization':'Bearer '+self.device['token']}
    def tearDown(self):
        self.ctx.studio_jobs.close();self.ctx.video_jobs.close();self.client.close();self.tmp.cleanup()
    def blob(self,data):
        sha=hashlib.sha256(data).hexdigest();self.client.put('/v1/blobs/'+sha,content=data,headers=self.headers);return sha
    def test_all_artifact_types_are_queued_with_pinned_inputs_and_private_manifest(self):
        sha=self.blob(b'image')
        cases=[('undress_image',{'prompt':'A blue suit'},{'image':sha,'refs':[sha]},'result.png','image/png'),
               ('build_lora_dataset',{'trigger_word':'skscharacter','anchor_embedding':encode_embedding(unit(1))},{'images':[sha,sha]},'dataset.zip','application/zip'),
               ('train_lora',{'trigger_word':'skscharacter','base_checkpoint':'sd15_realistic_base'},{'dataset':sha},'lora.safetensors','application/octet-stream'),
               ('generate_lora_images',{'trigger_word':'skscharacter','base_checkpoint':'sd15_realistic_base'},{'lora':sha,'reference':sha},'portraits.zip','application/zip')]
        for index,(kind,params,inputs,name,mime) in enumerate(cases):
            def runner(job,directory,report,stopped):
                self.assertTrue(list(directory.glob('input.*')))
                (directory/name).write_bytes(b'artifact')
                return {'trigger_word':'skscharacter'}
            self.ctx.studio_jobs.runner=runner
            response=self.client.post('/v1/jobs',json={'type':kind,'params':params,'inputs':inputs,'client_job_id':f'job-{index}'},headers=self.headers)
            self.assertEqual(response.status_code,201,response.text)
            job=response.json()['job_id']
            for _ in range(200):
                status=self.client.get('/v1/jobs/'+job,headers=self.headers).json()
                if status['status'] in ('completed','failed'):break
                time.sleep(.01)
            self.assertEqual(status['status'],'completed')
            manifest=self.client.get(f'/v1/jobs/{job}/result',headers=self.headers).json()
            self.assertEqual(manifest['files'][0]['mime'],mime)
            self.assertEqual(self.client.get(f'/v1/jobs/{job}/result/{name}',headers=self.headers).content,b'artifact')

    def test_unsafe_options_and_paths_are_rejected_before_queueing(self):
        caps=self.ctx.probe.snapshot()
        for kind,params in [('train_lora',{'trigger_word':'sksx','base_checkpoint':'../../outside'}),
                            ('generate_lora_images',{'trigger_word':'sksx','base_checkpoint':'sd15_realistic_base','num_images':100}),
                            ('undress_image',{'image_path':'C:/private.png'}),
                            ('build_lora_dataset',{'trigger_word':'sksx','anchor_embedding':'not-an-embedding'})]:
            slot={'train_lora':'dataset','generate_lora_images':'lora','undress_image':'image','build_lora_dataset':'images'}[kind]
            with self.assertRaises(ApiError):validate_artifact({'type':kind,'params':params,'inputs':{slot:['a'*64] if slot=='images' else 'a'*64}},caps)

    def test_dataset_archive_is_bounded_and_cannot_escape_or_load_python_state(self):
        def bundle(names):
            stream=io.BytesIO()
            with zipfile.ZipFile(stream,'w') as out:
                for name in names:out.writestr(name,b'photo' if not name.endswith('.txt') else b'sksx person')
            stream.seek(0);return stream
        for names in [['../outside.jpg'],['1_sksx person/model.pkl'],['C:/outside.png'],['1_sksx person/a.jpg']]:
            with tempfile.TemporaryDirectory() as tmp:
                with self.assertRaises(ValueError):extract_dataset(bundle(names),Path(tmp))
        with tempfile.TemporaryDirectory() as tmp:
            names=[f'20_sksx person/{i}.{ext}' for i in range(5) for ext in ('jpg','txt')]
            folder=extract_dataset(bundle(names),Path(tmp));self.assertEqual(len(list(folder.glob('*.jpg'))),5)

    def test_dataset_anchor_selects_the_person_instead_of_the_largest_face(self):
        from lora_dataset import detect_face_record_from_image
        import cv2
        from mobile_api.testing import FakeFace
        path=Path(self.tmp.name)/'photo.png';cv2.imwrite(str(path),np.zeros((100,100,3),np.uint8))
        faces=[FakeFace((0,0,80,80),unit(2)),FakeFace((10,10,30,30),unit(1))]
        record=detect_face_record_from_image(str(path),SimpleNamespace(get=lambda image:faces),unit(1))
        self.assertEqual(record['bbox_width'],20)
        self.assertIsNone(detect_face_record_from_image(str(path),SimpleNamespace(get=lambda image:faces),unit(9)))

    def test_empty_model_folders_are_not_reported_as_a_working_restyle_engine(self):
        from mobile_api.model_readiness import restyle_missing_models
        from undress_core import INPAINT_MODEL_ID
        root=Path(self.tmp.name)
        folder=root/'models'/'undress'/INPAINT_MODEL_ID.replace('/','--')
        folder.mkdir(parents=True)
        (folder/'model_index.json').write_text('{}')
        missing=restyle_missing_models(root,cache_roots=[])
        self.assertIn(INPAINT_MODEL_ID,missing)
        self.assertIn('lllyasviel/Annotators',missing)

    def test_basic_restyle_does_not_require_optional_sdxl_weights(self):
        caps = self.ctx.probe.snapshot()
        caps['engines']['undress'] = True
        caps['engines']['restyle_refine'] = False
        basic = {'type': 'undress_image', 'params': {'prompt': 'A blue coat', 'refine': False},
                 'inputs': {'image': 'a' * 64}}
        validate_artifact(basic, caps)
        for params in ({'prompt': 'A blue coat'}, {'prompt': 'A blue coat', 'refine': True}):
            with self.assertRaises(ApiError) as error:
                validate_artifact({**basic, 'params': params}, caps)
            self.assertEqual(error.exception.code, 'engine_unavailable')

    def test_caption_tagger_is_not_offered_as_a_dfm_face_model(self):
        from mobile_api.engines import available_dfm_models
        def model(path): return SimpleNamespace(path=path,model_type='Unknown')
        with patch('dfm_engine.DFMEngine.list_available_models',return_value=[
                model('models/wd14_tagger_model.onnx'),model('models/person.dfm'),model('models/dfm/person.onnx')]):
            self.assertEqual([m.path for m in available_dfm_models()],['models/person.dfm','models/dfm/person.onnx'])

    def test_generation_preserves_safetensors_extension_for_uploaded_weights(self):
        from mobile_api.artifact_jobs import run_artifact
        directory=Path(self.tmp.name)/'generation';directory.mkdir()
        (directory/'input.lora').write_bytes(b'safetensors fixture')
        def process(command,work,stopped,on_line,stdin=None,**kwargs):
            import json
            payload=json.loads(stdin)
            self.assertTrue(payload['lora_path'].endswith('.safetensors'))
            self.assertEqual(Path(payload['lora_path']).read_bytes(),b'safetensors fixture')
            (Path(payload['output_dir'])/'image.png').write_bytes(b'png')
            return 0
        with patch('mobile_api.artifact_jobs.run_process',process):
            run_artifact({'type':'generate_lora_images','params':{'trigger_word':'sksx','base_checkpoint':'sd15_realistic_base','num_images':1}},
                         directory,lambda *args,**kwargs:None,lambda:False,self.ctx)
        self.assertTrue((directory/'portraits.zip').is_file())


if __name__=='__main__':unittest.main(verbosity=2)
