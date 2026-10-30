"""Bounded, read-only resource sampling. No ML imports, downloads or process control.

RSS is summed over this process, recognised dashboard/API/queue roots and their
descendants. Shared pages can therefore be counted more than once. GPU-wide
usage is always distinct from process-attributed usage; unavailable is not zero.
"""

import csv
import io
import json
import logging
import os
import shutil
import subprocess
import threading
import time
from collections import deque
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
MIB = 1024 * 1024
log = logging.getLogger("your_gallery.resources")


@dataclass(frozen=True)
class ResourceLimits:
    enabled: bool = False
    max_app_ram_mb: int = 0
    min_free_ram_mb: int = 1024
    min_free_vram_mb: int = 256
    min_free_disk_mb: int = 2048

    @classmethod
    def parse(cls, values):
        if not isinstance(values, dict) or type(values.get("enabled", False)) is not bool:
            raise ValueError("Invalid resource limits")
        result = cls(**{k: values.get(k, v) for k, v in asdict(cls()).items()})
        for key, value in asdict(result).items():
            if key != "enabled" and (type(value) is not int or not 0 <= value <= 16 * 1024 * 1024):
                raise ValueError(f"Invalid {key}")
        return result


def load_limits(app_dir=APP_DIR):
    try:
        return ResourceLimits.parse(json.loads((Path(app_dir) / "resource_limits.json").read_text(encoding="utf-8")))
    except FileNotFoundError:
        return ResourceLimits()


