"""Offline inference worker for nonsexual background/object edits. No file outputs."""
import base64
import io
import json
import os
import sys

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['TOKENIZERS_PARALLELISM'] = 'false'


def main():
    from PIL import Image
    import torch
    from diffusers import StableDiffusionInpaintPipeline, DPMSolverMultistepScheduler
    from diffusers.pipelines.stable_diffusion.safety_checker import StableDiffusionSafetyChecker
    from transformers import CLIPImageProcessor
    import numpy as np
    from photo_edit import BASE_MODEL, SAFETY_MODEL, REMOVAL_MODEL, PREFIX, WORK_SIZE, validate_options, png64

    raw = sys.stdin.buffer.read(10*1024*1024+1)
    if len(raw) > 10*1024*1024:
        raise ValueError('The edit request is too large')
    request = json.loads(raw)
    options = validate_options({k:request[k] for k in ('operation','instruction','steps','seed')})
    def image(key, mode):
        opened = Image.open(io.BytesIO(base64.b64decode(request[key],validate=True)))
        if opened.size != (WORK_SIZE,WORK_SIZE):
            raise ValueError('Unsupported edit dimensions')
        return opened.convert(mode)
    original,mask = image('image','RGB'),image('mask','L')
    device = 'cuda' if torch.cuda.is_available() else 'cpu'
    dtype = torch.float16 if device == 'cuda' else torch.float32
    checker = StableDiffusionSafetyChecker.from_pretrained(str(SAFETY_MODEL),local_files_only=True,
                                                           use_safetensors=True,torch_dtype=dtype)
    processor = CLIPImageProcessor.from_pretrained(str(SAFETY_MODEL),local_files_only=True)
    if options['operation'] == 'remove':
        # A removal model reconstructs surrounding structure without a text
        # prior inventing a different scene inside a blank/simple background.
        import hashlib
        from download_photo_edit_removal import SHA256
        with REMOVAL_MODEL.open('rb') as source:
            digest = hashlib.sha256(source.read()).hexdigest()
        if digest != SHA256:
            raise ValueError('Object-removal model checksum mismatch')
        model = torch.jit.load(str(REMOVAL_MODEL),map_location=device).eval()
        pixels = torch.from_numpy(np.asarray(original).copy().transpose(2,0,1)).float().div(255).unsqueeze(0).to(device)
        selected = torch.from_numpy((np.asarray(mask) >= 128).astype(np.float32)).unsqueeze(0).unsqueeze(0).to(device)
        with torch.inference_mode():
            result = model(pixels,selected)[0].permute(1,2,0).float().cpu().numpy()
        result = np.clip(result,0,1)[None]
        checker.to(device)
        clip = processor(images=Image.fromarray((result[0]*255).astype(np.uint8)),return_tensors='pt').pixel_values.to(device=device,dtype=dtype)
        with torch.inference_mode():
            checked,flags = checker(images=result,clip_input=clip)
        if len(flags) != 1 or flags[0]:
            print(PREFIX+json.dumps(dict(safe=False)),flush=True)
            return
        print(PREFIX+json.dumps(dict(safe=True,image=png64((checked[0]*255).clip(0,255).astype(np.uint8)))),flush=True)
        return
    pipe = StableDiffusionInpaintPipeline.from_pretrained(str(BASE_MODEL),local_files_only=True,
        use_safetensors=True,torch_dtype=dtype,safety_checker=checker,feature_extractor=processor,
        requires_safety_checker=True)
    if pipe.safety_checker is None:
        raise ValueError('Output checking is unavailable')
    pipe.scheduler = DPMSolverMultistepScheduler.from_config(pipe.scheduler.config)
    pipe.enable_attention_slicing()
    pipe.enable_vae_slicing()
    pipe.to(device)
    pipe.set_progress_bar_config(disable=True)
    prompt = 'A realistic photograph of '+options['instruction']+', coherent surrounding background, consistent perspective and lighting, inanimate objects only'
    if len(pipe.tokenizer(prompt,truncation=False).input_ids) > pipe.tokenizer.model_max_length:
        print(PREFIX+json.dumps(dict(safe=False,reason='description_too_long')),flush=True)
        return
    negative = 'people, person, human, face, body, nude, nudity, sexual content, text, watermark, distorted perspective, artifacts, blurry'
    generated = pipe(prompt=prompt,negative_prompt=negative,image=original,mask_image=mask,
        height=WORK_SIZE,width=WORK_SIZE,strength=1.0,num_inference_steps=options['steps'],guidance_scale=7.,
        generator=torch.Generator(device=device).manual_seed(options['seed']))
    flags = generated.nsfw_content_detected
    if not isinstance(flags,(list,tuple)) or len(flags) != 1 or flags[0]:
        print(PREFIX+json.dumps(dict(safe=False)),flush=True)
        return
    print(PREFIX+json.dumps(dict(safe=True,image=png64(__import__('numpy').asarray(generated.images[0].convert('RGB'))))),flush=True)


if __name__ == '__main__':
    main()
