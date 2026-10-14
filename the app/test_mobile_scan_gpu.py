"""Offline scan acceptance with real local face/body models and an isolated workspace.

Run with the existing venv: python -X faulthandler test_mobile_scan_gpu.py --source photo.jpg
No downloads, desktop database writes, or dependency changes.
"""
import argparse
import faulthandler
import json
import os
import sys
import tempfile
import socket
import ssl
import time
from contextlib import contextmanager
from pathlib import Path

faulthandler.enable(all_threads=True)
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--live', action='store_true', help='Use a real isolated HTTPS server with pinned local TLS.')
    args = parser.parse_args()
    # Fail before engine construction if any weight could trigger an auto-fetch.
    import body_detector
    for spec in body_detector.MODEL_SPECS.values():
        path = body_detector.MODELS_DIR/spec['file']
        assert path.is_file() and path.stat().st_size == spec['onnx_size'], 'Missing local body weight'
    face_dir = Path.home()/'.insightface/models/buffalo_l'
    assert all((face_dir/name).is_file() for name in ('det_10g.onnx', 'w600k_r50.onnx', '1k3d68.onnx'))
    def no_download(*args, **kwargs):
        raise AssertionError('Downloads are disabled for this test')
    body_detector._download = no_download

    import cv2
    from fastapi.testclient import TestClient
    from mobile_api.app import create_app
    from mobile_api.engines import InsightEngines, CapabilityProbe
    from mobile_api.testing import make_test_context
    image = cv2.imread(str(args.source))
    assert image is not None, 'Unreadable source'
    engines = InsightEngines()
    @contextmanager
    def connection(root):
        if not args.live:
            ctx = make_test_context(root, engines=engines, probe=CapabilityProbe())
            with TestClient(create_app(ctx)) as client:
                yield client, {'Authorization': 'Bearer '+ctx.auth.add_device('Scan acceptance')['token']}
            return
        import httpx
        from mobile_dashboard_controller import MobileDashboardController
        from mobile_api import APP_DIR
        from mobile_api.tls import CERT_NAME
        def port():
            with socket.socket() as listener:
                listener.bind(('127.0.0.1',0))
                return listener.getsockname()[1]
        api_port, pair_port = port(), port()
        while pair_port == api_port: pair_port = port()
        controller = MobileDashboardController(APP_DIR, workspace=root/'workspace', log_dir=root/'logs',
            api_port=api_port, pair_port=pair_port, bind='127.0.0.1', mdns=False)
        try:
            controller.start()
            deadline = time.monotonic()+30
            while time.monotonic() < deadline:
                state = controller.status()
                if state['state'] == 'running': break
                assert state['state'] != 'failed', controller.log_tail()
                time.sleep(.1)
            assert state['state'] == 'running', controller.log_tail()
            context = ssl.create_default_context(cafile=str(root/'workspace/tls'/CERT_NAME))
            with httpx.Client(base_url=f'https://127.0.0.1:{api_port}', verify=context, trust_env=False, timeout=180) as client:
                code = controller.new_code('127.0.0.1')['pairing']['code']
                response = client.post('/v1/pair/complete', json={'code':code, 'device_name':'Scan acceptance'})
                assert response.status_code == 200, response.text
                headers = {'Authorization':'Bearer '+response.json()['token']}
                assert client.get('/v1/capabilities', headers=headers).status_code == 200
                yield client, headers
                assert controller.status()['state'] == 'running'
        finally:
            if controller._process and controller._process.poll() is None:
                controller.stop()
                controller.wait_stopped()
    with tempfile.TemporaryDirectory(prefix='ag_scan_acceptance_') as tmp:
        with connection(Path(tmp)) as (client, headers):
            for size in (512, 1600, 2560):
                frame = cv2.resize(image, (size, max(1, round(image.shape[0]*size/image.shape[1]))))
                payload = cv2.imencode('.jpg', frame)[1].tobytes()
                print(f'SCAN {size}px faces + bodies + pose', flush=True)
                response = client.post('/v1/analyze/image', headers=headers,
                    files={'image': ('fixture.jpg', payload, 'image/jpeg')},
                    data={'options': json.dumps({'detect_bodies': True, 'min_quality': .4})})
                assert response.status_code == 200, response.text[:1000]
                data = response.json()
                assert client.get('/v1/health').status_code == 200
                print(f"PASS {size}px: {len(data['faces'])} faces, {len(data['bodies'])} bodies", flush=True)
            if not args.live: assert engines._scan_worker.loaded
            print('PASS: real scan, all local models; server responsive after every request.', flush=True)
    print('Loaded Streamlit:', 'streamlit' in sys.modules, flush=True)


if __name__ == '__main__':
    main()
