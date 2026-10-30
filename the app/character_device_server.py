"""Opt-in loopback-only server for the separately packaged Android QA app."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--port', type=int, default=8447)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    import cv2
    import numpy as np
    import uvicorn
    from fastapi import Header, Depends
    from fastapi.responses import Response
    from mobile_api.app import create_app
    from mobile_api.auth import authenticate_header
    from mobile_api.engines import InsightEngines, CapabilityProbe
    from mobile_api.testing import make_test_context
    from mobile_api.tls import ensure_cert
    files = sorted({p.resolve() for folder in args.source for p in folder.rglob('*')
                    if p.is_file() and p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'}})
    ctx = make_test_context(args.output / 'server', engines=InsightEngines(), probe=CapabilityProbe())
    cert = ensure_cert(ctx.workspace.tls_dir)
    device = ctx.auth.add_device('Isolated Android QA')
    (args.output / 'config.json').write_text(json.dumps(dict(port=args.port, fingerprint=cert.fingerprint,
                                                          token=device['token'])), encoding='utf-8')
    app = create_app(ctx)
    async def auth(authorization: str = Header(default='')):
        return authenticate_header(ctx.auth, authorization)
    @app.get('/qa/corpus', dependencies=[Depends(auth)])
    def corpus():
        return [dict(id=i) for i in range(len(files))]
    @app.get('/qa/image/{index}', dependencies=[Depends(auth)])
    def image(index: int):
        assert 0 <= index < len(files)
        image = cv2.imdecode(np.fromfile(str(files[index]), np.uint8), cv2.IMREAD_COLOR)
        assert image is not None
        scale = min(1, 2560 / max(image.shape[:2]))
        if scale < 1:
            image = cv2.resize(image, (round(image.shape[1]*scale), round(image.shape[0]*scale)), interpolation=cv2.INTER_AREA)
        return Response(cv2.imencode('.jpg', image, [cv2.IMWRITE_JPEG_QUALITY, 95])[1].tobytes(), media_type='image/jpeg')
    @app.post('/qa/progress', dependencies=[Depends(auth)])
    def progress(data: dict):
        (args.output / 'phone-progress.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
        return {'ok': True}
    @app.post('/qa/report', dependencies=[Depends(auth)])
    def report(data: dict):
        (args.output / 'phone-report.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
        return {'ok': True}
    print(f'Isolated QA ready: {len(files)} images; localhost port {args.port}', flush=True)
    uvicorn.run(app, host='127.0.0.1', port=args.port, ssl_certfile=str(cert.cert_path),
                ssl_keyfile=str(cert.key_path), access_log=False, log_level='warning')


if __name__ == '__main__':
    main()
