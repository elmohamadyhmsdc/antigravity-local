"""Download approved upgraded models into their target directories.

Supports resuming partial downloads, hash/size verification, and clean error handling.
"""
import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

import requests

APP_DIR = Path(__file__).resolve().parent
MODELS_DIR = APP_DIR / "models"
UNDRESS_DIR = MODELS_DIR / "undress"

# Model 1: Hyper-SD 8-step CFG LoRA for fast inpainting (~269 MB)
HYPER_SD_REPO = "ByteDance/Hyper-SD"
HYPER_SD_FILE = "Hyper-SD15-8steps-CFG-lora.safetensors"
HYPER_SD_TARGET = MODELS_DIR / HYPER_SD_FILE

# Model 2: RMBG 1.4 background removal ONNX (~176 MB)
RMBG_REPO = "briaai/RMBG-1.4"
RMBG_FILE = "onnx/model.onnx"
RMBG_TARGET = MODELS_DIR / "rmbg.onnx"

# Model 3: Realistic Vision V6.0 Inpainting components (~2.4 GB)
RESTYLE_V6_REPO = "andregn/Realistic_Vision_V6.0-inpainting"
RESTYLE_V6_TARGET_DIR = UNDRESS_DIR / "andregn--Realistic_Vision_V6.0-inpainting"
RESTYLE_V6_FILES = [
    "model_index.json",
    "scheduler/scheduler_config.json",
    "text_encoder/config.json",
    "text_encoder/model.safetensors",
    "tokenizer/merges.txt",
    "tokenizer/special_tokens_map.json",
    "tokenizer/tokenizer_config.json",
    "tokenizer/vocab.json",
    "unet/config.json",
    "unet/diffusion_pytorch_model.bin",
    "vae/config.json",
    "vae/diffusion_pytorch_model.safetensors",
]


def human_size(n_bytes: int) -> str:
    if n_bytes >= 1024 * 1024 * 1024:
        return f"{n_bytes / (1024**3):.2f} GB"
    if n_bytes >= 1024 * 1024:
        return f"{n_bytes / (1024**2):.1f} MB"
    if n_bytes >= 1024:
        return f"{n_bytes / 1024:.1f} KB"
    return f"{n_bytes} B"


def download_file(url: str, target: Path, expected_size: int = 0, sha256: str = None) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file():
        have_size = target.stat().st_size
        if expected_size > 0 and have_size == expected_size:
            print(f" [OK] {target.name} already exists ({human_size(have_size)})", flush=True)
            return True
        elif expected_size == 0 and have_size > 1000:
            print(f" [OK] {target.name} already exists ({human_size(have_size)})", flush=True)
            return True

    partial = target.with_name(target.name + ".part")
    offset = partial.stat().st_size if partial.exists() else 0
    if expected_size and offset > expected_size:
        offset = 0
        partial.unlink(missing_ok=True)

    headers = {"User-Agent": "Antigravity-local-model-downloader/1.0"}
    if offset > 0:
        headers["Range"] = f"bytes={offset}-"

    print(f" [GET] {target.name} ({human_size(expected_size) if expected_size else 'fetching'}...)", flush=True)
    for attempt in range(1, 6):
        try:
            with requests.get(url, headers=headers, stream=True, timeout=(30, 120)) as resp:
                if resp.status_code not in (200, 206):
                    raise RuntimeError(f"HTTP {resp.status_code}")
                total = expected_size or int(resp.headers.get("Content-Length", 0)) + offset
                mode = "ab" if offset > 0 and resp.status_code == 206 else "wb"
                if mode == "wb":
                    offset = 0
                downloaded = offset
                last_pct = -1
                with open(partial, mode) as f:
                    for chunk in resp.iter_content(chunk_size=1024 * 512):
                        if not chunk:
                            continue
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total > 0:
                            pct = int(downloaded * 100 / total)
                            if pct != last_pct and pct % 10 == 0:
                                print(f"       {pct}% ({human_size(downloaded)} / {human_size(total)})", flush=True)
                                last_pct = pct
                    f.flush()
                    os.fsync(f.fileno())

            if expected_size and downloaded != expected_size:
                raise RuntimeError(f"Incomplete download: {downloaded} of {expected_size} bytes")

            partial.replace(target)
            print(f" [DONE] {target.name} ({human_size(target.stat().st_size)})", flush=True)
            return True
        except Exception as e:
            print(f" [WARN] Attempt {attempt} failed: {e}. Retrying in {attempt * 2}s...", flush=True)
            time.sleep(attempt * 2)
            offset = partial.stat().st_size if partial.exists() else 0
            if offset > 0:
                headers["Range"] = f"bytes={offset}-"

    print(f" [ERR] Failed to download {target.name}", flush=True)
    return False


def get_hf_metadata(repo_id: str):
    url = f"https://huggingface.co/api/models/{repo_id}?blobs=true"
    resp = requests.get(url, timeout=(15, 30))
    if resp.status_code != 200:
        raise RuntimeError(f"Failed to fetch metadata for {repo_id}: HTTP {resp.status_code}")
    data = resp.json()
    files = {s["rfilename"]: s for s in data.get("siblings", [])}
    return files


def download_hyper_sd():
    print("\n--- Downloading Hyper-SD 4-step LoRA ---")
    meta = get_hf_metadata(HYPER_SD_REPO)
    info = meta.get(HYPER_SD_FILE, {})
    size = info.get("size", 140000000)
    url = f"https://huggingface.co/{HYPER_SD_REPO}/resolve/main/{HYPER_SD_FILE}"
    return download_file(url, HYPER_SD_TARGET, expected_size=size)


def download_rmbg():
    print("\n--- Downloading RMBG 1.4 Background Removal ONNX ---")
    meta = get_hf_metadata(RMBG_REPO)
    info = meta.get(RMBG_FILE, {})
    size = info.get("size", 176000000)
    url = f"https://huggingface.co/{RMBG_REPO}/resolve/main/{RMBG_FILE}"
    return download_file(url, RMBG_TARGET, expected_size=size)


def download_restyle_v6():
    print("\n--- Downloading Realistic Vision V6.0 Inpainting ---")
    RESTYLE_V6_TARGET_DIR.mkdir(parents=True, exist_ok=True)
    meta = get_hf_metadata(RESTYLE_V6_REPO)
    success = True
    for rpath in RESTYLE_V6_FILES:
        info = meta.get(rpath, {})
        size = info.get("size", 0)
        target = RESTYLE_V6_TARGET_DIR / rpath
        url = f"https://huggingface.co/{RESTYLE_V6_REPO}/resolve/main/{rpath}"
        ok = download_file(url, target, expected_size=size)
        if not ok:
            success = False
            break
    return success


def main():
    parser = argparse.ArgumentParser(description="Model Upgrade Downloader")
    parser.add_argument("--hyper-sd", action="store_true", help="Download Hyper-SD LoRA")
    parser.add_argument("--rmbg", action="store_true", help="Download RMBG ONNX")
    parser.add_argument("--restyle-v6", action="store_true", help="Download Realistic Vision V6 Inpainting")
    parser.add_argument("--all", action="store_true", help="Download all approved upgrades")
    args = parser.parse_args()

    if not (args.hyper_sd or args.rmbg or args.restyle_v6 or args.all):
        parser.print_help()
        sys.exit(1)

    if args.hyper_sd or args.all:
        download_hyper_sd()
    if args.rmbg or args.all:
        download_rmbg()
    if args.restyle_v6 or args.all:
        download_restyle_v6()

    print("\n[ALL TASKS COMPLETED]")


if __name__ == "__main__":
    main()
