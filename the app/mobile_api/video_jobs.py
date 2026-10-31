"""Ephemeral, device-owned video analysis jobs. No user database or dashboard worker.

Each NDJSON line is a complete AnalyzeImageResponse with frame_number/timestamp_ms.
Crops travel inline, so a verified result file can be imported frame by frame on the phone.
"""

import hashlib
import base64
import json
import logging
import math
import os
import shutil
import threading
import time
import uuid
from datetime import datetime, timezone

import cv2

from analysis import AnalyzeOptions
from .errors import ApiError, bad_request, not_found
from .gpu_guard import Busy
from .schemas import analysis_to_response, parse_analyze_options
from .media_decode import IsolatedCapture
from . import video_journal
from .video_sampling import adaptive_interval

log = logging.getLogger("mobile_api")


def stamp():
    return datetime.now(timezone.utc).isoformat()


class VideoJobs:
    def __init__(self, ctx, capture_factory=None):
        self.ctx = ctx
        self.capture = capture_factory or (lambda path: IsolatedCapture(path, ctx.max_image_px))
        self.lock = threading.RLock()
        self.jobs = video_journal.recover(ctx)
        self.threads = {}

    def busy(self):
        with self.lock:
            for job in self.jobs.values():
                if job["status"] in ("running", "queued"):
                    return Busy(job["job_id"], "analyze_video", "mobile")
        return None

    def _owned(self, job_id, device):
        job = self.jobs.get(job_id)
        if job is None or job["owner"] != device["id"]:
            raise not_found("This job is no longer on this PC. Upload it again to continue.")
        return job

    @staticmethod
    def public(job):
        return {k: dict(v) if k == 'details' else v for k, v in job.items() if not k.startswith("_") and
                k not in ("owner", "params", "input_sha", "request", "touched")}

    def _expire(self):
        for job_id, job in list(self.jobs.items()):
            if job["status"] not in ("queued", "running") and time.time() - job["touched"] > 86400:
                self.ctx.workspace.purge_job(job_id)
                del self.jobs[job_id]
                self.threads.pop(job_id, None)

    def create(self, body, device):
        if not isinstance(body, dict) or body.get("type") != "analyze_video":
            raise bad_request("Only analyze_video jobs are available in this phase.")
        params, inputs = body.get("params"), body.get("inputs")
        if not isinstance(params, dict) or not isinstance(inputs, dict):
            raise bad_request("params and inputs must be objects.")
        sha = inputs.get("video")
        if not isinstance(sha, str) or not self.ctx.workspace.valid_sha(sha):
            raise bad_request("inputs.video must be a SHA-256 blob reference.")
        interval = params.get("frame_interval", 1.0)
        start = params.get("start_frame", 0)
        start_time = params.get("start_time", 0)
        sampling_mode = params.get('sampling_mode', 'fixed')
        if sampling_mode not in ('fixed', 'adaptive'):
            raise bad_request('sampling_mode must be fixed or adaptive.')
        if isinstance(interval, bool) or not isinstance(interval, (float, int)) or not 0.25 <= interval <= 60:
            raise bad_request("frame_interval must be between 0.25 and 60 seconds.")
        if type(start) is not int or not 0 <= start <= 2**31 - 1:
            raise bad_request("start_frame must be a non-negative integer.")
        if isinstance(start_time, bool) or not isinstance(start_time, (int, float)) or not 0 <= start_time <= 86400:
            raise bad_request("start_time must be between 0 and 86400 seconds.")
        opts = parse_analyze_options(json.dumps(params))
        if not opts.detect_characters and opts.model_id is not None and opts.model_id != self.ctx.engines.model_id:
            raise ApiError(409, "model_mismatch", "The video's embedding model differs from this PC.")
        client_id = body.get("client_job_id")
        if client_id is not None and (not isinstance(client_id, str) or not 1 <= len(client_id) <= 128):
            raise bad_request("client_job_id must be a string of 1 to 128 characters.")
        with self.lock:
            self._expire()
            for job in self.jobs.values():
                if client_id and job["owner"] == device["id"] and job["client_job_id"] == client_id:
                    if job["request"] != body:
                        raise ApiError(409, "job_conflict", "This client_job_id was used with different inputs.")
                    return self.public(job)
            self.ctx.gpu.require_free()
            if len(self.jobs) >= 32:
                raise ApiError(429, "rate_limited", "Download and remove old video jobs first.", retryable=True)
            job_id = "vid_" + uuid.uuid4().hex
            ws = self.ctx.workspace
            with ws._lock:  # pin the input before another upload evicts its cache entry
                if not ws.has_blob(sha):
                    raise ApiError(409, "missing_blobs", "Upload the video first.", extra={"missing": [sha]})
                directory = ws.job_dir(job_id, create=True)
                try:
                    try:
                        os.link(ws.blob_path(sha), directory / "input.video")
                    except OSError:
                        shutil.copyfile(ws.blob_path(sha), directory / "input.video")
                    ws.pin_job_inputs(job_id, [sha])
                except Exception:
                    ws.purge_job(job_id)
                    raise
            job = dict(job_id=job_id, client_job_id=client_id, type="analyze_video", status="queued",
                       progress=0.0, message="Preparing video", queue_position=0, created_at=stamp(),
                       started_at=None, completed_at=None, error=None, last_frame=-1, frames_done=0,
                       details={}, has_result=False, owner=device["id"], params=dict(params), input_sha=sha,
                       preview_jpeg=None, preview_timestamp_ms=None,
                       incremental_results=True, request=body, touched=time.time(), _stop=threading.Event(),
                       _next_frame=start, _result_bytes=0, _offsets=[0], _saved_at=0)
            job['_committed_next_frame'] = start
            self.jobs[job_id] = job
            video_journal.save(self.ctx, job)
            self._launch(job)
            return self.public(job)

    def _launch(self, job):
        job["_stop"].clear()
        job["status"] = "queued"
        thread = threading.Thread(target=self._run, args=(job,), name=job["job_id"], daemon=True)
        self.threads[job["job_id"]] = thread
        thread.start()

    def _checkpoint(self, job, output, force=False):
        if (not force and job['_result_bytes'] > 0 and (len(job['_offsets']) - 1) % 8
                and time.monotonic() - job.get('_flushed_at', 0) < 3):
            return
        output.flush()
        os.fsync(output.fileno())
        with self.lock:
            job['_result_bytes'] = output.tell()
            job['_committed_next_frame'] = job['_next_frame']
            job['_flushed_at'] = time.monotonic()
            video_journal.save(self.ctx, job)

    def _run(self, job):
        cap = None
        try:
            reasons = self.ctx.gpu.resource_check()
            if reasons:
                with self.lock:
                    job.update(status="paused", message="Resource protection: " + " ".join(reasons), touched=time.time())
                return
            directory = self.ctx.workspace.job_dir(job["job_id"])
            cap = self.capture(str(directory / "input.video"))
            if not cap.isOpened():
                raise ValueError("The video could not be opened.")
            fps = float(cap.get(cv2.CAP_PROP_FPS))
            total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            if not math.isfinite(fps) or not 0 < fps <= 1000 or total <= 0:
                raise ValueError("The video has no readable frame count or frame rate.")
            params = job["params"]
            # Preserve the same FPS and grid after worker/process recovery.
            fps = job['details'].get('fps', fps)
            interval = (adaptive_interval(total / fps) if params.get('sampling_mode') == 'adaptive'
                        else params.get('frame_interval', 1.0))
            step = job['details'].get('sample_step', max(1, round(fps * interval)))
            origin = round(params.get("start_time", 0) * fps)
            lower_bound = max(job["_next_frame"], origin)
            # start_frame is the phone's first uncommitted frame, not a new sampling
            # origin. Keep the same grid when the PC restarted between imports.
            frame_no = origin + ((lower_bound - origin + step - 1) // step) * step
            first_sample = origin + ((max(params.get('start_frame', 0), origin) - origin + step - 1) // step) * step
            opts = parse_analyze_options(json.dumps(params))
            engine_opts = AnalyzeOptions(min_face_quality=opts.min_face_quality,
                                         detect_characters=opts.detect_characters,
                                         detect_bodies=opts.detect_bodies, body_score=opts.body_score)
            with self.lock:
                job.update(status="running", started_at=job["started_at"] or stamp(),
                           error=None, details={**job['details'], "fps": fps, "total_frames": total,
                                                "frame_interval": step / fps, 'sample_step': step,
                                                'total_samples': max(0, (total - first_sample + step - 1) // step),
                                                'stage': 'decode',
                                                'sampling_mode': params.get('sampling_mode', 'fixed')})
            consecutive_errors = 0
            with open(directory / "detections.ndjson", "ab") as out:
                while frame_no < total:
                    if job["_stop"].is_set():
                        with self.lock:
                            job.update(status="paused", message="Paused", touched=time.time())
                        return
                    reasons = self.ctx.gpu.resource_check()
                    if reasons:
                        # Drop the disposable model process to release its RAM/VRAM.
                        with self.ctx.compute_lock:
                            if hasattr(self.ctx.engines, 'unload'):
                                self.ctx.engines.unload()
                        with self.lock:
                            job.update(status='paused', message='Resource protection: ' + ' '.join(reasons),
                                       touched=time.time())
                        return
                    # Respect heavy dashboard work that started while this job was running.
                    dashboard = self.ctx.gpu.dashboard_busy()
                    if dashboard is not None:
                        with self.lock:
                            job.update(status="paused", message="The dashboard needs the GPU", touched=time.time())
                        return
                    with self.lock:
                        job['details']['stage'] = 'decode'
                        job['message'] = 'Reading the next video sample'
                    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_no)
                    ok, img = cap.read()
                    if not ok or img is None or not img.size:
                        consecutive_errors += 1
                        with self.lock:
                            details = job['details']
                            details['skipped_frames'] = details.get('skipped_frames', 0) + 1
                            details['last_skipped_frame'] = frame_no
                            job.update(progress=min(1.0, (frame_no + 1) / total),
                                       message=f'Skipping unreadable frame {frame_no}',
                                       _next_frame=frame_no + step, touched=time.time())
                        log.warning('Skipping unreadable video frame %s in %s', frame_no, job['job_id'])
                        if consecutive_errors >= 8:
                            if not job['frames_done']:
                                raise ValueError('No sampled video frames could be decoded. The file may be damaged or its codec unavailable.')
                            with self.lock:
                                job['details']['incomplete'] = True
                                job['details']['warning'] = 'Stopped after 8 consecutive unreadable samples; earlier detections were saved.'
                            break
                        frame_no += step
                        self._checkpoint(job, out)
                        continue
                    consecutive_errors = 0
                    h, w = img.shape[:2]
                    if max(w, h) > self.ctx.max_image_px:
                        scale = self.ctx.max_image_px / max(w, h)
                        img = cv2.resize(img, (max(1, round(w * scale)), max(1, round(h * scale))))
                    scale = min(1.0, 480 / max(img.shape[:2]))
                    preview = cv2.resize(img, (max(1, round(img.shape[1] * scale)),
                                               max(1, round(img.shape[0] * scale))))
                    encoded, jpeg = cv2.imencode('.jpg', preview, [cv2.IMWRITE_JPEG_QUALITY, 65])
                    with self.lock:
                        job.update(preview_jpeg=base64.b64encode(jpeg).decode('ascii') if encoded else None,
                                   preview_timestamp_ms=round(frame_no * 1000 / fps))
                        job['details']['stage'] = 'inference'
                        job['message'] = 'Detecting faces and people in the current sample'
                    with self.ctx.compute_lock:
                        result = self.ctx.engines.analyze(img, engine_opts)
                    line = analysis_to_response(result, img, opts, self.ctx.engines.model_id)
                    line.update(frame_number=frame_no, timestamp_ms=round(frame_no * 1000 / fps))
                    encoded_line = (json.dumps(line, separators=(",", ":"), allow_nan=False) + '\n').encode('utf-8')
                    if len(encoded_line) > video_journal.MAX_LINE:
                        raise ValueError('A video frame result exceeded the safe transfer size.')
                    out.write(encoded_line)
                    with self.lock:
                        job['_offsets'].append(out.tell())
                        job.update(last_frame=frame_no, frames_done=job["frames_done"] + 1,
                                   progress=min(1.0, (frame_no + 1) / total), message="Analyzing video",
                                   _next_frame=frame_no + step, touched=time.time())
                    frame_no += step
                    self._checkpoint(job, out)
                with self.lock:
                    job['details']['stage'] = 'finalize'
                    job['message'] = 'Finalizing video detections'
                self._checkpoint(job, out, force=True)
            if not job['frames_done'] and lower_bound < total:
                raise ValueError('No sampled video frames could be decoded. The file may be damaged or its codec unavailable.')
            path = directory / "detections.ndjson"
            with open(path, "rb") as source:
                digest = hashlib.file_digest(source, "sha256").hexdigest()
            manifest = {"job_id": job["job_id"], "files": [{"name": path.name, "size": path.stat().st_size,
                        "sha256": digest, "mime": "application/x-ndjson"}], "meta": dict(job["details"])}
            (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            with self.lock:
                skipped = job['details'].get('skipped_frames', 0)
                message = 'Ready to download' + (f' ({skipped} unreadable samples skipped)' if skipped else '')
                job.update(status="completed", progress=1.0, message=message, has_result=True,
                           completed_at=stamp(), touched=time.time())
        except ApiError as error:
            log.exception('Video analysis interrupted: %s', job['job_id'])
            with self.lock:
                job.update(status='paused' if error.retryable else 'failed', error=error.message,
                           message=error.message, touched=time.time())
        except Exception as error:
            log.exception("Video analysis failed: %s", job["job_id"])
            with self.lock:
                job.update(status="failed", error=str(error) if isinstance(error, ValueError) else
                           "The PC could not analyze this video. Check the server log.",
                           message="Video analysis failed", touched=time.time())
        finally:
            if cap is not None:
                cap.release()
            with self.lock:
                path = self.ctx.workspace.job_dir(job['job_id']) / 'detections.ndjson'
                if path.is_file():
                    with open(path, 'ab') as output:
                        self._checkpoint(job, output, force=True)
                else:
                    video_journal.save(self.ctx, job)

    def get(self, job_id, device):
        with self.lock:
            self._expire()
            job = self._owned(job_id, device)
            job["touched"] = time.time()
            if time.monotonic() - job['_saved_at'] >= 30:
                video_journal.save(self.ctx, job)
            return self.public(job)

    def frames(self, job_id, device, cursor=0, limit=8):
        with self.lock:
            job = self._owned(job_id, device)
            job['touched'] = time.time()
            return video_journal.batch(self.ctx, job, cursor, limit)

    def control(self, job_id, device, resume=False):
        with self.lock:
            job = self._owned(job_id, device)
            if resume and job["status"] == "paused":
                thread = self.threads.get(job_id)
                if thread is not None and thread.is_alive():
                    raise ApiError(503, 'gpu_busy', 'The video worker is still pausing.', retryable=True,
                                   headers={'Retry-After': '2'})
                self.ctx.gpu.require_free()
                self._launch(job)
            elif not resume and job["status"] in ("queued", "running"):
                job["_stop"].set()
            return self.public(job)

    def result(self, job_id, device):
        with self.lock:
            job = self._owned(job_id, device)
            if not job["has_result"]:
                raise ApiError(409, "result_not_ready", "The video is not finished yet.", retryable=True)
            job["touched"] = time.time()
            return self.ctx.workspace.job_dir(job_id)

    def delete(self, job_id, device):
        with self.lock:
            job = self._owned(job_id, device)
            thread = self.threads.get(job_id)
            if thread is not None and thread.is_alive():
                raise ApiError(409, "job_running", "Pause this job before removing it.", retryable=True)
            self.ctx.workspace.purge_job(job_id)
            del self.jobs[job_id]
            self.threads.pop(job_id, None)
            for key in ("params", "request", "details"):
                job.pop(key, None)

    def close(self):
        with self.lock:
            for job in self.jobs.values():
                job["_stop"].set()
        for thread in list(self.threads.values()):
            thread.join(timeout=5)
