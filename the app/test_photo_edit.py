"""Model-free photo editor geometry, immutable pixels and Studio regressions."""
import base64
import hashlib
import io
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image
from fastapi.testclient import TestClient

import photo_edit
from mobile_api.app import create_app
from mobile_api.errors import ApiError
from mobile_api.photo_edit import validate_photo_edit
from mobile_api.testing import make_test_context


class PhotoEditTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        yy,xx = np.indices((120,180))
        self.photo = np.stack([xx,yy,(xx+yy)%256,np.full_like(xx,255)],axis=2).astype(np.uint8)
        self.photo[:20,:20,3] = 40
        self.mask = np.zeros((120,180),np.uint8)
        self.mask[40:70,60:90] = 255
        Image.fromarray(self.photo).save(self.directory/'input.image',format='PNG')
        Image.fromarray(self.mask).save(self.directory/'input.mask',format='PNG')
        self.job = dict(type='edit_image',params=dict(operation='replace',instruction='a small blue ceramic vase',seed=123))

    def render(self,*args):
        return np.full((768,768,3),(10,80,210),np.uint8)

    def test_native_dimensions_alpha_and_all_unselected_pixels_survive(self):
        meta = photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,
                                     finder=lambda image:[],renderer=self.render)
        result = np.asarray(Image.open(self.directory/'result.png'))
        self.assertEqual(result.shape,self.photo.shape)
        np.testing.assert_array_equal(result[self.mask == 0],self.photo[self.mask == 0])
        self.assertTrue(np.any(result[self.mask != 0] != self.photo[self.mask != 0]))
        np.testing.assert_array_equal(result[55,75,:3],[10,80,210])
        self.assertEqual(meta['seed'],123)
        self.assertTrue(meta['outside_selection_unchanged'])

    def test_transparent_selected_area_is_filled_without_changing_other_alpha(self):
        photo = self.photo.copy()
        photo[40:70,60:90,3] = 0
        canvas,mask,geometry = photo_edit.prepare_crop(photo,self.mask//255)
        result = photo_edit.composite(photo,self.mask//255,self.render(),geometry)
        self.assertEqual(result[55,75,3],255)
        np.testing.assert_array_equal(result[self.mask == 0],photo[self.mask == 0])

    def test_person_overlap_prevents_renderer_from_running(self):
        with patch('photo_edit.render_crop') as renderer:
            with self.assertRaisesRegex(ValueError,'protected person'):
                photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,
                                       finder=lambda image:[[65,45,88,68]])
            renderer.assert_not_called()
        self.assertFalse((self.directory/'result.png').exists())

    def test_person_detection_failure_is_not_treated_as_no_people(self):
        def fail(_): raise RuntimeError('Model unavailable')
        with patch('photo_edit.render_crop') as renderer:
            with self.assertRaises(RuntimeError):
                photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,finder=fail)
            renderer.assert_not_called()

    def test_invalid_protection_geometry_cannot_bypass_protection(self):
        for box in ([float('nan'),0,10,20],[0,0,0,0],[4,8]):
            with self.subTest(box=box),self.assertRaises(ValueError):
                photo_edit.check_protection(self.mask//255,[box])

    def test_empty_oversized_or_misaligned_masks_are_rejected(self):
        for mask in (np.zeros((120,180),np.uint8),np.full((120,180),255,np.uint8),np.ones((12,18),np.uint8)):
            Image.fromarray(mask).save(self.directory/'input.mask',format='PNG')
            with self.assertRaises(ValueError):
                photo_edit.read_inputs(self.directory/'input.image',self.directory/'input.mask')

    def test_only_png_single_frame_masks_are_accepted(self):
        Image.fromarray(self.mask).save(self.directory/'input.mask',format='JPEG')
        with self.assertRaisesRegex(ValueError,'PNG'):
            photo_edit.read_inputs(self.directory/'input.image',self.directory/'input.mask')

    def test_normalized_preview_mask_maps_to_upright_native_pixels(self):
        small = np.zeros((60,90),np.uint8)
        small[20:35,30:45] = 255
        Image.fromarray(small).save(self.directory/'input.mask',format='PNG')
        photo,mask = photo_edit.read_inputs(self.directory/'input.image',self.directory/'input.mask',True)
        np.testing.assert_array_equal(mask,self.mask//255)
        Image.fromarray(np.zeros((60,100),np.uint8)).save(self.directory/'input.mask',format='PNG')
        with self.assertRaisesRegex(ValueError,'dimensions'):
            photo_edit.read_inputs(self.directory/'input.image',self.directory/'input.mask',True)

    def test_original_color_profile_survives_png_export(self):
        from PIL import ImageCms
        profile = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()
        Image.fromarray(self.photo).save(self.directory/'input.image',format='PNG',icc_profile=profile)
        photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,
                             finder=lambda image:[],renderer=self.render)
        with Image.open(self.directory/'result.png') as result:
            self.assertEqual(result.info['icc_profile'],profile)

    def test_worker_requires_explicit_safe_result(self):
        from unittest.mock import Mock
        process = Mock(returncode=0)
        process.poll.return_value = 0
        process.communicate.return_value = ((photo_edit.PREFIX+json.dumps(dict(safe=False,image=''))).encode(),None)
        with patch('photo_edit.subprocess.Popen',return_value=process):
            with self.assertRaisesRegex(ValueError,'not supported'):
                photo_edit.render_crop(self.photo,self.mask,dict(operation='remove'),lambda:False)
        process.communicate.return_value = ((photo_edit.PREFIX+json.dumps(dict(safe=False,reason='description_too_long'))).encode(),None)
        with patch('photo_edit.subprocess.Popen',return_value=process):
            with self.assertRaisesRegex(ValueError,'Shorten the description'):
                photo_edit.render_crop(self.photo,self.mask,dict(operation='remove'),lambda:False)

    def test_cancel_kills_and_reaps_a_running_worker(self):
        import threading
        from unittest.mock import Mock
        released = threading.Event()
        process = Mock(returncode=None)
        process.poll.return_value = 0
        process.communicate.side_effect = lambda data:(released.wait(5) and b'',None)
        process.kill.side_effect = released.set
        with patch('photo_edit.subprocess.Popen',return_value=process):
            self.assertIsNone(photo_edit.render_crop(self.photo,self.mask,dict(operation='remove'),lambda:True))
        process.kill.assert_called_once()
        process.wait.assert_called_once()

    def test_exif_upright_dimensions_are_used(self):
        exif = Image.Exif()
        exif[274] = 6
        Image.fromarray(self.photo[:,:,:3]).save(self.directory/'input.image',format='JPEG',exif=exif)
        Image.fromarray(self.mask.T).save(self.directory/'input.mask',format='PNG')
        photo,mask = photo_edit.read_inputs(self.directory/'input.image',self.directory/'input.mask')
        self.assertEqual(photo.shape,(180,120,4))
        self.assertEqual(mask.shape,(180,120))

    def test_edge_selection_crop_stays_inside_source(self):
        mask = np.zeros_like(self.mask)
        mask[:20,:20] = 1
        canvas,selected,geometry = photo_edit.prepare_crop(self.photo,mask)
        self.assertEqual(canvas.shape,(768,768,3))
        self.assertEqual(selected.shape,(768,768))
        self.assertEqual(geometry[:2],(0,0))
        result = photo_edit.composite(self.photo,mask,self.render(),geometry)
        np.testing.assert_array_equal(result[mask == 0],self.photo[mask == 0])

    def test_stop_does_not_publish_partial_result(self):
        self.assertIsNone(photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:True))
        self.assertIsNone(photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,
                         finder=lambda image:[],renderer=lambda *args:None))
        self.assertFalse((self.directory/'result.png').exists())

    def test_invalid_worker_pixels_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'invalid image'):
            photo_edit.edit_photo(self.job,self.directory,lambda *a:None,lambda:False,
                                   finder=lambda image:[],renderer=lambda *args:np.zeros((2,2,3),np.uint8))

    def test_restricted_unknown_and_invalid_options_are_rejected(self):
        invalid = [dict(operation='replace',instruction=''),dict(operation='other'),
                   dict(operation='replace',instruction='nude photo'),dict(operation='replace',instruction='عري'),
                   dict(operation='remove',safety_checker=False),dict(operation='remove',steps=True),
                   dict(operation='remove',steps=41),dict(operation='remove',seed=2**32)]
        for options in invalid:
            with self.subTest(options=options),self.assertRaises(ValueError):
                photo_edit.validate_options(options)
        self.assertEqual(photo_edit.validate_options(dict(operation='remove'))['operation'],'remove')

    def test_capability_and_exact_input_slots_are_required(self):
        body = dict(type='edit_image',params=self.job['params'],inputs=dict(image='a'*64,mask='b'*64))
        validate_photo_edit(body,dict(engines=dict(photo_edit=True)))
        for changed in ({**body,'inputs':dict(image='a'*64)},
                        {**body,'inputs':dict(image=['a'*64],mask='b'*64)}):
            with self.assertRaises(ApiError): validate_photo_edit(changed,dict(engines=dict(photo_edit=True)))
        with self.assertRaises(ApiError) as error: validate_photo_edit(body,dict(engines={}))
        self.assertEqual(error.exception.status,409)


