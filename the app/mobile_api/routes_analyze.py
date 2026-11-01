"""POST /v1/analyze/image - faces, bodies and face<->body pairs for one picture."""

import json
import logging
from typing import Callable

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool


from .errors import ApiError, bad_request
from .schemas import analysis_to_response, parse_analyze_options, sensitive_region_json
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
        if opts.return_sensitive or opts.return_body_embeddings:
            _require_sensitive_model(ctx)
        if opts.return_body_embeddings:
            _require_embedding_model(ctx)
        ctx.gpu.require_free()

        try:
            data = await image.read(ctx.max_image_upload_bytes + 1)
        finally:
            await image.close()  # remove any multipart spool before GPU work starts
        if len(data) > ctx.max_image_upload_bytes:
            raise ApiError(413, "too_large", "The image is larger than the server accepts.")
        engine_options = opts.engine_options()
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

    @router.post("/v1/analyze/marks")
    async def analyze_marks(
        reference: UploadFile = File(...),
        candidates: list[UploadFile] = File(...),
        _: dict = Depends(require_device),
    ):
        """Roadmap 7.4 (Phase 6): OpenCV feature matching of a marked tattoo patch against candidate patches.
        No model, no GPU, nothing stored; the phone sends each candidate straight and on the opposite segment."""
        import mark_matching
        if not 1 <= len(candidates) <= mark_matching.MAX_CANDIDATES:
            raise bad_request(f"send between 1 and {mark_matching.MAX_CANDIDATES} candidate patches", code="bad_request")
        limit = min(ctx.max_image_upload_bytes, 4 * 1024 * 1024)

        async def read(upload: UploadFile) -> bytes:
            try:
                data = await upload.read(limit + 1)
            finally:
                await upload.close()
            if len(data) > limit:
                raise ApiError(413, "too_large", "A patch is larger than the server accepts.")
            return data

        raw_reference = await read(reference)
        raw_candidates = [await read(c) for c in candidates]

        def compute():
            ref = mark_matching.decode_patch(raw_reference)
            if ref is None:
                raise MediaDecodeError("The reference patch is not an image.")
            patches = [mark_matching.decode_patch(d) for d in raw_candidates]
            return mark_matching.match_patches(ref, patches)

        try:
            results = await run_in_threadpool(compute)
        except MediaDecodeError as error:
            raise bad_request(str(error), code="bad_image") from error
        except Exception:
            log.exception("analyze marks failed")
            raise ApiError(500, "internal", "Mark matching failed on the server.", retryable=True)
        return JSONResponse({"results": [dict(index=i, **r) for i, r in enumerate(results)]})

    @router.post("/v1/analyze/sensitive")
    async def analyze_sensitive(
        image: UploadFile = File(...),
        bodies: str = Form(default="[]"),
        embeddings: str = Form(default="false"),
        _: dict = Depends(require_device),
    ):
        """Roadmap section 8 backfill: the same regions as `return_sensitive`, for photos scanned before.
        With `embeddings=true` also the chest / lower-body embeddings and morphology per body (roadmap 7.5)."""
        want_embeddings = embeddings.strip().lower() == "true"
        if embeddings.strip().lower() not in ("true", "false"):
            raise bad_request("embeddings must be true or false", code="bad_request")
        _require_sensitive_model(ctx)
        if want_embeddings:
            _require_embedding_model(ctx)
        ctx.gpu.require_free()
        body_dicts = parse_sensitive_bodies(bodies)
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
                    return ctx.engines.compute_sensitive(img, body_dicts, want_embeddings) if want_embeddings else ctx.engines.compute_sensitive(img, body_dicts)

            result = await run_in_threadpool(compute)
            regions = result["regions"] if want_embeddings else result
        except ImageTooLarge as error:
            raise ApiError(413, "too_large", str(error)) from error
        except MediaDecodeError as error:
            raise bad_request(str(error), code="bad_image") from error
        except ApiError:
            raise
        except Exception:
            log.exception("analyze sensitive failed")
            raise ApiError(500, "internal", "Sensitive-region detection failed on the server.", retryable=True)
        import sensitive_detection
        payload = {"model_version": sensitive_detection.MODEL_VERSION,
                   "regions": [sensitive_region_json(r) for r in regions]}
        if want_embeddings:
            payload["bodies"] = [
                {"chest_embedding": b.get("chest_embedding"), "buttocks_embedding": b.get("buttocks_embedding"),
                 "morphology": b.get("morphology")} for b in result["bodies"]]
        return JSONResponse(payload)

    @router.post("/v1/analyze/garments")
    async def analyze_garments(
        image: UploadFile = File(...),
        bodies: str = Form(default="[]"),
        _: dict = Depends(require_device),
    ):
        """Roadmap Phase 7: raw WD14 garment scores for each given body. Nothing is stored; the phone keeps the
        tags for its own labelling and no tag is a filter yet."""
        _require_garment_model(ctx)
        ctx.gpu.require_free()
        body_dicts = parse_sensitive_bodies(bodies)
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
                    return ctx.engines.compute_garments(img, body_dicts)

            tags = await run_in_threadpool(compute)
        except ImageTooLarge as error:
            raise ApiError(413, "too_large", str(error)) from error
        except MediaDecodeError as error:
            raise bad_request(str(error), code="bad_image") from error
        except ApiError:
            raise
        except Exception:
            log.exception("analyze garments failed")
            raise ApiError(500, "internal", "Garment tagging failed on the server.", retryable=True)
        import garment_tags
        return JSONResponse({"model_version": garment_tags.GARMENT_VERSION,
                             "bodies": [{"tags": t} for t in tags]})

    return router


