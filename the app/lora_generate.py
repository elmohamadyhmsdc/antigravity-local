"""
Antigravity Local - LoRA reference-image generation

Runs in venv_ai (Python 3.10) as a subprocess of a `generate_lora_images` job
(see lora_generate_job.py, main venv). Reads one JSON request on stdin.
Loads the base SD1.5 checkpoint + a trained per-person LoRA and produces
"master reference" portraits per the idea.txt recipe: front-facing, neutral
expression, flat studio lighting, ready for Character Creator 4 / KeenTools.

Images are generated one at a time and written to `output_dir` as soon as each
is done, so a stopped or crashed run keeps what it finished. Progress goes to
stdout as one JSON object per line behind EVENT_PREFIX; anything else printed
(diffusers warnings, loading bars) is plain log text.

torch/diffusers are imported inside main(): the dashboard imports the prompt
defaults below from the main venv, whose torch is a CPU-only build.
"""
import sys
import json
import random
import time
from pathlib import Path

DEFAULT_PROMPT_TEMPLATE = (
    "front view portrait of {trigger} person, neutral expression, closed mouth, "
    "looking straight at camera, flat studio lighting, no shadows on face, "
    "symmetrical face, highly detailed skin texture, 8k resolution, solid white background"
)
DEFAULT_NEGATIVE_PROMPT = (
    "smiling, teeth, side view, dramatic lighting, harsh shadows, glasses, "
    "hair covering forehead, blurry, deformed"
)
DEFAULT_STEPS = 30
DEFAULT_GUIDANCE = 7.5

EVENT_PREFIX = "@@lora_generate "

STAGE_LOADING_TORCH = "Starting torch / CUDA"
STAGE_LOADING_CHECKPOINT = "Loading the base checkpoint"
STAGE_LOADING_LORA = "Applying the person's LoRA"
STAGE_PREPARING_GPU = "Preparing the GPU (CPU offload + attention)"
STAGE_GENERATING = "Generating"


def emit(event: str, **fields):
    print(EVENT_PREFIX + json.dumps({"event": event, **fields}), flush=True)


def load_person_lora(pipe, lora_path):
    """pipe.load_lora_weights(lora_path), working around a diffusers/transformers mismatch.

    diffusers converts the text-encoder half of a kohya (sd-scripts) LoRA to keys under
    `text_model.encoder...`, the CLIPTextModel layout of transformers 4. transformers 5 dropped that
    `text_model` wrapper, so no key matches a module and diffusers fails in get_peft_kwargs with
    "IndexError: list index out of range". Renaming the keys (and their alphas, which set the LoRA's
    strength) to the model's real module names fixes it; the calls below are what load_lora_weights does.
    """
    state_dict, network_alphas, metadata = pipe.lora_state_dict(lora_path, return_lora_metadata=True)
    if not hasattr(pipe.text_encoder, "text_model"):
        def rename(d):
            return {k.replace("text_encoder.text_model.", "text_encoder.", 1): v for k, v in d.items()} if d else d
        state_dict, network_alphas = rename(state_dict), rename(network_alphas)
    pipe.load_lora_into_unet(state_dict, network_alphas=network_alphas, unet=pipe.unet, metadata=metadata, _pipeline=pipe)
    pipe.load_lora_into_text_encoder(state_dict, network_alphas=network_alphas, text_encoder=pipe.text_encoder,
                                     lora_scale=pipe.lora_scale, metadata=metadata, _pipeline=pipe)


def main():
    request = json.loads(sys.stdin.read())

    trigger_word = request["trigger_word"]
    prompt = request.get("prompt") or DEFAULT_PROMPT_TEMPLATE.format(trigger=trigger_word)
    negative_prompt = request.get("negative_prompt") or DEFAULT_NEGATIVE_PROMPT
    num_images = int(request.get("num_images", 1))
    steps = int(request.get("steps", DEFAULT_STEPS))
    seed = int(request.get("seed", -1))
    output_dir = Path(request["output_dir"])
    file_prefix = request.get("file_prefix", "reference")
    output_dir.mkdir(parents=True, exist_ok=True)

    emit("stage", stage=STAGE_LOADING_TORCH)
    import torch
    from diffusers import StableDiffusionPipeline, UniPCMultistepScheduler

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32
    device_info = {"device": device, "torch": torch.__version__}
    if device == "cuda":
        props = torch.cuda.get_device_properties(0)
        device_info.update(gpu=props.name, vram_gb=round(props.total_memory / 2**30, 1))
    emit("device", **device_info)

    emit("stage", stage=STAGE_LOADING_CHECKPOINT)
    pipe = StableDiffusionPipeline.from_single_file(request["base_checkpoint"], torch_dtype=dtype, safety_checker=None)
    pipe.scheduler = UniPCMultistepScheduler.from_config(pipe.scheduler.config)
    pipe.set_progress_bar_config(disable=True)  # per-step progress is reported as events instead

    emit("stage", stage=STAGE_LOADING_LORA)
    load_person_lora(pipe, request["lora_path"])

    emit("stage", stage=STAGE_PREPARING_GPU)
    if device == "cuda":
        pipe.enable_model_cpu_offload()
        try:
            pipe.enable_xformers_memory_efficient_attention()
        except Exception:
            pass  # torch 2 already uses SDPA attention when xformers isn't installed

    # One seed per image (base + index) so any single result can be regenerated on its own.
    base_seed = seed if seed != -1 else random.randint(0, 2**31 - 1 - num_images)
    emit("stage", stage=STAGE_GENERATING, total_images=num_images, steps=steps, base_seed=base_seed)

    for index in range(num_images):
        image_seed = base_seed + index
        started = time.monotonic()
        if device == "cuda":
            torch.cuda.reset_peak_memory_stats()

        def on_step_end(_pipe, step, _timestep, callback_kwargs, index=index, started=started):
            emit("step", image=index + 1, step=step + 1, steps=steps, seconds=round(time.monotonic() - started, 2))
            return callback_kwargs

        image = pipe(
            prompt, negative_prompt=negative_prompt, num_inference_steps=steps, guidance_scale=DEFAULT_GUIDANCE,
            generator=torch.Generator(device).manual_seed(image_seed), callback_on_step_end=on_step_end,
        ).images[0]

        path = output_dir / f"{file_prefix}_{index + 1:02d}_seed{image_seed}.png"
        image.save(path)
        emit("image", image=index + 1, path=str(path), seed=image_seed, seconds=round(time.monotonic() - started, 1),
             peak_vram_gb=round(torch.cuda.max_memory_allocated() / 2**30, 2) if device == "cuda" else None)

    emit("done")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        emit("error", error=f"{type(e).__name__}: {e}", traceback=traceback.format_exc())
        sys.exit(1)
