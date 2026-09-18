"""
Antigravity Local - LoRA reference-image generation job

Main-venv side of a `generate_lora_images` job, mirroring how lora_trainer.py
drives sd-scripts: runs lora_generate.py inside venv_ai, folds its progress
events into the job's `details` (which the Character LoRA page's Generate tab
polls), keeps a log in jobs/{job_id}.log, and honours the job's stop signal.
"""

import hashlib
import json
import os
import subprocess
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from queue import Empty, Queue
from typing import Optional

from job_manager import JobStatus
from lora_generate import DEFAULT_STEPS, EVENT_PREFIX, STAGE_GENERATING, denoising_steps

APP_DIR = Path(__file__).parent
VENV_AI_PYTHON = APP_DIR / "venv_ai" / "Scripts" / "python.exe"
GENERATE_SCRIPT = APP_DIR / "lora_generate.py"
OUTPUT_ROOT = APP_DIR / "lora_output"
BASE_CHECKPOINT = APP_DIR / "models" / "sd15_realistic_base.safetensors"
# Leading underscore: lora_dataset._slugify strips it, so no character's upload folder can land here.
REFERENCE_DIR = APP_DIR / "lora_uploads" / "_generate_references"

REQUEST_KEYS = ("base_checkpoint", "lora_path", "trigger_word", "prompt", "negative_prompt", "num_images", "seed",
                "reference_image", "reference_mode", "reference_strength", "reference_scale",
                "lora_scale", "guidance_scale")

STAGE_LAUNCHING = "Launching venv_ai (Python 3.10)"


def generation_output_dir(person_name: str) -> Path:
    return OUTPUT_ROOT / person_name.replace(" ", "_")


def save_reference_image(data: bytes, filename: str, folder: Path = REFERENCE_DIR) -> Path:
    """Keeps an uploaded reference on disk for the background job. Named by content hash, so
    queueing the same upload again reuses the file instead of piling up copies."""
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{hashlib.sha1(data).hexdigest()[:16]}{Path(filename).suffix.lower() or '.png'}"
    if not path.exists():
        path.write_bytes(data)
    return path


def generation_request(job, output_dir: Path) -> dict:
    """The JSON request lora_generate.py reads on stdin for this job."""
    request = {key: job.params[key] for key in REQUEST_KEYS if job.params.get(key) is not None}
    request.update(steps=job.params.get("steps", DEFAULT_STEPS), output_dir=str(output_dir),
                   file_prefix=f"reference_{job.id}")
    return request


def generation_log_path(job, manager) -> Path:
    return manager.jobs_dir / f"{job.id}.log"


def generation_problems(lora_info: dict, person_name: Optional[str] = None) -> list:
    """venv_ai / LoRA file / base checkpoint checks shared by every caller that queues a
    generate_lora_images job, so the Generate tab and Reface V2's Trained LoRA source mode
    disable their buttons on the same conditions."""
    problems = []
    if not VENV_AI_PYTHON.exists():
        problems.append("venv_ai not found. See the Magic Undress page for setup instructions.")
    lora_path = lora_info.get("lora_path")
    if not lora_path or not Path(lora_path).exists():
        who = f" for {person_name}" if person_name else ""
        problems.append(f"The LoRA file{who} is missing: {lora_path or '(none)'}")
    if not BASE_CHECKPOINT.exists():
        problems.append(f"Base checkpoint not found at {BASE_CHECKPOINT}. "
                        "Run: python download_models.py sd15_realistic_base")
    return problems


def build_generation_params(person: dict, lora_info: dict, num_images: int, seed: int = -1,
                            prompt: Optional[str] = None, negative_prompt: Optional[str] = None,
                            reference_params: Optional[dict] = None,
                            lora_scale: Optional[float] = None,
                            guidance_scale: Optional[float] = None) -> dict:
    """The generate_lora_images job params for one person - shared by the Generate tab and Reface
    V2's Trained LoRA source mode so a queued job always looks the same either way."""
    from lora_generate import DEFAULT_NEGATIVE_PROMPT, DEFAULT_PROMPT_TEMPLATE, DEFAULT_STEPS

    params = {
        "person_id": person["id"], "person_name": person["name"],
        "base_checkpoint": str(BASE_CHECKPOINT), "lora_path": lora_info["lora_path"],
        "trigger_word": lora_info["trigger_word"],
        "prompt": prompt or DEFAULT_PROMPT_TEMPLATE.format(trigger=lora_info["trigger_word"]),
        "negative_prompt": negative_prompt or DEFAULT_NEGATIVE_PROMPT,
        "num_images": int(num_images), "seed": int(seed), "steps": DEFAULT_STEPS,
        "output_dir": str(generation_output_dir(person["name"])),
    }
    if lora_scale is not None:
        params["lora_scale"] = float(lora_scale)
    if guidance_scale is not None:
        params["guidance_scale"] = float(guidance_scale)
    params.update(reference_params or {})
    return params


