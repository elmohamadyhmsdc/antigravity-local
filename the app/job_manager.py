"""
Background Job Manager for Reface Operations.
Implements a sequential job queue - only one job runs at a time.
Jobs persist even if the browser tab is closed.
"""

import json
import os
import sys
import time
import uuid
import multiprocessing
import threading
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, asdict
from typing import Optional, List, Dict, Any
from enum import Enum


class JobStatus(Enum):
    PENDING = "pending"
    QUEUED = "queued"  # Waiting in queue
    RUNNING = "running"
    PAUSED = "paused"  # Stopped by user, can resume
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class Job:
    id: str
    job_type: str  # "reface_image" or "reface_video"
    status: JobStatus
    progress: float  # 0.0 to 1.0
    message: str
    created_at: str
    queue_position: int = 0  # Position in queue (0 = running or done)
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    result_path: Optional[str] = None
    error: Optional[str] = None
    params: Dict[str, Any] = None
    last_frame: int = 0  # For video resume - last processed frame
    
    def to_dict(self):
        d = asdict(self)
        d['status'] = self.status.value
        return d
    
    @staticmethod
    def from_dict(d):
        d['status'] = JobStatus(d['status'])
        return Job(**d)


class JobManager:
    """Manages background jobs with file-based persistence and queue."""
    
    LOCK_FILE = ".queue.lock"
    WORKER_PID_FILE = ".worker.pid"
    
    def __init__(self, jobs_dir: str = None):
        self.jobs_dir = Path(jobs_dir) if jobs_dir else Path(__file__).parent / "jobs"
        self.jobs_dir.mkdir(parents=True, exist_ok=True)
    
    def _job_file(self, job_id: str) -> Path:
        return self.jobs_dir / f"{job_id}.json"
    
    def _lock_file(self) -> Path:
        return self.jobs_dir / self.LOCK_FILE
    
    def _worker_pid_file(self) -> Path:
        return self.jobs_dir / self.WORKER_PID_FILE
    
    def save_job(self, job: Job):
        """Save job state to disk."""
        with open(self._job_file(job.id), 'w') as f:
            json.dump(job.to_dict(), f, indent=2)
    
    def load_job(self, job_id: str) -> Optional[Job]:
        """Load job state from disk."""
        path = self._job_file(job_id)
        if path.exists():
            try:
                with open(path, 'r') as f:
                    return Job.from_dict(json.load(f))
            except:
                pass
        return None
    
    def list_jobs(self, limit: int = 20) -> List[Job]:
        """List recent jobs, sorted by creation time (newest first)."""
        jobs = []
        for f in self.jobs_dir.glob("*.json"):
            try:
                job = self.load_job(f.stem)
                if job:
                    jobs.append(job)
            except:
                pass
        
        jobs.sort(key=lambda j: j.created_at, reverse=True)
        return jobs[:limit]
    
    def get_queued_jobs(self) -> List[Job]:
        """Get jobs in queue, sorted by creation time (oldest first = next to run)."""
        jobs = []
        for f in self.jobs_dir.glob("*.json"):
            try:
                job = self.load_job(f.stem)
                if job and job.status in [JobStatus.PENDING, JobStatus.QUEUED]:
                    jobs.append(job)
            except:
                pass
        
        jobs.sort(key=lambda j: j.created_at)  # Oldest first
        return jobs
    
    def get_running_job(self) -> Optional[Job]:
        """Get the currently running job, if any."""
        for f in self.jobs_dir.glob("*.json"):
            try:
                job = self.load_job(f.stem)
                if job and job.status == JobStatus.RUNNING:
                    return job
            except:
                pass
        return None
    
    def delete_job(self, job_id: str):
        """Delete a job file."""
        path = self._job_file(job_id)
        if path.exists():
            path.unlink()
    
    def create_job(self, job_type: str, params: Dict[str, Any]) -> Job:
        """Create a new job and add it to the queue."""
        # Count current queue position
        queued = self.get_queued_jobs()
        running = self.get_running_job()
        queue_pos = len(queued) + (1 if running else 0)
        
        job = Job(
            id=str(uuid.uuid4())[:8],
            job_type=job_type,
            status=JobStatus.QUEUED,
            progress=0.0,
            message=f"Queued (position {queue_pos + 1})" if queue_pos > 0 else "Waiting to start...",
            created_at=datetime.now().isoformat(),
            queue_position=queue_pos,
            params=params
        )
        self.save_job(job)
        return job
    
    def update_queue_positions(self):
        """Update queue position numbers for all queued jobs."""
        queued = self.get_queued_jobs()
        for i, job in enumerate(queued):
            job.queue_position = i + 1
            job.message = f"Queued (position {i + 1})"
            self.save_job(job)
    
    def is_worker_running(self) -> bool:
        """Check if the queue worker process is running.

        Handles both the current {pid, create_time} format and the older
        bare-PID format (a worker started before this format existed may
        still be alive) — falls back to a plain PID-exists check for the
        latter instead of misreading it as "not running".

        Cross-checking create_time (when available) guards against PID
        reuse: a crashed worker's PID can be recycled by an unrelated
        process (Windows reuses PIDs), which would otherwise read as a
        false "still running" and permanently block a new worker from ever
        being spawned.
        """
        pid_file = self._worker_pid_file()
        if not pid_file.exists():
            return False

        try:
            with open(pid_file, 'r') as f:
                data = json.loads(f.read().strip())

            import psutil
            if isinstance(data, dict):
                pid = data["pid"]
                recorded_create_time = data.get("create_time")
                if not psutil.pid_exists(pid):
                    return False
                if recorded_create_time is None:
                    return True
                return psutil.Process(pid).create_time() == recorded_create_time
            else:
                # Old format: a bare PID integer, no create_time to cross-check.
                return psutil.pid_exists(int(data))
        except Exception:
            return False

    def set_worker_pid(self, pid: int):
        """Save the worker process PID, plus its start time to detect PID reuse later."""
        create_time = None
        try:
            import psutil
            create_time = psutil.Process(pid).create_time()
        except Exception:
            pass
        with open(self._worker_pid_file(), 'w') as f:
            json.dump({"pid": pid, "create_time": create_time}, f)
    
    def clear_worker_pid(self):
        """Remove worker PID file."""
        pid_file = self._worker_pid_file()
        if pid_file.exists():
            pid_file.unlink()
    
    def _stop_signal_file(self, job_id: str) -> Path:
        """Get the stop signal file path for a job."""
        return self.jobs_dir / f".stop_{job_id}"
    
    def request_stop(self, job_id: str):
        """Request a running job to stop (creates a signal file)."""
        signal_file = self._stop_signal_file(job_id)
        signal_file.touch()
        print(f"[INFO] Stop requested for job {job_id}")
    
    def is_stop_requested(self, job_id: str) -> bool:
        """Check if a stop has been requested for a job."""
        return self._stop_signal_file(job_id).exists()
    
    def clear_stop_signal(self, job_id: str):
        """Clear the stop signal file."""
        signal_file = self._stop_signal_file(job_id)
        if signal_file.exists():
            signal_file.unlink()
    
    def pause_job(self, job_id: str, current_frame: int = 0):
        """Pause a running job and save its state."""
        job = self.load_job(job_id)
        if job and job.status == JobStatus.RUNNING:
            job.status = JobStatus.PAUSED
            job.last_frame = current_frame
            job.message = f"⏸️ Paused at frame {current_frame}" if current_frame > 0 else "⏸️ Paused"
            self.save_job(job)
            self.clear_stop_signal(job_id)
            print(f"[INFO] Job {job_id} paused at frame {current_frame}")
            return True
        return False
    
    def resume_job(self, job_id: str):
        """Mark a paused job to be resumed (puts it at front of queue)."""
        job = self.load_job(job_id)
        if job and job.status == JobStatus.PAUSED:
            job.status = JobStatus.QUEUED
            job.queue_position = 0  # Put at front
            job.message = "▶️ Resuming..."
            self.save_job(job)
            print(f"[INFO] Job {job_id} queued for resume from frame {job.last_frame}")
            return True
        return False
    
    def get_paused_jobs(self) -> List[Job]:
        """Get all paused jobs."""
        jobs = []
        for f in self.jobs_dir.glob("*.json"):
            try:
                job = self.load_job(f.stem)
                if job and job.status == JobStatus.PAUSED:
                    jobs.append(job)
            except:
                pass
        return jobs


