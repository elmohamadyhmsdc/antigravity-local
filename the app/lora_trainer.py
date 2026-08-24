"""
Antigravity Local - LoRA training dispatcher

Builds the sd-scripts (kohya-ss/sd-scripts) CLI invocation for a per-person
SD1.5 LoRA and runs it as a subprocess inside the isolated `venv_lora`
environment (Python 3.10), mirroring how undress_engine.py is invoked inside
venv_ai. Only the argument-building and subprocess/progress-parsing logic
lives in the main venv; the actual training code is sd-scripts itself.
"""

import re
from pathlib import Path

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
DEFAULT_MAX_RESOLUTION = 768

_EPOCH_RE = re.compile(r"epoch\s+(\d+)\s*/\s*(\d+)", re.IGNORECASE)
_STEP_RE = re.compile(r"steps:\s*\d+%\|.*\|\s*(\d+)/(\d+)")


def build_training_args(dataset_dir: str, output_dir: str, output_name: str, base_checkpoint: str,
                         epochs: int = DEFAULT_EPOCHS, network_dim: int = DEFAULT_NETWORK_DIM,
                         network_alpha: int = DEFAULT_NETWORK_ALPHA, learning_rate: float = DEFAULT_LEARNING_RATE,
                         batch_size: int = DEFAULT_BATCH_SIZE, max_resolution: int = DEFAULT_MAX_RESOLUTION) -> list:
    """Returns the CLI argument list (no interpreter/script) for sd-scripts' train_network.py."""
    # train_data_dir must be the PARENT of the "{repeats}_{trigger} person" folder.
    train_data_dir = str(Path(dataset_dir).parent)
    return [
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
        "--optimizer_type", "AdamW8bit",
        "--enable_bucket",
        "--min_bucket_reso", "256",
        "--max_bucket_reso", str(max_resolution),
        "--resolution", str(max_resolution),
        "--cache_latents",
        "--save_model_as", "safetensors",
    ]


def run_training(job, manager) -> bool:
    """Entry point called from job_manager.run_single_job for job_type == 'train_lora'."""
    import subprocess
    from datetime import datetime

    params = job.params
    job.status = JobStatus.RUNNING
    job.started_at = datetime.now().isoformat()
    job.message = "Starting LoRA training..."
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
    output_dir.mkdir(parents=True, exist_ok=True)

    args = build_training_args(
        dataset_dir=params["dataset_dir"], output_dir=str(output_dir), output_name=params["output_name"],
        base_checkpoint=params["base_checkpoint"], epochs=params.get("epochs", DEFAULT_EPOCHS),
        network_dim=params.get("network_dim", DEFAULT_NETWORK_DIM), network_alpha=params.get("network_alpha", DEFAULT_NETWORK_ALPHA),
        learning_rate=params.get("learning_rate", DEFAULT_LEARNING_RATE), batch_size=params.get("batch_size", DEFAULT_BATCH_SIZE),
        max_resolution=params.get("max_resolution", DEFAULT_MAX_RESOLUTION),
    )
    total_epochs = params.get("epochs", DEFAULT_EPOCHS)

    cmd = [str(VENV_LORA_PYTHON), str(SD_SCRIPTS_TRAIN_SCRIPT)] + args
    print(f"[JOB {job.id}] Launching: {' '.join(cmd)}")

    # sd-scripts/accelerate print Unicode glyphs that crash on Windows'
    # default cp1252 console encoding (confirmed via train_network.py --help)
    # - force UTF-8 on both the child's stdout and how we decode it here.
    import os
    child_env = dict(os.environ, PYTHONIOENCODING="utf-8")
    process = subprocess.Popen(cmd, cwd=str(SD_SCRIPTS_DIR), stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
                                bufsize=1, env=child_env)

    log_lines = []
    current_epoch = 0
    try:
        for line in process.stdout:
            log_lines.append(line.rstrip("\n"))
            print(f"[JOB {job.id}] {line.rstrip()}")

            epoch_match = _EPOCH_RE.search(line)
            if epoch_match:
                current_epoch, total_epochs = int(epoch_match.group(1)), int(epoch_match.group(2))
                job.progress = min(0.99, current_epoch / max(total_epochs, 1))
                job.message = f"Training epoch {current_epoch}/{total_epochs}"
                manager.save_job(job)
                continue

            step_match = _STEP_RE.search(line)
            if step_match:
                step, total_steps = int(step_match.group(1)), int(step_match.group(2))
                epoch_fraction = (step / max(total_steps, 1)) / max(total_epochs, 1)
                job.progress = min(0.99, (current_epoch / max(total_epochs, 1)) + epoch_fraction)
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

    trained_file = output_dir / f"{params['output_name']}.safetensors"
    if not trained_file.exists():
        job.status = JobStatus.FAILED
        job.message = "❌ Training finished but no .safetensors was produced"
        job.error = "\n".join(log_lines[-50:])
        manager.save_job(job)
        return False

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
