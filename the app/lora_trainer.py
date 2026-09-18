"""
Antigravity Local - LoRA training dispatcher

Builds the sd-scripts (kohya-ss/sd-scripts) CLI invocation for a per-person
SD1.5 LoRA and runs it as a subprocess inside the isolated `venv_lora`
environment (Python 3.10), mirroring how undress_engine.py is invoked inside
venv_ai. Only the argument-building and subprocess/progress-parsing logic
lives in the main venv; the actual training code is sd-scripts itself.

Each job trains into its own run folder (models/loras/runs/{job_id}) that
holds the per-epoch LoRA snapshots and sd-scripts training states. A failed
or interrupted job can be re-queued and continues from its newest saved
epoch; on success the finished LoRA is moved up into models/loras.
"""

import os
import re
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple

from job_manager import JobStatus
from database import set_person_lora_info

APP_DIR = Path(__file__).parent
VENV_LORA_PYTHON = APP_DIR / "venv_lora" / "Scripts" / "python.exe"
SD_SCRIPTS_DIR = APP_DIR / "sd-scripts"
SD_SCRIPTS_TRAIN_SCRIPT = SD_SCRIPTS_DIR / "train_network.py"

# 6GB-VRAM-safe defaults (RTX 4050 Laptop reference hardware) — all overridable from the UI.
DEFAULT_EPOCHS = 10
DEFAULT_NETWORK_DIM = 32
DEFAULT_NETWORK_ALPHA = 16
DEFAULT_LEARNING_RATE = 0.0001
DEFAULT_BATCH_SIZE = 1
DEFAULT_MAX_RESOLUTION = 512
RESOLUTION_OPTIONS = (512, 768)
# A person LoRA is usually done within 1,500 - 2,500 steps (at batch size 1); the
# dashboard suggests an epoch count that lands near this for the dataset's size.
TARGET_TOTAL_STEPS = 2000

_EPOCH_RE = re.compile(r"epoch\s+(\d+)\s*/\s*(\d+)", re.IGNORECASE)
_STEP_RE = re.compile(r"steps:\s*\d+%\|.*\|\s*(\d+)/(\d+)")
# Any tqdm bar, e.g. "100%|##########| 51/51 [00:05<00:00,  9.10it/s]" (latent caching has no desc).
_BAR_RE = re.compile(r"\d+%\|.*\|\s*(\d+)/(\d+)")
_RATE_RE = re.compile(r"(\d+(?:\.\d+)?)\s*(it/s|s/it)")
_LOSS_RE = re.compile(r"avr_loss=([-+]?\d+(?:\.\d*)?(?:e[-+]?\d+)?|nan|inf)", re.IGNORECASE)
# The one-line job message, for jobs saved before `details` existed.
_MESSAGE_PROGRESS_RE = re.compile(r"epoch (\d+)/(\d+)(?: — step (\d+)/(\d+))?")
_REPEATS_DIR_RE = re.compile(r"^(\d+)_")

STAGE_LAUNCHING = "Launching sd-scripts (Python + torch)"
STAGE_TRAINING = "Training"
# sd-scripts log lines that open a new stage, in the order they normally appear. Loading the model and
# caching latents print little for a minute or more; naming the stage keeps that from looking like a hang.
_STAGE_MARKERS = (
    ("prepare images", "Reading the dataset"),
    ("make buckets", "Grouping images into resolution buckets"),
    ("preparing accelerator", "Starting CUDA / accelerate"),
    ("load stablediffusion checkpoint", "Loading the base model"),
    ("loading u-net", "Loading the base model"),
    ("caching latents", "Caching latents (VAE-encoding each image once)"),
    ("import network module", "Building the LoRA network"),
    ("prepare optimizer", "Preparing the optimizer"),
    ("load train state", "Loading the saved training state"),
    ("running training", "Starting the training loop"),
    ("saving checkpoint", "Saving this epoch's LoRA"),
    ("saving state", "Saving the training state"),
    ("model saved", "Saving the final LoRA"),
)
_IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}  # sd-scripts' library/dataset.py list
# accelerate's save_state writes this file last, so a state folder without it was cut off mid-save.
_STATE_COMPLETE_MARKER = "random_states_0.pkl"


