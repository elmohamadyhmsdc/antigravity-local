"""Fetch the pinned FASHN Big-LaMa TorchScript artifact; no package changes.

Its serialization differs from IOPaint's original release. Validate this exact
revision's SHA256 rather than accepting a failed upstream MD5 check.
"""
import hashlib
from pathlib import Path
import download_photo_edit_safety as download

BASE = 'https://huggingface.co/fashn-ai/LaMa/resolve/da55aaf971ce271b42eddca79831e0f646c7711e/'
SHA256 = '7ba7aa7ac37a4d41fdbbeba3a2af7ead18058552997e3a3cd1a3b2210c9e6b4c'
TARGET = Path(__file__).resolve().parent/'models/photo_edit/big-lama.pt'


def main():
    TARGET.parent.mkdir(parents=True,exist_ok=True)
    if TARGET.is_file() and hashlib.sha256(TARGET.read_bytes()).hexdigest() == SHA256:
        print('Big-LaMa is already verified.')
        return
    download.DEST = TARGET.parent
    download.BASE = BASE
    download.fetch(TARGET.name,SHA256)
    print('Verified SHA256 '+SHA256,flush=True)


if __name__ == '__main__':
    main()
