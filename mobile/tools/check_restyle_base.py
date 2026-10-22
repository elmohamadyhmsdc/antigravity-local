"""Offline GPU smoke test of the approved base weights, using synthetic inputs.

Run with the existing venv_ai after download_restyle_base.py completes. This
checks loading, parser and OpenPose execution, IP-Adapter wiring and two real
diffusion steps. It does not claim photographic quality or phone acceptance.
"""
import gc
import json
import os
from pathlib import Path
import sys

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
APP = Path(__file__).resolve().parents[2] / 'the app'
sys.path.insert(0, str(APP))


def main():
    import numpy as np
    import torch
    from PIL import Image, ImageDraw
    from controlnet_aux import OpenposeDetector
    from undress_core import ensure_local_model
    from undress_engine import build_ip_kwargs, get_sd15_pipeline, load_global_models, parse_clothes

    if not torch.cuda.is_available():
        raise RuntimeError('The local CUDA environment is unavailable.')
    fixture = Image.new('RGB', (256, 256), (185, 185, 185))
    draw = ImageDraw.Draw(fixture)
    draw.ellipse((104, 20, 152, 70), fill=(205, 165, 130))
    draw.polygon([(95, 70), (161, 70), (180, 174), (76, 174)], fill=(30, 65, 130))
    draw.rectangle((92, 175, 120, 245), fill=(40, 45, 55))
    draw.rectangle((135, 175, 163, 245), fill=(40, 45, 55))
    device, dtype, processor, parser = load_global_models()
    labels = parse_clothes(fixture, processor, parser)
    assert labels.shape == (256, 256)
    del parser, processor
    gc.collect()
    print('PASS: local clothes parser executed.', flush=True)

    pose_path = ensure_local_model('lllyasviel/Annotators', 'body_pose_model.pth')
    for name in ('body_pose_model.pth', 'hand_pose_model.pth', 'facenet.pth'):
        state = torch.load(str(Path(pose_path) / name), map_location='cpu', weights_only=True)
        assert isinstance(state, dict) and state
        del state
    print('PASS: OpenPose tensor files passed restricted weights-only loading.', flush=True)
    pose = OpenposeDetector.from_pretrained(pose_path, local_files_only=True).to(device)
    control = pose(fixture, detect_resolution=256, image_resolution=256)
    assert control.size == fixture.size
    del pose
    gc.collect()
    torch.cuda.empty_cache()
    print('PASS: local body/hand/face annotator weights loaded and OpenPose executed.', flush=True)

    pipe, ip_loaded = get_sd15_pipeline(device, dtype)
    mask = Image.new('L', fixture.size, 0)
    ImageDraw.Draw(mask).rectangle((76, 70, 180, 174), fill=255)
    output = pipe(
        prompt='A fully clothed mannequin wearing a blue tailored jacket and trousers',
        negative_prompt='nudity, underwear, bad anatomy',
        image=fixture, mask_image=mask, control_image=control,
        num_inference_steps=2, strength=1.0, guidance_scale=3.0,
        height=256, width=256,
        generator=torch.Generator(device='cpu').manual_seed(7),
        **build_ip_kwargs(pipe, {}, ip_loaded),
    ).images[0]
    pixels = np.asarray(output)
    assert pixels.shape == (256, 256, 3) and pixels.std() > 0
    out_dir = APP.parent / 'mobile' / 'build' / 'restyle-base-check'
    out_dir.mkdir(parents=True, exist_ok=True)
    output.save(out_dir / 'synthetic-runtime.png')
    fixture.save(out_dir / 'synthetic-input.png')
    print(json.dumps({'result': 'passed', 'cuda': torch.cuda.get_device_name(0),
                      'ip_adapter_loaded': ip_loaded, 'steps': 2, 'sdxl_loaded': False,
                      'output': str(out_dir / 'synthetic-runtime.png')}), flush=True)
    del pipe
    gc.collect()
    torch.cuda.empty_cache()


if __name__ == '__main__':
    main()
