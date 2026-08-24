"""
Antigravity Local - LoRA reference-image generation

Runs in venv_ai (Python 3.10) as a subprocess, called by dashboard.py from
the main venv — same stdin/stdout JSON contract as undress_engine.py.
Loads the base SD1.5 checkpoint + a trained per-person LoRA and produces
"master reference" portraits per the idea.txt recipe: front-facing, neutral
expression, flat studio lighting, ready for Character Creator 4 / KeenTools.
"""
import sys
import json
import base64
from io import BytesIO

import torch
from diffusers import StableDiffusionPipeline, UniPCMultistepScheduler
from PIL import Image

DEFAULT_PROMPT_TEMPLATE = (
    "front view portrait of {trigger} person, neutral expression, closed mouth, "
    "looking straight at camera, flat studio lighting, no shadows on face, "
    "symmetrical face, highly detailed skin texture, 8k resolution, solid white background"
)
DEFAULT_NEGATIVE_PROMPT = (
    "smiling, teeth, side view, dramatic lighting, harsh shadows, glasses, "
    "hair covering forehead, blurry, deformed"
)


def main():
    input_data = json.loads(sys.stdin.read())

    base_checkpoint = input_data["base_checkpoint"]
    lora_path = input_data["lora_path"]
    trigger_word = input_data["trigger_word"]
    prompt = input_data.get("prompt") or DEFAULT_PROMPT_TEMPLATE.format(trigger=trigger_word)
    negative_prompt = input_data.get("negative_prompt") or DEFAULT_NEGATIVE_PROMPT
    num_images = int(input_data.get("num_images", 1))
    seed = input_data.get("seed", -1)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if device == "cuda" else torch.float32

    print(f"Loading base checkpoint: {base_checkpoint}", file=sys.stderr)
    pipe = StableDiffusionPipeline.from_single_file(base_checkpoint, torch_dtype=dtype, safety_checker=None)
    pipe.scheduler = UniPCMultistepScheduler.from_config(pipe.scheduler.config)

    print(f"Loading LoRA: {lora_path}", file=sys.stderr)
    pipe.load_lora_weights(lora_path)

    if device == "cuda":
        pipe.enable_model_cpu_offload()
        try:
            pipe.enable_xformers_memory_efficient_attention()
        except Exception:
            pass

    generator = None
    if seed != -1:
        generator = torch.Generator(device).manual_seed(int(seed))

    print(f"Generating {num_images} image(s)...", file=sys.stderr)
    images = pipe(
        prompt, negative_prompt=negative_prompt, num_images_per_prompt=num_images,
        num_inference_steps=30, guidance_scale=7.5, generator=generator,
    ).images

    def img_to_b64(img: Image.Image) -> str:
        buf = BytesIO()
        img.save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode("utf-8")

    print(json.dumps({"success": True, "images": [img_to_b64(im) for im in images]}))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        import traceback
        print(json.dumps({"success": False, "error": str(e), "traceback": traceback.format_exc()}))