def update_generation_state(state: dict, event: dict) -> Optional[str]:
    """Folds one lora_generate.py event into state (the job's `details`).

    Returns "stage" for a change worth saving at once, "progress" for a step tick (fine to save
    throttled), or None when the event changed nothing.
    """
    now = datetime.now().isoformat()
    kind = event.get("event")
    if kind == "stage":
        if state.get("stage") and state.get("stage_started_at"):
            took = (datetime.fromisoformat(now) - datetime.fromisoformat(state["stage_started_at"])).total_seconds()
            state.setdefault("stage_history", []).append([state["stage"], round(took, 1)])
        state.update(stage=event["stage"], stage_started_at=now)
        for key in ("total_images", "steps", "base_seed"):
            if key in event:
                state[key] = event[key]
        return "stage"
    if kind == "device":
        state["device"] = {k: v for k, v in event.items() if k != "event"}
        return "stage"
    if kind == "step":
        state.update(image=event["image"], step=event["step"], steps=event["steps"], updated_at=now)
        if event.get("seconds"):
            state["sec_per_step"] = event["seconds"] / event["step"]
        return "progress"
    if kind == "image":
        state.setdefault("images", []).append(
            {"path": event["path"], "seed": event["seed"], "seconds": event["seconds"], "peak_vram_gb": event.get("peak_vram_gb")})
        state["updated_at"] = now
        return "stage"
    return None


def generation_steps_done(state: dict) -> tuple:
    """(denoising steps finished, steps in the whole run) across all images."""
    steps = state.get("steps") or DEFAULT_STEPS
    total = (state.get("total_images") or 1) * steps
    finished_images = len(state.get("images", []))
    in_progress = state.get("step", 0) if state.get("image", 0) > finished_images else 0
    return min(finished_images * steps + in_progress, total), total


def describe_generation_state(state: dict) -> str:
    """The one-line job message for the current `details`."""
    stage = state.get("stage") or STAGE_LAUNCHING
    if stage != STAGE_GENERATING:
        return f"{stage}..."
    total_images = state.get("total_images", "?")
    current = min(len(state.get("images", [])) + 1, state.get("total_images") or 1)
    if state.get("image") == current:
        return f"Generating image {current}/{total_images} — step {state['step']}/{state['steps']}"
    return f"Generating image {current}/{total_images}..."


def generation_view(job, manager, now: Optional[datetime] = None) -> dict:
    """What the dashboard shows for a generate_lora_images job: its live `details` plus derived
    timings in seconds (None when unknown)."""
    now = now or datetime.now()
    view = dict(job.details or {})
    view.setdefault("images", [])

    def seconds_since(iso):
        return (now - datetime.fromisoformat(iso)).total_seconds() if iso else None

    view["queued_seconds"] = seconds_since(job.created_at)
    view["stage_seconds"] = seconds_since(view.get("stage_started_at"))
    if job.started_at and job.completed_at:
        view["elapsed_seconds"] = (datetime.fromisoformat(job.completed_at) - datetime.fromisoformat(job.started_at)).total_seconds()
    else:
        view["elapsed_seconds"] = seconds_since(job.started_at)

    view["steps_done"], view["steps_total"] = generation_steps_done(view)
    view["eta_seconds"] = None
    if job.status == JobStatus.RUNNING and view.get("sec_per_step"):
        # A whole image costs a little more than its steps (text encoding, VAE decode, saving), so
        # once one has finished, use its measured time for the images still to come.
        finished = view["images"]
        steps = view.get("steps") or DEFAULT_STEPS
        per_image = finished[-1]["seconds"] if finished else steps * view["sec_per_step"]
        images_left = max((view.get("total_images") or 1) - len(finished), 0)
        started_steps = view.get("step", 0) if view.get("image", 0) > len(finished) else 0
        if images_left:
            view["eta_seconds"] = max(per_image * images_left - started_steps * view["sec_per_step"]
                                      - (seconds_since(view.get("updated_at")) or 0), 0)

    heartbeats = []
    for path in (manager._job_file(job.id), generation_log_path(job, manager)):
        try:
            heartbeats.append(path.stat().st_mtime)
        except OSError:
            pass
    view["idle_seconds"] = now.timestamp() - max(heartbeats) if heartbeats else None
    return view