class PhotoEditStudioTests(unittest.TestCase):
    def test_owned_idempotent_lifecycle_download_and_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            ctx = make_test_context(Path(tmp))
            client = TestClient(create_app(ctx))
            phone = ctx.auth.add_device('Editing phone')
            other = ctx.auth.add_device('Other phone')
            headers = dict(Authorization='Bearer '+phone['token'])
            other_headers = dict(Authorization='Bearer '+other['token'])
            ctx.studio_jobs.runner = lambda job,directory,report,stopped: photo_edit.edit_photo(
                job,directory,report,stopped,finder=lambda image:[],
                renderer=lambda *args:np.full((768,768,3),90,np.uint8))
            image = np.full((80,100,3),140,np.uint8)
            mask = np.zeros((80,100),np.uint8)
            mask[30:50,40:60] = 255
            inputs = {}
            try:
                for slot,array in (('image',image),('mask',mask)):
                    payload = base64.b64decode(photo_edit.png64(array))
                    sha = hashlib.sha256(payload).hexdigest()
                    self.assertIn(client.put('/v1/blobs/'+sha,content=payload,headers=headers).status_code,(200,201))
                    inputs[slot] = sha
                body = dict(client_job_id='edit-request-1',type='edit_image',inputs=inputs,params=dict(operation='remove',seed=3))
                response = client.post('/v1/jobs',json=body,headers=headers)
                self.assertEqual(response.status_code,201,response.text)
                job_id = response.json()['job_id']
                self.assertEqual(client.post('/v1/jobs',json=body,headers=headers).json()['job_id'],job_id)
                changed = {**body,'params':dict(operation='remove',seed=4)}
                self.assertEqual(client.post('/v1/jobs',json=changed,headers=headers).status_code,409)
                self.assertEqual(client.get('/v1/jobs/'+job_id,headers=other_headers).status_code,404)
                deadline = time.monotonic()+5
                while time.monotonic() < deadline:
                    status = client.get('/v1/jobs/'+job_id,headers=headers).json()
                    if status['status'] in ('completed','failed'): break
                    time.sleep(.01)
                self.assertEqual(status['status'],'completed',status)
                manifest = client.get('/v1/jobs/'+job_id+'/result',headers=headers).json()
                download = client.get('/v1/jobs/'+job_id+'/result/result.png',headers=headers)
                self.assertEqual(hashlib.sha256(download.content).hexdigest(),manifest['files'][0]['sha256'])
                result = np.asarray(Image.open(io.BytesIO(download.content)).convert('RGB'))
                np.testing.assert_array_equal(result[mask == 0],image[mask == 0])
                self.assertEqual(client.get('/v1/jobs/'+job_id+'/result/input.image',headers=headers).status_code,404)
                self.assertEqual(client.delete('/v1/jobs/'+job_id,headers=headers).status_code,204)
                self.assertFalse(ctx.workspace.job_dir(job_id).exists())
                for sha in inputs.values(): self.assertFalse(ctx.workspace.has_blob(sha))
            finally:
                ctx.studio_jobs.close()
                ctx.video_jobs.close()
                client.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