def run_single_job(job_id: str, jobs_dir: str):
    """Execute a single reface, LoRA-training, or undress job."""
    manager = JobManager(jobs_dir)
    job = manager.load_job(job_id)

    if not job:
        print(f"[ERROR] Job {job_id} not found!")
        return False

    if job.job_type == "train_lora":
        from lora_trainer import run_training
        try:
            return run_training(job, manager)
        except Exception as e:
            import traceback
            error_msg = str(e)
            job.status = JobStatus.FAILED
            job.progress = 0.0
            job.message = f"❌ Error: {error_msg}"
            job.error = traceback.format_exc()
            job.completed_at = datetime.now().isoformat()
            manager.save_job(job)
            print(f"\n[JOB {job_id}] ❌ ERROR: {error_msg}")
            print(traceback.format_exc())
            return False

    if job.job_type == "undress_image":
        from undress_core import run_undress_job
        try:
            return run_undress_job(job, manager)
        except Exception as e:
            import traceback
            error_msg = str(e)
            job.status = JobStatus.FAILED
            job.progress = 0.0
            job.message = f"❌ Error: {error_msg}"
            job.error = traceback.format_exc()
            job.completed_at = datetime.now().isoformat()
            manager.save_job(job)
            print(f"\n[JOB {job_id}] ❌ ERROR: {error_msg}")
            print(traceback.format_exc())
            return False

    from reface_engine import RefaceEngine
    from reface_engine_v2 import RefaceEngineV2, EnhancementConfig, OcclusionConfig, VideoConfig

    try:
        # Mark as running
        job.status = JobStatus.RUNNING
        job.started_at = datetime.now().isoformat()
        job.message = "Initializing..."
        job.queue_position = 0
        manager.save_job(job)
        
        print(f"\n{'='*60}")
        print(f"[JOB {job_id}] Starting {job.job_type}")
        print(f"{'='*60}")
        
        params = job.params
        
        is_dfm = job.job_type in ["reface_image_dfm", "reface_video_dfm"]
        is_v3 = job.job_type in ["reface_image_v3", "reface_video_v3"] or is_dfm
        is_v2 = job.job_type in ["reface_image_v2", "reface_video_v2"]

        if is_v3:
            # Initialize V3 (HD) engine; DFM "pro" mode if a .dfm path is supplied
            from reface_engine_v3 import RefaceEngineV3
            engine = RefaceEngineV3(
                restorer=params.get('restorer', 'codeformer'),
                restorer_weight=params.get('restorer_weight', 0.5),
                use_parser=params.get('use_parser', True),
                use_occluder=params.get('use_occluder', True),
                dfm_path=params.get('dfm_path') if is_dfm else None,
                realism_preset=params.get('realism_preset', 'natural'),
                realism_overrides=params.get('realism_overrides') or None,
            )
        elif is_v2:
            # Build V2 engine WITH its configs (these are constructor args, NOT swap kwargs)
            engine = RefaceEngineV2(
                enhancement_config=EnhancementConfig(**params.get('enhancement_config', {})),
                occlusion_config=OcclusionConfig(**params.get('occlusion_config', {})),
                video_config=VideoConfig(**params.get('video_config', {})),
            )
        else:
            # Initialize V1 engine
            engine = RefaceEngine(
                upscale=params.get('upscale', 2),
                enable_enhancement=True
            )
        
        # Load or build faceset (DFM mode is trained per-person -> no source needed)
        if is_dfm and not params.get('faceset_name') and not params.get('source_paths'):
            faceset = None
        elif params.get('faceset_name'):
            print(f"[JOB {job_id}] Loading faceset: {params['faceset_name']}")
            faceset = engine.load_faceset_by_name(params['faceset_name'])
            if not faceset:
                raise Exception(f"Faceset '{params['faceset_name']}' not found")
        else:
            print(f"[JOB {job_id}] Building faceset from source media...")
            
            def build_progress(current, total):
                pct = current / total * 0.3
                job.progress = pct
                job.message = f"Building faceset: {current}/{total} ({int(pct*100)}%)"
                manager.save_job(job)
                print(f"[JOB {job_id}] {int(pct*100)}% - Building faceset: {current}/{total}")
            
            faceset = engine.build_faceset_from_media(
                params['source_paths'],
                faceset_name="temp_job",
                progress_callback=build_progress
            )
        
        if not is_dfm and (not faceset or not faceset.faces):
            raise Exception("No faces found in source media!")

        if faceset is not None and faceset.faces:
            print(f"[JOB {job_id}] Faceset ready with {len(faceset.faces)} faces")
        else:
            print(f"[JOB {job_id}] DFM mode: no source faceset needed")
        
        # Run the swap
        target_path = params['target_path']
        is_video = params.get('is_video', False)
        target_face_indices = params.get('target_face_indices')
        use_angle_matching = params.get('use_angle_matching', True)
        start_frame = job.last_frame  # For resume support
        
        # Flag to track if stop was requested
        stop_requested = [False]
        current_frame = [0]
        
        def swap_progress(current, total):
            current_frame[0] = current
            
            # Check for stop signal
            if manager.is_stop_requested(job_id):
                stop_requested[0] = True
                print(f"[JOB {job_id}] Stop signal received at frame {current}")
                return False  # Signal to stop processing
            
            pct = 0.3 + (current / total * 0.7)
            job.progress = pct
            job.last_frame = current
            job.message = f"Processing frame {current}/{total} ({int(pct*100)}%)" if is_video else f"Swapping faces... ({int(pct*100)}%)"
            manager.save_job(job)
            print(f"[JOB {job_id}] {int(pct*100)}% - Frame {current}/{total}")
            return True  # Continue processing
        
        if is_video:
            # Get trim parameters for video
            video_start_time = params.get('start_time', 0.0)
            video_end_time = params.get('end_time', None)
            
            if is_v3:
                result = engine.reface_video_v3(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                    progress_callback=swap_progress,
                    start_time=video_start_time,
                    end_time=video_end_time,
                )
            elif is_v2:
                result = engine.reface_video_with_faceset_v2(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                    apply_occlusion=params.get('occlusion_config', {}).get('enabled', True),
                    progress_callback=swap_progress,
                    start_time=video_start_time,
                    end_time=video_end_time,
                )
            else:
                result = engine.reface_video_with_faceset(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                    use_angle_matching=use_angle_matching,
                    progress_callback=swap_progress,
                    start_time=video_start_time,
                    end_time=video_end_time
                )
        else:
            if is_v3:
                result = engine.reface_image_v3(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                )
            elif is_v2:
                result = engine.reface_with_faceset_v2(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                    apply_occlusion=params.get('occlusion_config', {}).get('enabled', True),
                )
            else:
                result = engine.reface_with_faceset(
                    target_path,
                    faceset,
                    target_face_indices=target_face_indices,
                    use_angle_matching=use_angle_matching
                )
            swap_progress(1, 1)
        
        # Check if stopped
        if stop_requested[0]:
            manager.pause_job(job_id, current_frame[0])
            print(f"\n[JOB {job_id}] ⏸️ PAUSED at frame {current_frame[0]}")
            return False  # Not complete, paused
        
        # Complete
        job.status = JobStatus.COMPLETED
        job.progress = 1.0
        job.completed_at = datetime.now().isoformat()
        job.last_frame = 0  # Reset for next time
        
        if result.success:
            job.message = f"✅ {result.message}"
            job.result_path = result.output_path
            print(f"\n[JOB {job_id}] ✅ COMPLETED: {result.output_path}")
        else:
            job.status = JobStatus.FAILED
            job.message = f"❌ {result.message}"
            job.error = result.message
            print(f"\n[JOB {job_id}] ❌ FAILED: {result.message}")
        
        manager.save_job(job)
        return True
        
    except Exception as e:
        import traceback
        error_msg = str(e)
        job.status = JobStatus.FAILED
        job.progress = 0.0
        job.message = f"❌ Error: {error_msg}"
        job.error = traceback.format_exc()
        job.completed_at = datetime.now().isoformat()
        manager.save_job(job)
        print(f"\n[JOB {job_id}] ❌ ERROR: {error_msg}")
        print(traceback.format_exc())
        return False


