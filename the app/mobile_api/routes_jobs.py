"""Shared lifecycle for video analysis and Studio; SSE with a polling fallback."""

import asyncio
import json
from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse

from .errors import ApiError, bad_request, not_found


def build_jobs_router(ctx, require_device):
    router = APIRouter()
    def manager(job_id):
        return ctx.studio_jobs if job_id.startswith("studio_") else ctx.video_jobs

    @router.post("/v1/jobs", status_code=201)
    async def create(request: Request, device=Depends(require_device)):
        data = bytearray()
        async for chunk in request.stream():
            data.extend(chunk)
            if len(data) > 512 * 1024:
                raise ApiError(413, "too_large", "The job request is too large.")
        try:
            body = json.loads(data)
        except ValueError:
            raise bad_request("The job request must be JSON.")
        if not isinstance(body, dict):
            raise bad_request("The job request must be an object.")
        jobs = ctx.video_jobs if body.get("type") == "analyze_video" else ctx.studio_jobs
        with ctx.jobs_lock:
            if not ctx.auth.has_device(device['id']):
                raise ApiError(401,'unauthorized','This device has been disconnected.')
            result = jobs.create(body, device)
        return JSONResponse(result, status_code=201)

    @router.get("/v1/jobs")
    def listing(ids: str = "", device=Depends(require_device)):
        if ids:
            selected = ids.split(",")[:32]
            return {"jobs": [manager(job_id).get(job_id, device) for job_id in selected]}
        output = []
        for jobs in (ctx.video_jobs, ctx.studio_jobs):
            with jobs.lock:
                jobs._expire()
                output.extend(jobs.public(j) for j in jobs.jobs.values() if j["owner"] == device["id"])
        return {"jobs": output}

    @router.get("/v1/jobs/{job_id}")
    def status(job_id: str, device=Depends(require_device)):
        return manager(job_id).get(job_id, device)

    @router.get("/v1/jobs/{job_id}/events")
    async def events(job_id: str, request: Request, device=Depends(require_device)):
        jobs = manager(job_id)
        jobs.get(job_id, device)  # ownership / expiry checked before response headers

        async def stream():
            previous = None
            while not await request.is_disconnected():
                if not ctx.auth.has_device(device['id']):
                    return
                try:
                    status = jobs.get(job_id, device)
                except ApiError:
                    return
                encoded = json.dumps(status, separators=(",", ":"))
                if encoded != previous:
                    yield f"event: status\ndata: {encoded}\n\n"
                    previous = encoded
                else:
                    yield ": keepalive\n\n"
                if status["status"] in ("completed", "failed", "paused"):
                    return
                await asyncio.sleep(1)

        return StreamingResponse(stream(), media_type="text/event-stream",
                                 headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})

    @router.post("/v1/jobs/{job_id}/stop")
    def stop(job_id: str, device=Depends(require_device)):
        with ctx.jobs_lock:
            return manager(job_id).control(job_id, device)

    @router.post("/v1/jobs/{job_id}/resume")
    def resume(job_id: str, device=Depends(require_device)):
        with ctx.jobs_lock:
            return manager(job_id).control(job_id, device, resume=True)

    @router.get("/v1/jobs/{job_id}/result")
    def manifest(job_id: str, device=Depends(require_device)):
        return json.loads((manager(job_id).result(job_id, device) / "manifest.json").read_text(encoding="utf-8"))

    @router.get("/v1/jobs/{job_id}/result/{name}")
    def download(job_id: str, name: str, device=Depends(require_device)):
        directory = manager(job_id).result(job_id, device)
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        entry = next((f for f in manifest["files"] if f["name"] == name), None)
        if entry is None or name not in ("detections.ndjson", "result.png", "result.mp4", 'dataset.zip', 'portraits.zip', 'lora.safetensors'):
            raise not_found()
        return FileResponse(directory / name, media_type=entry["mime"], filename=name)

    @router.delete("/v1/jobs/{job_id}", status_code=204)
    def delete(job_id: str, device=Depends(require_device)):
        manager(job_id).delete(job_id, device)
        return Response(status_code=204)

    return router