def save_limits(limits, app_dir=APP_DIR):
    limits = ResourceLimits.parse(asdict(limits))
    target = Path(app_dir) / "resource_limits.json"
    temporary = target.with_name(f".resource_limits.{os.getpid()}.{threading.get_ident()}.tmp")
    try:
        temporary.write_text(json.dumps(asdict(limits), indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def admission_reasons(snapshot, limits):
    """Admission thresholds, not an OS allocation cap or an OOM guarantee."""
    if not limits.enabled:
        return []
    reasons = []
    ram, disk = snapshot.get("ram"), snapshot.get("disk")
    checks = [(limits.min_free_ram_mb, None if ram is None else ram["available_bytes"], "Free system RAM"),
              (limits.min_free_disk_mb, None if disk is None else disk["free_bytes"], "Free workspace disk")]
    if limits.max_app_ram_mb:
        used = snapshot.get("app_ram_bytes")
        if used is None or not snapshot.get("processes_complete", False):
            reasons.append("Application RAM measurement is unavailable or incomplete.")
        elif used >= limits.max_app_ram_mb * MIB:
            reasons.append("Application RAM reached its admission threshold.")
    if limits.min_free_vram_mb:
        gpus = snapshot.get("gpus", [])
        checks.append((limits.min_free_vram_mb, gpus[0]["free_bytes"] if gpus else None, "Free GPU 0 VRAM"))
    for threshold, available, label in checks:
        if threshold and available is None:
            reasons.append(f"{label} measurement is unavailable.")
        elif threshold and available < threshold * MIB:
            reasons.append(f"{label} is below {threshold} MiB.")
    return reasons


def _number(value):
    try:
        number = float(value)
        return number if number >= 0 and number < float("inf") else None
    except (ValueError, TypeError):
        return None


def sample_gpus(pids, runner=subprocess.run):
    exe = shutil.which("nvidia-smi")
    if exe is None:
        candidate = Path(r"C:\Windows\System32\nvidia-smi.exe")
        exe = str(candidate) if candidate.is_file() else None
    if exe is None:
        return [], "NVIDIA telemetry is unavailable."
    options = dict(capture_output=True, text=True, timeout=2,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    try:
        result = runner([exe, "--query-gpu=index,uuid,name,memory.total,memory.used,memory.free,utilization.gpu,temperature.gpu",
                         "--format=csv,noheader,nounits"], **options)
        if result.returncode:
            return [], "NVIDIA telemetry is unavailable."
        gpus = []
        for row in csv.reader(io.StringIO(result.stdout)):
            if len(row) != 8:
                continue
            index, uuid, name, total, used, free, util, temp = [v.strip() for v in row]
            numbers = [_number(v) for v in (total, used, free)]
            if any(v is None for v in numbers):
                continue
            gpus.append(dict(index=int(index), uuid=uuid, name=name,
                             total_bytes=int(numbers[0] * MIB), used_bytes=int(numbers[1] * MIB),
                             free_bytes=int(numbers[2] * MIB), utilization_percent=_number(util),
                             temperature_c=_number(temp), app_used_bytes=None))
        gpus.sort(key=lambda g: g["index"])
        # Some drivers (including WDDM) cannot attribute VRAM. Keep it null.
        try:
            apps = runner([exe, "--query-compute-apps=gpu_uuid,pid,used_gpu_memory", "--format=csv,noheader,nounits"], **options)
            if apps.returncode == 0:
                attributed = {}
                for row in csv.reader(io.StringIO(apps.stdout)):
                    if len(row) == 3 and row[1].strip().isdigit() and int(row[1]) in pids:
                        attributed.setdefault(row[0].strip(), []).append(_number(row[2].strip()))
                for gpu in gpus:
                    values = attributed.get(gpu["uuid"], [])
                    if values and all(v is not None for v in values):
                        gpu["app_used_bytes"] = int(sum(values) * MIB)
        except (OSError, subprocess.SubprocessError):
            pass
        return gpus, None if gpus else "NVIDIA telemetry is unavailable."
    except (OSError, ValueError, subprocess.SubprocessError):
        return [], "NVIDIA telemetry is unavailable."


def sample_memory(app_dir, ps=None):
    if ps is None:
        try:
            import psutil as ps
        except ImportError:
            return None, None, [], False, "RAM telemetry requires the existing psutil dependency."
    ram, processes, complete = None, [], True
    try:
        vm = ps.virtual_memory()
        ram = dict(total_bytes=vm.total, available_bytes=vm.available, used_percent=vm.percent)
    except (ps.Error, OSError):
        pass
    try:
        roots = {os.getpid()}
        app_dir = Path(app_dir).resolve()
        for proc in ps.process_iter(["pid", "name", "cmdline"]):
            try:
                info = proc.info
                process_name = (info["name"] or "").lower()
                if "python" not in process_name and "streamlit" not in process_name:
                    continue
                args = info["cmdline"] or []
                scripts = [Path(arg) for arg in args if Path(arg).name.lower() in ("dashboard.py", "job_manager.py")]
                module = any(args[i:i + 2] == ["-m", "mobile_api"] for i in range(len(args)))
                if not scripts and not module:
                    continue
                # A similarly named Python script outside this application is unrelated.
                absolute_entry = any(script.is_absolute() and script.parent.resolve() == app_dir for script in scripts)
                if absolute_entry or Path(proc.cwd()).resolve() == app_dir:
                    roots.add(info["pid"])
            except (ps.Error, OSError):
                continue
        # A multiprocessing queue worker can outlive its dashboard parent. Its
        # existing PID + creation-time record avoids attributing a recycled PID.
        try:
            record = json.loads((app_dir / "jobs" / ".worker.pid").read_text(encoding="utf-8"))
            if isinstance(record, dict) and type(record.get("pid")) is int and record.get("create_time") is not None:
                worker = ps.Process(record["pid"])
                if worker.create_time() == record["create_time"]:
                    roots.add(record["pid"])
        except (ps.Error, OSError, ValueError, TypeError):
            pass
        selected = {}
        for pid in roots:
            try:
                proc = ps.Process(pid)
                selected[pid] = proc
                selected.update({child.pid: child for child in proc.children(recursive=True)})
            except ps.NoSuchProcess:
                continue
            except (ps.Error, OSError):
                complete = False
        for proc in selected.values():
            try:
                processes.append(dict(pid=proc.pid, name=proc.name(), ram_bytes=proc.memory_info().rss))
            except ps.NoSuchProcess:
                continue
            except (ps.Error, OSError):
                complete = False
    except (ps.Error, OSError):
        complete = False
    return ram, sum(p["ram_bytes"] for p in processes) if processes else None, processes, complete, None


def _folder_entries(roots):
    """Yield running totals so one directory walk can span many short samples."""
    size, complete, seen = 0, True, set()
    stack = list(roots)
    while stack:
        directory = Path(stack.pop())
        if directory.is_symlink() or (hasattr(directory, "is_junction") and directory.is_junction()):
            complete = False
            continue
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_symlink() or (hasattr(os.path, "isjunction") and os.path.isjunction(entry.path)):
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(entry.path)
                    elif entry.is_file(follow_symlinks=False):
                        # Windows DirEntry.stat can omit inode/link-count fields.
                        stat = os.stat(entry.path, follow_symlinks=False)
                        key = (stat.st_dev, stat.st_ino)
                        # Only hard-linked files need deduplication state.
                        if stat.st_nlink <= 1 or not stat.st_ino or key not in seen:
                            size += stat.st_size
                            if stat.st_nlink > 1 and stat.st_ino:
                                seen.add(key)
                    yield size, False
        except FileNotFoundError:
            continue
        except OSError:
            complete = False
        yield size, False
    yield size, complete


def folder_usage(roots, budget_seconds=0.15):
    started, result = time.monotonic(), (0, False)
    entries = _folder_entries(roots)
    try:
        for result in entries:
            if time.monotonic() - started >= budget_seconds:
                return result[0], False
        return result
    finally:
        entries.close()


class ResourceMonitor:
    def __init__(self, app_dir=APP_DIR, *, storage_root=None, interval=5.0):
        self.app_dir = Path(app_dir)
        self.storage_root = Path(storage_root) if storage_root else self.app_dir
        self.interval = interval
        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._thread = None
        self._snapshot = None
        self._sampled = float("-inf")
        self._folder_sampled = float("-inf")
        self._folder = (0, False)
        self._folder_scan = None
        self._folder_stamp = None
        self.history = deque(maxlen=120)
        self.events = deque(maxlen=60)
        self._previous_alerts = set()

    def start(self):
        with self._lock:
            if self._thread is None or not self._thread.is_alive():
                self._stop.clear()
                self._thread = threading.Thread(target=self._run, name="resource-monitor", daemon=True)
                self._thread.start()
        return self

    def close(self):
        self._stop.set()
        thread = self._thread
        if thread is not None and thread is not threading.current_thread():
            thread.join(timeout=5)
        with self._lock:
            if self._folder_scan is not None:
                self._folder_scan.close()
                self._folder_scan = None

    def _run(self):
        while not self._stop.is_set():
            try:
                self.snapshot()
            except Exception:
                log.exception("Resource sample failed")
            self._stop.wait(self.interval)

    def snapshot(self):
        with self._lock:
            now = time.monotonic()
            if self._snapshot is not None and now - self._sampled < self.interval:
                return self._snapshot
            ram, app_ram, processes, complete, warning = sample_memory(self.app_dir)
            gpus, gpu_warning = sample_gpus({p["pid"] for p in processes})
            if not complete:
                for gpu in gpus:
                    gpu["app_used_bytes"] = None
            disk = None
            try:
                usage = shutil.disk_usage(self.storage_root)
                disk = dict(total_bytes=usage.total, used_bytes=usage.used, free_bytes=usage.free)
            except OSError:
                pass
            stamp = datetime.now(timezone.utc).isoformat()
            if self._folder_scan is None and now - self._folder_sampled >= 60:
                self._folder_scan = _folder_entries([self.storage_root])
                self._folder = (0, False)
            if self._folder_scan is not None:
                deadline = time.monotonic() + .03
                try:
                    while time.monotonic() < deadline:
                        self._folder = next(self._folder_scan)
                except StopIteration:
                    self._folder_scan = None
                    self._folder_sampled = now
                self._folder_stamp = stamp
            warnings = [message for message in (warning, gpu_warning) if message]
            if ram is None:
                warnings.append("System RAM telemetry is unavailable.")
            if not complete:
                warnings.append("Some application processes could not be measured.")
            if disk is None:
                warnings.append("Workspace disk telemetry is unavailable.")
            alerts = []
            if ram and ram["used_percent"] >= 90:
                alerts.append("System RAM usage is at least 90%.")
            if disk and disk["free_bytes"] < 2 * 1024 * MIB:
                alerts.append("Workspace disk has less than 2 GiB free.")
            for gpu in gpus:
                if gpu["total_bytes"] and gpu["used_bytes"] / gpu["total_bytes"] >= .9:
                    alerts.append(f"GPU {gpu['index']} VRAM usage is at least 90%.")
            snapshot = dict(sampled_at=stamp, ram=ram, app_ram_bytes=app_ram,
                            processes_complete=complete, processes=processes, gpus=gpus, disk=disk,
                            app_storage_bytes=self._folder[0], storage_complete=self._folder[1],
                            storage_sampled_at=self._folder_stamp,
                            warnings=warnings, alerts=alerts)
            for message in set(alerts) - self._previous_alerts:
                self.events.append(dict(at=stamp, message=message))
                log.warning(message)
            self._previous_alerts = set(alerts)
            self.history.append(dict(at=stamp, app_ram_bytes=app_ram,
                                     ram_used_percent=ram["used_percent"] if ram else None,
                                     gpu_used_bytes=gpus[0]["used_bytes"] if gpus else None))
            self._sampled, self._snapshot = time.monotonic(), snapshot
            return snapshot

    def admission_reasons(self):
        try:
            limits = load_limits(self.app_dir)
        except (OSError, ValueError, TypeError):
            return ["Resource limits could not be read. Check PC Settings."]
        return admission_reasons(self.snapshot(), limits) if limits.enabled else []

    def scan_admission_reasons(self):
        """Keep a small RAM reserve for the API even with custom limits disabled."""
        reasons = self.admission_reasons()
        ram = self.snapshot().get('ram')
        if ram and (ram['available_bytes'] < 1024 * MIB or ram['used_percent'] >= 97):
            reasons.append('System RAM is critically low. Scanning is paused to keep the server online.')
        return reasons


_monitor = None
_monitor_lock = threading.Lock()


def get_resource_monitor():
    global _monitor
    with _monitor_lock:
        if _monitor is None:
            _monitor = ResourceMonitor().start()
        return _monitor
