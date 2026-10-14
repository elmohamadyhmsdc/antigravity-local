"""
Starts the mobile API: HTTPS API on 0.0.0.0:<port> + the localhost-only pairing page.

    venv\\Scripts\\python -m mobile_api [--port 8443] [--pair-port 8444] [--name "My PC"]
                                       [--host-ip 192.168.1.20] [--no-mdns] [--no-browser] [--preload]

Windows Firewall: the first run makes Windows ask whether python.exe may accept connections;
phones on the LAN need "Private networks" allowed. This program never changes firewall rules.
"""

import argparse
import logging
import threading
import webbrowser
from pathlib import Path

from . import API_VERSION, APP_DIR
from .app import ServerContext, create_app
from .auth import AuthStore
from .discovery import Discovery, lan_addresses
from .engines import CapabilityProbe, InsightEngines
from .gpu_guard import GpuGuard
from .pair_ui import create_pair_app
from .pairing import PairingManager
from .tls import ensure_cert
from .workspace import Workspace

DEFAULT_WORKSPACE = APP_DIR / "mobile_workspace"
DEFAULT_PORT = 8443
DEFAULT_PAIR_PORT = 8444


def build_context(workspace_dir=DEFAULT_WORKSPACE, *, name=None, host_ip=None, port=DEFAULT_PORT,
                  pair_port=DEFAULT_PAIR_PORT, wipe=True, engines=None, probe=None) -> ServerContext:
    ws = Workspace(workspace_dir)
    ws.prepare(wipe=wipe)
    auth = AuthStore(ws.devices_path, server_name=name)
    addresses = [host_ip] if host_ip else lan_addresses()
    cert = ensure_cert(ws.tls_dir, hosts=addresses, common_name=auth.server_name)
    return ServerContext(
        workspace=ws, auth=auth, pairing=PairingManager(auth),
        gpu=GpuGuard(APP_DIR / "jobs", ws.jobs_dir),
        engines=engines or InsightEngines(), probe=probe or CapabilityProbe(),
        cert=cert, host_addresses=addresses, api_port=port, pair_port=pair_port)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="mobile_api", description=__doc__.split("\n\n")[0])
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--pair-port", type=int, default=DEFAULT_PAIR_PORT)
    ap.add_argument("--bind", default="0.0.0.0", help="address the HTTPS API listens on")
    ap.add_argument("--name", help="server name shown on the phone (default: this PC's name)")
    ap.add_argument("--host-ip", help="address to put in the QR code (default: auto-detected)")
    ap.add_argument("--workspace", default=str(DEFAULT_WORKSPACE))
    ap.add_argument("--no-mdns", action="store_true")
    ap.add_argument("--no-browser", action="store_true", help="do not open the pairing page")
    ap.add_argument("--preload", action="store_true", help="load the face models now instead of on the first request")
    args = ap.parse_args(argv)

    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    ctx = build_context(args.workspace, name=args.name, host_ip=args.host_ip, port=args.port,
                        pair_port=args.pair_port)
    issued = ctx.pairing.issue()
    pair_url = f"http://127.0.0.1:{args.pair_port}/pair"

    print("=" * 64)
    print(f" Antigravity Mobile API {API_VERSION} - {ctx.auth.server_name} ({ctx.auth.server_id})")
    print(f" API            https://{(ctx.host_addresses or ['127.0.0.1'])[0]}:{args.port}")
    print(f" Pairing page   {pair_url}   (only reachable from this PC)")
    print(f" Pairing code   {issued.code}   (valid {issued.ttl // 60} min, single use)")
    print(f" Cert SHA-256   {ctx.cert.fingerprint}")
    print(f" Workspace      {ctx.workspace.root}")
    print("=" * 64)

    if args.preload:
        ctx.engines.load()

    pair_server = uvicorn.Server(uvicorn.Config(create_pair_app(ctx), host="127.0.0.1", port=args.pair_port,
                                                log_level="warning"))
    threading.Thread(target=pair_server.run, name="pair-ui", daemon=True).start()

    discovery = Discovery()
    if not args.no_mdns:
        discovery.start(name=ctx.auth.server_name, server_id=ctx.auth.server_id, api_version=API_VERSION,
                        port=args.port, addresses=ctx.host_addresses)
    if not args.no_browser:
        threading.Timer(1.5, lambda: webbrowser.open(pair_url)).start()

    try:
        uvicorn.run(create_app(ctx), host=args.bind, port=args.port,
                    ssl_certfile=str(ctx.cert.cert_path), ssl_keyfile=str(ctx.cert.key_path),
                    # uvicorn's default (5 s) drops idle keep-alive connections that the phone's HTTP client
                    # still pools; its next request then fails ("Connection closed before full header")
                    timeout_keep_alive=75,
                    log_level="info")
    finally:
        pair_server.should_exit = True
        discovery.stop()
    return 0
