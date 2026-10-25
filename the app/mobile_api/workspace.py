"""
The server's scratch space: the app/mobile_workspace/ (gitignored).

  blobs/<ab>/<sha256>   temporary upload cache, removed after the last using job is ACKed
  uploads/<sha256>.part partial (resumable) uploads
  jobs/<job_id>/        per-job scratch + results (phase P4)
  tls/                  PERSISTENT - the self-signed certificate
  devices.json          PERSISTENT - paired devices (hashed tokens) + server identity

Everything except the two persistent entries is wiped when the server starts: the
phone is the source of truth, so a blob that is gone is just a 409 "upload it again".
Unclaimed uploads expire after six idle hours. Registered jobs protect shared inputs;
inactive unacknowledged jobs expire after 24 hours. The app runs a periodic cleaner.
"""

import os
import re
import shutil
import threading
import time
from pathlib import Path
from typing import Iterable, List, Optional

MARKER = ".antigravity-mobile-workspace"
PERSISTENT = {"devices.json", "tls", MARKER}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")

GB = 1024 ** 3
DEFAULT_BLOB_CACHE_BYTES = 20 * GB
DEFAULT_MAX_UPLOAD_BYTES = 2 * GB
PARTIAL_MAX_AGE_SECONDS = 6 * 3600
BLOB_MAX_AGE_SECONDS = 6 * 3600


class WorkspaceError(RuntimeError):
    pass


