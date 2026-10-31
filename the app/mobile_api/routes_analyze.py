"""POST /v1/analyze/image - faces, bodies and face<->body pairs for one picture."""

import json
import logging
from typing import Callable

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from analysis import AnalyzeOptions

from .errors import ApiError, bad_request
from .schemas import analysis_to_response, parse_analyze_options
from .media_decode import ImageTooLarge, MediaDecodeError

log = logging.getLogger("mobile_api")


def build_analyze_router(ctx, require_device: Callable) -> APIRouter:
    router = APIRouter()

    @router.post("/v1/analyze/image")
    async def analyze_image(image: UploadFile = File(...), options: str = Form(default=""),
                            _: dict = Depends(require_device)):
        opts = parse_analyze_options(options)
        if not opts.detect_characters and opts.model_id is not None and opts.model_id != ctx.engines.model_id:
            raise ApiError(409, "model_mismatch",
                           f"This server embeds with {ctx.engines.model_id}, not {opts.model_id}.")
        ctx.gpu.require_free()

        try:
            data = await image.read(ctx.max_image_upload_bytes + 1)
        finally:
            await image.close()  # remove any multipart spool before GPU work starts
        if len(data) > ctx.max_image_upload_bytes:
            raise ApiError(413, "too_large", "The image is larger than the server accepts.")
        engine_options = AnalyzeOptions(min_face_quality=opts.min_face_quality,
                                        detect_characters=opts.detect_characters,
                                        detect_bodies=opts.detect_bodies, body_score=opts.body_score,
                                        outlines=opts.return_outlines)
        try:
            def compute():
                with ctx.compute_lock:
                    ctx.gpu.require_free()
                    # Decode under the same admission lock as inference: concurrent
                    # uploads must not allocate several full-resolution images at once.
                    img = ctx.image_decoder.image(data, ctx.max_image_px)
                    return img, ctx.engines.analyze(img, engine_options)
            img, result = await run_in_threadpool(compute)
        except ImageTooLarge as error:
            raise ApiError(413, 'too_large', str(error)) from error
        except MediaDecodeError as error:
            raise bad_request(str(error), code='bad_image') from error
        except ApiError:
            raise
        except Exception:  # noqa: BLE001
            log.exception("analyze failed")
            raise ApiError(500, "internal", "Image analysis failed on the server.", retryable=True)
        body = await run_in_threadpool(analysis_to_response, result, img, opts, ctx.engines.model_id)
        return JSONResponse(body)

    @router.post("/v1/analyze/outlines")
    async def analyze_outlines(
        image: UploadFile = File(...),
        targets: str = Form(...),
        _: dict = Depends(require_device),
    ):
        ctx.gpu.require_free()

        try:
            raw_targets = json.loads(targets)
        except Exception as error:
            raise bad_request("targets must be a valid JSON list", code="bad_request") from error

        if not isinstance(raw_targets, list):
            raise bad_request("targets must be a list", code="bad_request")
        if len(raw_targets) > 32:
            raise bad_request("At most 32 targets allowed", code="bad_request")

        for i, t in enumerate(raw_targets):
            if not isinstance(t, dict) or "kind" not in t or t["kind"] not in ("f", "b") or "bbox" not in t:
                raise bad_request(f"target {i} is invalid: must have kind ('f'|'b') and bbox", code="bad_request")
            bbox = t["bbox"]
            if not isinstance(bbox, dict) or not all(k in bbox for k in ("x", "y", "w", "h")):
                raise bad_request(f"target {i} bbox must have x, y, w, h", code="bad_request")

        try:
            data = await image.read(ctx.max_image_upload_bytes + 1)
        finally:
            await image.close()

        if len(data) > ctx.max_image_upload_bytes:
            raise ApiError(413, "too_large", "The image is larger than the server accepts.")

        try:
            def compute():
                with ctx.compute_lock:
                    ctx.gpu.require_free()
                    img = ctx.image_decoder.image(data, ctx.max_image_px)
                    return ctx.engines.compute_outlines(img, raw_targets)

            outlines = await run_in_threadpool(compute)
        except ImageTooLarge as error:
            raise ApiError(413, "too_large", str(error)) from error
        except MediaDecodeError as error:
            raise bad_request(str(error), code="bad_image") from error
        except ApiError:
            raise
        except Exception:
            log.exception("analyze outlines failed")
            raise ApiError(500, "internal", "Outline computation failed on the server.", retryable=True)

        return JSONResponse({"outlines": outlines})

    return router
