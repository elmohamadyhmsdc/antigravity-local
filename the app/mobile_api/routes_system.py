"""GET /v1/health, GET /v1/capabilities, POST /v1/pair/complete."""

from typing import Callable

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from . import EMBEDDING_DIM, EMBEDDING_MODEL_ID
from .errors import ApiError
from .pairing import PairingError

_PAIR_STATUS = {"invalid": 401, "none": 401, "expired": 401, "locked": 429}


class PairRequest(BaseModel):
    code: str = Field(min_length=1, max_length=64)
    device_name: str = Field(min_length=1, max_length=128)


def build_system_router(ctx, require_device: Callable) -> APIRouter:
    router = APIRouter()

    @router.get("/v1/health")
    async def health():
        return {"status": "ok", "server_id": ctx.auth.server_id, "name": ctx.auth.server_name,
                "api_version": ctx.api_version}

    @router.get("/v1/capabilities")
    async def capabilities(_: dict = Depends(require_device)):
        snap = ctx.probe.snapshot()
        busy = ctx.gpu.busy()
        return {
            "api_version": ctx.api_version,
            "server_id": ctx.auth.server_id,
            "name": ctx.auth.server_name,
            "embedding_model": {"id": EMBEDDING_MODEL_ID, "dim": EMBEDDING_DIM},
            "gpu": snap["gpu"],
            "engines": snap["engines"],
            "restorers": snap["restorers"],
            "lora_base_checkpoints": snap["lora_base_checkpoints"],
            "limits": {"max_image_px": ctx.max_image_px,
                       "max_upload_mb": ctx.workspace.max_upload_bytes // (1024 * 1024),
                       "blob_cache_mb": ctx.workspace.blob_cache_bytes // (1024 * 1024)},
            "busy": None if busy is None else busy.as_dict(),
        }

    @router.post("/v1/pair/complete")
    async def pair_complete(body: PairRequest):
        try:
            device, server_id = ctx.pairing.complete(body.code, body.device_name)
        except PairingError as e:
            code = "pairing_locked" if e.kind == "locked" else "invalid_code"
            raise ApiError(_PAIR_STATUS[e.kind], code, e.message, retryable=False)
        return {"token": device["token"], "server_id": server_id, "server_name": ctx.auth.server_name}

    return router