def run_generation(job, manager) -> bool:
    """Entry point called from job_manager.run_single_job for job_type == 'generate_lora_images'."""
    params = job.params
    output_dir = Path(params["output_dir"])

    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.completed_at = None
    job.error = None
    job.progress = 0.0
    job.details = {"stage": STAGE_LAUNCHING, "stage_started_at": job.started_at, "images": [],
                   "total_images": params["num_images"], "steps": denoising_steps(params)}
    job.message = describe_generation_state(job.details)
    manager.save_job(job)

    def finish(status, message, error=None):
        job.status = status
        job.message = message
        job.error = error
        job.completed_at = datetime.now().isoformat()
        manager.save_job(job)
        print(f"[JOB {job.id}] {message}")
        return status == JobStatus.COMPLETED

    if not VENV_AI_PYTHON.exists():
        return finish(JobStatus.FAILED, "❌ venv_ai not found",
                      f"Expected {VENV_AI_PYTHON}. See the Magic Undress page for setup instructions.")

    # An undress job earlier in this worker keeps its own venv_ai process (with SD weights loaded)
    # alive between jobs; a 6 GB card can't hold that and this pipeline at once.
    try:
        from undress_core import close_shared_client
        close_shared_client()
    except Exception:
        pass

    request = generation_request(job, output_dir)

    cmd = [str(VENV_AI_PYTHON), str(GENERATE_SCRIPT)]
    print(f"[JOB {job.id}] Launching: {' '.join(cmd)}")
    # Same encoding/buffering reasons as lora_trainer.run_training: UTF-8 both ways, and unbuffered
    # so each progress event arrives when it happens rather than when the process exits.
    child_env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1")
    process = subprocess.Popen(cmd, cwd=str(APP_DIR), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                               bufsize=1, env=child_env)
    process.stdin.write(json.dumps(request))
    process.stdin.close()

    # Read on a thread so the stop signal is still noticed while the model loads and prints nothing.
    lines: Queue = Queue()

    def pump():
        for raw in process.stdout:
            lines.put(raw.rstrip("\n"))
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()

    outcome, error_event = None, None
    output_tail = deque(maxlen=50)
    last_save = time.monotonic()
    log = open(generation_log_path(job, manager), "a", encoding="utf-8")
    log.write(f"===== {datetime.now():%Y-%m-%d %H:%M:%S} generate {params['num_images']} image(s) =====\n"
              f"{json.dumps(request, indent=2)}\n")
    try:
        while True:
            if manager.is_stop_requested(job.id):
                outcome = "stopped"
                break
            try:
                line = lines.get(timeout=1.0)
            except Empty:
                continue
            if line is None:
                break
            if not line.startswith(EVENT_PREFIX):
                if line.strip():
                    output_tail.append(line)
                    log.write(line + "\n")
                    log.flush()
                    print(f"[JOB {job.id}] {line}")
                continue
            try:
                event = json.loads(line[len(EVENT_PREFIX):])
            except ValueError:
                continue
            if event.get("event") != "step":
                log.write(line[len(EVENT_PREFIX):] + "\n")
                log.flush()
            if event.get("event") == "done":
                outcome = "done"
                continue
            if event.get("event") == "error":
                outcome, error_event = "error", event
                continue

            change = update_generation_state(job.details, event)
            if change is None:
                continue
            done, total = generation_steps_done(job.details)
            job.progress = min(0.99, done / max(total, 1))
            job.message = describe_generation_state(job.details)
            if change == "stage" or time.monotonic() - last_save >= 1.0:
                manager.save_job(job)
                last_save = time.monotonic()
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        log.write(f"===== lora_generate.py exited with code {process.returncode} =====\n")
        log.close()

    saved = len(job.details.get("images", []))
    if outcome == "stopped":
        manager.clear_stop_signal(job.id)
        return finish(JobStatus.FAILED, f"⏹️ Stopped — kept {saved} of {params['num_images']} image(s)")
    if outcome == "done" and process.returncode == 0:
        job.progress = 1.0
        job.result_path = str(output_dir)
        return finish(JobStatus.COMPLETED, f"✅ {saved} reference image(s) saved to {output_dir}")
    if error_event:
        return finish(JobStatus.FAILED, f"❌ {error_event.get('error')}", error_event.get("traceback"))
    return finish(JobStatus.FAILED, f"❌ lora_generate.py exited with code {process.returncode}", "\n".join(output_tail))
