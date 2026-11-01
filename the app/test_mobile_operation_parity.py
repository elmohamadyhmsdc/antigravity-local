"""CPU-only execution-contract tests, fake engines and workspace-owned fixtures."""
import copy
import math
from pathlib import Path
import tempfile
import unittest

from fastapi.testclient import TestClient

from mobile_api.action_matching import match_request, ActionRequestError
from mobile_api.operation_support import operation_support

HERE = Path(__file__).resolve().parent


def frame(time=0, angle=0, count=1):
    points = [(50,10),(54,8),(46,8),(58,10),(42,10),(65,25),(35,25),(72,43),
              (28,43),(74,60),(26,60),(59,55),(41,55),(61,75),(39,75),(65,95),(35,95)]
    members = []
    for member in range(count):
        data = []
        for x, y in points:
            data.extend(((x-50)*math.cos(angle)/30-(y-55)*math.sin(angle)/30+member*3,
                         (x-50)*math.sin(angle)/30+(y-55)*math.cos(angle)/30))
        members.append(dict(points=data, mask=(1 << 17)-1, scale='torso' if count == 1 else 'group'))
    return dict(time=time, members=members)


class OperationParityTests(unittest.TestCase):
    def test_matrix_distinguishes_model_paths_and_missing_assets(self):
        flags = dict(face_detection=True, character_identity=True, body_detection=True,
                     dataset_person=True, dataset_character=True, reface=True, reface_reference=False,
                     lora_train=True, lora_generate=True)
        entries = operation_support(dict(engines=flags))
        find = lambda op, kind: next(e for e in entries if e['operation']==op and e['kind']==kind)
        self.assertTrue(find('dataset_build','character')['available'])
        self.assertEqual(find('dataset_build','character')['identity_models'], ['ccip-caformer24@1'])
        self.assertEqual(find('dataset_build','person')['identity_models'], ['buffalo_l@1'])
        self.assertTrue(find('reface','person')['available'])
        self.assertFalse(find('reface','character')['available'])
        flags['reface_reference'] = True
        self.assertTrue(next(e for e in operation_support(dict(engines=flags))
                             if e['operation']=='reface' and e['kind']=='character')['available'])

    def test_action_photos_preserve_group_geometry_and_detection_order(self):
        query = frame(count=2)
        same = copy.deepcopy(query)
        same['members'].reverse()
        apart = copy.deepcopy(query)
        apart['members'][1]['points'] = [v+5 if i%2==0 else v for i,v in enumerate(apart['members'][1]['points'])]
        result = match_request(dict(kind='photo',query=[query],candidates=[
            dict(id='same',frames=[same]),dict(id='apart',frames=[apart]),dict(id='one',frames=[frame()])]))
        values = {m['id']:m['score'] for m in result['matches']}
        self.assertAlmostEqual(values['same'],1)
        self.assertLess(values['apart'],.1)
        self.assertIsNone(values['one'])

    def test_action_motion_retains_direction_and_allows_timing_variation(self):
        query = [frame(i*1000,i*math.pi/4) for i in range(3)]
        same = [frame(i*600,i*math.pi/8) for i in range(5)]
        reverse = [frame(i*1000,(2-i)*math.pi/4) for i in range(3)]
        result = match_request(dict(kind='video',query=query,candidates=[
            dict(id='same',frames=same),dict(id='reverse',frames=reverse)]))
        self.assertGreater(result['matches'][0]['score'],.82)
        self.assertLess(result['matches'][1]['score'],.82)

    def test_action_limits_reject_malformed_or_unbounded_work(self):
        base = dict(kind='photo',query=[frame()],candidates=[dict(id='a',frames=[frame()])])
        for change in ('nan','count','mask','duplicates','time','kind','boolean'):
            body = copy.deepcopy(base)
            if change=='nan': body['query'][0]['members'][0]['points'][0] = float('nan')
            elif change=='count': body['candidates'] *= 65
            elif change=='mask': body['query'][0]['members'][0]['mask'] = 1
            elif change=='duplicates': body['candidates'] *= 2
            elif change=='time': body['query'][0]['time'] = -1
            elif change=='kind': body['kind']='text'
            else: body['allow_mirror']=1
            with self.subTest(change=change), self.assertRaises(ActionRequestError):
                match_request(body)

    def test_character_grouping_contract_and_execution_agree_on_dimensions(self):
        import json
        import grouping_core
        from test_mobile_api_contract import schema_errors
        base=HERE/'mobile_api/contract/fixtures'
        request=json.loads((base/'GroupingPlanRequest.character_identity.json').read_text())
        self.assertEqual(schema_errors('GroupingPlanRequest',request),[])
        result=grouping_core.plan_request(request)
        covered=set(result['unsorted_face_ids'])
        for group in result['groups']: covered.update(group['face_ids'])
        for assignment in result['assignments']: covered.add(assignment['face_id'])
        self.assertEqual(covered,{501,502})
        wrong=copy.deepcopy(request)
        legacy=json.loads((base/'AnalyzeImageResponse.two_faces_one_body.json').read_text())
        wrong['pending'][0]['embedding']=legacy['faces'][0]['embedding']
        self.assertTrue(schema_errors('GroupingPlanRequest',wrong))
        with self.assertRaises(grouping_core.GroupingRequestError):grouping_core.plan_request(wrong)

    def test_endpoint_is_authenticated_stateless_cpu_and_schema_shaped(self):
        from mobile_api.app import create_app
        from mobile_api.testing import make_test_context
        from test_mobile_api_contract import check_schema
        (HERE/'build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=HERE/'build',prefix='parity_test_') as tmp:
            ctx=make_test_context(Path(tmp))
            try:
                with TestClient(create_app(ctx),raise_server_exceptions=False) as client:
                    request=dict(kind='photo',query=[frame()],candidates=[dict(id='one',frames=[frame()])])
                    self.assertEqual(client.post('/v1/actions/match',json=request).status_code,401)
                    code=ctx.pairing.issue().code
                    token=client.post('/v1/pair/complete',json=dict(code=code,device_name='CPU fixture')).json()['token']
                    auth={'Authorization':'Bearer '+token}
                    ctx.gpu.require_free=lambda: (_ for _ in ()).throw(AssertionError('CPU match must not acquire GPU'))
                    response=client.post('/v1/actions/match',json=request,headers=auth)
                    self.assertEqual(response.status_code,200,response.text)
                    self.assertAlmostEqual(response.json()['matches'][0]['score'],1)
                    self.assertEqual(ctx.video_jobs.jobs,{})
                    self.assertEqual(ctx.studio_jobs.jobs,{})
                    caps=client.get('/v1/capabilities',headers=auth)
                    self.assertEqual(caps.status_code,200,caps.text)
                    check_schema('Capabilities',caps.json())
                    entries=caps.json()['operations']
                    self.assertTrue(all(any(e['operation']=='action_match' and e['kind']==kind and e['available']
                                           for e in entries) for kind in ('person','character')))
                    import json
                    group=json.loads((HERE/'mobile_api/contract/fixtures/GroupingPlanRequest.character_identity.json').read_text())
                    grouped=client.post('/v1/grouping/plan',json=group,headers=auth)
                    self.assertEqual(grouped.status_code,200,grouped.text)
                    check_schema('GroupingPlanResponse',grouped.json())
                    self.assertEqual(client.post('/v1/actions/match',json={},headers=auth).status_code,400)
                    huge={**auth,'Content-Length':str(17*1024*1024)}
                    self.assertEqual(client.post('/v1/actions/match',content=b'{}',headers=huge).status_code,413)
            finally:
                ctx.image_decoder.close()


if __name__=='__main__':
    unittest.main()