def queue_worker(jobs_dir: str):
    """
    Main queue worker that processes jobs one at a time.
    Runs continuously until no more jobs are in the queue.
    """
    # This process's own stdout/stderr can be bound to a legacy codepage (e.g. cp1252
    # on Windows) that can't encode everything jobs print (emoji, raw subprocess output).
    # Reconfigure so one bad character can't take down the whole worker process.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")

    manager = JobManager(jobs_dir)

    print("\n" + "="*60)
    print("[QUEUE WORKER] Started - Processing jobs sequentially")
    print("="*60)
    
    while True:
        # Get next job in queue
        queued_jobs = manager.get_queued_jobs()
        
        if not queued_jobs:
            print("[QUEUE WORKER] No more jobs in queue. Exiting.")
            try:
                from undress_core import close_shared_client
                close_shared_client()
            except Exception:
                pass
            manager.clear_worker_pid()
            break
        
        next_job = queued_jobs[0]
        print(f"\n[QUEUE WORKER] Next job: {next_job.id} ({next_job.job_type})")
        print(f"[QUEUE WORKER] {len(queued_jobs) - 1} job(s) remaining in queue")
        
        # Run the job
        run_single_job(next_job.id, jobs_dir)
        
        # Update queue positions for remaining jobs
        manager.update_queue_positions()
        
        # Small delay between jobs
        time.sleep(1)
    
    print("[QUEUE WORKER] Worker exited.")


