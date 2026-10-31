"""Read-only checks for local Restyle weights; never start workers or downloads."""

import os
from pathlib import Path


def hub_roots():
    roots = [Path.home()/'.cache'/'huggingface'/'hub']
    for key in ('HF_HUB_CACHE', 'HUGGINGFACE_HUB_CACHE'):
        if os.environ.get(key): roots.insert(0,Path(os.environ[key]))
    if os.environ.get('HF_HOME'): roots.insert(0,Path(os.environ['HF_HOME'])/'hub')
    return list(dict.fromkeys(roots))


def restyle_missing_models(app_dir, *, refine=True, cache_roots=None):
    """Require real weights, rather than treating an empty models directory as ready."""
    from undress_core import INPAINT_MODEL_ID, SDXL_INPAINT_MODEL_ID, OPENPOSE_CONTROLNET_ID, CLOTHES_PARSER_ID
    roots = hub_roots() if cache_roots is None else cache_roots
    component_weights = (
        ('model_index.json',),
        ('unet/diffusion_pytorch_model.safetensors','unet/diffusion_pytorch_model.fp16.safetensors','unet/diffusion_pytorch_model.bin'),
        ('vae/diffusion_pytorch_model.safetensors','vae/diffusion_pytorch_model.fp16.safetensors','vae/diffusion_pytorch_model.bin'),
        ('text_encoder/model.safetensors','text_encoder/model.fp16.safetensors','text_encoder/pytorch_model.bin'),
    )
    required = {
        CLOTHES_PARSER_ID: (('config.json',),('model.safetensors','pytorch_model.bin')),
        INPAINT_MODEL_ID: component_weights,
        OPENPOSE_CONTROLNET_ID: (('config.json',),('diffusion_pytorch_model.safetensors','diffusion_pytorch_model.bin')),
        'lllyasviel/Annotators': (('body_pose_model.pth',),('hand_pose_model.pth',),('facenet.pth',)),
    }
    if refine:
        required[SDXL_INPAINT_MODEL_ID] = component_weights + (
            ('text_encoder_2/model.safetensors','text_encoder_2/model.fp16.safetensors','text_encoder_2/pytorch_model.bin'),)
    missing = []
    for repo, groups in required.items():
        candidates = [Path(app_dir)/'models'/'undress'/repo.replace('/','--')]
        for root in roots:
            snapshots = Path(root)/('models--'+repo.replace('/','--'))/'snapshots'
            if snapshots.is_dir(): candidates.extend(p for p in snapshots.iterdir() if p.is_dir())
        if not any(all(any((p/name).is_file() and (p/name).stat().st_size > 0 for name in group)
                       for group in groups) for p in candidates):
            missing.append(repo)
    return missing
