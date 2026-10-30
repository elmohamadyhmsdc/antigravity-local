"""POST /v1/analyze/image - faces, bodies and face<->body pairs for one picture."""

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
                                        detect_bodies=opts.detect_bodies, body_score=opts.body_score)
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

    return router
