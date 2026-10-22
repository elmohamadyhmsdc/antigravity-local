"""Download only the explicitly approved base Restyle files, never SDXL.

Run with the existing main Python environment. Default is metadata/plan only;
--download performs resumable transfers and validates published hashes before
publishing a model. No package installation or environment changes are made.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import shutil
import time
import threading

import requests

APP = Path(__file__).resolve().parents[2] / 'the app'
ROOT = APP / 'models' / 'undress'
MANIFEST = ROOT / 'base-download-manifest.json'
BASE = 'Uminosachi/realisticVisionV51_v51VAE-inpainting'
CONTROL = 'lllyasviel/control_v11p_sd15_openpose'
POSE = 'lllyasviel/Annotators'
FILES = {
    BASE: [
        'model_index.json', 'feature_extractor/preprocessor_config.json',
        'scheduler/scheduler_config.json', 'text_encoder/config.json',
        'text_encoder/model.safetensors', 'tokenizer/merges.txt',
        'tokenizer/special_tokens_map.json', 'tokenizer/tokenizer_config.json',
        'tokenizer/vocab.json', 'unet/config.json',
        'unet/diffusion_pytorch_model.safetensors', 'vae/config.json',
        'vae/diffusion_pytorch_model.safetensors',
    ],
    CONTROL: ['config.json', 'diffusion_pytorch_model.safetensors'],
    POSE: ['body_pose_model.pth', 'hand_pose_model.pth', 'facenet.pth'],
}
REUSE = {
    'body_pose_model.pth': ROOT / 'lllyasviel--ControlNet/annotator/ckpts/body_pose_model.pth',
    'hand_pose_model.pth': ROOT / 'lllyasviel--ControlNet/annotator/ckpts/hand_pose_model.pth',
}
MAX_DOWNLOAD = 3_800_000_000  # approved ~3.74 decimal GB, allowing small configs


def emit(event, **fields):
    print(json.dumps({'event': event, **fields}), flush=True)


def verify(path, entry):
    if not path.is_file() or path.stat().st_size != entry['size']:
        return False
    lfs = entry.get('lfs')
    digest = hashlib.sha256() if lfs else hashlib.sha1()
    if not lfs:
        digest.update(f"blob {entry['size']}\0".encode())
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == (lfs['sha256'] if lfs else entry['blobId'])


def metadata(session, repo):
    response = session.get(f'https://huggingface.co/api/models/{repo}',
                           params={'blobs': 'true'}, timeout=(20, 45))
    if response.status_code != 200:
        raise RuntimeError(f'Metadata failed for {repo}: HTTP {response.status_code}')
    result = response.json()
    return result['sha'], {entry['rfilename']: entry for entry in result['siblings']}


def transfer(repo, revision, entry, target, receipt, lock):
    session = requests.Session()
    session.headers['User-Agent'] = 'Antigravity-local-approved-base-download/1.0'
    partial = target.with_name(target.name + '.download.part')
    target.parent.mkdir(parents=True, exist_ok=True)
    expected = entry['size']
    last_report = 0
    for attempt in range(1, 6):
        offset = partial.stat().st_size if partial.exists() else 0
        if offset > expected:
            raise RuntimeError(f'Oversized partial: {entry["rfilename"]}')
        if offset == expected:
            break
        url = f'https://huggingface.co/{repo}/resolve/{revision}/{entry["rfilename"]}'
        headers = {'Accept-Encoding': 'identity'}
        if offset:
            headers['Range'] = f'bytes={offset}-'
        try:
            # Fresh resolver request avoids stale, cached, expiring CDN redirects.
            with session.get(url, params={'download': 'true', 'request': str(time.time_ns())},
                             headers=headers, stream=True, timeout=(30, 120)) as response:
                if response.status_code not in (200, 206):
                    raise RuntimeError(f'HTTP {response.status_code}')
                if offset and (response.status_code != 206 or not
                               response.headers.get('Content-Range', '').startswith(f'bytes {offset}-')):
                    raise RuntimeError('Server did not accept the saved resume offset')
                with partial.open('ab' if offset else 'wb') as output:
                    for chunk in response.iter_content(1024 * 1024):
                        if not chunk:
                            continue
                        offset += len(chunk)
                        with lock:
                            receipt['network_bytes'] += len(chunk)
                            transferred = receipt['network_bytes']
                        if offset > expected or transferred > MAX_DOWNLOAD:
                            raise RuntimeError('Transfer exceeded the approved byte budget')
                        output.write(chunk)
                        if time.monotonic() - last_report >= 10:
                            emit('progress', file=entry['rfilename'], done=offset,
                                 total=expected, network_bytes=transferred)
                            last_report = time.monotonic()
                    output.flush()
                    os.fsync(output.fileno())
            if offset == expected:
                break
            raise RuntimeError('Download ended before the complete file arrived')
        except (requests.RequestException, RuntimeError) as error:
            # Retain partials for a bounded retry; never restart a large file.
            emit('retry', file=entry['rfilename'], attempt=attempt,
                 reason=type(error).__name__, offset=partial.stat().st_size if partial.exists() else 0)
            if attempt == 5 or receipt['network_bytes'] > MAX_DOWNLOAD:
                raise RuntimeError(f'Download stopped for {entry["rfilename"]}; partial retained') from None
            time.sleep(min(attempt * 2, 10))
    if not verify(partial, entry):
        raise RuntimeError(f'Published checksum did not match {entry["rfilename"]}; file not installed')
    partial.replace(target)
    emit('verified', repo=repo, file=entry['rfilename'], bytes=expected,
         sha256=entry.get('lfs', {}).get('sha256'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--download', action='store_true')
    args = parser.parse_args()
    session = requests.Session()
    session.headers['User-Agent'] = 'Antigravity-local-approved-base-download/1.0'
    plan = []
    revisions = {}
    for repo, names in FILES.items():
        revision, entries = metadata(session, repo)
        revisions[repo] = revision
        for name in names:
            entry = entries[name]
            target = ROOT / repo.replace('/', '--') / name
            if verify(target, entry):
                action, source = 'existing', None
            elif target.exists():
                raise RuntimeError(f'Existing file differs from the published revision; left untouched: {target}')
            elif repo == POSE and name in REUSE:
                source = REUSE[name]
                if not verify(source, entry):
                    raise RuntimeError(f'Local reusable OpenPose file did not match its published hash: {name}')
                action = 'reuse'
            else:
                action, source = 'download', None
            plan.append((repo, revision, entry, target, action, source))
    total = sum(entry['size'] for _, _, entry, _, action, _ in plan if action == 'download')
    if total > MAX_DOWNLOAD:
        raise RuntimeError('The selected files exceed the approved ~3.74 GB base-model budget')
    if shutil.disk_usage(ROOT).free < total + 1024 * 1024 * 1024:
        raise RuntimeError('Not enough free disk space for the selected models and verification')
    emit('plan', download_bytes=total, download_gb=round(total / 1e9, 6),
         reuse_files=sum(item[4] == 'reuse' for item in plan),
         files=[{'repo': repo, 'file': entry['rfilename'], 'size': entry['size'], 'action': action}
                for repo, _, entry, _, action, _ in plan])
    if not args.download:
        return
    receipt = {'selection': 'base-only', 'authorized_on': '2026-10-18',
               'revisions': revisions, 'network_bytes': 0, 'files': []}
    pending = []
    for repo, revision, entry, target, action, source in plan:
        if action == 'reuse':
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                os.link(source, target)
            except OSError:
                shutil.copy2(source, target)
            if not verify(target, entry):
                raise RuntimeError(f'Local copy verification failed: {target.name}')
            emit('reused', file=entry['rfilename'], bytes=entry['size'])
        elif action == 'download':
            pending.append((repo, revision, entry, target))
        receipt['files'].append({'repo': repo, 'file': entry['rfilename'], 'bytes': entry['size'],
                                 'sha256': entry.get('lfs', {}).get('sha256'), 'action': action})
    lock = threading.Lock()
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(transfer, *item, receipt, lock) for item in pending]
        for future in as_completed(futures):
            future.result()
    MANIFEST.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    emit('complete', network_bytes=receipt['network_bytes'], manifest=str(MANIFEST))


if __name__ == '__main__':
    main()
