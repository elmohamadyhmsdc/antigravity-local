"""A bounded, device-owned Studio queue in ephemeral job workspaces."""

import hashlib
import json
import logging
import math
import os
import shutil
import threading
import time
import uuid

import numpy as np

from .errors import ApiError, bad_request, not_found
from .gpu_guard import Busy
from .reface_runner import run_reface
from .reference_reface import REFERENCE_TYPES, run_reference_reface, validate_reference_reface
from .artifact_jobs import ARTIFACT_TYPES, run_artifact, validate_artifact
from .schemas import decode_embedding
from .video_jobs import stamp
from .photo_edit import TYPE as PHOTO_EDIT_TYPE, run_photo_edit, validate_photo_edit

log = logging.getLogger("mobile_api")
REFACE_TYPES = {f"reface_{kind}_{engine}" for kind in ("image", "video") for engine in ("v3", "v2", "dfm")}
REFACE_TYPES.update(("reface_image", "reface_video"))
REFACE_TYPES.update(REFERENCE_TYPES)


def validate_generate_lora_request(params: dict) -> dict:
    if not isinstance(params, dict):
        raise bad_request("Parameters must be a JSON object.")
    result = dict(params)
    mode = params.get("generation_mode", "portrait")
    if mode not in ("portrait", "full_body"):
        raise bad_request("generation_mode must be 'portrait' or 'full_body'.")
    result["generation_mode"] = mode

    aspect = params.get("aspect_ratio", "square")
    if aspect not in ("square", "vertical_768", "tall_896"):
        raise bad_request("aspect_ratio must be 'square', 'vertical_768', or 'tall_896'.")
    result["aspect_ratio"] = aspect

    pose_id = params.get("pose_media_id")
    if pose_id is not None and (isinstance(pose_id, bool) or not isinstance(pose_id, int)):
        raise bad_request("pose_media_id must be an integer ID.")
    result["pose_media_id"] = pose_id

    detailer = params.get("enable_face_detailer", True)
    if not isinstance(detailer, bool):
        raise bad_request("enable_face_detailer must be a boolean.")
    result["enable_face_detailer"] = detailer

    return result


