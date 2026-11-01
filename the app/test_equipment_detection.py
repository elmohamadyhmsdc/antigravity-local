"""Equipment geometry, isolated worker protocol, auth and API shape. No GPU or server launch."""
import json
import sys
import unittest
from unittest.mock import patch

import numpy as np
import equipment_detection as equipment


class EquipmentTests(unittest.TestCase):
    def test_only_equipment_near_people_is_kept(self):
        body = {"bbox": [10, 10, 100, 190], "kpts": None, "kpt_scores": None}
        objects = [{"label": "dumbbells", "bbox": [80, 80, 120, 110]},
                   {"label": "person", "bbox": [10, 10, 100, 190]},
                   {"label": "ball", "bbox": [270, 220, 290, 240]},
                   {"label": "racket", "bbox": [float('nan'), 0, 20, 20]}, None]
        rows = equipment.associate_objects(objects, [body], 300, 300)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['label'], 'dumbbell')
        self.assertEqual(rows[0]['body_index'], 0)
        self.assertTrue(all(0 <= v <= 1 for v in rows[0]['bbox'].values()))

    def test_ambiguous_owner_remains_shared(self):
        body = {"bbox": [10, 10, 150, 190], "kpts": None, "kpt_scores": None}
        rows = equipment.associate_objects([{"label": "ball", "bbox": [60, 60, 100, 100]}], [body, body], 300, 300)
        self.assertIsNone(rows[0]['body_index'])

    def test_worker_bytes_are_piped_without_saving_images(self):
        code = "import json,sys; x=json.loads(sys.stdin.read()); assert x['image']; print('@@equipment '+json.dumps([{'label':'ball','bbox':[40,40,80,80]}]))"
        rows = equipment.detect_equipment(np.zeros((100,100,3),dtype=np.uint8),
            [{"bbox":[10,10,90,90]}], worker_command=[sys.executable,'-c',code])
        self.assertEqual(rows[0]['label'], 'ball')
        with self.assertRaises(RuntimeError):
            equipment.detect_equipment(np.zeros((100,100,3),dtype=np.uint8), [],
                worker_command=[sys.executable,'-c',"raise RuntimeError('failed')"])

    def test_endpoint_auth_missing_model_validation_and_response_schema(self):
        import test_mobile_api_contract as contract
        with contract.Env() as env:
            env.ctx.engines.equipment_ready = True
            env.ctx.engines.compute_equipment = lambda image, bodies: [{"object_key":"racket:1", "label":"racket",
                "body_index":0,"bbox":{"x":.1,"y":.1,"w":.2,"h":.2}}] if bodies else []
            files = {'image': ('photo.jpg',contract.jpeg_bytes(),'image/jpeg')}
            bodies = json.dumps([{'bbox': {'x':10,'y':10,'w':200,'h':300}}])
            response = env.client.post('/v1/analyze/equipment',files=files,data={'bodies':bodies},headers=env.auth)
            self.assertEqual(response.status_code,200,response.text)
            contract.check_schema('EquipmentResponse',response.json())
            self.assertEqual(env.client.post('/v1/analyze/equipment',files=files).status_code,401)
            self.assertEqual(env.client.post('/v1/analyze/equipment',files=files,data={'bodies':'wrong'},headers=env.auth).status_code,400)
            env.ctx.engines.equipment_ready = False
            self.assertEqual(env.client.post('/v1/analyze/equipment',files=files,headers=env.auth).status_code,409)
            env.ctx.engines.equipment_ready = True
            env.ctx.engines.compute_equipment = lambda *_: (_ for _ in ()).throw(RuntimeError('worker failed'))
            response = env.client.post('/v1/analyze/equipment',files=files,headers=env.auth)
            self.assertEqual(response.status_code,500)
            self.assertTrue(response.json()['error']['retryable'])


if __name__ == '__main__':
    unittest.main()
