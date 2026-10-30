"""Isolated HTTPS server used by the actual Flutter Studio client acceptance test.

Fake compute is the default. --gpu uses installed local Reface models. Neither
mode reads a desktop library or starts the user's existing server/workspace.
Connection credentials are written only to the caller's temporary ready file.
"""
import argparse
import json
import os
import socket
import sys
import threading
from pathlib import Path

APP = Path(__file__).resolve().parents[2] / "the app"
sys.path.insert(0, str(APP))
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--ready", type=Path, required=True)
    parser.add_argument("--gpu", action="store_true")
    parser.add_argument("--transfer-mib", type=int, default=0,
                        help="Pad the disposable fixture result for transfer benchmarks (no GPU)")
    args = parser.parse_args()
    import cv2
    import uvicorn
    from mobile_api.app import create_app
    from mobile_api.testing import make_test_context
    from mobile_api.tls import ensure_cert

    options = {}
    if args.gpu:
        from mobile_api.engines import CapabilityProbe, InsightEngines
        options = dict(engines=InsightEngines(), probe=CapabilityProbe())
    ctx = make_test_context(args.root, max_upload_bytes=128*1024*1024,
                            blob_cache_bytes=256*1024*1024, **options)
    ctx.cert = ensure_cert(ctx.workspace.tls_dir, hosts=["127.0.0.1"])
    device = ctx.auth.add_device("Flutter stateless acceptance")
    if not args.gpu:
        # Fixture compute must stay independent of unrelated host RAM/GPU load.
        # Resource protection has its own tests; --gpu retains real admission.
        from types import SimpleNamespace
        from mobile_api.contract.resource_fixture import resource_fixture
        ctx.resources = SimpleNamespace(start=lambda: None, close=lambda: None,
            admission_reasons=lambda: [], snapshot=resource_fixture)
    app = create_app(ctx)
    if not args.gpu:
        def compute(job, directory, report, stopped):
            image = cv2.imread(str(directory / "input.target"))
            if image is None:
                raise ValueError("Unreadable fixture image")
            image = cv2.bitwise_not(image)
            if not cv2.imwrite(str(directory / "result.png"), image):
                raise ValueError("Could not write fixture output")
            if args.transfer_mib:
                with (directory / "result.png").open("ab") as output:
                    output.truncate(args.transfer_mib * 1024 * 1024)
            return dict(faces_swapped=1, settings=dict(swapper="fixture", restorer="none"))
        ctx.studio_jobs.runner = compute
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(128)
    listener.setblocking(False)
    port = listener.getsockname()[1]
    ready = dict(server_id=ctx.auth.server_id, host="127.0.0.1", port=port,
                 fingerprint=ctx.cert.fingerprint, token=device["token"],
                 workspace=str(ctx.workspace.root))
    temporary = args.ready.with_suffix(".tmp")
    temporary.write_text(json.dumps(ready), encoding="utf-8")
    os.replace(temporary, args.ready)
    server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port,
        ssl_certfile=str(ctx.cert.cert_path), ssl_keyfile=str(ctx.cert.key_path),
        access_log=False, log_level="error"))
    finished = threading.Event()
    def watch_shutdown():
        while not finished.wait(.1):
            if args.ready.with_suffix(".stop").exists():
                server.should_exit = True
                return
    watcher = threading.Thread(target=watch_shutdown, daemon=True)
    watcher.start()
    try:
        server.run(sockets=[listener])
    finally:
        finished.set()
        watcher.join(timeout=2)
        listener.close()


if __name__ == "__main__":
    main()