def samples_per_epoch(train_data_dir) -> int:
    """Images x repeats over every "{repeats}_{name}" subfolder sd-scripts trains from
    train_data_dir (like sd-scripts, folders without a repeats prefix are ignored)."""
    samples = 0
    for subdir in Path(train_data_dir).iterdir():
        match = _REPEATS_DIR_RE.match(subdir.name)
        if subdir.is_dir() and match:
            images = sum(1 for p in subdir.iterdir() if p.suffix.lower() in _IMAGE_EXTENSIONS)
            samples += images * int(match.group(1))
    return samples


def training_run_dir(job) -> Path:
    """The job's own sd-scripts output folder: epoch snapshots plus the states a resume continues from."""
    return Path(job.params["output_dir"]) / "runs" / job.id


def latest_resume_state(run_dir, output_name: str) -> Optional[Tuple[int, Path]]:
    """(finished epoch, state folder) for the newest completely saved epoch state in run_dir, or None."""
    state_name_re = re.compile(re.escape(output_name) + r"-(\d+)-state")
    latest = None
    if Path(run_dir).is_dir():
        for state_dir in Path(run_dir).iterdir():
            match = state_name_re.fullmatch(state_dir.name)
            if match and (state_dir / _STATE_COMPLETE_MARKER).exists():
                epoch = int(match.group(1))
                if latest is None or epoch > latest[0]:
                    latest = (epoch, state_dir)
    return latest


def can_resume_training(job, manager) -> bool:
    """True for a train_lora job that failed, or that is still marked running although no queue
    worker is alive any more (e.g. the PC restarted mid-run)."""
    if job.job_type != "train_lora":
        return False
    return job.status == JobStatus.FAILED or (job.status == JobStatus.RUNNING and not manager.is_worker_running())


def resume_training_job(job, manager):
    """Re-queues the job; run_training then continues from its newest epoch state instead of starting over."""
    job.status = JobStatus.QUEUED
    job.message = "▶️ Queued to resume"
    manager.save_job(job)


def training_log_path(job) -> Path:
    """Everything sd-scripts printed for this job, appended across resumes."""
    return training_run_dir(job) / "train.log"


def read_log_tail(path, max_lines: int = 40) -> str:
    """Last lines of a log that may still be growing, without reading the whole file."""
    path = Path(path)
    if not path.exists():
        return ""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - 64_000))
        text = f.read().decode("utf-8", errors="replace")
    return "\n".join(text.splitlines()[-max_lines:])


