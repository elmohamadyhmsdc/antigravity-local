"""
Starts the mobile API: HTTPS API on 0.0.0.0:<port> + the localhost-only pairing page.

    venv\\Scripts\\python -m mobile_api [--port 8443] [--pair-port 8444] [--name "My PC"]
                                       [--host-ip 192.168.1.20] [--no-mdns] [--no-browser] [--preload]

Windows Firewall: the first run makes Windows ask whether python.exe may accept connections;
phones on the LAN need "Private networks" allowed. This program never changes firewall rules.
"""

import argparse
import json
import logging
import os
import socket
import threading
import webbrowser
from contextlib import ExitStack
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
from .admin import CONTROL_FILE, PROTOCOL
from .lan_discovery import LanResponder, NetworkMonitor, DISCOVERY_PORT

DEFAULT_WORKSPACE = APP_DIR / "mobile_workspace"
DEFAULT_PORT = 8443
DEFAULT_PAIR_PORT = 8444


def reserve_listener(host, port):
    """Reserve both ports before preparing/wiping scratch space."""
    family = socket.AF_INET6 if ':' in host else socket.AF_INET
    listener = socket.socket(family,socket.SOCK_STREAM)
    try:
        if os.name == 'nt': listener.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        listener.bind((host,port))
        listener.listen(128)
        listener.setblocking(False)
        return listener
    except BaseException:
        listener.close()
        raise


def write_control(ctx):
    path = ctx.workspace.root/CONTROL_FILE
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps({'protocol':PROTOCOL,'admin_token':ctx.admin_token,
        'pair_port':ctx.pair_port,'api_port':ctx.api_port,'server_id':ctx.auth.server_id,'pid':os.getpid()}),encoding='utf-8')
    os.replace(temporary,path)


def remove_control(ctx):
    path = ctx.workspace.root/CONTROL_FILE
    try:
        if json.loads(path.read_text(encoding='utf-8')).get('admin_token') == ctx.admin_token:
            path.unlink()
    except (OSError,ValueError):
        pass


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
    ap.add_argument("--no-discovery", action="store_true", help="disable LAN UDP discovery")
    ap.add_argument("--discovery-port", type=int, default=DISCOVERY_PORT)
    ap.add_argument("--no-browser", action="store_true", help="do not open the pairing page")
    ap.add_argument("--preload", action="store_true", help="load the face models now instead of on the first request")
    ap.add_argument("--check-models", action="store_true", help="report local engine/model readiness and exit without downloading")
    args = ap.parse_args(argv)

    if args.check_models:
        from .model_readiness import restyle_missing_models
        print(json.dumps({'engines': CapabilityProbe().engines(),
                          'restyle_missing_models': restyle_missing_models(APP_DIR)},indent=2))
        return 0

    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    with ExitStack() as listeners:
        try:
            api_socket = listeners.enter_context(reserve_listener(args.bind,args.port))
            pair_socket = listeners.enter_context(reserve_listener('127.0.0.1',args.pair_port))
        except OSError as error:
            print(f'Cannot start Mobile API: {error}. Another server may already be using these ports.')
            return 1
        return serve(args,api_socket,pair_socket)


def serve(args,api_socket,pair_socket):
    import uvicorn
    ctx = build_context(args.workspace, name=args.name, host_ip=args.host_ip, port=args.port,
                        pair_port=args.pair_port)
    ctx.bind_address = args.bind
    ctx.discovery_port = args.discovery_port
    issued = ctx.pairing.issue()
    pair_url = f"http://127.0.0.1:{args.pair_port}/pair"

    print("=" * 64)
    print(f" Your Gallery Mobile API {API_VERSION} - {ctx.auth.server_name} ({ctx.auth.server_id})")
    print(f" API            https://{(ctx.host_addresses or ['127.0.0.1'])[0]}:{args.port}")
    print(f" Pairing page   {pair_url}   (only reachable from this PC)")
    print(f" Pairing code   {issued.code}   (valid {issued.ttl // 60} min, single use)")
    print(f" Cert SHA-256   {ctx.cert.fingerprint}")
    print(f" Workspace      {ctx.workspace.root}")
    print("=" * 64)

    if args.preload:
        ctx.engines.load()

    api_app = create_app(ctx)
    api_server = uvicorn.Server(uvicorn.Config(api_app,host=args.bind,port=args.port,
                    ssl_certfile=str(ctx.cert.cert_path),ssl_keyfile=str(ctx.cert.key_path),
                    timeout_keep_alive=75,log_level='info'))
    ctx.shutdown = lambda: setattr(api_server,'should_exit',True)
    pair_server = uvicorn.Server(uvicorn.Config(create_pair_app(ctx), host="127.0.0.1", port=args.pair_port,
                                                log_level="info", access_log=False))
    pair_thread = threading.Thread(target=lambda: pair_server.run(sockets=[pair_socket]),name='pair-ui',daemon=True)
    pair_thread.start()
    write_control(ctx)

    discovery = Discovery()
    monitor = NetworkMonitor(ctx,discovery,addresses=lan_addresses,mdns=not args.no_mdns,fixed_host=args.host_ip)
    monitor.start()
    responder = LanResponder(ctx,bind=args.bind,port=args.discovery_port)
    if not args.no_discovery: ctx.lan_discovery_ready = responder.start()
    if not args.no_browser:
        threading.Timer(1.5, lambda: webbrowser.open(pair_url)).start()

    try:
        api_server.run(sockets=[api_socket])
    finally:
        pair_server.should_exit = True
        responder.stop()
        monitor.stop()
        discovery.stop()
        pair_thread.join(timeout=5)
        remove_control(ctx)
    return 0