def validate_reface(body, capabilities):
    if body.get("type") in REFERENCE_TYPES:
        return validate_reference_reface(body, capabilities)
    kind, params, inputs = body.get("type"), body.get("params"), body.get("inputs")
    if kind not in REFACE_TYPES or not isinstance(params, dict) or not isinstance(inputs, dict):
        raise bad_request("A supported Reface type, params and inputs are required.")
    allowed_inputs = {"target", "identity_bundle"}
    if "target" not in inputs or set(inputs) - allowed_inputs:
        raise bad_request("Reface requires exactly one target blob (and optional identity_bundle).")
    if any(not isinstance(value, str) for value in inputs.values()):
        raise bad_request("Reface inputs must be single blob references.")
    allowed = {"source_faces", "model_id", "target_faces", "restorer", "restorer_weight", "use_parser",
               "use_occluder", "realism_preset", "dfm_model", "start_time", "end_time",
               "target_embeddings", "target_indices", "preview", "identity_boost", "swapper", "quality_profile",
               "identity_bundle", "use_3d_geometry"}
    if set(params) - allowed:
        raise bad_request("An unsupported Reface option was supplied.")
    if params.get("model_id", "buffalo_l@1") != "buffalo_l@1":
        raise ApiError(409, "model_mismatch", "The source identity uses a different embedding model.")
    has_bundle = "identity_bundle" in inputs or "identity_bundle" in params
    if "identity_bundle" in inputs and "identity_bundle" in params:
        raise bad_request("Supply the identity bundle as either a blob or an inline object.")
    if "identity_bundle" in params:
        from identity_bundle import validate_bundle_dict
        valid_b, b_err = validate_bundle_dict(params["identity_bundle"])
        if not valid_b:
            raise bad_request(f"Invalid identity_bundle parameter: {b_err}")
    faces = params.get("source_faces")
    unified = kind in ("reface_image", "reface_video")
    dfm = kind.endswith("_dfm") or (unified and "dfm_model" in params)
    if not has_bundle:
        if not isinstance(faces, list) or len(faces) > 100 or (not faces and not dfm):
            raise bad_request("Choose between 1 and 100 source faces (DFM may omit them).")
    elif faces is not None:
        if not isinstance(faces, list) or len(faces) > 100:
            raise bad_request("Choose between 1 and 100 source faces.")
    for face in (faces or []):
        try:
            embedding = decode_embedding(face["embedding"])
            quality = face["quality"]
            if "generated" in face and not isinstance(face["generated"], bool):
                raise ValueError()
            if not np.all(np.isfinite(embedding)) or np.linalg.norm(embedding) < 1e-8:
                raise ValueError()
            if isinstance(quality, bool) or not isinstance(quality, (int, float)) or not 0 <= quality <= 1:
                raise ValueError()
            pose = face.get("pose")
            if pose is not None:
                if not isinstance(pose, dict) or not {"yaw", "pitch"} <= set(pose) or set(pose) - {"yaw", "pitch", "roll"}:
                    raise ValueError()
                for key, value in pose.items():
                    if key == "roll" and value is None:
                        continue
                    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
                        raise ValueError()
        except (KeyError, TypeError, ValueError):
            raise bad_request("A source face has an invalid embedding, quality or pose.")
    engines = capabilities["engines"]
    if dfm:
        if params.get("dfm_model") not in engines["dfm_models"]:
            raise bad_request("Choose an available DFM model.")
    elif "dfm_model" in params:
        raise bad_request("A DFM model is only valid with the DFM engine.")
    elif not (engines.get("reface", False) if unified else engines["reface_v2" if kind.endswith("_v2") else "reface_v3"]):
        raise ApiError(409, "engine_unavailable", "This Reface engine is not available on the PC.")
    if params.get("restorer", "auto") not in ["auto", "none", *capabilities["restorers"]]:
        raise bad_request("Choose an available restorer.")
    for key in ("use_parser", "use_occluder", "use_3d_geometry"):
        if key in params and not isinstance(params[key], bool):
            raise bad_request(f"{key} must be true or false.")
    for key, low, high in [("restorer_weight", 0, 1), ("start_time", 0, 86400), ("end_time", 0, 86400)]:
        value = params.get(key)
        if value is not None and (isinstance(value, bool) or not isinstance(value, (int, float)) or not low <= value <= high):
            raise bad_request(f"{key} is outside the supported range.")
    if params.get("end_time") is not None and params["end_time"] <= params.get("start_time", 0):
        raise bad_request("The trim end must be after the start.")
    if params.get("realism_preset", "natural") not in ("natural", "maximum_detail", "clean"):
        raise bad_request("Choose a supported realism preset.")
    if "preview" in params and not isinstance(params["preview"], bool):
        raise bad_request("preview must be true or false.")
    boost = params.get("identity_boost", .5)
    if isinstance(boost, bool) or not isinstance(boost, (int, float)) or not 0 <= boost <= 1:
        raise bad_request("identity_boost must be between zero and one.")
    if params.get("swapper", "auto") not in ("auto", "inswapper_128", "hyperswap_1b_256", "hyperswap_1c_256"):
        raise bad_request("Choose a supported swapper.")
    legacy = kind.endswith("_v2")
    if legacy and "use_3d_geometry" in params:
        raise bad_request("3D geometry requires the shared Reface engine.")
    if "quality_profile" in params:
        from reface_config import QUALITY_PROFILES
        if not unified or params["quality_profile"] not in QUALITY_PROFILES:
            raise bad_request("Quality profiles require unified Reface and must be fast, balanced or detail.")
    if legacy and (params.get("restorer", "auto") not in ("auto", "none") or
                   params.get("realism_preset", "natural") != "natural" or
                   params.get("use_parser", True) is not True):
        raise bad_request("Legacy supports automatic/disabled enhancement and occlusion protection only.")
    if (legacy or dfm) and any(key in params for key in ("identity_boost", "swapper")):
        raise bad_request("Swapper and identity strength do not apply to legacy or trained-identity jobs.")
    refs, picks = params.get("target_embeddings"), params.get("target_indices")
    if refs is not None or picks is not None:
        if not kind.startswith("reface_video") or "target_faces" in params:
            raise bad_request("Reference identities are supported for video only.")
        if not isinstance(refs, list) or not 1 <= len(refs) <= 32 or not isinstance(picks, list) or not picks:
            raise bad_request("Provide reference embeddings and selected reference indices.")
        if len(picks) != len(set(p for p in picks if isinstance(p, int) and not isinstance(p, bool))) or any(
                isinstance(p, bool) or not isinstance(p, int) or not 0 <= p < len(refs) for p in picks):
            raise bad_request("Selected reference indices are invalid.")
        try:
            for ref in refs:
                vector = decode_embedding(ref)
                if not np.isfinite(vector).all() or np.linalg.norm(vector) < 1e-8:
                    raise ValueError()
        except (ValueError, TypeError):
            raise bad_request("A target identity embedding is invalid.")
    boxes = params.get("target_faces")
    if boxes is not None:
        if kind.startswith("reface_video"):
            raise bad_request("Target boxes are photo-only. Use reference identities to select video faces.")
        if not isinstance(boxes, list) or not 1 <= len(boxes) <= 32:
            raise bad_request("Select at least one target face.")
        for box in boxes:
            if not isinstance(box, dict) or set(box) != {"x", "y", "w", "h"} or any(
                    isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or abs(v) > 100000
                    for v in box.values()) or box["w"] <= 0 or box["h"] <= 0:
                raise bad_request("A selected target box is invalid.")


