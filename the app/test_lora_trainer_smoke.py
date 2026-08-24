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
    ]
    missing = [f for f in required_flags if f not in args]
    if missing:
        print(f"build_training_args is missing required flags: {missing}")
        exit(1)

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
