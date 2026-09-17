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

import re
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
# A person LoRA is usually done within a few thousand steps (at batch size 1); the
# dashboard suggests an epoch count that lands near this for the dataset's size.
TARGET_TOTAL_STEPS = 3000

_EPOCH_RE = re.compile(r"epoch\s+(\d+)\s*/\s*(\d+)", re.IGNORECASE)
_STEP_RE = re.compile(r"steps:\s*\d+%\|.*\|\s*(\d+)/(\d+)")
_REPEATS_DIR_RE = re.compile(r"^(\d+)_")
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
        "--train_batch_size", str(batch_size),
        "--max_train_epochs", str(epochs),
        "--learning_rate", str(learning_rate),
        "--mixed_precision", "fp16",
        "--gradient_checkpointing",
        # Memory-efficient attention. Without it every attention layer materialises a full
        # tokens x tokens matrix (several GB at 768px): on a 6 GB card the Windows driver
        # silently spills VRAM into system RAM (~10 s/step) until it finally hits CUDA OOM.
        "--sdpa",
        "--optimizer_type", "AdamW8bit",
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
    import os
    import shutil
    import subprocess
    from datetime import datetime

    params = job.params
    run_dir = training_run_dir(job)
    resume = latest_resume_state(run_dir, params["output_name"])
    resumed_epochs = resume[0] if resume else 0

    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.message = f"Resuming LoRA training after epoch {resumed_epochs}..." if resume else "Starting LoRA training..."
    job.error = None
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
    total_epochs = params.get("epochs", DEFAULT_EPOCHS)

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

    log_lines = []
    current_epoch = resumed_epochs
    try:
        for line in process.stdout:
            log_lines.append(line.rstrip("\n"))
            print(f"[JOB {job.id}] {line.rstrip()}")

            epoch_match = _EPOCH_RE.search(line)
            if epoch_match:
                current_epoch, total_epochs = int(epoch_match.group(1)), int(epoch_match.group(2))
                job.message = f"Training epoch {current_epoch}/{total_epochs}"
                manager.save_job(job)
                continue

            step_match = _STEP_RE.search(line)
            if step_match:
                # sd-scripts' step counter runs across all epochs, not per epoch. After a resume it
                # restarts from 0 while its total still spans the whole run, so add the done epochs back.
                step, total_steps = int(step_match.group(1)), int(step_match.group(2))
                step += resumed_epochs * (total_steps // max(total_epochs, 1))
                job.progress = min(0.99, step / max(total_steps, 1))
                job.message = f"Training epoch {current_epoch}/{total_epochs} — step {step}/{total_steps}"
                manager.save_job(job)
    finally:
        # If anything above raises (e.g. another stdout-encoding surprise), don't leave
        # train_network.py orphaned and blocked writing to a pipe nobody is draining.
        if process.poll() is None:
            process.kill()
        process.wait()

    if process.returncode != 0:
        job.status = JobStatus.FAILED
        job.message = "❌ sd-scripts training failed"
        job.error = "\n".join(log_lines[-50:])
        manager.save_job(job)
        print(f"[JOB {job.id}] ❌ FAILED (exit code {process.returncode})")
        return False

    final_file = run_dir / f"{params['output_name']}.safetensors"
    if not final_file.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ Training finished but no .safetensors was produced"
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