class StudioJobs:
    def __init__(self, ctx, runner=None):
        self.ctx = ctx
        self.runner = runner or self._run_engine
        self.lock = threading.RLock()
        self.jobs = {}
        self.wake = threading.Event()
        self.closing = threading.Event()
        self.worker = None

    def busy(self):
        with self.lock:
            for job in self.jobs.values():
                if job["status"] in ("queued", "running"):
                    return Busy(job["job_id"], job["type"], "mobile")
        return None

    @staticmethod
    def public(job):
        keys = ("job_id", "client_job_id", "type", "status", "progress", "message", "queue_position",
                "created_at", "started_at", "completed_at", "error", "last_frame", "frames_done", "details", "has_result")
        return {k: job[k] for k in keys}

    def _expire(self):
        for job_id, job in list(self.jobs.items()):
            if job["status"] not in ("queued", "running") and time.time() - job["touched"] > 86400:
                self.ctx.workspace.purge_job(job_id)
                del self.jobs[job_id]

    def _owned(self, job_id, device):
        job = self.jobs.get(job_id)
        if job is None or job["owner"] != device["id"]:
            raise not_found("This job has expired or the PC restarted. Retry from the phone.")
        return job

    def create(self, body, device):
        if body.get('type') == PHOTO_EDIT_TYPE:
            validate_photo_edit(body, self.ctx.probe.snapshot())
        elif body.get('type') in ARTIFACT_TYPES:
            validate_artifact(body, self.ctx.probe.snapshot())
        else:
            validate_reface(body, self.ctx.probe.snapshot())
        client_id = body.get("client_job_id")
        if not isinstance(client_id, str) or not 1 <= len(client_id) <= 128:
            raise bad_request("Studio jobs require a stable client_job_id.")
        blobs = []
        for slot, value in body['inputs'].items():
            values = value if isinstance(value, list) else [value]
            for index, sha in enumerate(values):
                if not isinstance(sha, str) or not self.ctx.workspace.valid_sha(sha):
                    raise bad_request('Every input must be a SHA-256 blob reference.')
                name = f'input.{slot}.{index:04d}' if isinstance(value,list) else f'input.{slot}'
                blobs.append((name,sha))
        with self.lock:
            self._expire()
            for job in self.jobs.values():
                if job["owner"] == device["id"] and job["client_job_id"] == client_id:
                    if job["request"] != body:
                        raise ApiError(409, "job_conflict", "This request ID was used with different parameters.")
                    return self.public(job)
            if len(self.jobs) >= 32:
                raise ApiError(429, "rate_limited", "Remove completed jobs before submitting more.", retryable=True)
            ws = self.ctx.workspace
            job_id = "studio_" + uuid.uuid4().hex
            with ws._lock:
                missing = sorted({sha for _,sha in blobs if not ws.has_blob(sha)})
                if missing:
                    raise ApiError(409, "missing_blobs", "Upload the inputs first.", extra={"missing": missing})
                directory = ws.job_dir(job_id, create=True)
                try:
                    for name,sha in blobs:
                        try:
                            os.link(ws.blob_path(sha), directory / name)
                        except OSError:
                            shutil.copyfile(ws.blob_path(sha), directory / name)
                    ws.pin_job_inputs(job_id, (sha for _, sha in blobs))
                except Exception:
                    ws.purge_job(job_id)
                    raise
            job = dict(job_id=job_id, client_job_id=client_id, type=body["type"], params=body["params"],
                       request=body, owner=device["id"], status="queued", progress=0.0, message="Waiting for GPU",
                       queue_position=0, created_at=stamp(), started_at=None, completed_at=None, error=None,
                       last_frame=-1, frames_done=0, details={}, has_result=False, touched=time.time(),
                       _stop=threading.Event())
            self.jobs[job_id] = job
            if self.worker is None:
                self.worker = threading.Thread(target=self._work, name="mobile-studio", daemon=True)
                self.worker.start()
            self.wake.set()
            return self.public(job)

    def _work(self):
        while not self.closing.is_set():
            self.wake.wait(0.25)
            self.wake.clear()
            with self.ctx.jobs_lock, self.lock:
                waiting = [j for j in self.jobs.values() if j["status"] == "queued"]
                for position, job in enumerate(waiting):
                    job["queue_position"] = position
                if not waiting:
                    continue
                job = waiting[0]
                if self.ctx.video_jobs.busy() or self.ctx.gpu.dashboard_busy():
                    continue
                reasons = self.ctx.gpu.resource_check()
                if reasons:
                    job.update(message="Waiting for resources: " + " ".join(reasons))
                    continue
                job.update(status="running", started_at=job["started_at"] or stamp(), message="Preparing engine")
            directory = self.ctx.workspace.job_dir(job["job_id"])

            def report(progress, message, **details):
                with self.lock:
                    job.update(progress=progress, message=message, touched=time.time(), **details)

            def stopped():
                return job["_stop"].is_set() or self.closing.is_set() or self.ctx.gpu.dashboard_busy() is not None

            try:
                with self.ctx.compute_lock:
                    # Recheck after acquiring compute access; a scan may have run
                    # since the queue's preflight. Keep the request queued.
                    reasons = self.ctx.gpu.resource_check()
                    if reasons:
                        with self.lock:
                            paused = job["_stop"].is_set()
                            job.update(status="paused" if paused else "queued",
                                       message="Paused" if paused else "Waiting for resources: " + " ".join(reasons))
                        continue
                    self._release_scan_engines()
                    meta = self.runner(job, directory, report, stopped)
                with self.lock:
                    if meta is None:
                        job.update(status="paused", message="Paused", touched=time.time())
                        continue
                files = []
                for name, mime in [("result.png", "image/png"), ("result.mp4", "video/mp4"),
                                   ('dataset.zip','application/zip'), ('portraits.zip','application/zip'),
                                   ('lora.safetensors','application/octet-stream'), ('identity_bundle.json', 'application/json')]:
                    path = directory / name
                    if path.exists():
                        with open(path, "rb") as source:
                            digest = hashlib.file_digest(source, "sha256").hexdigest()
                        files.append(dict(name=name, size=path.stat().st_size, sha256=digest, mime=mime))
                if len(files) != 1 or files[0]["size"] <= 0:
                    raise ValueError("The engine did not produce a result.")
                manifest = dict(job_id=job["job_id"], files=files, meta=meta)
                (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
                with self.lock:
                    job.update(status="completed", progress=1.0, message="Ready to download", has_result=True,
                               completed_at=stamp(), details=meta, touched=time.time())
            except Exception as exc:
                log.exception("Studio job failed: %s", job["job_id"])
                from photo_edit import PhotoEditError
                actionable = job['type'] == PHOTO_EDIT_TYPE and isinstance(exc, PhotoEditError)
                with self.lock:
                    job.update(status="failed", message="Adjust the photo edit" if actionable else "Processing failed", touched=time.time(),
                               error=str(exc) if actionable else "The PC could not process this target. Check the PC log, then retry.")

    def get(self, job_id, device):
        with self.lock:
            self._expire()
            job = self._owned(job_id, device)
            job["touched"] = time.time()
            return self.public(job)

    def control(self, job_id, device, resume=False):
        with self.lock:
            job = self._owned(job_id, device)
            if resume and job["status"] == "paused":
                job["_stop"].clear()
                job.update(status="queued", message="Waiting for GPU")
                self.wake.set()
            elif not resume and job["status"] == "queued":
                job.update(status="paused", message="Paused")
            elif not resume and job["status"] == "running":
                job["_stop"].set()
            return self.public(job)

    def result(self, job_id, device):
        with self.lock:
            job = self._owned(job_id, device)
            if not job["has_result"]:
                raise ApiError(409, "result_not_ready", "This job has no result yet.", retryable=True)
            job["touched"] = time.time()
            return self.ctx.workspace.job_dir(job_id)

    def delete(self, job_id, device):
        with self.lock:
            job = self._owned(job_id, device)
            if job["status"] in ("queued", "running"):
                raise ApiError(409, "job_running", "Pause the job before removing it.", retryable=True)
            self.ctx.workspace.purge_job(job_id)
            del self.jobs[job_id]
            # The idle worker may still hold this dict after its loop iteration.
            for key in ("params", "request", "details"):
                job.pop(key, None)

    def close(self):
        self.closing.set()
        self.wake.set()
        if self.worker is not None:
            self.worker.join(timeout=5)

    def _release_scan_engines(self):
        """Free the idle scan models before a Studio job. Called under compute_lock, so no
        scan is running. Most-detail Reface alone peaks at ~5.9 of the 6 GB card; resident
        scan/outline sessions pushed it into shared system memory (measured 2026-11-11 on a
        1080p clip: 0.8 s -> 6.0 s per frame). The next scan reloads them on demand."""
        unload = getattr(self.ctx.engines, "unload", None)
        if unload is None:
            return
        try:
            unload()
        except Exception:  # noqa: BLE001 - a slow render beats a refused job
            log.exception("Could not release scan engines before a Studio job")

    def _run_engine(self, job, directory, report, stopped):
        if job['type'] == PHOTO_EDIT_TYPE:
            return run_photo_edit(job, directory, report, stopped)
        if job['type'] in REFERENCE_TYPES:
            return run_reference_reface(job, directory, report, stopped)
        if job['type'] in ARTIFACT_TYPES:
            return run_artifact(job,directory,report,stopped,self.ctx)
        return run_reface(job,directory,report,stopped)
