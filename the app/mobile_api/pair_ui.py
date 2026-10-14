"""
The PC-side pairing page. A SEPARATE app on 127.0.0.1 (plain HTTP, `--pair-port`, default 8444):
the HTTPS API listener never serves it, and it additionally rejects non-loopback clients.
"""

import base64
import io
import re
from typing import Optional

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .discovery import lan_addresses
from .admin import build_admin_router, revoke_device
from .pairing import pair_payload, render_pair_page

_HOST_RE = re.compile(r"^[A-Za-z0-9.\-]{1,253}$")
LOOPBACK = {"127.0.0.1", "::1", "localhost", "testclient"}  # "testclient" = Starlette's TestClient


def qr_png_b64(text: str) -> str:
    import qrcode
    img = qrcode.make(text, box_size=8, border=1)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("ascii")


def create_pair_app(ctx, addresses_fn=lan_addresses) -> FastAPI:
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)

    @app.middleware("http")
    async def loopback_only(request: Request, call_next):
        client = request.client.host if request.client else ""
        if client not in LOOPBACK:
            return HTMLResponse("Not found", status_code=404)
        # DNS-rebinding / cross-site form posts from a web page open in the PC's browser
        host = (request.headers.get("host") or "").rsplit(":", 1)[0].strip("[]")
        origin = request.headers.get("origin")
        origin_host = "" if not origin else origin.split("//", 1)[-1].rsplit(":", 1)[0].strip("[]")
        if host not in LOOPBACK | {"testserver"} or (origin and origin_host not in LOOPBACK | {"testserver"}):
            return HTMLResponse("Forbidden", status_code=403)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        return response

    app.include_router(build_admin_router(ctx))

    def page(host: Optional[str], notice: str = "") -> HTMLResponse:
        addresses = list(dict.fromkeys([*(ctx.host_addresses or addresses_fn()),'127.0.0.1','10.0.2.2']))
        if ctx.bind_address in ('127.0.0.1','localhost','::1'): addresses = ['127.0.0.1','10.0.2.2']
        elif ctx.bind_address not in ('0.0.0.0','::'): addresses = [ctx.bind_address]
        chosen = host if host in addresses else (addresses[0] if addresses else "127.0.0.1")
        issued = ctx.pairing.current() or ctx.pairing.issue()
        fp = ctx.cert.fingerprint if ctx.cert else ""
        payload = pair_payload(chosen, ctx.api_port, fp, issued.code)
        html = render_pair_page(payload=payload, qr_png_b64=qr_png_b64(payload), code=issued, host=chosen,
                                port=ctx.api_port, fingerprint=fp, server_name=ctx.auth.server_name,
                                other_hosts=[a for a in addresses if a != chosen], devices=ctx.auth.devices(),
                                notice=notice)
        return HTMLResponse(html, headers={"Cache-Control": "no-store"})

    @app.get("/")
    async def root():
        return RedirectResponse("/pair")

    @app.get("/pair")
    async def pair_page(h: Optional[str] = None):
        return page(h)

    @app.post("/pair/new")
    async def new_code():
        ctx.pairing.issue()
        return RedirectResponse("/pair", status_code=303)

    @app.post("/pair/revoke/{device_id}")
    async def revoke(device_id: str):
        revoke_device(ctx,device_id)
        return RedirectResponse("/pair", status_code=303)

    return app
