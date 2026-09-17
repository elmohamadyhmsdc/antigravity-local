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

    # --- lora_trainer.py: live stage/progress parsing of sd-scripts output (what the dashboard shows) ---
    from datetime import datetime, timedelta
    from lora_trainer import (update_training_state, describe_training_state, read_log_tail, training_view,
                              STAGE_TRAINING, _TrainingLog)

    state = {"epoch": 1, "total_epochs": 3}
    feed = [
        ("2026-09-17 10:07:01 INFO     load StableDiffusion checkpoint: models/sd15.safetensors  model_io.py:361", "stage", "Loading the base model..."),
        ("                    INFO     loading u-net: <All keys matched successfully>           model_util.py:1017", None, "Loading the base model..."),
        ("                    INFO     caching latents...                                       dataset.py:802", "stage", None),
        (" 39%|###9      | 20/51 [00:02<00:03,  9.10it/s]", "progress", None),
        ("some unrelated line", None, None),
        ("running training / 学習開始", "stage", "Starting the training loop..."),
        ("steps:   0%|          | 0/3060 [00:00<?, ?it/s]", "stage", "Training epoch 1/3 — step 0/3060"),
        ("epoch 1/3", "stage", "Training epoch 1/3 — step 0/3060"),
        ("steps:  19%|█▉        | 589/3060 [05:12<21:50,  1.89it/s, avr_loss=0.0912]", "progress", "Training epoch 1/3 — step 589/3060"),
    ]
    for line, expected_change, expected_message in feed:
        change = update_training_state(state, line)
        if change != expected_change:
            print(f"update_training_state({line!r}) should return {expected_change!r}, got {change!r}")
            exit(1)
        if expected_message and describe_training_state(state) != expected_message:
            print(f"After {line!r} the message should be {expected_message!r}, got {describe_training_state(state)!r}")
            exit(1)
        if line.startswith(" 39%") and (state.get("stage_done"), state.get("stage_total")) != (20, 51):
            print(f"The latent-caching bar should record 20/51, got {state}")
            exit(1)
    if state["stage"] != STAGE_TRAINING or "stage_total" in state:
        print(f"Entering training should drop the caching bar's counts: {state}")
        exit(1)
    if state["loss"] != 0.0912 or abs(state["sec_per_step"] - 1 / 1.89) > 1e-9:
        print(f"Loss and speed should come from the step bar: {state}")
        exit(1)

    slow = {"total_epochs": 3}
    update_training_state(slow, "steps:  50%|#####     | 10/20 [00:50<00:50,  5.00s/it, avr_loss=0.1]")
    if slow["sec_per_step"] != 5.0:
        print(f"A 's/it' rate is already seconds per step: {slow}")
        exit(1)
    resumed = {"total_epochs": 3}
    update_training_state(resumed, "steps:   0%|          | 0/3060 [00:00<?, ?it/s]", resumed_epochs=2)
    if resumed["step"] != 2040:
        print(f"After resuming past 2 of 3 epochs, step 0 should read as 2040, got {resumed['step']}")
        exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "train.log"
        log_path.write_text("\n".join(f"line {i}" for i in range(100)), encoding="utf-8")
        tail = read_log_tail(log_path).splitlines()
        if len(tail) != 40 or tail[-1] != "line 99":
            print(f"read_log_tail should return the last 40 lines, got {len(tail)} ending {tail[-1:]}")
            exit(1)
        if read_log_tail(Path(tmp) / "missing.log") != "":
            print("read_log_tail should return '' for a missing log")
            exit(1)

        thinned_path = Path(tmp) / "thinned.log"
        log = _TrainingLog(thinned_path)
        for step in range(6):  # redraws within BAR_INTERVAL: only the first and the last one are kept
            log.write(f"steps:  {step}%|          | {step}/3060 [00:00<?, ?it/s]")
        log.write("saving checkpoint: example-000001.safetensors")
        log.close()
        kept = thinned_path.read_text(encoding="utf-8").splitlines()
        if len(kept) != 3 or "| 0/3060" not in kept[0] or "| 5/3060" not in kept[1]:
            print(f"_TrainingLog should keep the first bar, the last bar before a normal line, and that line: {kept}")
            exit(1)

        # A job saved before `details` existed: epoch/step come from its message, the ETA is extrapolated.
        now = datetime(2026, 9, 17, 12, 0, 0)
        old_job = Job(id="abc12345", job_type="train_lora", status=JobStatus.RUNNING, progress=0.19,
                      message="Training epoch 1/3 — step 589/3060", created_at=(now - timedelta(minutes=11)).isoformat(),
                      started_at=(now - timedelta(minutes=10)).isoformat(), params={"output_dir": tmp, "output_name": "example"})
        view = training_view(old_job, JobManager(tmp), now=now)
        if (view.get("epoch"), view.get("step"), view.get("total_steps")) != (1, 589, 3060):
            print(f"training_view should read epoch/step from an old job's message: {view}")
            exit(1)
        if not view["eta_is_rough"] or abs(view["eta_seconds"] - 600 * (3060 - 589) / 589) > 1e-6:
            print(f"training_view should extrapolate a rough ETA from elapsed time: {view}")
            exit(1)
    print("Training progress parsing verification successful!")

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

    # --- lora_generate.py / lora_generate_job.py: reference image ---
    import tempfile
    from types import SimpleNamespace
    from lora_generate import denoising_steps, reference_mode, reference_size, uses_img2img, uses_ip_adapter
    from lora_generate_job import generation_request, save_reference_image

    checks = [
        # (request, mode, img2img, ip_adapter, denoising steps)
        ({"steps": 30}, None, False, False, 30),
        ({"steps": 30, "reference_mode": "both"}, None, False, False, 30),  # a mode without an image is ignored
        ({"steps": 30, "reference_image": "r.png"}, "composition", True, False, 18),  # default strength 0.6
        ({"steps": 30, "reference_image": "r.png", "reference_mode": "composition", "reference_strength": 0.45}, "composition", True, False, 13),
        ({"steps": 30, "reference_image": "r.png", "reference_mode": "style", "reference_strength": 0.3}, "style", False, True, 30),
        ({"steps": 30, "reference_image": "r.png", "reference_mode": "both", "reference_strength": 0.9}, "both", True, True, 27),
    ]
    for request, mode, img2img, ip_adapter, steps in checks:
        got = (reference_mode(request), uses_img2img(request), uses_ip_adapter(request), denoising_steps(request))
        if got != (mode, img2img, ip_adapter, steps):
            print(f"Reference plan for {request} should be {(mode, img2img, ip_adapter, steps)}, got {got}")
            exit(1)

    for (w, h), expected in {(1024, 1024): (512, 512), (600, 800): (512, 680), (1080, 1920): (432, 768),
                             (4000, 3000): (680, 512), (300, 300): (512, 512), (2000, 500): (768, 192)}.items():
        if reference_size(w, h) != expected:
            print(f"reference_size({w}, {h}) should be {expected}, got {reference_size(w, h)}")
            exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        first = save_reference_image(b"fake image bytes", "Pose.JPG", Path(tmp))
        again = save_reference_image(b"fake image bytes", "renamed.jpg", Path(tmp))
        other = save_reference_image(b"other bytes", "pose.png", Path(tmp))
        if first != again or first.suffix != ".jpg" or first.read_bytes() != b"fake image bytes":
            print(f"The same upload should map to one .jpg file: {first} vs {again}")
            exit(1)
        if other == first or len(list(Path(tmp).iterdir())) != 2:
            print(f"Different uploads should get different files: {list(Path(tmp).iterdir())}")
            exit(1)

    job = SimpleNamespace(id="abc123", params={
        "person_name": "x", "base_checkpoint": "base.safetensors", "lora_path": "x.safetensors", "trigger_word": "sks",
        "prompt": "p", "negative_prompt": "n", "num_images": 2, "seed": -1, "steps": 30, "output_dir": "out",
        "reference_image": "ref.png", "reference_mode": "both", "reference_strength": 0.5, "reference_scale": 0.4})
    request = generation_request(job, Path("out"))
    for key in ("reference_image", "reference_mode", "reference_strength", "reference_scale", "steps", "file_prefix"):
        if key not in request:
            print(f"generation_request should pass {key} to lora_generate.py: {request}")
            exit(1)
    if "person_name" in request or generation_request(SimpleNamespace(id="a", params={"num_images": 1, "reference_image": None}),
                                                      Path("out")).get("reference_image", "absent") != "absent":
        print(f"generation_request should only pass generator keys that are set: {request}")
        exit(1)

    print("Reference image verification successful! Modes, step counts, sizes, saving and the job request line up.")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
