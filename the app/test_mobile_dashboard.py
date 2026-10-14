"""Local-only dashboard control, pairing, revoke and real server lifecycle acceptance."""

import json
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

import cv2
import httpx
import numpy as np
from fastapi.testclient import TestClient

from mobile_api import APP_DIR
from mobile_api.admin import PROTOCOL
from mobile_api.app import create_app
from mobile_api.auth import AuthStore
from mobile_api.pair_ui import create_pair_app
from mobile_api.schemas import encode_embedding
from mobile_api.testing import make_test_context,unit
from mobile_dashboard_controller import MobileDashboardController,ControlError


class AdminTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='ag_mobile_admin_')
        self.ctx=make_test_context(Path(self.tmp.name))
        self.api=TestClient(create_app(self.ctx));self.api.__enter__()
        self.admin=TestClient(create_pair_app(self.ctx))
        self.headers={'X-Antigravity-Admin':self.ctx.admin_token}
    def tearDown(self):
        self.admin.close();self.api.__exit__(None,None,None);self.tmp.cleanup()

    def test_admin_controls_need_local_peer_and_secret_and_never_live_on_phone_api(self):
        self.assertEqual(self.admin.get('/admin/status').status_code,403)
        self.assertEqual(self.admin.get('/admin/status',headers={'X-Antigravity-Admin':'wrong'}).status_code,403)
        self.assertEqual(self.admin.get('/admin/status',headers={**self.headers,'Host':'evil.example'}).status_code,403)
        self.assertEqual(self.admin.post('/admin/pairing',json={},headers={**self.headers,'Origin':'https://evil.example'}).status_code,403)
        remote=TestClient(create_pair_app(self.ctx),client=('192.168.1.55',1234))
        self.assertEqual(remote.get('/admin/status',headers=self.headers).status_code,404);remote.close()
        self.assertEqual(self.api.get('/admin/status',headers=self.headers).status_code,404)
        response=self.admin.get('/admin/status',headers=self.headers)
        self.assertEqual(response.status_code,200)
        self.assertEqual(response.headers['cache-control'],'no-store')
        self.assertNotIn('admin_token',response.json())

    def test_qr_is_single_use_cancelable_and_addresses_are_from_this_pc(self):
        from unittest.mock import patch
        # Deterministic QR fixture: OpenCV's decoder has mask-dependent failures
        # for some random payloads; token randomness is tested in the API suite.
        with patch('mobile_api.pairing.secrets.choice',side_effect=iter('ABCDEFGH')):
            response=self.admin.post('/admin/pairing',json={'host':'192.168.1.20'},headers=self.headers)
        pairing=response.json()['pairing'];self.assertEqual(pairing['remaining_seconds'],300)
        from mobile_devices_page import pairing_qr
        from mobile_api.pairing import parse_payload
        qr=cv2.imdecode(np.frombuffer(pairing_qr(pairing['payload']),np.uint8),cv2.IMREAD_GRAYSCALE)
        decoded,_,_=cv2.QRCodeDetector().detectAndDecode(qr)
        self.assertEqual(parse_payload(decoded)['c'],pairing['code'])
        device=self.api.post('/v1/pair/complete',json={'code':pairing['code'],'device_name':'Phone'})
        self.assertEqual(device.status_code,200)
        self.assertIsNone(self.admin.get('/admin/status',headers=self.headers).json()['pairing'])
        self.assertEqual(self.api.post('/v1/pair/complete',json={'code':pairing['code'],'device_name':'Second'}).status_code,401)
        self.admin.post('/admin/pairing',json={},headers=self.headers)
        self.admin.post('/admin/pairing/cancel',headers=self.headers)
        self.assertIsNone(self.ctx.pairing.current())
        self.assertEqual(self.admin.post('/admin/pairing',json={'host':'evil.example'},headers=self.headers).status_code,400)

    def test_device_activity_rename_and_revocation_are_persistent_and_no_tokens_leak(self):
        phone=self.ctx.auth.add_device('Original name');other=self.ctx.auth.add_device('Other phone')
        headers={'Authorization':'Bearer '+phone['token']}
        self.api.get('/v1/capabilities',headers=headers)
        devices=self.admin.get('/admin/status',headers=self.headers).json()['devices']
        self.assertTrue(next(d for d in devices if d['id']==phone['id'])['active_recently'])
        self.assertFalse(next(d for d in devices if d['id']==other['id'])['active_recently'])
        self.assertNotIn('token_hash',json.dumps(devices));self.assertNotIn(phone['token'],json.dumps(devices))
        self.assertEqual(self.admin.post(f"/admin/devices/{phone['id']}/rename",json={'name':'My Samsung'},headers=self.headers).status_code,200)
        self.assertEqual(AuthStore(self.ctx.auth.path).devices()[0]['name'],'My Samsung')
        self.ctx.pairing.issue()
        self.admin.post(f"/admin/devices/{phone['id']}/revoke",headers=self.headers)
        self.assertIsNone(self.ctx.pairing.current())
        self.assertEqual(self.api.get('/v1/capabilities',headers=headers).status_code,401)
        self.assertEqual(self.api.get('/v1/capabilities',headers={'Authorization':'Bearer '+other['token']}).status_code,200)
        self.assertFalse(AuthStore(self.ctx.auth.path).has_device(phone['id']))

    def test_disconnect_pauses_work_for_that_phone(self):
        phone=self.ctx.auth.add_device('Worker phone');headers={'Authorization':'Bearer '+phone['token']}
        entered=threading.Event()
        def runner(job,directory,report,stopped):
            entered.set()
            while not stopped():time.sleep(.01)
            return None
        self.ctx.studio_jobs.runner=runner
        import hashlib
        blob=b'target';sha=hashlib.sha256(blob).hexdigest()
        self.api.put('/v1/blobs/'+sha,headers=headers,content=blob)
        response=self.api.post('/v1/jobs',headers=headers,json={'type':'reface_image_v3','client_job_id':'disconnect-fixture',
            'inputs':{'target':sha},'params':{'source_faces':[{'embedding':encode_embedding(unit(1)),'quality':.9}]}})
        self.assertEqual(response.status_code,201,response.text);job=response.json()['job_id']
        self.assertTrue(entered.wait(3))
        response=self.admin.post(f"/admin/devices/{phone['id']}/revoke",headers=self.headers)
        self.assertEqual(response.json()['paused_jobs'],1)
        for _ in range(100):
            if self.ctx.studio_jobs.jobs[job]['status']=='paused':break
            time.sleep(.01)
        self.assertEqual(self.ctx.studio_jobs.jobs[job]['status'],'paused')
        self.assertEqual(self.api.get('/v1/jobs/'+job,headers=headers).status_code,401)

    def test_disconnect_all_invalidates_pairing_and_both_device_tokens(self):
        devices=[self.ctx.auth.add_device(name) for name in ('One','Two')]
        self.ctx.pairing.issue()
        self.assertEqual(self.admin.post('/admin/devices/revoke-all',headers=self.headers).json()['revoked'],2)
        self.assertFalse(self.ctx.auth.devices());self.assertIsNone(self.ctx.pairing.current())
        for d in devices:self.assertIsNone(self.ctx.auth.authenticate(d['token']))