class Workspace:
    def __init__(self, root, blob_cache_bytes: int = DEFAULT_BLOB_CACHE_BYTES,
                 max_upload_bytes: int = DEFAULT_MAX_UPLOAD_BYTES):
        self.root = Path(root)
        self.blob_cache_bytes = int(blob_cache_bytes)
        self.max_upload_bytes = int(max_upload_bytes)
        self._lock = threading.RLock()
        self._job_inputs = {}  # registered job id -> input hashes; guarded by _lock

    # --- layout -----------------------------------------------------------

    @property
    def blobs_dir(self) -> Path:
        return self.root / "blobs"

    @property
    def uploads_dir(self) -> Path:
        return self.root / "uploads"

    @property
    def jobs_dir(self) -> Path:
        return self.root / "jobs"

    @property
    def tls_dir(self) -> Path:
        return self.root / "tls"

    @property
    def devices_path(self) -> Path:
        return self.root / "devices.json"

    # --- lifecycle --------------------------------------------------------

    def prepare(self, wipe: bool = True) -> None:
        """Create the folders. With wipe=True (server start) delete everything that is not
        persistent. Refuses to touch a non-empty folder this class did not create, so a wrong
        path can never delete someone's files."""
        self.root.mkdir(parents=True, exist_ok=True)
        marker = self.root / MARKER
        if not marker.exists():
            if any(self.root.iterdir()):
                raise WorkspaceError(
                    f"{self.root} is not empty and was not created by the mobile API; refusing to use it")
            marker.write_text("Created by Your Gallery Mobile API. Everything here except devices.json and tls/ "
                              "is a cache and is deleted when the server starts.\n", encoding="utf-8")
        if wipe:
            for entry in self.root.iterdir():
                if entry.name in PERSISTENT:
                    continue
                if entry.is_dir() and not entry.is_symlink():
                    shutil.rmtree(entry)
                else:
                    entry.unlink(missing_ok=True)
            self._job_inputs.clear()
        for d in (self.blobs_dir, self.uploads_dir, self.jobs_dir, self.tls_dir):
            d.mkdir(parents=True, exist_ok=True)

    # --- blobs ------------------------------------------------------------

    @staticmethod
    def valid_sha(sha: str) -> bool:
        return bool(SHA256_RE.match(sha or ""))

    def blob_path(self, sha: str) -> Path:
        if not self.valid_sha(sha):
            raise WorkspaceError(f"not a sha256: {sha!r}")
        return self.blobs_dir / sha[:2] / sha

    def has_blob(self, sha: str) -> bool:
        return self.blob_path(sha).is_file()

    def blob_size(self, sha: str) -> Optional[int]:
        try:
            return self.blob_path(sha).stat().st_size
        except OSError:
            return None

    def touch_blob(self, sha: str) -> bool:
        """Mark a blob as used just now (LRU)."""
        try:
            os.utime(self.blob_path(sha))
            return True
        except OSError:
            return False

    def missing(self, shas: Iterable[str]) -> List[str]:
        return [s for s in dict.fromkeys(shas) if not self.has_blob(s)]

    def partial_path(self, sha: str) -> Path:
        if not self.valid_sha(sha):
            raise WorkspaceError(f"not a sha256: {sha!r}")
        return self.uploads_dir / f"{sha}.part"

    def partial_size(self, sha: str) -> int:
        try:
            return self.partial_path(sha).stat().st_size
        except OSError:
            return 0

    def discard_partial(self, sha: str) -> None:
        self.partial_path(sha).unlink(missing_ok=True)

    def commit_partial(self, sha: str) -> Path:
        """Move a fully received, hash-verified upload into the cache and evict if over the cap."""
        with self._lock:
            dest = self.blob_path(sha)
            dest.parent.mkdir(parents=True, exist_ok=True)
            os.replace(self.partial_path(sha), dest)
            self.evict(protect={sha})
            return dest

    def cache_bytes(self) -> int:
        total = 0
        for f in self.blobs_dir.rglob("*"):
            try:
                if f.is_file():
                    total += f.stat().st_size
            except OSError:
                pass
        return total

    def evict(self, protect: Iterable[str] = ()) -> List[str]:
        """Delete least-recently-used blobs until the cache fits blob_cache_bytes.
        `protect` blobs (e.g. inputs of a queued job) are never removed."""
        protect = set(protect)
        with self._lock:
            files = []
            total = 0
            for f in self.blobs_dir.rglob("*"):
                try:
                    if f.is_file():
                        st = f.stat()
                        files.append((st.st_mtime, st.st_size, f))
                        total += st.st_size
                except OSError:
                    pass
            removed = []
            if total <= self.blob_cache_bytes:
                return removed
            for _, size, f in sorted(files):
                if total <= self.blob_cache_bytes:
                    break
                if f.name in protect:
                    continue
                try:
                    f.unlink()
                    total -= size
                    removed.append(f.name)
                except OSError:
                    pass
            return removed

    def purge_stale_partials(self, now: Optional[float] = None, max_age: float = PARTIAL_MAX_AGE_SECONDS) -> int:
        now = time.time() if now is None else now
        n = 0
        for f in self.uploads_dir.glob("*.part"):
            try:
                if now - f.stat().st_mtime > max_age:
                    f.unlink()
                    n += 1
            except OSError:
                pass
        return n

    def purge_stale_blobs(self, now=None, max_age=BLOB_MAX_AGE_SECONDS) -> int:
        """Expire abandoned uploads, keeping every registered job's input cache."""
        now = time.time() if now is None else now
        removed = 0
        with self._lock:
            protected = set().union(*self._job_inputs.values())
            for path in self.blobs_dir.glob("*/*"):
                try:
                    if path.name not in protected and path.is_file() and now - path.stat().st_mtime > max_age:
                        path.unlink()
                        removed += 1
                except FileNotFoundError:
                    pass
        return removed

    # --- job dirs ---------------------------------------------------------

    def job_dir(self, job_id: str, create: bool = False) -> Path:
        if not re.match(r"^[A-Za-z0-9_-]{1,64}$", job_id or ""):
            raise WorkspaceError(f"bad job id: {job_id!r}")
        d = self.jobs_dir / job_id
        if create:
            d.mkdir(parents=True, exist_ok=True)
        return d

    def pin_job_inputs(self, job_id: str, hashes: Iterable[str]) -> None:
        """Register inputs only after this job has pinned its own copies.

        References include queued, running, paused and unacknowledged jobs.
        Deleting one job must not evict a blob referenced by any other job.
        """
        directory = self.job_dir(job_id)
        hashes = set(hashes)
        if not directory.is_dir() or any(not self.valid_sha(sha) for sha in hashes):
            raise WorkspaceError("Invalid job input registration")
        with self._lock:
            self._job_inputs[job_id] = hashes

    def purge_job(self, job_id: str) -> bool:
        with self._lock:
            d = self.job_dir(job_id)
            existed = d.exists()
            if existed:
                # An unsuccessful deletion must fail the ACK so the phone retries.
                shutil.rmtree(d)
            inputs = self._job_inputs.get(job_id, set())
            others = set().union(*(hashes for key, hashes in self._job_inputs.items() if key != job_id))
            for sha in inputs - others:
                path = self.blob_path(sha)
                path.unlink(missing_ok=True)
                try:
                    path.parent.rmdir()
                except OSError:
                    pass  # this prefix may still contain other cached inputs
            # Keep the registration if a deletion raises; the same ACK can retry.
            self._job_inputs.pop(job_id, None)
            return existed

    def purge_expired_jobs(self, ttl_seconds: float = 24 * 3600, now: Optional[float] = None) -> List[str]:
        """Remove job dirs untouched for ttl_seconds (the phone never ACKed the download)."""
        now = time.time() if now is None else now
        removed = []
        for d in self.jobs_dir.iterdir():
            try:
                if d.name not in self._job_inputs and d.is_dir() and now - d.stat().st_mtime > ttl_seconds:
                    shutil.rmtree(d)
                    removed.append(d.name)
            except OSError:
                pass
        return removed
