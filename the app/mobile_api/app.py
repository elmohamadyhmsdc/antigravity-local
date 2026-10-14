"""
The FastAPI application (HTTPS, port 8443 by default).

`create_app(ctx)` is a pure factory over a ServerContext, so tests build it with fake engines
and a temporary workspace and drive it with FastAPI's TestClient - no GPU, no network.
"""

import logging
import traceback
from dataclasses import dataclass, field
from typing import List, Optional

from fastapi import Depends, FastAPI, Header, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from . import API_VERSION
from .auth import AuthStore, authenticate_header
from .errors import ApiError, code_for_status
from .gpu_guard import GpuGuard
from .pairing import PairingManager
from .routes_analyze import build_analyze_router
from .routes_blobs import build_blob_router
from .routes_grouping import build_grouping_router
from .routes_system import build_system_router
from .tls import CertInfo
from .workspace import Workspace

log = logging.getLogger("mobile_api")

MAX_IMAGE_PX = 4096          # long side accepted by /v1/analyze/image
MAX_IMAGE_UPLOAD_BYTES = 64 * 1024 * 1024
MAX_PLAN_WIRE_BYTES = 128 * 1024 * 1024      # /v1/grouping/plan body as sent (gzip)
MAX_PLAN_JSON_BYTES = 512 * 1024 * 1024      # ...and inflated


@dataclass
class ServerContext:
    workspace: Workspace
    auth: AuthStore
    pairing: PairingManager
    gpu: GpuGuard
    engines: object                       # .model_id, .analyze(img, options) -> analysis.FrameAnalysis
    probe: object                         # .snapshot() -> {gpu, engines, restorers, lora_base_checkpoints}
    cert: Optional[CertInfo] = None
    host_addresses: List[str] = field(default_factory=list)
    api_port: int = 8443
    pair_port: int = 8444
    max_image_px: int = MAX_IMAGE_PX
    max_image_upload_bytes: int = MAX_IMAGE_UPLOAD_BYTES
    max_plan_wire_bytes: int = MAX_PLAN_WIRE_BYTES
    max_plan_json_bytes: int = MAX_PLAN_JSON_BYTES
    api_version: str = API_VERSION


def create_app(ctx: ServerContext) -> FastAPI:
    app = FastAPI(title="Antigravity Mobile API", version=ctx.api_version,
                  docs_url=None, redoc_url=None, openapi_url=None)  # the contract is contract/openapi.yaml

    async def require_device(authorization: Optional[str] = Header(default=None)) -> dict:
        return authenticate_header(ctx.auth, authorization)

    app.include_router(build_system_router(ctx, require_device))
    app.include_router(build_blob_router(ctx, require_device))
    app.include_router(build_analyze_router(ctx, require_device))
    app.include_router(build_grouping_router(ctx, require_device))

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError):
        return JSONResponse(exc.body(), status_code=exc.status, headers=exc.headers)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException):
        code, retryable = code_for_status(exc.status_code)
        return JSONResponse({"error": {"code": code, "message": str(exc.detail), "retryable": retryable}},
                            status_code=exc.status_code, headers=getattr(exc, "headers", None))

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError):
        first = exc.errors()[0] if exc.errors() else {}
        where = ".".join(str(p) for p in first.get("loc", ()) if p != "body")
        message = f"{where}: {first.get('msg', 'invalid request')}" if where else first.get("msg", "invalid request")
        return JSONResponse({"error": {"code": "bad_request", "message": message, "retryable": False}}, status_code=400)

    @app.exception_handler(Exception)
    async def _unexpected(_: Request, exc: Exception):
        log.error("unhandled error: %s", traceback.format_exc())
        return JSONResponse({"error": {"code": "internal", "message": "The server hit an unexpected error.",
                                       "retryable": False}}, status_code=500)

    return app