def start_queue_worker(jobs_dir: str):
    """Start the queue worker if not already running."""
    manager = JobManager(jobs_dir)
    
    if manager.is_worker_running():
        print("[INFO] Queue worker already running")
        return None
    
    # Start worker in a new process
    process = multiprocessing.Process(
        target=queue_worker,
        args=(jobs_dir,),
        daemon=False
    )
    process.start()
    manager.set_worker_pid(process.pid)
    
    print(f"[INFO] Started queue worker (PID: {process.pid})")
    return process.pid


def add_job_to_queue(job_type: str, params: Dict[str, Any], jobs_dir: str = None) -> Job:
    """Add a new job to the queue and ensure worker is running."""
    manager = JobManager(jobs_dir)
    
    # Create the job
    job = manager.create_job(job_type, params)
    print(f"[INFO] Created job {job.id} - Queue position: {job.queue_position + 1}")
    
    # Start worker if not running
    start_queue_worker(str(manager.jobs_dir))
    
    return job


# Keep old function for compatibility
def start_background_job(job_id: str, jobs_dir: str):
    """Legacy function - now just starts the queue worker."""
    start_queue_worker(jobs_dir)


if __name__ == "__main__":
    manager = JobManager()
    print(f"Jobs directory: {manager.jobs_dir}")
    
    queued = manager.get_queued_jobs()
    running = manager.get_running_job()
    
    print(f"Running: {running.id if running else 'None'}")
    print(f"Queued: {len(queued)}")
    
    for job in queued:
        print(f"  - {job.id}: {job.message}")
