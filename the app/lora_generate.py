"""
Antigravity Local - LoRA reference-image generation

Runs in venv_ai (Python 3.10) as a subprocess of a `generate_lora_images` job
(see lora_generate_job.py, main venv). Reads one JSON request on stdin.
Loads the base SD1.5 checkpoint + a trained per-person LoRA and produces
"master reference" portraits per the idea.txt recipe: front-facing, neutral
expression, flat studio lighting, ready for Character Creator 4 / KeenTools.

An optional `reference_image` steers the result while the face still comes from
the LoRA: "composition" starts img2img from it (pose, framing, lighting),
"style" feeds it to IP-Adapter (look, clothes, colours, without copying the
layout), "both" does both. The IP-Adapter weights are the ones Magic Undress
already keeps in models/undress.

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
    "raw candid color photo portrait of {trigger} person, natural daylight, "
    "soft natural shadows, authentic skin texture, realistic facial features, "
    "shallow depth of field, 35mm film photography, highly detailed, photorealistic"
)
DEFAULT_NEGATIVE_PROMPT = (
    "doll, plastic, smooth skin, cartoon, anime, illustration, 3d render, painting, "
    "deformed, bad anatomy, bad eyes, disfigured, blurry, oversaturated, harsh contrast"
)
DEFAULT_STEPS = 30
DEFAULT_GUIDANCE = 4.5
DEFAULT_LORA_SCALE = 0.8

REFERENCE_COMPOSITION = "composition"
REFERENCE_STYLE = "style"
REFERENCE_BOTH = "both"
REFERENCE_MODES = {
    REFERENCE_COMPOSITION: "Pose & composition",
    REFERENCE_STYLE: "Style & look",
    REFERENCE_BOTH: "Both",
}
DEFAULT_REFERENCE_STRENGTH = 0.6  # img2img: how far each image moves away from the reference
DEFAULT_REFERENCE_SCALE = 0.5     # IP-Adapter: much higher and the reference's face overrides the LoRA's

EVENT_PREFIX = "@@lora_generate "

STAGE_LOADING_TORCH = "Starting torch / CUDA"
STAGE_LOADING_CHECKPOINT = "Loading the base checkpoint"
STAGE_LOADING_LORA = "Applying the person's LoRA"
STAGE_LOADING_IP_ADAPTER = "Loading IP-Adapter for the reference image"
STAGE_PREPARING_GPU = "Preparing the GPU (CPU offload + attention)"
STAGE_GENERATING = "Generating"


def emit(event: str, **fields):
    print(EVENT_PREFIX + json.dumps({"event": event, **fields}), flush=True)


def reference_mode(request: dict):
    """How the request follows its reference image, or None when it has none."""
    if not request.get("reference_image"):
        return None
    return request.get("reference_mode") or REFERENCE_COMPOSITION


def uses_img2img(request: dict) -> bool:
    return reference_mode(request) in (REFERENCE_COMPOSITION, REFERENCE_BOTH)


def uses_ip_adapter(request: dict) -> bool:
    return reference_mode(request) in (REFERENCE_STYLE, REFERENCE_BOTH)


def denoising_steps(request: dict) -> int:
    """Denoising steps each image actually runs. img2img skips the start of the schedule, and this
    is the same int(steps * strength) diffusers uses, so progress and ETA line up with its callback."""
    steps = int(request.get("steps", DEFAULT_STEPS))
    if not uses_img2img(request):
        return steps
    strength = float(request.get("reference_strength", DEFAULT_REFERENCE_STRENGTH))
    return min(int(steps * strength), steps)


def reference_size(width: int, height: int, base: int = 512, max_side: int = 768) -> tuple:
    """SD1.5 working size that keeps the reference's aspect ratio: short side at `base` unless that
    pushes the long side past `max_side`, both rounded down to the multiple of 8 the VAE needs."""
    scale = base / min(width, height)
    if max(width, height) * scale > max_side:
        scale = max_side / max(width, height)
    return max(8, round(width * scale) // 8 * 8), max(8, round(height * scale) // 8 * 8)


def load_person_lora(pipe, lora_path, lora_scale: float = DEFAULT_LORA_SCALE):
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
    if network_alphas:
        network_alphas = {k: float(v) * float(lora_scale) for k, v in network_alphas.items()}
    adapter_name = "person_lora"
    pipe.load_lora_into_unet(state_dict, network_alphas=network_alphas, unet=pipe.unet,
                            adapter_name=adapter_name, metadata=metadata, _pipeline=pipe)
    if hasattr(pipe, "text_encoder") and pipe.text_encoder is not None:
        pipe.load_lora_into_text_encoder(state_dict, network_alphas=network_alphas, text_encoder=pipe.text_encoder,
                                         adapter_name=adapter_name, lora_scale=float(lora_scale), metadata=metadata, _pipeline=pipe)
    try:
        pipe.set_adapters([adapter_name], adapter_weights=[float(lora_scale)])
    except Exception:
        pass


def main():
    request = json.loads(sys.stdin.read())

    trigger_word = request["trigger_word"]
    prompt = request.get("prompt") or DEFAULT_PROMPT_TEMPLATE.format(trigger=trigger_word)
    negative_prompt = request.get("negative_prompt") or DEFAULT_NEGATIVE_PROMPT
    num_images = int(request.get("num_images", 1))
    steps = int(request.get("steps", DEFAULT_STEPS))
    seed = int(request.get("seed", -1))
    lora_scale = float(request.get("lora_scale", DEFAULT_LORA_SCALE))
    guidance_scale = float(request.get("guidance_scale", DEFAULT_GUIDANCE))
    output_dir = Path(request["output_dir"])
    file_prefix = request.get("file_prefix", "reference")
    output_dir.mkdir(parents=True, exist_ok=True)

    use_img2img, use_ip_adapter = uses_img2img(request), uses_ip_adapter(request)
    run_steps = denoising_steps(request)
    reference = size = None
    if reference_mode(request):
        # Opened before torch loads, so a missing or broken file fails in seconds rather than minutes.
        from PIL import Image, ImageOps
        reference = ImageOps.exif_transpose(Image.open(request["reference_image"])).convert("RGB")
        size = reference_size(*reference.size)

    emit("stage", stage=STAGE_LOADING_TORCH)
    import torch
    from diffusers import DPMSolverMultistepScheduler, StableDiffusionImg2ImgPipeline, StableDiffusionPipeline

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32
    device_info = {"device": device, "torch": torch.__version__}
    if device == "cuda":
        props = torch.cuda.get_device_properties(0)
        device_info.update(gpu=props.name, vram_gb=round(props.total_memory / 2**30, 1))
    emit("device", **device_info)

    emit("stage", stage=STAGE_LOADING_CHECKPOINT)
    pipeline_class = StableDiffusionImg2ImgPipeline if use_img2img else StableDiffusionPipeline
    pipe = pipeline_class.from_single_file(request["base_checkpoint"], torch_dtype=dtype, safety_checker=None)
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config, use_karras_sigmas=True)
    pipe.set_progress_bar_config(disable=True)  # per-step progress is reported as events instead

    emit("stage", stage=STAGE_LOADING_LORA)
    load_person_lora(pipe, request["lora_path"], lora_scale=lora_scale)

    if use_ip_adapter:
        emit("stage", stage=STAGE_LOADING_IP_ADAPTER)
        from undress_core import IP_ADAPTER_SUBFOLDER, IP_ADAPTER_WEIGHT_NAME, ensure_ip_adapter
        ip_src = ensure_ip_adapter()
        if ip_src is None:
            raise RuntimeError("IP-Adapter weights are missing and could not be downloaded (see the log). "
                               "Use the 'Pose & composition' reference mode, which doesn't need them.")
        pipe.load_ip_adapter(str(ip_src), subfolder=IP_ADAPTER_SUBFOLDER, weight_name=IP_ADAPTER_WEIGHT_NAME)
        pipe.set_ip_adapter_scale(float(request.get("reference_scale", DEFAULT_REFERENCE_SCALE)))

    emit("stage", stage=STAGE_PREPARING_GPU)
    if device == "cuda":
        pipe.enable_model_cpu_offload()
        if not use_ip_adapter:  # swapping attention processors would drop IP-Adapter's (see undress_engine.py)
            try:
                pipe.enable_xformers_memory_efficient_attention()
            except Exception:
                pass  # torch 2 already uses SDPA attention when xformers isn't installed

    reference_kwargs = {}
    if use_img2img:
        reference_kwargs.update(image=reference.resize(size, Image.LANCZOS),
                                strength=float(request.get("reference_strength", DEFAULT_REFERENCE_STRENGTH)))
    elif reference is not None:
        reference_kwargs.update(width=size[0], height=size[1])  # img2img takes its size from the image
    if use_ip_adapter:
        reference_kwargs["ip_adapter_image"] = reference

    # One seed per image (base + index) so any single result can be regenerated on its own.
    base_seed = seed if seed != -1 else random.randint(0, 2**31 - 1 - num_images)
    emit("stage", stage=STAGE_GENERATING, total_images=num_images, steps=run_steps, base_seed=base_seed)

    for index in range(num_images):
        image_seed = base_seed + index
        started = time.monotonic()
        if device == "cuda":
            torch.cuda.reset_peak_memory_stats()

        def on_step_end(_pipe, step, _timestep, callback_kwargs, index=index, started=started):
            emit("step", image=index + 1, step=step + 1, steps=run_steps, seconds=round(time.monotonic() - started, 2))
            return callback_kwargs

        image = pipe(
            prompt, negative_prompt=negative_prompt, num_inference_steps=steps, guidance_scale=guidance_scale,
            generator=torch.Generator(device).manual_seed(image_seed), callback_on_step_end=on_step_end,
            **reference_kwargs,
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
