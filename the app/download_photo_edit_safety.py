"""Fetch the pinned, non-executable safety weights used by photo editing.

No package, Python, CUDA or application settings are changed.
"""
import hashlib
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DEST = ROOT / 'models' / 'photo_edit' / 'safety_checker'
REVISION = '9e7bda5882659ee2f75d255807a9f2f7feb61fc3'
BASE = 'https://huggingface.co/CompVis/stable-diffusion-safety-checker/resolve/' + REVISION + '/'
WEIGHT_SHA256 = '11cfe53105625af8c00faac32a430626641cce686454f3c39d837f14397d858b'


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def fetch(name, expected_hash=None):
    target = DEST / name
    if target.is_file() and (digest(target) == expected_hash if expected_hash else target.stat().st_size > 0):
        print(name + ': already available', flush=True)
        return
    partial = target.with_suffix(target.suffix + '.part')
    for attempt in range(4):
        try:
            offset = partial.stat().st_size if partial.exists() else 0
            request = urllib.request.Request(BASE + name, headers={'User-Agent': 'FaceGallery-local-model-setup'})
            if offset:
                request.add_header('Range', f'bytes={offset}-')
            with urllib.request.urlopen(request, timeout=30) as response:
                append = response.status == 206 and response.headers.get('Content-Range', '').startswith(f'bytes {offset}-')
                mode = 'ab' if append else 'wb'
                done = offset if append else 0
                reported = done // (64 * 1024 * 1024)
                with partial.open(mode) as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
                        done += len(chunk)
                        if done // (64 * 1024 * 1024) > reported:
                            reported = done // (64 * 1024 * 1024)
                            print(f'{name}: {done // (1024 * 1024)} MiB', flush=True)
            if expected_hash and digest(partial) != expected_hash:
                # Keep a corrupt transfer isolated; never load it as a model.
                partial.replace(partial.with_suffix(partial.suffix + '.invalid'))
                raise ValueError('Downloaded model checksum did not match')
            if partial.stat().st_size <= 0:
                raise ValueError('Downloaded file is empty')
            partial.replace(target)
            print(name + ': verified', flush=True)
            return
        except Exception:
            if attempt == 3:
                raise
            time.sleep(min(2 ** attempt, 4))


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for name in ('config.json', 'preprocessor_config.json'):
        fetch(name)
    fetch('model.safetensors', WEIGHT_SHA256)
    print('Photo editing safety model is ready; no packages or CUDA settings changed.', flush=True)


if __name__ == '__main__':
    main()