def _require_garment_model(ctx=None) -> None:
    ready = getattr(getattr(ctx, "engines", None), "garments_ready", None)   # the test fakes set it
    if ready is None:
        import garment_tags
        ready = garment_tags.model_available()
    if not ready:
        raise ApiError(409, "model_missing", "The garment tagger model is not installed on this PC.")


def _require_sensitive_model(ctx=None) -> None:
    ready = getattr(getattr(ctx, "engines", None), "sensitive_ready", None)   # the test fakes set it
    if ready is None:
        import sensitive_detection
        ready = sensitive_detection.model_available(sensitive_detection.env_model_path())
    if not ready:
        raise ApiError(409, "model_missing", "The sensitive-region model is not installed on this PC.")


def _require_embedding_model(ctx=None) -> None:
    ready = getattr(getattr(ctx, "engines", None), "embeddings_ready", None)   # the test fakes set it
    if ready is None:
        import body_embeddings
        ready = body_embeddings.model_available()
    if not ready:
        raise ApiError(409, "model_missing", "The body-embedding model is not installed on this PC.")


MAX_SENSITIVE_BODIES = 64


def parse_sensitive_bodies(raw: str) -> list:
    """`bodies` form field: [{bbox: {x, y, w, h} pixels, kpts: [[x, y, score] x17] | null}] -> engine dicts."""
    try:
        items = json.loads(raw or "[]")
    except ValueError as error:
        raise bad_request("bodies must be valid JSON", code="bad_request") from error
    if not isinstance(items, list) or len(items) > MAX_SENSITIVE_BODIES:
        raise bad_request(f"bodies must be a list of at most {MAX_SENSITIVE_BODIES} bodies", code="bad_request")
    out = []
    for i, item in enumerate(items):
        box = item.get("bbox") if isinstance(item, dict) else None
        if not isinstance(box, dict) or not all(isinstance(box.get(k), (int, float)) and not isinstance(box.get(k), bool)
                                                for k in ("x", "y", "w", "h")):
            raise bad_request(f"bodies[{i}].bbox must have numeric x, y, w, h", code="bad_request")
        kpts = item.get("kpts")
        points = scores = None
        if kpts is not None:
            if (not isinstance(kpts, list) or len(kpts) != 17
                    or any(not isinstance(k, list) or len(k) != 3 for k in kpts)):
                raise bad_request(f"bodies[{i}].kpts must be 17 [x, y, score] triples or null", code="bad_request")
            try:
                points = [[float(k[0]), float(k[1])] for k in kpts]
                scores = [float(k[2]) for k in kpts]
            except (TypeError, ValueError) as error:
                raise bad_request(f"bodies[{i}].kpts must be numeric", code="bad_request") from error
        out.append({"bbox": [float(box["x"]), float(box["y"]),
                             float(box["x"]) + float(box["w"]), float(box["y"]) + float(box["h"])],
                    "kpts": points, "kpt_scores": scores})
    return out
