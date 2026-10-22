"""Download and verify the missing SDXL FP16 refinement components only.

Uses the existing downloader's resumable transfers and published checksum
verification. No packages, environments or base-model files are changed.
Default is a metadata-only plan; --download installs the selected files.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import json
import shutil
import threading

import requests

import download_restyle_base as download


REPO = 'diffusers/stable-diffusion-xl-1.0-inpainting-0.1'
FILES = [
    'model_index.json', 'scheduler/scheduler_config.json',
    'text_encoder/config.json', 'text_encoder/model.fp16.safetensors',
    'text_encoder_2/config.json', 'text_encoder_2/model.fp16.safetensors',
    'tokenizer/merges.txt', 'tokenizer/special_tokens_map.json',
    'tokenizer/tokenizer_config.json', 'tokenizer/vocab.json',
    'tokenizer_2/merges.txt', 'tokenizer_2/special_tokens_map.json',
    'tokenizer_2/tokenizer_config.json', 'tokenizer_2/vocab.json',
    'unet/config.json', 'unet/diffusion_pytorch_model.fp16.safetensors',
    'vae/config.json', 'vae/diffusion_pytorch_model.fp16.safetensors',
]
MAX_DOWNLOAD = 7_100_000_000


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args()
    session = requests.Session()
    session.headers['User-Agent'] = 'Antigravity-local-refine-download/1.0'
    revision, entries = download.metadata(session, REPO)
    root = download.ROOT / REPO.replace('/', '--')
    plan = []
    for name in FILES:
        entry = entries[name]
        target = root / name
        if download.verify(target, entry):
            action = 'existing'
        elif target.exists():
            raise RuntimeError(f'Existing file differs from published revision; left untouched: {target}')
        else:
            action = 'download'
        plan.append((entry, target, action))
    total = sum(entry['size'] for entry, _, action in plan if action == 'download')
    if total > MAX_DOWNLOAD:
        raise RuntimeError('Selected files exceed the expected 6.94 GB model size')
    if shutil.disk_usage(download.ROOT).free < total + 1024 ** 3:
        raise RuntimeError('Insufficient free disk space for download and verification')
    download.emit('plan', repo=REPO, revision=revision, download_bytes=total,
                  download_gb=round(total / 1e9, 6),
                  files=[{'file': entry['rfilename'], 'bytes': entry['size'], 'action': action}
                         for entry, _, action in plan])
    if not args.download:
        return
    download.MAX_DOWNLOAD = MAX_DOWNLOAD
    receipt = {'selection': 'sdxl-refinement-fp16',
               'started_at_utc': datetime.now(timezone.utc).isoformat(),
               'revisions': {REPO: revision}, 'network_bytes': 0,
               'files': [{'repo': REPO, 'file': entry['rfilename'],
                          'bytes': entry['size'], 'sha256': entry.get('lfs', {}).get('sha256'),
                          'blob_id': entry['blobId'], 'action': action}
                         for entry, _, action in plan]}
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(download.transfer, REPO, revision, entry, target, receipt, lock)
                   for entry, target, action in plan if action == 'download']
        for future in as_completed(futures):
            future.result()
    for entry, target, _ in plan:
        if not download.verify(target, entry):
            raise RuntimeError(f'Final checksum verification failed: {target}')
    receipt['completed_at_utc'] = datetime.now(timezone.utc).isoformat()
    manifest = download.ROOT / 'refine-download-manifest.json'
    temporary = manifest.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    temporary.replace(manifest)
    download.emit('complete', network_bytes=receipt['network_bytes'], manifest=str(manifest))


if __name__ == '__main__':
    main()
