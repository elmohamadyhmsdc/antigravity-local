"""
One GPU, two job queues. The 6 GB card cannot host a heavy job from the Streamlit dashboard
(`the app/jobs/`) and one from this API (`mobile_workspace/jobs/`) at the same time, so GPU
endpoints answer `503 gpu_busy` + Retry-After while either queue has a running job and the
phone retries later.

  dashboard queue : job_manager.gpu_heavy_job_running (LoRA train/generate, undress)
  mobile queue    : any running job - every job type this API accepts uses the GPU

`job_manager` only holds queue bookkeeping here; it never imports the user database.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

from .errors import ApiError

RETRY_AFTER_SECONDS = 15


@dataclass(frozen=True)
class Busy:
    job_id: str
    job_type: str
    source: str  # "mobile" | "dashboard"

    def as_dict(self) -> dict:
        return {"job_id": self.job_id, "job_type": self.job_type, "source": self.source}


class GpuGuard:
    def __init__(self, dashboard_jobs_dir: Optional[Path], mobile_jobs_dir: Optional[Path],
                 manager_factory: Optional[Callable] = None):
        self.dashboard_jobs_dir = Path(dashboard_jobs_dir) if dashboard_jobs_dir else None
        self.mobile_jobs_dir = Path(mobile_jobs_dir) if mobile_jobs_dir else None
        self._manager_factory = manager_factory
        self.mobile_busy = lambda: None
        self.resource_check = lambda: []

    def _manager(self, jobs_dir: Path):
        if self._manager_factory is not None:
            return self._manager_factory(jobs_dir)
        from job_manager import JobManager
        return JobManager(str(jobs_dir))

    def busy(self) -> Optional[Busy]:
        """The job holding the GPU, or None. Mobile jobs win when both queues are busy."""
        active = self.mobile_busy()
        if active is not None:
            return active
        if self.mobile_jobs_dir is not None and self.mobile_jobs_dir.exists():
            manager = self._manager(self.mobile_jobs_dir)
            if manager.is_worker_running():
                job = manager.get_running_job()
                if job is not None:
                    return Busy(job.id, job.job_type, "mobile")
        return self.dashboard_busy()

    def dashboard_busy(self) -> Optional[Busy]:
        from job_manager import gpu_heavy_job_running
        if self.dashboard_jobs_dir is not None and self.dashboard_jobs_dir.exists():
            job = gpu_heavy_job_running(self._manager(self.dashboard_jobs_dir))
            if job is not None:
                return Busy(job.id, job.job_type, "dashboard")
        return None

    def require_free(self) -> None:
        b = self.busy()
        if b is not None:
            raise ApiError(503, "gpu_busy", f"A {b.job_type} job is running on the GPU.", retryable=True,
                           headers={"Retry-After": str(RETRY_AFTER_SECONDS)})
        self.require_resources()

    def require_resources(self) -> None:
        reasons = self.resource_check()
        if reasons:
            raise ApiError(503, "resource_pressure", " ".join(reasons), retryable=True,
                           headers={"Retry-After": str(RETRY_AFTER_SECONDS)})
