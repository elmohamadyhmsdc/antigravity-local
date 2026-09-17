try:
    from lora_trainer import build_training_args, VENV_LORA_PYTHON, SD_SCRIPTS_TRAIN_SCRIPT

    args = build_training_args(
        dataset_dir="lora_datasets/example/20_sks1 person",
        output_dir="models/loras",
        output_name="example",
        base_checkpoint="models/sd15_realistic_base.safetensors",
        epochs=10,
        network_dim=32,
        network_alpha=16,
        learning_rate=0.0001,
        batch_size=1,
    )

    required_flags = [
        "--pretrained_model_name_or_path", "--train_data_dir", "--output_dir",
        "--output_name", "--network_module", "--network_dim", "--network_alpha",
        "--train_batch_size", "--max_train_epochs", "--learning_rate",
        "--mixed_precision", "--gradient_checkpointing", "--enable_bucket",
        "--save_model_as",
        # Without --sdpa, attention at 768px overflows a 6 GB card (~10 s/step, then CUDA OOM).
        "--sdpa", "--save_every_n_epochs",
        # The per-epoch state is what the dashboard's Resume button continues from.
        "--save_state",
    ]
    missing = [f for f in required_flags if f not in args]
    if missing:
        print(f"build_training_args is missing required flags: {missing}")
        exit(1)
    if "--resume" in args or "--initial_epoch" in args:
        print(f"A fresh run must not pass --resume/--initial_epoch: {args}")
        exit(1)

    resume_args = build_training_args(
        dataset_dir="lora_datasets/example/20_sks1 person",
        output_dir="models/loras/runs/abc12345",
        output_name="example",
        base_checkpoint="models/sd15_realistic_base.safetensors",
        resume_state="models/loras/runs/abc12345/example-000002-state",
        resumed_epochs=2,
    )
    expected_tail = ["--resume", "models/loras/runs/abc12345/example-000002-state", "--initial_epoch", "3"]
    if resume_args[-4:] != expected_tail:
        print(f"Resuming after epoch 2 should end with {expected_tail}, got {resume_args[-4:]}")
        exit(1)

    # --- lora_trainer.py: step-count math matches how sd-scripts reads the dataset folders ---
    import tempfile
    from pathlib import Path
    from lora_trainer import samples_per_epoch

    with tempfile.TemporaryDirectory() as root:
        subset = Path(root) / "20_sks1 person"
        subset.mkdir()
        for name in ("a.jpg", "b.JPG", "c.png"):
            (subset / name).write_bytes(b"")
        (subset / "a.txt").write_text("sks1 person")
        (Path(root) / "no_repeats_prefix").mkdir()  # sd-scripts ignores this folder
        (Path(root) / "no_repeats_prefix" / "d.jpg").write_bytes(b"")

        samples = samples_per_epoch(root)
        if samples != 60:
            print(f"samples_per_epoch should count 3 images x 20 repeats = 60, got {samples}")
            exit(1)
    print("samples_per_epoch verification successful!")

    # --- lora_trainer.py: resume picks the newest fully saved epoch state of a failed/interrupted job ---
    from job_manager import Job, JobManager, JobStatus
    from lora_trainer import latest_resume_state, can_resume_training

    with tempfile.TemporaryDirectory() as run_dir:
        # epoch 2 was cut off mid-save (no RNG file, which accelerate writes last); "other" is another person
        for state_name, fully_saved in (("example-000001-state", True), ("example-000002-state", False),
                                        ("other-000005-state", True), ("example-state", True)):
            (Path(run_dir) / state_name).mkdir()
            if fully_saved:
                (Path(run_dir) / state_name / "random_states_0.pkl").write_bytes(b"")

        latest = latest_resume_state(run_dir, "example")
        if latest is None or latest[0] != 1:
            print(f"latest_resume_state should pick epoch 1 (skip the half-saved epoch 2 and other states), got {latest}")
            exit(1)
        if latest_resume_state(Path(run_dir) / "missing", "example") is not None:
            print("latest_resume_state should return None when the run folder doesn't exist")
            exit(1)

    with tempfile.TemporaryDirectory() as jobs_dir:
        manager = JobManager(jobs_dir)  # no worker pid file here, so no queue worker counts as alive
        cases = [
            ("train_lora", JobStatus.FAILED, True),
            ("train_lora", JobStatus.RUNNING, True),  # still marked running, but its worker is gone
            ("train_lora", JobStatus.COMPLETED, False),
            ("train_lora", JobStatus.QUEUED, False),
            ("reface_video_v3", JobStatus.FAILED, False),
        ]
        for job_type, status, expected in cases:
            job = Job(id="abc12345", job_type=job_type, status=status, progress=0.0, message="", created_at="", params={})
            if can_resume_training(job, manager) != expected:
                print(f"can_resume_training({job_type}, {status.value}) should be {expected}")
                exit(1)
    print("Resume helpers verification successful!")

    if "networks.lora" not in args:
        print(f"Expected network_module 'networks.lora' in args: {args}")
        exit(1)
    if "safetensors" not in args:
        print(f"Expected --save_model_as safetensors in args: {args}")
        exit(1)

    print(f"VENV_LORA_PYTHON path configured as: {VENV_LORA_PYTHON}")
    print(f"SD_SCRIPTS_TRAIN_SCRIPT path configured as: {SD_SCRIPTS_TRAIN_SCRIPT}")
    print("Task 9 verification successful! build_training_args produces a well-formed CLI argument list.")

    # --- lora_generate.py: prompt template defaults ---
    from lora_generate import DEFAULT_PROMPT_TEMPLATE, DEFAULT_NEGATIVE_PROMPT

    if "{trigger}" not in DEFAULT_PROMPT_TEMPLATE:
        print(f"DEFAULT_PROMPT_TEMPLATE must contain a {{trigger}} placeholder: {DEFAULT_PROMPT_TEMPLATE!r}")
        exit(1)
    if "flat studio lighting" not in DEFAULT_PROMPT_TEMPLATE:
        print(f"DEFAULT_PROMPT_TEMPLATE should request flat studio lighting per the master-reference recipe: {DEFAULT_PROMPT_TEMPLATE!r}")
        exit(1)
    if not DEFAULT_NEGATIVE_PROMPT:
        print("DEFAULT_NEGATIVE_PROMPT should not be empty")
        exit(1)

    print("lora_generate.py verification successful! Prompt templates are well-formed.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