def update_training_state(state: dict, line: str, resumed_epochs: int = 0) -> Optional[str]:
    """Folds one line of sd-scripts output into state (the job's `details`).

    Returns "stage" when the run entered a new stage or epoch (worth saving at once), "progress" for a
    progress-bar tick (fine to save throttled), or None when the line changed nothing.
    """
    now = datetime.now().isoformat()

    def enter(stage) -> bool:
        if state.get("stage") == stage:
            return False
        state.update(stage=stage, stage_started_at=now)
        state.pop("stage_done", None)
        state.pop("stage_total", None)
        return True

    step_match = _STEP_RE.search(line)
    if step_match:
        # sd-scripts' step counter runs across all epochs, not per epoch. After a resume it
        # restarts from 0 while its total still spans the whole run, so add the done epochs back.
        step, total_steps = int(step_match.group(1)), int(step_match.group(2))
        step += resumed_epochs * (total_steps // max(state.get("total_epochs") or 1, 1))
        state.update(step=step, total_steps=total_steps, updated_at=now)
        rate = _RATE_RE.search(line)
        if rate and float(rate.group(1)) > 0:
            value = float(rate.group(1))
            state["sec_per_step"] = value if rate.group(2) == "s/it" else 1.0 / value
        loss = _LOSS_RE.search(line)
        if loss:
            state["loss"] = float(loss.group(1))
        return "stage" if enter(STAGE_TRAINING) else "progress"

    epoch_match = _EPOCH_RE.search(line)
    if epoch_match:
        state.update(epoch=int(epoch_match.group(1)), total_epochs=int(epoch_match.group(2)))
        enter(STAGE_TRAINING)
        return "stage"

    bar_match = _BAR_RE.search(line)
    if bar_match:
        if state.get("stage") in (None, STAGE_TRAINING):
            return None
        state.update(stage_done=int(bar_match.group(1)), stage_total=int(bar_match.group(2)), updated_at=now)
        return "progress"

    lowered = line.lower()
    for marker, stage in _STAGE_MARKERS:
        if marker in lowered:
            return "stage" if enter(stage) else None
    return None


def describe_training_state(state: dict) -> str:
    """The one-line job message for the current `details`."""
    stage = state.get("stage") or STAGE_LAUNCHING
    if stage == STAGE_TRAINING:
        text = f"Training epoch {state.get('epoch', '?')}/{state.get('total_epochs', '?')}"
        if state.get("total_steps"):
            text += f" — step {state['step']}/{state['total_steps']}"
        return text
    if state.get("stage_total"):
        return f"{stage} — {state['stage_done']}/{state['stage_total']}"
    return f"{stage}..."


def training_view(job, manager, now: Optional[datetime] = None) -> dict:
    """What the dashboard shows for a train_lora job: its live `details` plus derived timings in
    seconds (None when unknown) and the LoRA snapshots saved so far."""
    now = now or datetime.now()
    view = dict(job.details or {})
    if "step" not in view:
        match = _MESSAGE_PROGRESS_RE.search(job.message or "")
        if match:
            view.setdefault("epoch", int(match.group(1)))
            view.setdefault("total_epochs", int(match.group(2)))
            if match.group(3):
                view["step"], view["total_steps"] = int(match.group(3)), int(match.group(4))

    def seconds_since(iso):
        return (now - datetime.fromisoformat(iso)).total_seconds() if iso else None

    view["queued_seconds"] = seconds_since(job.created_at)
    view["stage_seconds"] = seconds_since(view.get("stage_started_at"))
    if job.started_at and job.completed_at:
        view["elapsed_seconds"] = (datetime.fromisoformat(job.completed_at) - datetime.fromisoformat(job.started_at)).total_seconds()
    else:
        view["elapsed_seconds"] = seconds_since(job.started_at)

    view["eta_seconds"], view["eta_is_rough"] = None, False
    if job.status == JobStatus.RUNNING and view.get("total_steps"):
        steps_left = max(view["total_steps"] - view["step"], 0)
        if view.get("sec_per_step"):
            view["eta_seconds"] = max(steps_left * view["sec_per_step"] - (seconds_since(view.get("updated_at")) or 0), 0)
        elif view["step"] and view["elapsed_seconds"]:
            # No measured speed (job saved before `details` existed): extrapolate from the run so far, start-up included.
            view["eta_seconds"] = view["elapsed_seconds"] * steps_left / view["step"]
            view["eta_is_rough"] = True

    # The job file is rewritten on every progress tick and the log on every line, so their newest
    # modification time is the last sign of life from the run.
    heartbeats = []
    for path in (manager._job_file(job.id), training_log_path(job)):
        try:
            heartbeats.append(path.stat().st_mtime)
        except OSError:
            pass
    view["idle_seconds"] = now.timestamp() - max(heartbeats) if heartbeats else None

    view["saved_files"] = []
    run_dir = training_run_dir(job)
    if run_dir.is_dir():
        for path in sorted(run_dir.glob("*.safetensors")):
            try:
                view["saved_files"].append((path.name, path.stat().st_size / 2**20))
            except OSError:  # sd-scripts removed an old snapshot between the glob and the stat
                pass
    return view


class _TrainingLog:
    """train.log in the run folder. Progress bars redraw several times a second, so those are thinned
    to one line every BAR_INTERVAL seconds (plus the last one before any other line) to stay readable."""

    BAR_INTERVAL = 10.0

    def __init__(self, path):
        self._file = open(path, "a", encoding="utf-8")
        self._pending_bar = None
        self._last_bar = 0.0

    def write(self, line: str):
        if _BAR_RE.search(line):
            if time.monotonic() - self._last_bar < self.BAR_INTERVAL:
                self._pending_bar = line
                return
            self._last_bar = time.monotonic()
        elif self._pending_bar:
            self._file.write(self._pending_bar + "\n")
        self._pending_bar = None
        self._file.write(line + "\n")
        self._file.flush()

    def close(self):
        if self._pending_bar:
            self._file.write(self._pending_bar + "\n")
        self._file.close()


def build_training_args(dataset_dir: str, output_dir: str, output_name: str, base_checkpoint: str,
                         epochs: int = DEFAULT_EPOCHS, network_dim: int = DEFAULT_NETWORK_DIM,
                         network_alpha: int = DEFAULT_NETWORK_ALPHA, learning_rate: float = DEFAULT_LEARNING_RATE,
                         batch_size: int = DEFAULT_BATCH_SIZE, max_resolution: int = DEFAULT_MAX_RESOLUTION,
                         resume_state: Optional[str] = None, resumed_epochs: int = 0) -> list:
    """Returns the CLI argument list (no interpreter/script) for sd-scripts' train_network.py."""
    # train_data_dir must be the PARENT of the "{repeats}_{trigger} person" folder.
    train_data_dir = str(Path(dataset_dir).parent)
    args = [
        "--pretrained_model_name_or_path", base_checkpoint,
        "--train_data_dir", train_data_dir,
        "--output_dir", output_dir,
        "--output_name", output_name,
        "--network_module", "networks.lora",
        "--network_dim", str(network_dim),
        "--network_alpha", str(network_alpha),
        "--network_train_unet_only",
        "--train_batch_size", str(batch_size),
        "--max_train_epochs", str(epochs),
        "--learning_rate", str(learning_rate),
        "--lr_scheduler", "cosine_with_restarts",
        "--lr_warmup_steps", "100",
        "--mixed_precision", "fp16",
        "--gradient_checkpointing",
        # Memory-efficient attention. Without it every attention layer materialises a full
        # tokens x tokens matrix (several GB at 768px): on a 6 GB card the Windows driver
        # silently spills VRAM into system RAM (~10 s/step) until it finally hits CUDA OOM.
        "--sdpa",
        "--optimizer_type", "AdamW8bit",
        "--caption_extension", ".txt",
        "--shuffle_caption",
        "--keep_tokens", "1",
        "--enable_bucket",
        "--min_bucket_reso", "256",
        "--max_bucket_reso", str(max_resolution),
        "--resolution", str(max_resolution),
        "--cache_latents",
        # Latents are cached, so one persistent loader worker is plenty; the default of 8
        # worker processes is re-spawned (re-importing torch) at every epoch on Windows.
        "--max_data_loader_n_workers", "1",
        "--persistent_data_loader_workers",
        # Keep the LoRA from each finished epoch ({output_name}-00000N) so a crash late
        # in a long run doesn't throw all of it away. The final file is still {output_name}.
        "--save_every_n_epochs", "1",
        "--save_last_n_epochs", "3",
        # ...plus the training state beside it ({output_name}-00000N-state: LoRA weights, optimizer,
        # lr scheduler, RNG), which is what a resume continues from. Only the newest one is kept.
        "--save_state",
        "--save_last_n_epochs_state", "1",
        "--save_model_as", "safetensors",
    ]
    if resume_state:
        # Name the epoch explicitly rather than trusting the step count sd-scripts keeps in the
        # state: that count restarts from 0 after a resume, so a second resume would repeat an epoch.
        args += ["--resume", resume_state, "--initial_epoch", str(resumed_epochs + 1)]
    return args


def run_training(job, manager) -> bool:
    """Entry point called from job_manager.run_single_job for job_type == 'train_lora'."""
    import shutil
    import subprocess

    params = job.params
    run_dir = training_run_dir(job)
    resume = latest_resume_state(run_dir, params["output_name"])
    resumed_epochs = resume[0] if resume else 0

    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.completed_at = None
    job.message = f"Resuming LoRA training after epoch {resumed_epochs}..." if resume else "Starting LoRA training..."
    job.error = None
    job.details = {"stage": STAGE_LAUNCHING, "stage_started_at": job.started_at,
                   "epoch": resumed_epochs + 1, "total_epochs": params.get("epochs", DEFAULT_EPOCHS)}
    manager.save_job(job)

    if not VENV_LORA_PYTHON.exists() or not SD_SCRIPTS_TRAIN_SCRIPT.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ venv_lora / sd-scripts not set up"
        job.error = (
            f"Expected {VENV_LORA_PYTHON} and {SD_SCRIPTS_TRAIN_SCRIPT} to exist. "
            "Run the one-time setup in docs/superpowers/plans/2026-08-02-character-lora-pipeline.md (Task 10)."
        )
        manager.save_job(job)
        return False

    output_dir = Path(params["output_dir"])
    run_dir.mkdir(parents=True, exist_ok=True)

    args = build_training_args(
        dataset_dir=params["dataset_dir"], output_dir=str(run_dir), output_name=params["output_name"],
        base_checkpoint=params["base_checkpoint"], epochs=params.get("epochs", DEFAULT_EPOCHS),
        network_dim=params.get("network_dim", DEFAULT_NETWORK_DIM), network_alpha=params.get("network_alpha", DEFAULT_NETWORK_ALPHA),
        learning_rate=params.get("learning_rate", DEFAULT_LEARNING_RATE), batch_size=params.get("batch_size", DEFAULT_BATCH_SIZE),
        max_resolution=params.get("max_resolution", DEFAULT_MAX_RESOLUTION),
        resume_state=str(resume[1]) if resume else None, resumed_epochs=resumed_epochs,
    )

    cmd = [str(VENV_LORA_PYTHON), str(SD_SCRIPTS_TRAIN_SCRIPT)] + args
    print(f"[JOB {job.id}] Launching: {' '.join(cmd)}")

    # sd-scripts/accelerate print Unicode glyphs that crash on Windows'
    # default cp1252 console encoding (confirmed via train_network.py --help)
    # - force UTF-8 on both the child's stdout and how we decode it here.
    # PYTHONUNBUFFERED: the "epoch N/M" lines go to stdout, which is block-buffered
    # when piped, so without it they only arrive when the process exits.
    child_env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUNBUFFERED="1")
    process = subprocess.Popen(cmd, cwd=str(SD_SCRIPTS_DIR), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                bufsize=1, env=child_env)

    log = _TrainingLog(training_log_path(job))
    log.write(f"===== {datetime.now():%Y-%m-%d %H:%M:%S} "
              f"{f'resuming after epoch {resumed_epochs}' if resume else 'new run'} =====")
    log.write(" ".join(cmd))

    log_lines = []
    last_save = time.monotonic()
    try:
        for line in process.stdout:
            line = line.rstrip("\n")
            log_lines.append(line)
            log.write(line)
            print(f"[JOB {job.id}] {line.rstrip()}")

            try:
                change = update_training_state(job.details, line, resumed_epochs)
            except Exception as e:  # a display-only parsing slip must never abort (and kill) a long training run
                print(f"[JOB {job.id}] could not parse progress line: {e}")
                change = None
            if change is None:
                continue
            if job.details.get("total_steps"):
                job.progress = min(0.99, job.details["step"] / max(job.details["total_steps"], 1))
            job.message = describe_training_state(job.details)
            # A new stage is saved at once; progress-bar ticks at most once a second.
            if change == "stage" or time.monotonic() - last_save >= 1.0:
                manager.save_job(job)
                last_save = time.monotonic()
    finally:
        # If anything above raises (e.g. another stdout-encoding surprise), don't leave
        # train_network.py orphaned and blocked writing to a pipe nobody is draining.
        if process.poll() is None:
            process.kill()
        process.wait()
        log.write(f"===== sd-scripts exited with code {process.returncode} =====")
        log.close()

    if process.returncode != 0:
        job.status = JobStatus.FAILED
        job.message = "❌ sd-scripts training failed"
        job.error = "\n".join(log_lines[-50:])
        job.completed_at = datetime.now().isoformat()
        manager.save_job(job)
        print(f"[JOB {job.id}] ❌ FAILED (exit code {process.returncode})")
        return False

    final_file = run_dir / f"{params['output_name']}.safetensors"
    if not final_file.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ Training finished but no .safetensors was produced"
        job.completed_at = datetime.now().isoformat()
        job.error = "\n".join(log_lines[-50:])
        manager.save_job(job)
        return False

    trained_file = output_dir / final_file.name
    try:
        os.replace(final_file, trained_file)
    except OSError:
        # A previous LoRA of that name is open in another program (Windows locks it); keep the new one in the run folder.
        trained_file = final_file
    # Training states only matter for resuming an unfinished run (this also removes the end-of-training
    # state sd-scripts writes under --save_state); the per-epoch LoRA snapshots stay in the run folder.
    for state_dir in run_dir.glob("*-state"):
        shutil.rmtree(state_dir, ignore_errors=True)

    if params.get("person_id") is not None:
        set_person_lora_info(params["person_id"], lora_path=str(trained_file))

    job.status = JobStatus.COMPLETED
    job.progress = 1.0
    job.completed_at = datetime.now().isoformat()
    job.message = f"✅ LoRA trained: {trained_file}"
    job.result_path = str(trained_file)
    manager.save_job(job)
    print(f"[JOB {job.id}] ✅ COMPLETED: {trained_file}")
    return True