class UiTests(unittest.TestCase):
    def test_dashboard_access_uses_the_servers_socket_peer(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        from mobile_devices_page import local_dashboard_session
        client=SimpleNamespace(client_context=SimpleNamespace(remote_ip='127.0.0.1'))
        runtime=SimpleNamespace(get_client=lambda session_id:client)
        with patch('streamlit.runtime.get_instance',return_value=runtime), patch(
                'streamlit.runtime.scriptrunner.get_script_run_ctx',return_value=SimpleNamespace(session_id='fixture')):
            self.assertTrue(local_dashboard_session())
            client.client_context.remote_ip='192.168.1.55'
            self.assertFalse(local_dashboard_session())
            client.client_context.remote_ip=None
            self.assertFalse(local_dashboard_session())

    def app(self,controller,local=True):
        from streamlit.testing.v1 import AppTest
        from unittest.mock import patch
        app=AppTest.from_string('from mobile_devices_page import render_mobile_devices\nrender_mobile_devices()',default_timeout=20)
        self.patch=patch('mobile_devices_page.mobile_controller',return_value=controller)
        self.patch.start();self.addCleanup(self.patch.stop)
        access=patch('mobile_devices_page.local_dashboard_session',return_value=local)
        access.start();self.addCleanup(access.stop)
        return app.run()

    def test_page_starts_server_and_shows_qr_controls_devices_and_disconnect(self):
        class Controller:
            pair_port=8444
            def __init__(self):self.started=False;self.calls=[]
            def status(self,host=None):
                if not self.started:return {'state':'stopped'}
                return {'state':'running','name':'PC','host':'192.168.1.20','addresses':['192.168.1.20','127.0.0.1'],
                        'api_port':8443,'fingerprint':'a'*64,'pairing':{'payload':'agmobile://pair?h=192.168.1.20','code':'ABCD-EFGH','remaining_seconds':250},
                        'devices':[{'id':'dev_fixture','name':'My phone','active_recently':True,'active_jobs':1,'last_seen':None,'created_at':'2026-10-14T10:00:00'}]}
            def start(self):self.started=True;self.calls.append('start')
            def new_code(self,host):self.calls.append(('new',host))
            def revoke(self,id):self.calls.append(('revoke',id))
        controller=Controller();app=self.app(controller)
        self.assertFalse(app.exception)
        app.button(key='mobile_start').click().run();self.assertFalse(app.exception)
        self.assertEqual(controller.calls,['start'])
        self.assertTrue(any('My phone' in item.value for item in app.text))
        app.button(key='mobile_new_code').click().run();self.assertFalse(app.exception)
        app.button(key='mobile_revoke_dev_fixture').click().run();self.assertFalse(app.exception)
        self.assertIn(('new','192.168.1.20'),controller.calls)
        self.assertIn(('revoke','dev_fixture'),controller.calls)

    def test_remote_dashboard_session_never_displays_or_calls_pc_controls(self):
        class Controller:
            def status(self,*args):raise AssertionError('A remote page must not query PC administration.')
        app=self.app(Controller(),local=False)
        self.assertFalse(app.exception)
        self.assertEqual(len(app.button),0)
        self.assertIn('localhost',app.info[0].value)

    def test_mobile_route_is_reachable_without_changing_existing_numeric_routes(self):
        from nav_routes import resolve_route,get_primary_slug
        self.assertEqual(resolve_route('9'),'⚙️ Settings')
        self.assertEqual(resolve_route('mobile'),'📱 Mobile Devices')
        self.assertEqual(resolve_route('الأجهزة'),'📱 Mobile Devices')
        self.assertEqual(get_primary_slug(resolve_route('10')),'mobile')

    def test_full_dashboard_routes_to_the_mobile_page_using_a_fixture_library(self):
        import os
        from unittest.mock import patch
        import test_gallery_ui
        class Controller:
            def status(self,*args):return {'state':'stopped'}
        previous=os.getcwd()
        try:
            with patch('mobile_devices_page.local_dashboard_session',return_value=True),patch(
                    'mobile_devices_page.mobile_controller',return_value=Controller()):
                app=test_gallery_ui.run_app(query={'page':'mobile'})
                self.assertFalse(app.exception)
                self.assertEqual(app.sidebar.radio[0].value,'📱 Mobile Devices')
                self.assertEqual(app.button(key='mobile_start').label,'Start mobile server')
        finally:
            os.chdir(previous)


class RealLocalServerTests(unittest.TestCase):
    def test_start_pair_disconnect_and_stop_against_real_local_http_and_pinned_https(self):
        def free_port():
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0));return listener.getsockname()[1]
        with tempfile.TemporaryDirectory(prefix='ag_dashboard_server_') as tmp:
            root=Path(tmp);api_port=free_port();pair_port=free_port()
            while pair_port==api_port:pair_port=free_port()
            controller=MobileDashboardController(APP_DIR,workspace=root/'workspace',api_port=api_port,pair_port=pair_port,
                                                 bind='127.0.0.1',mdns=False,log_dir=root/'logs')
            try:
                controller.start()
                process=controller._process
                controller.start();self.assertIs(controller._process,process)
                deadline=time.monotonic()+25
                while time.monotonic()<deadline:
                    state=controller.status()
                    if state['state'] in ('running','failed'):break
                    time.sleep(.1)
                self.assertEqual(state['state'],'running',controller.log_tail())
                other=MobileDashboardController(APP_DIR,workspace=root/'workspace',api_port=api_port,pair_port=pair_port)
                self.assertEqual(other.status()['server_id'],state['server_id'])
                # A second launch cannot wipe any cache while the first listener is alive.
                sentinel=root/'workspace'/'sentinel';sentinel.write_text('keep')
                from mobile_api.server import main
                self.assertEqual(main(['--bind','127.0.0.1','--port',str(api_port),'--pair-port',str(pair_port),
                                       '--workspace',str(root/'workspace'),'--no-browser','--no-mdns']),1)
                self.assertEqual(sentinel.read_text(),'keep')
                pairing=controller.new_code('127.0.0.1')['pairing']
                from mobile_api.tls import CERT_NAME
                import ssl
                ssl_context=ssl.create_default_context(cafile=str(root/'workspace'/'tls'/CERT_NAME))
                with httpx.Client(base_url=f'https://127.0.0.1:{api_port}',verify=ssl_context,trust_env=False) as phone:
                    response=phone.post('/v1/pair/complete',json={'code':pairing['code'],'device_name':'Fixture phone'})
                    self.assertEqual(response.status_code,200,response.text)
                    token=response.json()['token'];headers={'Authorization':'Bearer '+token}
                    self.assertEqual(phone.get('/v1/capabilities',headers=headers).status_code,200)
                    device=controller.status()['devices'][0]
                    controller.rename(device['id'],'Renamed phone')
                    self.assertEqual(controller.status()['devices'][0]['name'],'Renamed phone')
                    controller.revoke(device['id'])
                    self.assertEqual(phone.get('/v1/capabilities',headers=headers).status_code,401)
                controller.stop();controller.wait_stopped(timeout=10)
                self.assertFalse((root/'workspace'/'control.json').exists())
                self.assertEqual(controller.status()['state'],'stopped')
            finally:
                if controller._process and controller._process.poll() is None:
                    try:controller.stop();controller.wait_stopped(timeout=10)
                    except (ControlError,subprocess.TimeoutExpired,OSError):controller._process.kill();controller._process.wait()


if __name__=='__main__':unittest.main(verbosity=2)
