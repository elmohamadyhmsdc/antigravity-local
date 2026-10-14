"""Inspect Restyle weights, or explicitly plan/download the missing models.

Run with venv_ai\Scripts\python. The default is entirely local and read-only.
--plan reads Hugging Face file metadata; --download fetches the displayed files.
Neither mode installs packages or changes Python/CUDA configuration.
"""

import argparse
import json
from pathlib import Path

from mobile_api import APP_DIR
from mobile_api.model_readiness import restyle_missing_models
from undress_core import SDXL_INPAINT_MODEL_ID


def files_for_repo(repo, entries):
    names = {entry.rfilename: entry.size or 0 for entry in entries}
    if repo == 'lllyasviel/Annotators':
        selected = ['body_pose_model.pth','hand_pose_model.pth','facenet.pth']
    else:
        selected = [name for name in names if name.endswith(('.json','.txt','.model'))
                    and not name.startswith(('.cache/','safety_checker/'))]
        # Each component gets one weight format, avoiding duplicate multi-GB weights.
        prefixes = [''] if 'model_index.json' not in names else ['unet/','vae/','text_encoder/']
        if repo == SDXL_INPAINT_MODEL_ID: prefixes.append('text_encoder_2/')
        for prefix in prefixes:
            if repo == SDXL_INPAINT_MODEL_ID:
                weights = [prefix+'diffusion_pytorch_model.fp16.safetensors',prefix+'model.fp16.safetensors']
            else:
                weights = [prefix+'diffusion_pytorch_model.safetensors',prefix+'model.safetensors',
                           prefix+'diffusion_pytorch_model.bin',prefix+'pytorch_model.bin']
            weight = next((name for name in weights if name in names),None)
            if weight is None: raise ValueError(f'No supported weight found for {repo}/{prefix}')
            selected.append(weight)
    if any(name not in names for name in selected): raise ValueError(f'Missing expected files in {repo}')
    return {name:names[name] for name in sorted(set(selected))}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--plan',action='store_true',help='Read remote filenames/sizes without downloading weights.')
    mode.add_argument('--download',action='store_true',help='Download the selected weights; requires explicit user authorization.')
    parser.add_argument('--without-refine',action='store_true',help='Prepare only the base pass, omitting optional SDXL refine.')
    args=parser.parse_args()
    missing=restyle_missing_models(APP_DIR,refine=not args.without_refine)
    if not (args.plan or args.download):
        print(json.dumps({'missing_models':missing},indent=2));return
    from huggingface_hub import HfApi, snapshot_download
    api=HfApi()
    plan=[]
    for repo in missing:
        metadata=api.model_info(repo,files_metadata=True)
        selected=files_for_repo(repo,metadata.siblings)
        folder=APP_DIR/'models'/'undress'/repo.replace('/','--')
        needed={name:size for name,size in selected.items()
                if not (folder/name).is_file() or (folder/name).stat().st_size != size}
        plan.append({'repo':repo,'revision':metadata.sha,'directory':str(folder),
                     'bytes':sum(needed.values()),'files':needed})
    print(json.dumps({'total_gib':round(sum(p['bytes'] for p in plan)/1024**3,2),'models':plan},indent=2),flush=True)
    if args.download:
        for item in plan:
            if item['files']:
                snapshot_download(item['repo'],revision=item['revision'],local_dir=item['directory'],
                                  allow_patterns=list(item['files']),max_workers=2)
        remaining=restyle_missing_models(APP_DIR,refine=not args.without_refine)
        if remaining: raise RuntimeError('Models still incomplete: '+', '.join(remaining))
        print('Restyle weights are ready.',flush=True)


if __name__=='__main__':main()
