"""
POST /v1/grouping/plan - the pure grouping function (grouping_core.plan_request).

Nothing is stored and the GPU is not involved (it is NumPy / scikit-learn on the CPU), so unlike
/v1/analyze/image this never answers gpu_busy. The phone sends embeddings for everything the
decision needs; a first scan can be several MB of base64, so the request body may be
`Content-Encoding: gzip` (the server never trusts its size: both the compressed and the inflated
size are capped) and the answer is gzipped when the client accepts it.
"""

import asyncio
import gzip
import json
import logging
import zlib
from typing import Callable

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse, Response
from starlette.concurrency import run_in_threadpool
from starlette.requests import ClientDisconnect

import grouping_core

from .errors import ApiError, bad_request

log = logging.getLogger("mobile_api")

GZIP_RESPONSE_MIN_BYTES = 1024


async def read_limited_body(request: Request, max_wire_bytes: int, max_json_bytes: int) -> bytearray:
    """The request body, inflated if it is gzip, never holding more than the limits allow."""
    declared = request.headers.get("content-length")
    if declared is not None and declared.isdigit() and int(declared) > max_wire_bytes:
        raise ApiError(413, "too_large", "The grouping request is larger than the server accepts.")
    encoding = request.headers.get("content-encoding", "identity").strip().lower()
    if encoding not in ("", "identity", "gzip"):
        raise bad_request(f"Content-Encoding {encoding!r} is not supported (use gzip or none).")
    inflater = zlib.decompressobj(wbits=31) if encoding == "gzip" else None
    wire_size = 0
    data = bytearray()
    try:
        async for chunk in request.stream():
            wire_size += len(chunk)
            if wire_size > max_wire_bytes:
                raise ApiError(413, "too_large", "The grouping request is larger than the server accepts.")
            remaining = max_json_bytes - len(data)
            decoded = chunk if inflater is None else inflater.decompress(chunk, remaining + 1)
            if len(decoded) > remaining:
                raise ApiError(413, "too_large", "The grouping request is larger than the server accepts.")
            data.extend(decoded)
    except zlib.error:
        raise bad_request("The request body is not valid gzip.")
    if inflater is not None and (not inflater.eof or inflater.unused_data):
        raise bad_request("The request body is not valid gzip.")
    return data


def build_grouping_router(ctx, require_device: Callable) -> APIRouter:
    router = APIRouter()
    one_plan_at_a_time = asyncio.Lock()  # a 100k-face clustering is memory hungry; queue the rest

    @router.post("/v1/grouping/plan")
    async def grouping_plan(request: Request, _: dict = Depends(require_device)):
        try:
            raw = await read_limited_body(request, ctx.max_plan_wire_bytes, ctx.max_plan_json_bytes)
        except ClientDisconnect:
            log.info("Phone disconnected during grouping upload.")
            return Response(status_code=499)

        def compute():
            try:
                req = json.loads(raw)
            except ValueError:
                raise bad_request("The request body is not valid JSON.")
            finally:
                raw.clear()
            return grouping_core.plan_request(req)

        try:
            async with one_plan_at_a_time:
                response = await run_in_threadpool(compute)
        except grouping_core.GroupingRequestError as e:
            raise bad_request(str(e))
        except ApiError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("grouping plan failed")
            raise ApiError(500, "internal", "Grouping failed on the server.", retryable=True)

        body = json.dumps(response, separators=(",", ":")).encode("utf-8")
        accepts = request.headers.get("accept-encoding", "")
        if "gzip" in accepts.lower() and len(body) >= GZIP_RESPONSE_MIN_BYTES:
            return Response(gzip.compress(body, 5), media_type="application/json",
                            headers={"Content-Encoding": "gzip", "Vary": "Accept-Encoding"})
        return JSONResponse(response)

    return router
